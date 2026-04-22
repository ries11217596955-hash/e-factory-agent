import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { chromium } from 'playwright';

const MIN_CAPTURE_SIZE_BYTES = 4096;

function slugForUrl(url) {
  return crypto.createHash('sha1').update(url).digest('hex').slice(0, 10);
}

function readInput(inputPath) {
  const raw = fs.readFileSync(inputPath, 'utf8');
  const parsed = JSON.parse(raw);
  const pages = Array.isArray(parsed.pages) ? parsed.pages : [];
  return {
    pages: pages.slice(0, 5),
    screenshotsDir: parsed.screenshots_dir,
    viewport: parsed.viewport || { width: 1366, height: 768 }
  };
}

async function settlePage(page) {
  await page.waitForSelector('body', { timeout: 10000 });
  try {
    await page.waitForLoadState('networkidle', { timeout: 7000 });
  } catch {
    // fall through; network can stay busy on many modern pages
  }
  await page.waitForTimeout(800);
}

async function captureSegments(page, pageDescriptor, screenshotsDir) {
  const pageIndex = pageDescriptor.index;
  const slug = slugForUrl(pageDescriptor.url);
  const viewportHeight = page.viewportSize()?.height || 768;
  const totalHeight = await page.evaluate(() => {
    const doc = document.documentElement;
    const body = document.body;
    return Math.max(
      doc?.scrollHeight || 0,
      doc?.offsetHeight || 0,
      body?.scrollHeight || 0,
      body?.offsetHeight || 0
    );
  });

  const anchorPoints = [0, Math.max(0, Math.floor(totalHeight / 2) - Math.floor(viewportHeight / 2)), Math.max(0, totalHeight - viewportHeight)];
  const segmentNames = ['top', 'mid', 'bottom'];

  const captures = [];
  for (let i = 0; i < segmentNames.length; i += 1) {
    const segment = segmentNames[i];
    const y = anchorPoints[i];
    await page.evaluate((scrollY) => window.scrollTo(0, scrollY), y);
    await page.waitForTimeout(250);
    const fileName = `page-${String(pageIndex).padStart(2, '0')}-${slug}-${segment}.png`;
    const outPath = path.join(screenshotsDir, fileName);
    let captureStatus = 'ok';
    let captureError = '';
    let captureSizeBytes = 0;

    try {
      await page.screenshot({ path: outPath, type: 'png', fullPage: false });
    } catch (err) {
      captureStatus = 'render_fail';
      captureError = err instanceof Error ? err.message : String(err);
    }

    if (captureStatus !== 'render_fail') {
      if (!fs.existsSync(outPath)) {
        captureStatus = 'missing_capture';
        captureError = 'Screenshot file missing after capture call.';
      } else {
        const stats = fs.statSync(outPath);
        captureSizeBytes = Number(stats.size || 0);
        if (captureSizeBytes < MIN_CAPTURE_SIZE_BYTES) {
          captureStatus = 'empty_capture';
          captureError = `Screenshot size ${captureSizeBytes} bytes is below minimum ${MIN_CAPTURE_SIZE_BYTES} bytes.`;
        }
      }
    }

    captures.push({
      segment,
      type: segment,
      file: `screenshots/${fileName}`,
      size_bytes: captureSizeBytes,
      status: captureStatus,
      error: captureError
    });
  }

  return captures;
}

async function run() {
  const [inputPath, outputManifestPath] = process.argv.slice(2);
  if (!inputPath || !outputManifestPath) {
    throw new Error('Usage: node capture_visuals.mjs <inputPath> <outputManifestPath>');
  }

  const { pages, screenshotsDir, viewport } = readInput(inputPath);
  fs.mkdirSync(screenshotsDir, { recursive: true });

  const startedAt = new Date().toISOString();
  const manifest = {
    status: 'SUCCESS',
    started_at_utc: startedAt,
    finished_at_utc: null,
    requested_pages: pages.length,
    processed_pages: 0,
    failed_pages: 0,
    pages: []
  };

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport });

  try {
    for (const descriptor of pages) {
      const page = await context.newPage();
      const pageResult = {
        index: descriptor.index,
        url: descriptor.url,
        status: 'SUCCESS',
        error: '',
        captures: []
      };

      try {
        await page.goto(descriptor.url, { waitUntil: 'domcontentloaded', timeout: 25000 });
        await settlePage(page);
        pageResult.captures = await captureSegments(page, descriptor, screenshotsDir);
        const hasCaptureFailure = pageResult.captures.some((capture) => capture.status !== 'ok');
        pageResult.status = hasCaptureFailure ? 'PARTIAL' : 'SUCCESS';
        manifest.processed_pages += 1;
        if (hasCaptureFailure) {
          manifest.failed_pages += 1;
        }
      } catch (err) {
        pageResult.status = 'FAIL';
        pageResult.error = err instanceof Error ? err.message : String(err);
        manifest.failed_pages += 1;
      } finally {
        manifest.pages.push(pageResult);
        await page.close();
      }
    }
  } finally {
    await context.close();
    await browser.close();
  }

  if (manifest.processed_pages === 0) {
    manifest.status = 'FAIL';
  } else if (manifest.failed_pages > 0) {
    manifest.status = 'PARTIAL';
  }

  manifest.finished_at_utc = new Date().toISOString();
  fs.writeFileSync(outputManifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
}

run().catch((err) => {
  const fallback = {
    status: 'FAIL',
    started_at_utc: new Date().toISOString(),
    finished_at_utc: new Date().toISOString(),
    requested_pages: 0,
    processed_pages: 0,
    failed_pages: 0,
    pages: [],
    fatal_error: err instanceof Error ? err.message : String(err)
  };

  const [, , , outputManifestPath] = process.argv;
  if (outputManifestPath) {
    fs.writeFileSync(outputManifestPath, `${JSON.stringify(fallback, null, 2)}\n`, 'utf8');
  }

  process.exitCode = 1;
});
