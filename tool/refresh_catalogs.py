import concurrent.futures
import json
import math
import os
import re
import subprocess
import tempfile
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'catalogs'
HONGGUO = 'https://hongguoduanju.com'
RANKS = {'hongguo': 'hot-real-drama', 'comic': 'hot-comic-drama'}


class Publication(HTMLParser):
    def __init__(self, page):
        super().__init__(convert_charrefs=True)
        self.nodes = []
        self.script_type = None
        self.feed(page)
        self.close()

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == 'script':
            self.script_type = values.get('type', '')

    def handle_endtag(self, tag):
        if tag == 'script':
            self.script_type = None

    def handle_data(self, data):
        if self.script_type == 'application/ld+json':
            obj = json.loads(data)
            self.nodes.extend(obj.get('@graph', [obj]))


def get(url):
    result = subprocess.run(['curl', '--silent', '--show-error', '--max-time', '20',
                             '--retry', '1', '--max-filesize', '2097152', '--proto', '=https',
                             '--write-out', '\n%{http_code}', '--', url],
                            capture_output=True, check=True, timeout=50)
    body, status = result.stdout.rsplit(b'\n', 1)
    if status in (b'404', b'410') or status.startswith(b'3'):
        return ''
    if status != b'200':
        raise ValueError(f'{url} returned HTTP {status.decode()}')
    return body.decode('utf-8')


def publication(url):
    return Publication(get(url))


def duration(url, container='mov'):
    result = subprocess.run(['ffprobe', '-v', 'error', '-rw_timeout', '12000000',
                             '-protocol_whitelist', 'https,tls,tcp,crypto', '-f', container,
                             '-select_streams', 'v:0', '-show_entries',
                             'stream=codec_name:format=duration', '-of', 'json', url],
                            capture_output=True, check=True, timeout=25)
    probe = json.loads(result.stdout)
    seconds = float(probe['format']['duration'])
    if not probe['streams'] or not math.isfinite(seconds) or seconds <= 0:
        raise ValueError(f'Invalid video at {url}')
    return seconds


def hongguo_title(item):
    detail = item['url']
    match = re.fullmatch(re.escape(HONGGUO) + r'/detail\?series_id=(\d+)', detail)
    if not match:
        return None
    series_id = match[1]
    series = next((n for n in publication(detail).nodes if n.get('url') == detail
                   and n.get('@type') in ('TVSeries', 'TVSeason') and n.get('episode')), None)
    if not series:
        return None
    episodes = []
    tags = []
    used = set()
    for entry in sorted(series['episode'], key=lambda e: e['episodeNumber']):
        page = entry['url']
        if not re.fullmatch(re.escape(f'{HONGGUO}/player/{series_id}') + r'(?:/\d+)?', page):
            continue
        video = next((n for n in publication(page).nodes if n.get('@type') == 'VideoObject'
                      and n.get('url') == page and n.get('about', {}).get('@id') == entry['@id']), None)
        if not video:
            continue
        media = video.get('contentUrl', '')
        match = re.fullmatch(re.escape(HONGGUO) + r'/video/public/(\d+)/\d+p\.mp4', media)
        if not match or match[1] in used:
            continue
        actual = duration(media)
        label = f"第{entry['episodeNumber']}集"
        declared = re.fullmatch(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?', video.get('duration', ''))
        total = sum(float(v or 0) * unit for v, unit in zip(declared.groups(), (3600, 60, 1))) if declared else 0
        if not total or abs(actual - total) > 1:
            label += f' · {round(actual)} 秒片段'
        episodes.append({'id': match[1], 'title': label, 'url': media, 'page': page,
                         'durationMs': round(actual * 1000), 'listedMs': round(total * 1000)})
        used.add(match[1])
        tags.extend(video.get('genre') or [])
    if episodes:
        return {'id': series_id, 'title': series['name'], 'tags': list(dict.fromkeys(tags)) or ['短剧'],
                'cover': item.get('image'), 'episodes': episodes}
    return None


def save(name, dramas):
    if not dramas:
        raise ValueError(f'Empty catalog: {name}')
    data = json.dumps({'version': 1, 'dramas': dramas}, ensure_ascii=False, indent=2) + '\n'
    ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=ROOT, delete=False, mode='w', encoding='utf-8', newline='\n') as tmp:
        tmp.write(data)
    os.replace(tmp.name, ROOT / f'{name}.json')
    print(f'{name}: {len(dramas)} titles, {sum(len(d["episodes"]) for d in dramas)} videos')


def poster(record):
    publisher, drama = record
    first = drama['episodes'][0]
    if not re.fullmatch(r'[A-Za-z0-9_-]+', first['id']):
        raise ValueError('Invalid poster ID')
    folder = ROOT.parent / 'posters'
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"{publisher}-{first['id']}.webp"
    encoder = ['-frames:v', '1', '-an', '-vf', 'scale=560:560:force_original_aspect_ratio=decrease',
               '-c:v', 'libwebp', '-quality', '78', '-f', 'image2pipe', 'pipe:1']
    ffmpeg = ['ffmpeg', '-nostdin', '-loglevel', 'error']
    if not re.fullmatch(r'https://p\d+-novel(?:-seo)?\.byteimg\.com/[^\s]+', drama['cover']):
        raise ValueError('Unexpected Hongguo poster host')
    image = subprocess.run(['curl', '-fsS', '--max-time', '15', '--retry', '1', '--max-filesize',
                            '8388608', '--proto', '=https', '--', drama['cover']],
                           capture_output=True, check=True, timeout=40).stdout
    args = ['-protocol_whitelist', 'pipe', '-max_pixels', '25000000', '-i', 'pipe:0']
    encoded = subprocess.run(ffmpeg + args + encoder, input=image, capture_output=True,
                             check=True, timeout=40).stdout
    if encoded[:4] != b'RIFF' or encoded[8:12] != b'WEBP':
        raise ValueError(f'Invalid poster for {first["id"]}')
    with tempfile.NamedTemporaryFile(dir=folder, delete=False) as tmp:
        tmp.write(encoded)
    os.replace(tmp.name, target)


def main():
    covers = set()
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for category, slug in RANKS.items():
            rank = publication(f'{HONGGUO}/rank/{slug}')
            items = next(n['itemListElement'] for n in rank.nodes if n.get('@type') == 'ItemList')
            titles = [d for d in pool.map(hongguo_title, items) if d]
            list(pool.map(poster, ((category, d) for d in titles)))
            save(category, titles)
            covers.update(f"{category}-{d['episodes'][0]['id']}.webp" for d in titles)
    for category in RANKS:
        for old in (ROOT.parent / 'posters').glob(f'{category}-*.webp'):
            if old.name not in covers:
                old.unlink()


if __name__ == '__main__':
    main()
