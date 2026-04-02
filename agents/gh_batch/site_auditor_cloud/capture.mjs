import fs from "fs";
import path from "path";
import { chromium } from "playwright";

const baseUrl = process.argv[2];
const routeFile = process.argv[3];
const outDir = process.argv[4];

const routes = JSON.parse(fs.readFileSync(routeFile, "utf-8"));

const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: 1440, height: 900 }
});

const manifest = [];

for (const url of routes) {
  console.log("CAPTURE:", url);

  try {
    await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });

    const height = await page.evaluate(() => document.body.scrollHeight);
    const step = 800;
    let index = 0;
    let screenshots = [];

    for (let y = 0; y < height; y += step) {
      await page.evaluate((_y) => window.scrollTo(0, _y), y);
      await page.waitForTimeout(500);

      const fileName = `screenshot_${index}.png`;
      const filePath = path.join(outDir, "screenshots", fileName);

      await page.screenshot({ path: filePath });

      screenshots.push(fileName);
      index++;
    }

    manifest.push({
      url,
      status: "ok",
      height,
      segments: screenshots.length,
      screenshots
    });

  } catch (err) {
    console.log("FAIL:", url);

    manifest.push({
      url,
      status: "fail",
      error: err.message
    });
  }
}

await browser.close();

fs.writeFileSync(
  path.join(outDir, "visual_manifest.json"),
  JSON.stringify(manifest, null, 2)
);
