import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

const ROUTES = ['/', '/hubs/', '/tools/', '/start-here/', '/search/'];
const BASE = process.env.BASE_URL || 'https://automation-kb.pages.dev';
const REPORTS_DIR = path.resolve(process.env.REPORTS_DIR || path.join(process.cwd(), 'reports'));
const SCREEN_DIR = path.join(REPORTS_DIR, 'screenshots');
const VIEWPORT = { width: 1440, height: 1200 };
const CAPTURE_POSITIONS = [
  { key: 'top', ratio: 0 },
  { key: 'mid', ratio: 0.5 },
  { key: 'bottom', ratio: 1 },
];

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

function categorizeRoute(route) {
  const normalized = (route || '').toLowerCase();
  if (normalized === '/') return 'ROOT';
  if (normalized.startsWith('/hubs')) return 'HUB';
  if (normalized.startsWith('/tools')) return 'TOOL';
  if (normalized.startsWith('/search')) return 'SEARCH';
  if (normalized.startsWith('/start-here')) return 'START';
  return 'CONTENT';
}

async function waitForPageStability(page) {
  await page.waitForLoadState('domcontentloaded', { timeout: 30000 });

  try {
    await page.waitForLoadState('networkidle', { timeout: 4000 });
  } catch {
    // best effort only
  }

  try {
    await page.evaluate(async () => {
      if (!document.fonts || !document.fonts.ready) return;
      const timeout = new Promise((resolve) => setTimeout(resolve, 2500));
      await Promise.race([document.fonts.ready, timeout]);
    });
  } catch {
    // best effort only
  }

  try {
    await page.evaluate(async () => {
      const imgs = Array.from(document.images || []);
      const timeout = new Promise((resolve) => setTimeout(resolve, 2500));
      const loaded = Promise.all(
        imgs.map((img) => {
          if (img.complete) return Promise.resolve();
          return new Promise((resolve) => {
            const done = () => resolve();
            img.addEventListener('load', done, { once: true });
            img.addEventListener('error', done, { once: true });
          });
        }),
      );
      await Promise.race([loaded, timeout]);
    });
  } catch {
    // best effort only
  }

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

async function scrollToRatio(page, ratio) {
  await page.evaluate((targetRatio) => {
    const bodyHeight = document.body?.scrollHeight || 0;
    const htmlHeight = document.documentElement?.scrollHeight || 0;
    const viewport = window.innerHeight || 1;
    const totalHeight = Math.max(bodyHeight, htmlHeight, viewport);
    const maxScrollY = Math.max(totalHeight - viewport, 0);
    const targetY = Math.round(maxScrollY * targetRatio);
    window.scrollTo(0, targetY);
  }, ratio);
  await delay(250);
}

async function safeShot(page, route, posLabel, fullPage = false) {
  const fileName = `${slug(route)}_${posLabel}.png`;
  const filePath = path.join(SCREEN_DIR, fileName);
  await page.screenshot({ path: filePath, fullPage });
  return `screenshots/${fileName}`;
}

function detectIssueClasses(status, metrics) {
  const sample = `${metrics.visibleTextSample || ''} ${metrics.title || ''}`.toLowerCase();
  const classes = [];

  if (Number(status) >= 400 || metrics.bodyTextLength <= 80) {
    classes.push('EMPTY_OR_NEAR_EMPTY_PAGE');
  }
  if (Number(status) >= 500 || sample.includes('{{') || sample.includes('{%') || sample.includes('undefined')) {
    classes.push('BROKEN_RENDER_OR_TEMPLATE_LEAKAGE');
  }
  if ((metrics.contaminationFlags || []).length > 0) {
    classes.push('OVERLAY_OR_UI_CONTAMINATION');
  }
  if ((!metrics.hasMain && !metrics.hasArticle) || metrics.h1Count === 0) {
    classes.push('DUPLICATE_SHELL_OR_MISSING_CRITICAL_BLOCK');
  }
  if (metrics.bodyTextLength > 0 && metrics.links === 0 && metrics.images === 0 && metrics.buttonCount === 0) {
    classes.push('SEVERE_LAYOUT_BREAK');
  }

  return Array.from(new Set(classes));
}

async function captureIssueEvidence(page, route, issueClass, deterministicRefs) {
  const evidence = [];
  try {
    evidence.push(await safeShot(page, route, `issue_${issueClass.toLowerCase()}`));
  } catch {
    try {
      evidence.push(await safeShot(page, route, `issue_${issueClass.toLowerCase()}_fullpage`, true));
    } catch {
      // leave empty; caller can enforce fail path
    }
  }

  if (evidence.length === 0 && deterministicRefs.length > 0) {
    evidence.push(...deterministicRefs.slice(0, 1));
  }
  return evidence;
}

async function processRoute(browser, route) {
  const url = new URL(route, BASE).toString();
  const page = await browser.newPage({ viewport: VIEWPORT });
  const screenshotMap = { top: '', mid: '', bottom: '' };

  try {
    const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await waitForPageStability(page);

    for (const position of CAPTURE_POSITIONS) {
      await scrollToRatio(page, position.ratio);
      screenshotMap[position.key] = await safeShot(page, route, position.key);
    }

    const deterministicRefs = CAPTURE_POSITIONS.map((p) => screenshotMap[p.key]).filter(Boolean);
    const metrics = await extract(page);
    const status = response ? response.status() : 0;
    const issueClasses = detectIssueClasses(status, metrics);
    const issues = [];
    const issueShots = [];

    for (const issueClass of issueClasses) {
      const evidence = await captureIssueEvidence(page, route, issueClass, deterministicRefs);
      issueShots.push(...evidence);
      issues.push({
        class: issueClass,
        requires_visual_proof: true,
        evidence_refs: Array.from(new Set(evidence)),
      });
    }

    return {
      url,
      route_path: route,
      routeCategory: categorizeRoute(route),
      status,
      screenshotCount: deterministicRefs.length + issueShots.length,
      screenshots: deterministicRefs,
      screenshot_map: screenshotMap,
      issue_screenshots: Array.from(new Set(issueShots)),
      issues,
      captureProfile: 'DETERMINISTIC_TOP_MID_BOTTOM_V1',
      viewport_policy: `${VIEWPORT.width}x${VIEWPORT.height}`,
      ...metrics,
    };
  } catch (err) {
    const fallbackShots = [];
    try {
      fallbackShots.push(await safeShot(page, route, 'failure_fullpage', true));
    } catch {
      // best effort only
    }

    return {
      url,
      route_path: route,
      routeCategory: categorizeRoute(route),
      status: 'error',
      error: String(err?.message || err),
      screenshotCount: fallbackShots.length,
      screenshots: fallbackShots,
      screenshot_map: { top: '', mid: '', bottom: '' },
      issue_screenshots: fallbackShots,
      issues: fallbackShots.length > 0
        ? [{ class: 'BROKEN_RENDER_OR_TEMPLATE_LEAKAGE', requires_visual_proof: true, evidence_refs: fallbackShots }]
        : [{ class: 'BROKEN_RENDER_OR_TEMPLATE_LEAKAGE', requires_visual_proof: true, evidence_refs: [] }],
      captureProfile: 'DETERMINISTIC_TOP_MID_BOTTOM_V1',
      viewport_policy: `${VIEWPORT.width}x${VIEWPORT.height}`,
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
