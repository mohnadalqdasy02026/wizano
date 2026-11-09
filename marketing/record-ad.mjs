import { chromium } from 'playwright';
import path from 'path';
import fs from 'fs';

const dir = process.cwd();
const htmlPath = path.join(dir, 'wizano-ad-preview-enhanced.html');
const url = 'file:///' + htmlPath.replace(/\\/g, '/');

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1080, height: 1350 },
  deviceScaleFactor: 1,
  recordVideo: {
    dir: dir,
    size: { width: 1080, height: 1350 }
  }
});

const page = await context.newPage();
await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(39000);

await page.close();
await context.close();
await browser.close();

const videos = fs.readdirSync(dir).filter(f => f.endsWith('.webm'));
if (videos.length > 0) {
  const src = path.join(dir, videos[0]);
  const dest = path.join(dir, 'wizano-ad-1080x1350.mp4');
  fs.renameSync(src, dest);
  console.log(dest);
} else {
  console.log('NO_VIDEO');
}
