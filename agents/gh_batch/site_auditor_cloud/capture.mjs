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

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

const manifest = [];
let total = 0;

for (const url of routes) {
  console.log("CAPTURE:", url);

  try {
    await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });

    const height = await page.evaluate(() => document.body.scrollHeight);
    const step = 800;

    const shots = [];

    for (let y = 0; y < height; y += step) {
      await page.evaluate((_y) => window.scrollTo(0, _y), y);
      await page.waitForTimeout(400);

      const name = `${slug(url)}_${shots.length}.png`;
      const file = path.join(screenshotsDir, name);

      await page.screenshot({ path: file });

      shots.push(name);
      total++;
    }

    manifest.push({
      url,
      status: "ok",
      screenshotCount: shots.length,
      screenshots: shots
    });

  } catch (err) {
    manifest.push({
      url,
      status: "fail",
      error: String(err),
      screenshotCount: 0
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
  JSON.stringify({
    routes: routes.length,
    screenshots: total
  }, null, 2)
);
