const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require('playwright-core');

const root = path.resolve(process.argv[2]);
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const pathname = new URL(req.url, 'http://localhost').pathname;
  const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : decodeURIComponent(pathname)));
  if (!file.startsWith(root + path.sep) || !fs.statSync(file, { throwIfNoEntry: false })?.isFile()) {
    res.writeHead(404).end();
    return;
  }
  res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream',
    'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'credentialless' });
  fs.createReadStream(file).pipe(res);
});

async function test() {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ channel: 'chrome' });
  try {
    const page = await browser.newPage({ viewport: { width: 1000, height: 780 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('requestfailed', req => console.error('Request failed', new URL(req.url()).hostname, req.failure()?.errorText));
    page.on('response', res => { if (res.status() >= 400) console.error('HTTP', res.status(), new URL(res.url()).hostname); });
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    await page.locator('flt-semantics-placeholder').dispatchEvent('click');
    const titles = [['央视频剧场', '梦笔不能停'], ['广州微短剧', '源起'], ['红果片段', '做兄弟，在心中']];
    for (const [publisher, title] of titles) {
      console.log('Testing', publisher, title);
      await page.getByRole('checkbox', { name: publisher }).press('Space');
      await page.getByRole('button', { name: new RegExp(title) }).first().press('Enter');
      await page.waitForFunction(() => {
        const video = document.querySelector('video');
        return video?.currentTime >= 1 && video.videoWidth > 0;
      }, null, { timeout: 45000 });
      if (title === '梦笔不能停') {
        await page.locator('video').first().evaluate(v => { v.currentTime = 30; });
        await page.waitForFunction(() => document.querySelector('video')?.currentTime >= 31);
        await page.getByRole('button', { name: '返回', exact: true }).first().evaluate(el => el.click());
        await page.getByRole('button', { name: new RegExp(title) }).first().press('Enter');
        await page.waitForFunction(() => document.querySelector('video')?.currentTime >= 30, null, { timeout: 18000 });
      }
      await page.getByRole('button', { name: '返回', exact: true }).first().evaluate(el => el.click());
      await page.getByRole('tab', { name: '历史' }).waitFor();
    }
    await page.reload();
    await page.locator('flt-semantics-placeholder').dispatchEvent('click');
    await page.getByRole('tab', { name: '历史' }).click();
    for (const [, title] of titles) await page.getByRole('button', { name: new RegExp(title) }).first().waitFor();
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
}

test().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => server.close());
