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
  if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
}

function delay(ms) {
  return new Promise(res => setTimeout(res, ms));
}

async function extractMetrics(page) {
  return await page.evaluate(() => {
    const text = document.body?.innerText || '';
    const links = document.querySelectorAll('a').length;
    const images = document.querySelectorAll('img').length;
    const title = document.title || '';

    const mainDetected = !!document.querySelector('main');
    const footerDetected = !!document.querySelector('footer');

    return {
      title,
      bodyTextLength: text.length,
      links,
      images,
      mainDetected,
      footerDetected
    };
  });
}

async function waitForContent(page) {
  try {
    await page.waitForFunction(() => {
      const text = document.body?.innerText || '';
      const links = document.querySelectorAll('a').length;
      return text.length > 80 || links > 3;
    }, { timeout: 5000 });
  } catch {
    // soft fail — продолжаем
  }
}

async function processRoute(browser, route) {
  const url = BASE + route;
  const context = await browser.newContext();
  const page = await context.newPage();

  let retried = false;
  let metrics;

  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });

    try {
      await page.waitForLoadState('networkidle', { timeout: 3000 });
    } catch {}

    await page.waitForSelector('body', { timeout: 5000 });
    await waitForContent(page);

    metrics = await extractMetrics(page);

    // retry если пусто
    if ((metrics.bodyTextLength < 50 || metrics.links === 0) && !retried) {
      retried = true;
      await page.reload({ waitUntil: 'domcontentloaded' });
      await delay(1000);
      await waitForContent(page);
      metrics = await extractMetrics(page);
    }

    const screenshotPath = path.join(SCREEN_DIR, route.replace(/\//g, '_') + '.png');
    await page.screenshot({ path: screenshotPath, fullPage: true });

    return {
      url,
      status: 'ok',
      screenshotCount: 1,
      screenshots: [screenshotPath],
      ...metrics,
      contentMetricsPresent: true,
      contentLikelyMissing: metrics.bodyTextLength < 50 && metrics.links === 0,
      retried
    };

  } catch (err) {
    return {
      url,
      status: 'fail',
      error: String(err),
      screenshotCount: 0,
      screenshots: [],
      contentMetricsPresent: false,
      retried
    };
  } finally {
    await context.close();
  }
}

async function main() {
  ensureDir(OUT_DIR);
  ensureDir(SCREEN_DIR);

  const browser = await chromium.launch({ headless: true });

  const results = [];
  for (const route of ROUTES) {
    const r = await processRoute(browser, route);
    results.push(r);
  }

  await browser.close();

  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(results, null, 2));

  const summary = {
    totalRoutes: results.length,
    okRoutes: results.filter(r => r.status === 'ok').length,
    failedRoutes: results.filter(r => r.status !== 'ok').length,
    retriedRoutes: results.filter(r => r.retried).length,
    schemaVersion: 'visual-audit-v3.4'
  };

  fs.writeFileSync(SUMMARY_PATH, JSON.stringify(summary, null, 2));

  console.log('CAPTURE DONE');
}

main();
