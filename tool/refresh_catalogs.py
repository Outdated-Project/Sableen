import concurrent.futures
from contextlib import contextmanager
import hashlib
import json
import math
import os
import re
import subprocess
import tempfile
import time
from urllib.parse import urlsplit
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'catalogs'
HONGGUO = 'https://hongguoduanju.com'
RANKS = {'hongguo': 'hot-real-drama', 'comic': 'hot-comic-drama'}


class Publication(HTMLParser):
    def __init__(self, page):
        super().__init__(convert_charrefs=True)
        self.nodes = []
        self.public_video = {}
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
        elif self.script_type == '' and data.lstrip().startswith('_ROUTER_DATA = '):
            state, _ = json.JSONDecoder().raw_decode(data.lstrip()[len('_ROUTER_DATA = '):])
            for route in state.get('loaderData', {}).values():
                if isinstance(route, dict) and isinstance(route.get('publicVideoSeo'), dict):
                    self.public_video = route['publicVideoSeo']


def get(url):
    for attempt in range(2):
        result = subprocess.run(['curl', '--silent', '--show-error', '--max-time', '20',
                                 '--retry', '1', '--max-filesize', '2097152', '--proto', '=https',
                                 '--write-out', '\n%{http_code}', '--', url],
                                capture_output=True, check=True, timeout=50)
        body, status = result.stdout.rsplit(b'\n', 1)
        if status in (b'404', b'410') or status.startswith(b'3'):
            return ''
        if status != b'200':
            raise ValueError(f'{url} returned HTTP {status.decode()}')
        if body.strip():
            return body.decode('utf-8')
        if attempt == 0:
            time.sleep(0.4)
    raise ValueError(f'Empty publication at {url}')


def publication(url):
    return Publication(get(url))


@contextmanager
def media_snapshot(url):
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'episode.mp4'
        subprocess.run(['curl', '--fail', '--silent', '--show-error', '--max-time', '90',
                        '--retry', '1', '--max-filesize', '536870912', '--proto', '=https',
                        '--output', str(path), '--', url], check=True, timeout=190)
        yield path


def fingerprint(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return {'bytes': path.stat().st_size, 'sha256': digest.hexdigest()}


def video_track(path):
    result = subprocess.run([os.environ.get('SABLEEN_FFPROBE', 'ffprobe'), '-v', 'error', '-protocol_whitelist', 'file', '-f', 'mov',
                             '-select_streams', 'v:0', '-show_entries',
                             'stream=width,height,duration,codec_tag_string:format=duration', '-of', 'json', str(path)],
                            capture_output=True, check=True, timeout=25)
    probe = json.loads(result.stdout)
    track = next(iter(probe['streams']), {})
    seconds = float(track.get('duration', probe['format']['duration']))
    width, height = track.get('width', 0), track.get('height', 0)
    if not math.isfinite(seconds) or seconds <= 0 or min(width, height) <= 0:
        raise ValueError(f'Invalid video at {path}')
    return round(seconds * 1000), width, height, track['codec_tag_string']


def published_video(doc, series_id, page):
    """Follow the public season → episode → video links for this exact player page."""
    base = f'{HONGGUO}/player/{series_id}'
    match = re.fullmatch(re.escape(base) + r'(?:/(\d+))?', page)
    if not match:
        return None
    detail = f'{HONGGUO}/detail?series_id={series_id}'
    episode = next((n for n in doc.nodes if n.get('@type') == 'TVEpisode' and n.get('url') == page
                    and n.get('@id') == page + '#episode' and (
                        n.get('partOfSeason', {}).get('@id') == detail + '#season' or
                        n.get('partOfSeries', {}).get('@id') == detail + '#series')), None)
    if not episode or not episode.get('video', {}).get('@id'):
        return None
    video = next((n for n in doc.nodes if n.get('@type') == 'VideoObject' and n.get('url') == page
                  and n.get('@id') == episode['video']['@id'] and n.get('about', {}).get('@id') == episode['@id']), None)
    if not video or not video.get('contentUrl'):
        return None
    uri = urlsplit(video['contentUrl'])
    if (uri.scheme != 'https' or uri.netloc != urlsplit(HONGGUO).netloc or not uri.path.endswith('.mp4')
            or uri.fragment or uri.query or not video['contentUrl'].isascii() or '\\' in video['contentUrl']):
        return None
    ids = {match[1]} if match[1] else set()
    public = doc.public_video
    if public:
        if public.get('available') is not True or str(public.get('seriesId')) != series_id:
            return None
        ids.add(str(public.get('itemId')))
    canonical = re.fullmatch(r'/video/public/(\d+)/\d+p\.mp4', uri.path)
    if canonical:
        ids.add(canonical[1])
    if len(ids) != 1 or not re.fullmatch(r'[0-9]+', item_id := ids.pop()):
        return None
    return item_id, episode['episodeNumber'], video


def public_encodings(video, item_id):
    urls = [video['contentUrl']]
    entries = video.get('encoding') or []
    for entry in entries if isinstance(entries, list) else [entries]:
        if not isinstance(entry, dict):
            continue
        url = entry.get('contentUrl')
        if not isinstance(url, str) or not re.fullmatch(re.escape(HONGGUO) + r'/[\w./%-]+\.mp4', url, flags=re.ASCII):
            continue
        canonical = re.fullmatch(r'/video/public/(\d+)/\d+p\.mp4', urlsplit(url).path)
        if (not canonical or canonical[1] == item_id) and url not in urls:
            urls.append(url)
    return urls


def listed_ms(video):
    declared = re.fullmatch(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?', video.get('duration', ''))
    return round(1000 * sum(float(v or 0) * unit for v, unit in zip(declared.groups(), (3600, 60, 1)))) if declared else 0


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
        resolved = published_video(publication(page), series_id, page)
        if not resolved:
            continue
        item_id, number, video = resolved
        if item_id in used or number != entry['episodeNumber'] or entry['@id'] != page + '#episode':
            continue
        total = listed_ms(video)
        verified = []
        for url in public_encodings(video, item_id):
            try:
                with media_snapshot(url) as path:
                    actual, width, height, codec = video_track(path)
                    verified.append((url, actual, width, height, fingerprint(path), codec))
            except (subprocess.SubprocessError, ValueError, KeyError) as error:
                print(f'Unavailable published media on {page}: {error}', flush=True)
        if not verified:
            raise ValueError(f'No usable published media on {page}')
        # Prefer a full episode, then the highest measured resolution.
        media, actual, _, _, evidence, codec = max(verified, key=lambda v: (
            bool(total) and abs(v[1] - total) <= 1000,
            min(v[2:4]) >= 1080 and max(v[2:4]) >= 1920, v[2] * v[3], v[1]))
        mirrors = [url for url, _, _, _, other, _ in verified if url != media and other == evidence][:3]
        label = f'第{number}集'
        if not total or abs(actual - total) > 1000:
            label += f' · {round(actual / 1000)} 秒片段'
        episodes.append({'id': item_id, 'title': label, 'url': media, 'page': page,
                         'durationMs': actual, 'listedMs': total, **evidence,
                         **({'mirrors': mirrors} if mirrors else {})})
        if codec == 'bvc2':
            from transcode_bytevc2 import prepare_rendition
            episodes[-1]['_rendition'] = prepare_rendition(media, evidence, ROOT.parent / 'renditions')
        used.add(item_id)
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


def encode_poster(args, image=None):
    encoder = ['-frames:v', '1', '-an', '-vf', 'scale=560:560:force_original_aspect_ratio=decrease',
               '-c:v', 'libwebp', '-quality', '78', '-f', 'image2pipe', 'pipe:1']
    ffmpeg = ['ffmpeg', '-nostdin', '-loglevel', 'error']
    encoded = subprocess.run(ffmpeg + args + encoder, input=image, capture_output=True,
                             check=True, timeout=20).stdout
    if encoded[:4] != b'RIFF' or encoded[8:12] != b'WEBP':
        raise ValueError('Invalid WebP output')
    return encoded


def cover_image(url):
    if not url or not re.fullmatch(r'https://p\d+-novel(?:-seo)?\.byteimg\.com/[^\s]+', url):
        raise ValueError('No supported publisher cover')
    image = subprocess.run(['curl', '-fsS', '--max-time', '15', '--retry', '1', '--max-filesize',
                            '8388608', '--proto', '=https', '--', url],
                           capture_output=True, check=True, timeout=40).stdout
    args = ['-protocol_whitelist', 'pipe', '-max_pixels', '25000000', '-i', 'pipe:0']
    return encode_poster(args, image)


def poster(publisher, drama, primary):
    first = drama['episodes'][0]
    if not re.fullmatch(r'[0-9]+', first['id']):
        raise ValueError('Invalid poster ID')
    folder = ROOT.parent / 'posters'
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"{publisher}-{first['id']}.webp"
    try:
        encoded = primary.result()
    except (ValueError, subprocess.SubprocessError):
        # A missing cover can use a frame from this exact verified episode.
        with media_snapshot(first['url']) as path:
            if fingerprint(path)['sha256'] != first['sha256']:
                raise ValueError(f'Media changed while generating {target.name}')
            encoded = encode_poster(['-protocol_whitelist', 'file', '-max_pixels', '25000000',
                                     '-f', 'mov', '-i', str(path)])
    with tempfile.NamedTemporaryFile(dir=folder, delete=False) as tmp:
        tmp.write(encoded)
    os.replace(tmp.name, target)


def main():
    covers = set()
    renditions = {}
    with (concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool,
          concurrent.futures.ThreadPoolExecutor(max_workers=2) as images):
        for category, slug in RANKS.items():
            rank = publication(f'{HONGGUO}/rank/{slug}')
            items = next(n['itemListElement'] for n in rank.nodes if n.get('@type') == 'ItemList')
            titles, pending, primary = [], [], {}
            for drama in pool.map(hongguo_title, items):
                if drama is None:
                    continue
                for episode in drama['episodes']:
                    if rendition := episode.pop('_rendition', None):
                        renditions[episode['sha256']] = rendition
                titles.append(drama)
                url = drama.get('cover')
                if url not in primary:
                    primary[url] = images.submit(cover_image, url)
                pending.append(images.submit(poster, category, drama, primary[url]))
            for future in pending:
                future.result()
            save(category, titles)
            covers.update(f"{category}-{d['episodes'][0]['id']}.webp" for d in titles)
    folder = ROOT.parent / 'renditions'
    with tempfile.NamedTemporaryFile(dir=folder, delete=False, mode='w', encoding='utf-8') as index:
        json.dump(renditions, index, indent=2, sort_keys=True)
        index.write('\n')
    os.replace(index.name, folder / 'index.json')
    retained = {r['sha256'] for r in renditions.values()}
    for old in folder.glob('*.mp4'):
        if re.fullmatch('[a-f0-9]{64}', old.stem) and old.stem not in retained:
            old.unlink()
    for category in RANKS:
        for old in (ROOT.parent / 'posters').glob(f'{category}-*.webp'):
            if old.name not in covers:
                old.unlink()


if __name__ == '__main__':
    main()
