import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { chromium } from 'playwright';

const MIN_CAPTURE_SIZE_BYTES = 10000;

function slugForUrl(url) {
  return crypto.createHash('sha1').update(url).digest('hex').slice(0, 10);
}

function readInput(inputPath) {
  const parsed = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  return {
    pages: Array.isArray(parsed.pages) ? parsed.pages : [],
    screenshotsDir: parsed.screenshots_dir,
    viewport: parsed.viewport || { width: 1366, height: 768 }
  };
}

async function settlePage(page) {
  await page.waitForSelector('body', { timeout: 10000 });
  try { await page.waitForLoadState('networkidle', { timeout: 7000 }); } catch {}
  await page.waitForTimeout(800);
}

async function captureSegments(page, descriptor, dir) {
  const slug = slugForUrl(descriptor.url);
  const vpH = page.viewportSize()?.height || 768;

  const total = await page.evaluate(() =>
    Math.max(
      document.documentElement.scrollHeight,
      document.body.scrollHeight
    )
  );

  const anchors = [0, Math.max(0, total/2 - vpH/2), Math.max(0, total - vpH)];
  const names = ['top','mid','bottom'];
  const out = [];

  for (let i=0;i<3;i++) {
    await page.evaluate(y=>window.scrollTo(0,y), anchors[i]);
    await page.waitForTimeout(250);

    const file = `page-${String(descriptor.index).padStart(2,'0')}-${slug}-${names[i]}.png`;
    const p = path.join(dir,file);

    let status='ok', err='', size=0;

    try {
      await page.screenshot({ path:p });
      const st = fs.statSync(p);
      size = st.size;
      if (size < MIN_CAPTURE_SIZE_BYTES) {
        status='empty_capture';
        err=`too small ${size}`;
      }
    } catch(e){
      status='render_fail';
      err=String(e);
    }

    out.push({segment:names[i],file:`screenshots/${file}`,size_bytes:size,status,error:err});
  }

  return out;
}

async function run(){
  const [inp,outp]=process.argv.slice(2);
  if(!inp||!outp) throw new Error('Usage');

  const {pages,screenshotsDir,viewport}=readInput(inp);
  fs.mkdirSync(screenshotsDir,{recursive:true});

  const manifest={
    status:'SUCCESS',
    requested_pages:pages.length,
    processed_pages:0,
    failed_pages:0,
    pages:[]
  };

  const browser=await chromium.launch();
  const ctx=await browser.newContext({viewport});

  for(const d of pages){
    const p=await ctx.newPage();
    const r={index:d.index,url:d.url,status:'SUCCESS',error:'',captures:[]};

    try{
      await p.goto(d.url,{timeout:25000});
      await settlePage(p);
      r.captures=await captureSegments(p,d,screenshotsDir);
      if(r.captures.some(c=>c.status!=='ok')){
        r.status='PARTIAL';
        manifest.failed_pages++;
      }
      manifest.processed_pages++;
    }catch(e){
      r.status='FAIL';
      r.error=String(e);
      manifest.failed_pages++;
    }

    manifest.pages.push(r);
    await p.close();
  }

  if(manifest.processed_pages===0) manifest.status='FAIL';
  else if(manifest.failed_pages>0) manifest.status='PARTIAL';

  fs.writeFileSync(outp,JSON.stringify(manifest,null,2));
  await ctx.close();
  await browser.close();
}

run().catch(e=>{console.error(e);process.exit(1);});
