import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

const ROUTES = ['/', '/hubs/', '/tools/', '/start-here/', '/search/'];
const BASE = 'https://automation-kb.pages.dev';

const OUT_DIR = 'reports';
const SCREEN_DIR = path.join(OUT_DIR, 'screenshots');

function ensureDir(p) {
  if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
}

function delay(ms) {
  return new Promise(res => setTimeout(res, ms));
}

function slug(route) {
  if (route === '/') return 'home';
  return route.replace(/\//g, '_').replace(/_+/g, '_');
}

async function scrollStep(page, position) {
  await page.evaluate((pos) => {
    const h = document.body.scrollHeight;
    window.scrollTo(0, h * pos);
  }, position);

  await delay(600);
}

async function extract(page) {
  return await page.evaluate(() => {
    const text = document.body?.innerText || '';
    return {
      title: document.title || '',
      bodyTextLength: text.length,
      links: document.querySelectorAll('a').length,
      images: document.querySelectorAll('img').length,
      contentMetricsPresent: text.length > 0
    };
  });
}

async function processRoute(browser, route) {
  const url = BASE + route;
  const page = await browser.newPage();

  let metrics;

  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await delay(1200);

  // --- TOP ---
  await scrollStep(page, 0);
  const topPath = `${SCREEN_DIR}/${slug(route)}_top.png`;
  await page.screenshot({ path: topPath });

  // --- MID ---
  await scrollStep(page, 0.5);
  const midPath = `${SCREEN_DIR}/${slug(route)}_mid.png`;
  await page.screenshot({ path: midPath });

  // --- BOTTOM ---
  await scrollStep(page, 1);
  const botPath = `${SCREEN_DIR}/${slug(route)}_bot.png`;
  await page.screenshot({ path: botPath });

  // назад вверх
  await scrollStep(page, 0);

  metrics = await extract(page);

  await page.close();

  return {
    url,
    status: 'ok',
    screenshotCount: 3,
    screenshots: [topPath, midPath, botPath],
    ...metrics
  };
}

async function main() {
  ensureDir(OUT_DIR);
  ensureDir(SCREEN_DIR);

  const browser = await chromium.launch({ headless: true });

  const results = [];
  for (const r of ROUTES) {
    results.push(await processRoute(browser, r));
  }

  await browser.close();

  fs.writeFileSync(
    path.join(OUT_DIR, 'visual_manifest.json'),
    JSON.stringify(results, null, 2)
  );

  console.log('V3.6 CAPTURE DONE');
}

main();
