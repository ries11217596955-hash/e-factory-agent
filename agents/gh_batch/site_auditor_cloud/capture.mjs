import fs from "fs";
import path from "path";
import { chromium } from "playwright";

const baseUrl = process.argv[2];
const routeFile = process.argv[3];
const outDir = process.argv[4];

if (!baseUrl || !routeFile || !outDir) {
  console.error("Usage: node capture.mjs <baseUrl> <routes.json> <outDir>");
  process.exit(1);
}

const routes = JSON.parse(fs.readFileSync(routeFile, "utf-8"));
const screenshotsDir = path.join(outDir, "screenshots");

fs.mkdirSync(screenshotsDir, { recursive: true });

function slug(url) {
  return url.replace(/^https?:\/\//, "").replace(/[^a-zA-Z0-9]+/g, "_");
}

function normalizeText(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim();
}

async function collectDomMetrics(page, screenshotCount) {
  const metrics = await page.evaluate(() => {
    const body = document.body;
    const title = (document.title || "").trim();
    const bodyText = body ? body.innerText || "" : "";
    const normalizedBodyText = bodyText.replace(/\s+/g, " ").trim();
    const links = Array.from(document.querySelectorAll("a[href]")).filter((a) => {
      const href = (a.getAttribute("href") || "").trim();
      return href.length > 0 && !href.startsWith("javascript:");
    }).length;
    const images = document.querySelectorAll("img").length;
    const footerDetected = Boolean(
      document.querySelector("footer") ||
      document.querySelector('[role="contentinfo"]')
    );

    return {
      title,
      bodyTextLength: normalizedBodyText.length,
      links,
      images,
      footerDetected,
      contentMetricsPresent: true
    };
  });

  const title = normalizeText(metrics.title);
  const bodyTextLength = Number.isFinite(metrics.bodyTextLength) ? metrics.bodyTextLength : 0;
  const links = Number.isFinite(metrics.links) ? metrics.links : 0;
  const images = Number.isFinite(metrics.images) ? metrics.images : 0;
  const footerDetected = Boolean(metrics.footerDetected);
  const lowCoverage = screenshotCount < 3;
  const suspectShortPage = bodyTextLength < 300;
  const suspectEmptyTitle = title.length === 0;
  const suspectFooterMissing = !footerDetected;

  return {
    title,
    bodyTextLength,
    links,
    images,
    lowCoverage,
    suspectShortPage,
    suspectEmptyTitle,
    suspectFooterMissing,
    contentMetricsPresent: true
  };
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

const manifest = [];
let total = 0;

for (const url of routes) {
  console.log("CAPTURE:", url);

  try {
    await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });
    await page.waitForTimeout(1200);

    const height = await page.evaluate(() => {
      const body = document.body;
      const doc = document.documentElement;
      return Math.max(
        body ? body.scrollHeight : 0,
        body ? body.offsetHeight : 0,
        doc ? doc.clientHeight : 0,
        doc ? doc.scrollHeight : 0,
        doc ? doc.offsetHeight : 0,
        window.innerHeight || 0
      );
    });

    const viewportHeight = page.viewportSize()?.height || 1000;
    const step = Math.max(700, Math.floor(viewportHeight * 0.8));
    const maxShots = 8;
    const shots = [];

    for (let y = 0; y < height && shots.length < maxShots; y += step) {
      await page.evaluate((_y) => window.scrollTo(0, _y), y);
      await page.waitForTimeout(400);

      const name = `${slug(url)}_${shots.length}.png`;
      const file = path.join(screenshotsDir, name);

      await page.screenshot({ path: file });

      shots.push(name);
      total++;
    }

    const metrics = await collectDomMetrics(page, shots.length);

    manifest.push({
      url,
      status: "ok",
      screenshotCount: shots.length,
      screenshots: shots,
      title: metrics.title,
      bodyTextLength: metrics.bodyTextLength,
      links: metrics.links,
      images: metrics.images,
      lowCoverage: metrics.lowCoverage,
      suspectShortPage: metrics.suspectShortPage,
      suspectEmptyTitle: metrics.suspectEmptyTitle,
      suspectFooterMissing: metrics.suspectFooterMissing,
      contentMetricsPresent: true
    });
  } catch (err) {
    manifest.push({
      url,
      status: "fail",
      error: String(err),
      screenshotCount: 0,
      contentMetricsPresent: false
    });
  }
}

await browser.close();

fs.writeFileSync(
  path.join(outDir, "visual_manifest.json"),
  JSON.stringify(manifest, null, 2)
);

fs.writeFileSync(
  path.join(outDir, "visual_capture_summary.json"),
  JSON.stringify(
    {
      routes: routes.length,
      screenshots: total,
      schemaVersion: "visual-audit-v3.3c"
    },
    null,
    2
  )
);
