import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

const ROUTES = ['/', '/hubs/', '/tools/', '/start-here/', '/search/'];
const BASE = process.env.BASE_URL || 'https://automation-kb.pages.dev';
const REPORTS_DIR = path.resolve(process.env.REPORTS_DIR || path.join(process.cwd(), 'reports'));
const SCREEN_DIR = path.join(REPORTS_DIR, 'screenshots');

function ensureDir(p) {
  if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
}

function delay(ms) {
  return new Promise((res) => setTimeout(res, ms));
}

function slug(route) {
  if (route === '/') return 'home';
  return route.replace(/\//g, '_').replace(/_+/g, '_').replace(/^_+|_+$/g, '');
}

async function scrollStep(page, position) {
  await page.evaluate((pos) => {
    const h = Math.max(document.body?.scrollHeight || 0, document.documentElement?.scrollHeight || 0, 1);
    window.scrollTo(0, h * pos);
  }, position);
  await delay(500);
}

async function extract(page) {
  return page.evaluate(() => {
    const text = document.body?.innerText || '';
    const normalize = (value) => (value || '').toLowerCase();
    const bodyTextLower = normalize(text);
    const title = document.title || '';
    const titleLower = normalize(title);
    const contaminationFlags = [];
    const contaminationChecks = [
      { key: 'edit_on_github', phrase: 'edit on github' },
      { key: 'built_with', phrase: 'built with' },
      { key: 'placeholder_lorem', phrase: 'lorem ipsum' },
      { key: 'placeholder_todo', phrase: 'todo' },
      { key: 'placeholder_coming_soon', phrase: 'coming soon' },
      { key: 'placeholder_placeholder', phrase: 'placeholder' },
    ];
    for (const check of contaminationChecks) {
      if (bodyTextLower.includes(check.phrase) || titleLower.includes(check.phrase)) {
        contaminationFlags.push(check.key);
      }
    }
    const visibleTextSample = text.replace(/\s+/g, ' ').trim().slice(0, 280);
    return {
      title,
      bodyTextLength: text.length,
      links: document.querySelectorAll('a').length,
      images: document.querySelectorAll('img').length,
      h1Count: document.querySelectorAll('h1').length,
      buttonCount: document.querySelectorAll('button').length,
      hasMain: !!document.querySelector('main'),
      hasArticle: !!document.querySelector('article'),
      hasNav: !!document.querySelector('nav'),
      hasFooter: !!document.querySelector('footer'),
      visibleTextSample,
      contaminationFlags,
      contentMetricsPresent: text.length > 0,
    };
  });
}

async function safeShot(page, route, posLabel) {
  const fileName = `${slug(route)}_${posLabel}.png`;
  const filePath = path.join(SCREEN_DIR, fileName);
  await page.screenshot({ path: filePath, fullPage: false });
  return `screenshots/${fileName}`;
}

async function processRoute(browser, route) {
  const url = new URL(route, BASE).toString();
  const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });
  const shots = [];

  try {
    const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await delay(1500);

    await scrollStep(page, 0);
    shots.push(await safeShot(page, route, 'top'));
    await scrollStep(page, 0.5);
    shots.push(await safeShot(page, route, 'mid'));
    await scrollStep(page, 1);
    shots.push(await safeShot(page, route, 'bot'));

    const metrics = await extract(page);
    return {
      url,
      route_path: route,
      status: response ? response.status() : 0,
      screenshotCount: shots.length,
      screenshots: shots,
      ...metrics,
    };
  } catch (err) {
    return {
      url,
      route_path: route,
      status: 'error',
      error: String(err?.message || err),
      screenshotCount: shots.length,
      screenshots: shots,
      title: '',
      bodyTextLength: 0,
      links: 0,
      images: 0,
      h1Count: 0,
      buttonCount: 0,
      hasMain: false,
      hasArticle: false,
      hasNav: false,
      hasFooter: false,
      visibleTextSample: '',
      contaminationFlags: [],
      contentMetricsPresent: false,
    };
  } finally {
    await page.close();
  }
}

async function main() {
  ensureDir(REPORTS_DIR);
  ensureDir(SCREEN_DIR);
  const browser = await chromium.launch({ headless: true });
  const results = [];
  for (const route of ROUTES) {
    results.push(await processRoute(browser, route));
  }
  await browser.close();
  fs.writeFileSync(path.join(REPORTS_DIR, 'visual_manifest.json'), JSON.stringify(results, null, 2));
  console.log(`CAPTURE DONE ${BASE}`);
}

main().catch((err) => {
  console.error(err?.stack || String(err));
  process.exit(1);
});
