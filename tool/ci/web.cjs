const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require('playwright-core');

const root = path.resolve(process.argv[2]);
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.mp4': 'video/mp4', '.json': 'application/json' };
let disconnected = false;
const server = http.createServer((req, res) => {
  if (disconnected) { req.socket.destroy(); return; }
  const pathname = new URL(req.url, 'http://localhost').pathname;
  const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : decodeURIComponent(pathname)));
  if (!file.startsWith(root + path.sep) || !fs.statSync(file, { throwIfNoEntry: false })?.isFile()) {
    res.writeHead(404).end();
    return;
  }
  const size = fs.statSync(file).size;
  const headers = { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream',
    'Content-Length': size, 'Accept-Ranges': 'bytes',
    'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'credentialless' };
  if (req.headers.range) {
    const range = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range);
    const start = range ? Number(range[1]) : size;
    const end = range?.[2] ? Math.min(size - 1, Number(range[2])) : size - 1;
    if (start > end) return res.writeHead(416, {'Content-Range': `bytes */${size}`}).end();
    res.writeHead(206, {...headers, 'Content-Range': `bytes ${start}-${end}/${size}`, 'Content-Length': end - start + 1});
    fs.createReadStream(file, {start, end}).pipe(res);
    return;
  }
  res.writeHead(200, headers);
  fs.createReadStream(file).pipe(res);
});

function fullEpisodes(drama) {
  const files = new Map(drama.episodes.filter(e => e.sha256 && e.bytes > 0 &&
    e.listedMs > 0 && e.durationMs > 0 && Math.abs(e.listedMs - e.durationMs) <= 1000).map(e => [e.id, e]));
  return drama.published_ids.map(id => files.get(id));
}

async function checkEpisodeTransition(browser, url, drama, renditions) {
  const episodes = fullEpisodes(drama);
  const index = episodes.findIndex(Boolean);
  assert(index >= 0 && episodes[index + 1], `Two consecutive full episodes are needed to verify autoplay for ${drama.title}`);
  const context = await browser.newContext({serviceWorkers: 'block'});
  try {
    const page = await context.newPage();
    await page.goto(url);
    await page.locator('flt-semantics-placeholder').dispatchEvent('click');
    await page.getByRole('button', {name: drama.title, exact: false}).first().press('Enter');
    await page.waitForFunction(() => document.querySelector('video')?.currentTime > .25);
    const element = await page.locator('video').elementHandle();
    const original = await element.evaluate(v => v.currentSrc);
    const filename = e => `${renditions[e.sha256]?.sha256 ?? e.sha256}.mp4`;
    assert(new URL(original).pathname.endsWith('/' + filename(episodes[index])));
    // Trigger the real ended event and observe the next source playing in the same view.
    await element.evaluate(v => { v.currentTime = v.duration - .5; });
    await page.waitForFunction(({element, expected}) => element.isConnected && element.currentSrc.endsWith('/' + expected) &&
      !element.paused && element.videoWidth > 0 && element.currentTime > .25, {element, expected: filename(episodes[index + 1])});
    await page.mouse.move(80, 75);
    await page.getByRole('button', {name: '选集'}).press('Enter');
    if (index % 15 === 14) {
      const start = index + 2;
      await page.getByRole('button', {name: `${start}–${Math.min(start + 14, episodes.length)}`, exact: true}).press('Enter');
      await page.getByRole('button', {name: `${start - 15}–${start - 1}`, exact: true}).press('Enter');
    }
    await page.getByText(episodes[index].title, {exact: true}).last().click();
    await page.waitForFunction(({element, original}) => element.isConnected && element.currentSrc === original &&
      !element.paused && element.currentTime > .25, {element, original});
  } finally {
    await context.close();
  }
}

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
    const charts = [['红果短剧', 'hongguo'], ['红果漫剧', 'comic']].map(([label, file]) =>
      [label, JSON.parse(fs.readFileSync(path.join(root, 'assets/assets/catalogs', file + '.json'), 'utf8')).dramas[0]]);
    const titles = charts.map(([label, drama]) => {
      const episode = fullEpisodes(drama).find(Boolean);
      assert(episode, `No full episode for playback verification of ${drama.title}`);
      return [label, drama.title, episode, drama.episode_count, drama.published_ids.indexOf(episode.id)];
    });
    await checkEpisodeTransition(browser, page.url(), charts[0][1], renditions);
    for (const [, title] of titles) await page.getByRole('button', { name: new RegExp(title) }).first().waitFor();
    const firstRow = await Promise.all(titles.map(([, title]) => page.getByRole('button', { name: new RegExp(title) }).first().boundingBox()));
    assert(firstRow.every(box => box && box.y >= 0 && box.y + box.height < 780));
    assert(Math.abs(firstRow[0].y - firstRow[1].y) < 2 && firstRow[0].x < firstRow[1].x);
    await page.getByRole('button', { name: '切换为单列' }).press('Enter');
    await page.getByRole('button', { name: '切换为双列' }).press('Enter');
    const savedSizes = new Map();
    for (const [publisher, title, episode, total, index] of titles) {
      console.log('Testing', publisher, title);
      await page.getByRole('checkbox', { name: publisher }).press('Space');
      await page.getByRole('button', { name: new RegExp(title) }).first().press('Enter');
      await page.waitForFunction(() => {
        const video = document.querySelector('video');
        return video?.currentTime >= 1 && video.videoWidth > 0;
      }, null, { timeout: 45000 });
      await page.mouse.move(80, 60);
      await page.getByRole('button', { name: '选集' }).press('Enter');
      if (total > 15) {
        const first = Math.floor(index / 15) * 15 + 1;
        await page.getByRole('button', {name: `${first}–${Math.min(first + 14, total)}`, exact: true}).waitFor();
      } else {
        await page.getByText(`全 ${total} 集`, {exact: false}).first().waitFor();
      }
      assert((await page.locator('body').ariaSnapshot()).includes(`全 ${total} 集`));
      await page.keyboard.press('Escape');
      let saved = episode;
      await page.getByRole('button', { name: '1×', exact:true }).press('Enter');
      await page.getByText('1.25×', {exact: true}).last().click();
      await page.waitForFunction(() => document.querySelector('video')?.playbackRate === 1.25);
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
      if (episode.encodings?.length > 1) {
        const alternate = episode.encodings.find(f => f.sha256 !== episode.sha256);
        await page.mouse.move(110, 90);
        await page.getByRole('button', { name: '暂停', exact: true }).last().press('Enter');
        await page.waitForFunction(() => document.querySelector('video')?.paused === true);
        const before = await page.locator('video').first().evaluate(v => ({w: v.videoWidth, h: v.videoHeight, time: v.currentTime}));
        await page.getByRole('button', { name: `${before.w}×${before.h}`, exact: true }).press('Enter');
        await page.getByText(`${alternate.width}×${alternate.height}`, {exact: true}).last().click();
        await page.waitForFunction(({width, height, time}) => {
          const v = document.querySelector('video');
          return v?.paused && v.videoWidth === width && v.videoHeight === height && Math.abs(v.currentTime - time) < .75;
        }, {...alternate, time: before.time});
        saved = alternate;
        savedSizes.set(title, [alternate.width, alternate.height]);
      }
      await page.mouse.move(70, 70);
      await page.getByRole('button', { name: '离线下载' }).first().press('Enter');
      await page.getByRole('button', { name: `下载 ${episode.title}`, exact: true }).press('Enter');
      const downloadedSize = episode.encodings?.find(f => f.sha256 === saved.sha256);
      const suffix = downloadedSize ? ` · ${downloadedSize.width}×${downloadedSize.height}` : '';
      await page.getByRole('group', { name: `${title} · ${episode.title}${suffix} 已保存`, exact: true }).waitFor();
      const digest = renditions[saved.sha256]?.sha256 ?? saved.sha256;
      assert.equal(await page.evaluate(async hash => {
        const cache = await caches.open('sableen-episodes-v1');
        const response = await cache.match(new URL(`media/${hash}.mp4`, document.baseURI));
        const bytes = await response.arrayBuffer();
        const verified = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
        return Array.from(verified, b => b.toString(16).padStart(2, '0')).join('');
      }, digest), digest);
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
      if (savedSizes.has(title)) {
        assert.deepEqual(await offlinePage.locator('video').first().evaluate(v => [v.videoWidth, v.videoHeight]), savedSizes.get(title));
      }
      await offlinePage.mouse.move(80, 60);
      await offlinePage.getByRole('button', { name: '返回', exact: true }).first().evaluate(el => el.click());
    }
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
}

test().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => server.close());
