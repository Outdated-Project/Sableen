import concurrent.futures
import json
import math
import os
import re
import subprocess
import tempfile
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'catalogs'
HONGGUO = 'https://hongguoduanju.com'
GUANGZHOU = 'https://www.gzjjjc.gov.cn/ljgzw/ztzl/ljwhwdj/'


class Publication(HTMLParser):
    def __init__(self, page):
        super().__init__(convert_charrefs=True)
        self.nodes = []
        self.links = []
        self.scripts = []
        self.script_type = None
        self.feed(page)
        self.close()

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == 'script':
            self.script_type = values.get('type', '')
        elif tag == 'a' and values.get('title') and values.get('href'):
            self.links.append((values['href'], values['title']))

    def handle_endtag(self, tag):
        if tag == 'script':
            self.script_type = None

    def handle_data(self, data):
        if self.script_type == 'application/ld+json':
            obj = json.loads(data)
            self.nodes.extend(obj.get('@graph', [obj]))
        elif self.script_type is not None and 'var playerOpt =' in data:
            self.scripts.append(data)


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


def cctv_episode(entry):
    pid = entry['guid']
    if not re.fullmatch(r'[a-f0-9]{32}', pid) or entry['vip_flag'] != 0:
        return None
    data = json.loads(get(f'https://vdn.apps.cntv.cn/api/getHttpVideoInfo.do?pid={pid}'))
    if data.get('ack') != 'yes' or any(str(data.get(key)) != expected for key, expected in [
            ('public', '1'), ('play', '1'), ('is_preview', '0'),
            ('is_invalid_copyright', '0'), ('is_protected', '0')]):
        return None
    media = data['hls_url']
    uri = urlsplit(media)
    if uri.scheme != 'https' or not uri.path.endswith('.m3u8') or pid not in uri.path:
        raise ValueError(f'Unexpected HLS URL for {pid}')
    if abs(duration(media, 'hls') - entry['vduration']) > 2:
        raise ValueError(f'Episode duration mismatch: {pid}')
    return {'id': pid, 'title': entry['vbrief'], 'url': media}


def cctv_series(pool):
    media_id = '25uQNfmi0328'
    url = f'https://media.app.cctv.cn/vapi/video/dvplist.do?mid={media_id}&type=1&p=1&n=100'
    catalog = json.loads(get(url))
    entries = sorted(catalog['data'], key=lambda entry: entry['episodes'])
    if not entries or len(entries) != catalog['count'] or any(e['mediaId'] != media_id for e in entries):
        raise ValueError('Unexpected CCTV episode list')
    episodes = [e for e in pool.map(cctv_episode, entries) if e]
    if not episodes:
        raise ValueError('No full episodes currently available from CCTV')
    genres = list(dict.fromkeys(t for e in entries for t in e['keywords'].split(',') if t and t != '短剧'))
    return {'id': media_id, 'title': entries[0]['mediaName'], 'tags': genres or ['短剧'],
            'cover': entries[0]['mediaImg'], 'episodes': episodes}


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
        if total == 0 or actual + 1 < total:
            label += f' · {round(actual)} 秒片段'
        episodes.append({'id': match[1], 'title': label, 'url': media})
        used.add(match[1])
        tags.extend(video.get('genre') or [])
    if episodes:
        return {'id': series_id, 'title': series['name'], 'tags': list(dict.fromkeys(tags)) or ['短剧'],
                'cover': item.get('image'), 'episodes': episodes}
    return None


def guangzhou_episode(link):
    url, title = link
    article = re.fullmatch(r'https?://www\.gzjjjc\.gov\.cn/ljgzw/ztzl/ljwhwdj/content/post_(\d+)\.html', url)
    show = re.search(r'《([^》]+)》', title)
    if not article or not show:
        return None
    page = publication(f'{GUANGZHOU}content/post_{article[1]}.html')
    for script in page.scripts:
        opt, _ = json.JSONDecoder().raw_decode(script.partition('var playerOpt =')[2].lstrip())
        media = json.loads(opt['source']).get('SD', '') if opt.get('format') == 'mp4' else ''
        if urlsplit(media).netloc != 'gdvideo.southcn.com' or not media.startswith('https://'):
            continue
        duration(media)
        episode = {'id': article[1], 'title': title[show.end():].strip() or show[1], 'url': media}
        return show[1], episode, opt.get('cover', '').replace('http://www.gzjjjc.gov.cn/', 'https://www.gzjjjc.gov.cn/')
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
    if publisher == 'guangzhou':
        args = ['-ss', '2', '-rw_timeout', '12000000', '-protocol_whitelist', 'https,tls,tcp',
                '-f', 'mov', '-i', first['url']]
        image = None
    else:
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
    rank = publication(f'{HONGGUO}/rank/hot-search-real-drama')
    items = next(n['itemListElement'] for n in rank.nodes if n.get('@type') == 'ItemList')
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        cctv = cctv_series(pool)
        gz = {}
        for record in pool.map(guangzhou_episode, dict(publication(GUANGZHOU).links).items()):
            if record:
                name, episode, cover = record
                drama = gz.setdefault(name, {'id': name, 'title': name, 'tags': ['廉洁文化'],
                                              'cover': cover or None, 'episodes': []})
                drama['episodes'].append(episode)
        titles = [d for d in pool.map(hongguo_title, items) if d]
        records = [('cctv', cctv)] + [('hongguo', d) for d in titles] + [('guangzhou', d) for d in gz.values()]
        list(pool.map(poster, records))
    if not gz or not titles:
        raise ValueError('Publisher returned no playable titles')
    save('guangzhou', list(gz.values()))
    save('hongguo', titles)
    save('cctv', [cctv])


if __name__ == '__main__':
    main()
