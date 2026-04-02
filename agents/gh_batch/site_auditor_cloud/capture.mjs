import fs from "fs";
import path from "path";
import { chromium } from "playwright";

const baseUrl = process.argv[2];
const routeFile = process.argv[3];
const outDir = process.argv[4];

if (!baseUrl || !routeFile || !outDir) {
  console.error("Usage: node capture.mjs <baseUrl> <routeInventory.json> <reportsDir>");
  process.exit(2);
}

const routes = JSON.parse(fs.readFileSync(routeFile, "utf-8"));
const screenshotsDir = path.join(outDir, "screenshots");

fs.mkdirSync(screenshotsDir, { recursive: true });

function slugifyRoute(url) {
  let s = url.replace(/^https?:\/\//, "");
  s = s.replace(/[^a-zA-Z0-9/_-]+/g, "_");
  s = s.replace(/[\/]+/g, "__");
  s = s.replace(/^_+|_+$/g, "");
  if (!s) s = "root";
  return s;
}

function buildCapturePoints(scrollHeight, viewportHeight) {
  const minShots = 3;
  const maxShots = 8;

  // Короткие страницы: top / mid / bottom
  if (scrollHeight <= viewportHeight * 1.5) {
    return [0, Math.max(0, Math.floor((scrollHeight - viewportHeight) / 2)), Math.max(0, scrollHeight - viewportHeight)]
      .filter((v, i, arr) => arr.indexOf(v) === i);
  }

  // Более длинные страницы: сегменты по высоте
  const effectiveScrollable = Math.max(0, scrollHeight - viewportHeight);
  let count = Math.ceil(scrollHeight / viewportHeight);
  count = Math.max(minShots, count);
  count = Math.min(maxShots, count);

  const points = [];
  for (let i = 0; i < count; i++) {
    const ratio = count === 1 ? 0 : i / (count - 1);
    const y = Math.round(effectiveScrollable * ratio);
    points.push(y);
  }

  return points.filter((v, i, arr) => arr.indexOf(v) === i);
}

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({
  viewport: { width: 1440, height: 1000 }
});

const manifest = [];
let totalScreenshots = 0;

for (const url of routes) {
  console.log("CAPTURE:", url);

  const routeSlug = slugifyRoute(url);

  try {
    await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });
    await page.waitForTimeout(800);

    const metrics = await page.evaluate(() => {
      const body = document.body;
      const doc = document.documentElement;

      const scrollHeight = Math.max(
        body ? body.scrollHeight : 0,
        doc ? doc.scrollHeight : 0,
        body ? body.offsetHeight : 0,
        doc ? doc.offsetHeight : 0,
        body ? body.clientHeight : 0,
        doc ? doc.clientHeight : 0
      );

      return {
        title: document.title || "",
        scrollHeight,
        bodyTextLength: (body?.innerText || "").trim().length
      };
    });

    const viewport = page.viewportSize();
    const viewportHeight = viewport?.height || 1000;
    const capturePoints = buildCapturePoints(metrics.scrollHeight, viewportHeight);

    const screenshots = [];

    for (let i = 0; i < capturePoints.length; i++) {
      const y = capturePoints[i];

      await page.evaluate((_y) => window.scrollTo(0, _y), y);
      await page.waitForTimeout(500);

      const fileName = `${routeSlug}__seg_${String(i).padStart(2, "0")}.png`;
      const filePath = path.join(screenshotsDir, fileName);

      await page.screenshot({
        path: filePath,
        fullPage: false
      });

      screenshots.push({
        file: fileName,
        y,
        viewportHeight
      });

      totalScreenshots++;
    }

    const lowCoverage = screenshots.length < 3;

    manifest.push({
      url,
      status: "ok",
      title: metrics.title,
      scrollHeight: metrics.scrollHeight,
      viewportHeight,
      bodyTextLength: metrics.bodyTextLength,
      screenshotCount: screenshots.length,
      lowCoverage,
      screenshots
    });

  } catch (err) {
    manifest.push({
      url,
      status: "fail",
      error: String(err && err.message ? err.message : err),
      screenshotCount: 0,
      lowCoverage: true,
      screenshots: []
    });
  }
}

await browser.close();

const summary = {
  routeCount: routes.length,
  screenshotsCount: totalScreenshots,
  okRoutes: manifest.filter(x => x.status === "ok").length,
  failedRoutes: manifest.filter(x => x.status === "fail").length,
  lowCoverageRoutes: manifest.filter(x => x.lowCoverage).map(x => x.url)
};

fs.writeFileSync(
  path.join(outDir, "visual_manifest.json"),
  JSON.stringify(manifest, null, 2)
);

fs.writeFileSync(
  path.join(outDir, "visual_capture_summary.json"),
  JSON.stringify(summary, null, 2)
);
