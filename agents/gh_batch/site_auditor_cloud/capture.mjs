import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

const ROUTES = ['/', '/hubs/', '/tools/', '/start-here/', '/search/'];
const BASE = 'https://automation-kb.pages.dev';

const OUT_DIR = 'reports';
const SCREEN_DIR = path.join(OUT_DIR, 'screenshots');
const MANIFEST_PATH = path.join(OUT_DIR, 'visual_manifest.json');
const SUMMARY_PATH = path.join(OUT_DIR, 'visual_capture_summary.json');

function ensureDir(p) {
  if (!fs.existsSync(p)) {
    fs.mkdirSync(p, { recursive: true });
  }
}

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function safeFileSlug(route) {
  if (route === '/') return 'home';
  return route
    .replace(/^\/+|\/+$/g, '')
    .replace(/[^\w\-]+/g, '_')
    .replace(/_+/g, '_')
    .toLowerCase() || 'route';
}

async function tryWaitNetworkIdle(page, timeout = 4000) {
  try {
    await page.waitForLoadState('networkidle', { timeout });
    return true;
  } catch {
    return false;
  }
}

async function waitForBody(page, timeout = 5000) {
  try {
    await page.waitForSelector('body', { timeout });
    return true;
  } catch {
    return false;
  }
}

async function waitForHydrationSignals(page, timeout = 6000) {
  try {
    await page.waitForFunction(() => {
      const body = document.body;
      if (!body) return false;

      const text = (body.innerText || '').trim();
      const links = document.querySelectorAll('a').length;
      const images = document.querySelectorAll('img').length;
      const main = document.querySelector('main');
      const article = document.querySelector('article');
      const section = document.querySelector('section');
      const title = (document.title || '').trim();

      return (
        text.length > 120 ||
        links >= 4 ||
        images >= 1 ||
        !!main ||
        !!article ||
        (!!section && text.length > 80) ||
        title.length > 3
      );
    }, { timeout });

    return true;
  } catch {
    return false;
  }
}

async function autoScroll(page) {
  try {
    await page.evaluate(async () => {
      const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
      const maxSteps = 20;
      let lastHeight = 0;

      for (let i = 0; i < maxSteps; i++) {
        const currentHeight = Math.max(
          document.body ? document.body.scrollHeight : 0,
          document.documentElement ? document.documentElement.scrollHeight : 0
        );

        window.scrollTo(0, Math.min((i + 1) * 500, currentHeight));
        await sleep(120);

        if (currentHeight === lastHeight && i > 4) {
          break;
        }
        lastHeight = currentHeight;
      }

      window.scrollTo(0, 0);
      await sleep(150);
    });

    return true;
  } catch {
    return false;
  }
}

async function extractMetrics(page) {
  return await page.evaluate(() => {
    const body = document.body;
    const rawText = body ? (body.innerText || '') : '';
    const text = rawText.replace(/\s+/g, ' ').trim();

    const title = (document.title || '').trim();
    const links = document.querySelectorAll('a').length;
    const images = document.querySelectorAll('img').length;
    const mainDetected = !!document.querySelector('main');
    const footerDetected = !!document.querySelector('footer');
    const articleDetected = !!document.querySelector('article');
    const sectionCount = document.querySelectorAll('section').length;
    const headingCount = document.querySelectorAll('h1, h2, h3').length;

    const bodyTextLength = text.length;
    const lowCoverage = bodyTextLength < 120 && links < 3 && !mainDetected && !articleDetected;
    const suspectShortPage = bodyTextLength < 80;
    const suspectEmptyTitle = title.length === 0;
    const suspectFooterMissing = !footerDetected;

    const contentMetricsPresent =
      title.length > 0 ||
      bodyTextLength > 0 ||
      links > 0 ||
      images > 0 ||
      mainDetected ||
      articleDetected ||
      sectionCount > 0 ||
      headingCount > 0;

    const contentLikelyMissing =
      bodyTextLength < 50 &&
      links === 0 &&
      images === 0 &&
      title.length === 0 &&
      !mainDetected &&
      !articleDetected &&
      sectionCount === 0 &&
      headingCount === 0;

    return {
      title,
      bodyTextLength,
      links,
      images,
      mainDetected,
      footerDetected,
      articleDetected,
      sectionCount,
      headingCount,
      lowCoverage,
      suspectShortPage,
      suspectEmptyTitle,
      suspectFooterMissing,
      contentMetricsPresent,
      contentLikelyMissing
    };
  });
}

async function settlePage(page) {
  const waitNotes = [];

  const bodyOk = await waitForBody(page, 5000);
  waitNotes.push(`body:${bodyOk ? 'ok' : 'timeout'}`);

  const networkIdleOk = await tryWaitNetworkIdle(page, 3500);
  waitNotes.push(`networkidle:${networkIdleOk ? 'ok' : 'skip'}`);

  const hydrationOk = await waitForHydrationSignals(page, 6000);
  waitNotes.push(`hydrate:${hydrationOk ? 'ok' : 'timeout'}`);

  const scrollOk = await autoScroll(page);
  waitNotes.push(`scroll:${scrollOk ? 'ok' : 'skip'}`);

  await delay(1200);

  return {
    hydrationTriggered: hydrationOk || scrollOk,
    waitNotes
  };
}

async function processRoute(browser, route) {
  const url = BASE + route;
  const slug = safeFileSlug(route);
  const screenshotPath = path.join(SCREEN_DIR, `${slug}.png`);

  const context = await browser.newContext({
    viewport: { width: 1440, height: 2200 }
  });

  const page = await context.newPage();

  let retried = false;
  let hydrationTriggered = false;
  let metrics = null;
  let waitNotes = [];
  let finalStatus = 'fail';

  try {
    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 20000
    });

    const settle1 = await settlePage(page);
    hydrationTriggered = settle1.hydrationTriggered;
    waitNotes = waitNotes.concat(settle1.waitNotes);

    metrics = await extractMetrics(page);

    const weakMetrics =
      !metrics.contentMetricsPresent ||
      metrics.contentLikelyMissing ||
      (metrics.bodyTextLength < 80 && metrics.links === 0);

    if (weakMetrics) {
      retried = true;

      await page.reload({
        waitUntil: 'domcontentloaded',
        timeout: 20000
      });

      const settle2 = await settlePage(page);
      hydrationTriggered = hydrationTriggered || settle2.hydrationTriggered;
      waitNotes = waitNotes.concat(settle2.waitNotes.map(x => `retry:${x}`));

      metrics = await extractMetrics(page);
    }

    await page.screenshot({
      path: screenshotPath,
      fullPage: true
    });

    finalStatus = 'ok';

    return {
      url,
      status: finalStatus,
      screenshotCount: 1,
      screenshots: [screenshotPath],
      retried,
      hydrationTriggered,
      waitNotes,
      ...metrics
    };
  } catch (err) {
    try {
      await page.screenshot({
        path: screenshotPath,
        fullPage: true
      });
    } catch {
      // ignore screenshot-on-fail errors
    }

    return {
      url,
      status: 'fail',
      error: String(err && err.message ? err.message : err),
      screenshotCount: fs.existsSync(screenshotPath) ? 1 : 0,
      screenshots: fs.existsSync(screenshotPath) ? [screenshotPath] : [],
      retried,
      hydrationTriggered,
      waitNotes,
      contentMetricsPresent: false,
      contentLikelyMissing: false
    };
  } finally {
    await context.close();
  }
}

async function main() {
  ensureDir(OUT_DIR);
  ensureDir(SCREEN_DIR);

  const browser = await chromium.launch({
    headless: true
  });

  const results = [];
  for (const route of ROUTES) {
    const result = await processRoute(browser, route);
    results.push(result);
  }

  await browser.close();

  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(results, null, 2), 'utf8');

  const okRoutes = results.filter(r => r.status === 'ok');
  const failedRoutes = results.filter(r => r.status !== 'ok');
  const retriedRoutes = results.filter(r => r.retried);
  const hydrationTriggeredRoutes = results.filter(r => r.hydrationTriggered);
  const contentMetricsRoutes = results.filter(r => r.contentMetricsPresent);
  const likelyMissingRoutes = results.filter(r => r.contentLikelyMissing);

  const summary = {
    totalRoutes: results.length,
    okRoutes: okRoutes.length,
    failedRoutes: failedRoutes.length,
    retriedRoutes: retriedRoutes.length,
    hydrationTriggeredRoutes: hydrationTriggeredRoutes.length,
    contentMetricsRoutes: contentMetricsRoutes.length,
    likelyMissingRoutes: likelyMissingRoutes.length,
    schemaVersion: 'visual-audit-v3.5'
  };

  fs.writeFileSync(SUMMARY_PATH, JSON.stringify(summary, null, 2), 'utf8');

  console.log('CAPTURE DONE');
  console.log(JSON.stringify(summary));
}

main().catch(err => {
  console.error('CAPTURE FAILED');
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(1);
});
