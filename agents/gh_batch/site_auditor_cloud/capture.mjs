import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

const ROUTES = ['/', '/hubs/', '/tools/', '/start-here/', '/search/'];
const BASE = (process.env.BASE_URL || 'https://automation-kb.pages.dev').replace(/\/$/, '');

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
  return route.replace(/\//g, '_').replace(/_+/g, '_').replace(/^_+|_+$/g, '');
}

async function scrollStep(page, position) {
  await page.evaluate((pos) => {
    const h = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
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
  const page = await browser.newPage({ viewport: { width: 1440, height: 1600 } });
  let status = 'ok';
  let metrics = { title: '', bodyTextLength: 0, links: 0, images: 0, contentMetricsPresent: false };
  const shots = [];

  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await delay(1500);

    for (const [label, pos] of [['top', 0], ['mid', 0.5], ['bot', 1]]) {
      await scrollStep(page, pos);
      const p = `${SCREEN_DIR}/${slug(route)}_${label}.png`;
      await page.screenshot({ path: p, fullPage: false });
      shots.push(p);
    }

    await scrollStep(page, 0);
    metrics = await extract(page);
  } catch (err) {
    status = 'capture_error';
  } finally {
    await page.close();
  }

  return {
    route_path: route,
    url,
    status,
    screenshotCount: shots.length,
    screenshots: shots,
    ...metrics
  };
}

async function main() {
  ensureDir(OUT_DIR);
  ensureDir(SCREEN_DIR);

  const browser = await chromium.launch({ headless: true });
  const results = [];

  for (const route of ROUTES) {
    results.push(await processRoute(browser, route));
  }

  await browser.close();
  fs.writeFileSync(path.join(OUT_DIR, 'visual_manifest.json'), JSON.stringify(results, null, 2));
  console.log('CAPTURE DONE');
}

main().catch(err => {
  console.error(err?.message || String(err));
  process.exit(1);
});
