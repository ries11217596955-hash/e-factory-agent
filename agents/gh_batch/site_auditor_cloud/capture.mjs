import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

const ROUTES = ['/', '/hubs/', '/tools/', '/start-here/', '/search/'];
const BASE = process.env.BASE_URL || 'https://automation-kb.pages.dev';
const OUT_DIR = 'reports';
const SCREEN_DIR = path.join(OUT_DIR, 'screenshots');

function ensureDir(p) {
  if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
}
function delay(ms) { return new Promise(res => setTimeout(res, ms)); }
function slug(route) { return route === '/' ? 'home' : route.replace(/\//g, '_').replace(/_+/g, '_'); }
async function scrollStep(page, position) {
  await page.evaluate((pos) => {
    const h = Math.max(document.body?.scrollHeight || 0, document.documentElement?.scrollHeight || 0, 1);
    window.scrollTo(0, h * pos);
  }, position);
  await delay(700);
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
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
  await delay(1500);
  const shots = [];
  for (const [name, pos] of [['top',0],['mid',0.5],['bot',1]]) {
    await scrollStep(page, pos);
    const out = `${SCREEN_DIR}/${slug(route)}_${name}.png`;
    await page.screenshot({ path: out, fullPage: false });
    shots.push(out);
  }
  await scrollStep(page, 0);
  const metrics = await extract(page);
  await page.close();
  return { route_path: route, url, status: 'ok', screenshotCount: shots.length, screenshots: shots, ...metrics };
}
async function main() {
  ensureDir(OUT_DIR); ensureDir(SCREEN_DIR);
  const browser = await chromium.launch({ headless: true });
  const results = [];
  for (const route of ROUTES) {
    try { results.push(await processRoute(browser, route)); }
    catch (e) { results.push({ route_path: route, url: BASE + route, status: 'error', error: String(e), screenshotCount: 0, screenshots: [] }); }
  }
  await browser.close();
  fs.writeFileSync(path.join(OUT_DIR, 'visual_manifest.json'), JSON.stringify(results, null, 2));
  console.log('CAPTURE DONE', BASE);
}
main().catch(err => { console.error(err); process.exit(1); });
