const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require('playwright-core');

const root = path.resolve(process.argv[2]);
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json' };
let disconnected = false;
const server = http.createServer((req, res) => {
  if (disconnected) { req.socket.destroy(); return; }
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
    const context = await browser.newContext({ viewport: { width: 1000, height: 780 } });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('requestfailed', req => console.error('Request failed', new URL(req.url()).hostname, req.failure()?.errorText));
    page.on('response', res => { if (res.status() >= 400) console.error('HTTP', res.status(), new URL(res.url()).hostname); });
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    await page.locator('flt-semantics-placeholder').dispatchEvent('click');
    const renditions = JSON.parse(fs.readFileSync(path.join(root, 'assets/assets/renditions/index.json'), 'utf8'));
    const titles = [['红果短剧', 'hongguo'], ['红果漫剧', 'comic']].map(([label, file]) => {
      const drama = JSON.parse(fs.readFileSync(path.join(root, 'assets/assets/catalogs', file + '.json'), 'utf8')).dramas[0];
      return [label, drama.title, drama.episodes[0], drama.episode_count];
    });
    for (const [, title] of titles) await page.getByRole('button', { name: new RegExp(title) }).first().waitFor();
    const firstRow = await Promise.all(titles.map(([, title]) => page.getByRole('button', { name: new RegExp(title) }).first().boundingBox()));
    assert(firstRow.every(box => box && box.y >= 0 && box.y + box.height < 780));
    assert(Math.abs(firstRow[0].y - firstRow[1].y) < 2 && firstRow[0].x < firstRow[1].x);
    await page.getByRole('button', { name: '切换为单列' }).press('Enter');
    await page.getByRole('button', { name: '切换为双列' }).press('Enter');
    for (const [publisher, title, episode, total] of titles) {
      console.log('Testing', publisher, title);
      await page.getByRole('checkbox', { name: publisher }).press('Space');
      await page.getByRole('button', { name: new RegExp(title) }).first().press('Enter');
      await page.waitForFunction(() => {
        const video = document.querySelector('video');
        return video?.currentTime >= 1 && video.videoWidth > 0;
      }, null, { timeout: 45000 });
      await page.mouse.move(80, 60);
      await page.getByRole('button', { name: '选集' }).press('Enter');
      await page.getByText(`全 ${total} 集 · 当前可播放 `, { exact: false }).first().waitFor();
      await page.keyboard.press('Escape');
      if (publisher === '红果漫剧' && await page.evaluate(() => document.pictureInPictureEnabled)) {
        await page.mouse.move(80, 80);
        await page.getByRole('button', { name: '小窗播放' }).press('Enter');
        await page.waitForFunction(() => document.pictureInPictureElement?.tagName === 'VIDEO');
        const time = await page.evaluate(() => document.pictureInPictureElement.currentTime);
        await page.waitForFunction(t => document.pictureInPictureElement?.currentTime > t + .4, time);
        await page.evaluate(() => document.exitPictureInPicture());
      }
      if (publisher === '红果短剧') {
        await page.locator('video').first().evaluate(v => { v.currentTime = v.duration * .45; });
        await page.waitForFunction(() => { const v = document.querySelector('video'); return v?.currentTime >= v?.duration * .5; });
        await page.mouse.move(60, 60);
        await page.getByRole('button', { name: '返回', exact: true }).first().evaluate(el => el.click());
        await page.getByRole('button', { name: new RegExp(title) }).first().press('Enter');
        await page.waitForFunction(() => { const v = document.querySelector('video'); return v?.currentTime >= v?.duration * .45; }, null, { timeout: 4500 });
      }
      await page.mouse.move(70, 70);
      await page.getByRole('button', { name: '离线下载' }).first().press('Enter');
      await page.getByRole('button', { name: `下载 ${episode.title}`, exact: true }).press('Enter');
      await page.getByRole('group', { name: `${title} · ${episode.title} 已保存`, exact: true }).waitFor();
      await page.waitForFunction(async hash => {
        const cache = await caches.open('sableen-episodes-v1');
        return !!(await cache.match(new URL(`media/${hash}.mp4`, document.baseURI)));
      }, renditions[episode.sha256]?.sha256 ?? episode.sha256);
      await page.keyboard.press('Escape');
      await page.mouse.move(100, 70);
      assert.equal(page.context().pages().length, 1);
      await page.getByRole('button', { name: '返回', exact: true }).first().evaluate(el => el.click());
      await page.getByRole('tab', { name: '历史纪录' }).waitFor();
    }
    await page.reload();
    await page.locator('flt-semantics-placeholder').dispatchEvent('click');
    await page.getByRole('tab', { name: '历史纪录' }).press('Enter');
    for (const [, title] of titles) await page.getByRole('button', { name: new RegExp(title) }).first().waitFor();
    await page.getByRole('tab', { name: '下载' }).press('Enter');
    disconnected = true;
    await page.context().setOffline(true);
    await page.close();
    const offlinePage = await context.newPage();
    offlinePage.on('pageerror', error => errors.push(error.message));
    await offlinePage.goto(`http://127.0.0.1:${server.address().port}`);
    await offlinePage.locator('flt-semantics-placeholder').dispatchEvent('click');
    await offlinePage.getByRole('tab', { name: '下载' }).press('Enter');
    for (const [, title] of titles) {
      await offlinePage.getByRole('button', { name: new RegExp(title) }).first().press('Enter');
      await offlinePage.waitForFunction(() => {
        const v = document.querySelector('video');
        return v?.currentSrc.startsWith('blob:') && v.videoWidth > 0 && v.currentTime > .5;
      });
      await offlinePage.mouse.move(80, 60);
      await offlinePage.getByRole('button', { name: '返回', exact: true }).first().evaluate(el => el.click());
    }
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
}

test().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => server.close());
