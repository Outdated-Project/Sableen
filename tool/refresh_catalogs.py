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
from publisher_feed import load_feed


ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'catalogs'
HONGGUO = 'https://hongguoduanju.com'
RANKS = {'hongguo': 'hot-real-drama', 'comic': 'hot-comic-drama'}
COMPATIBILITY_CODECS = {'bvc2': 'bvc2', 'hev1': 'hevc', 'hvc1': 'hevc', 'av01': 'av1', 'vp09': 'vp9'}


class Publication(HTMLParser):
    def __init__(self, page):
        super().__init__(convert_charrefs=True)
        self.nodes = []
        self.public_video = {}
        self.series_detail = {}
        self.player_links = set()
        self.script_type = None
        self.feed(page)
        self.close()

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == 'script':
            self.script_type = values.get('type', '')
        elif tag == 'a':
            link = values.get('href') or ''
            if link.startswith('/player/'):
                link = HONGGUO + link
            if link.startswith(HONGGUO + '/player/'):
                self.player_links.add(link)

    def handle_endtag(self, tag):
        if tag == 'script':
            self.script_type = None

    def handle_data(self, data):
        if self.script_type == 'application/ld+json':
            obj = json.loads(data)
            for node in obj if isinstance(obj, list) else [obj]:
                if isinstance(node, dict):
                    self.nodes.extend(n for n in node.get('@graph', [node]) if isinstance(n, dict))
        elif self.script_type == '' and data.lstrip().startswith('_ROUTER_DATA = '):
            state, _ = json.JSONDecoder().raw_decode(data.lstrip()[len('_ROUTER_DATA = '):])
            detail = state.get('loaderData', {}).get('detail_page', {}).get('seriesDetail')
            if isinstance(detail, dict):
                self.series_detail = detail
            for route in state.get('loaderData', {}).values():
                if isinstance(route, dict) and isinstance(route.get('publicVideoSeo'), dict):
                    self.public_video = route['publicVideoSeo']


def get(url):
    for attempt in range(2):
        result = subprocess.run(['curl', '--disable', '--silent', '--show-error', '--max-time', '20',
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
        subprocess.run(['curl', '--disable', '--fail', '--silent', '--show-error', '--max-time', '90',
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


def decode_end(path, duration):
    frames = subprocess.check_output([
        os.environ.get('SABLEEN_FFMPEG', 'ffmpeg'), '-nostdin', '-v', 'error', '-xerror', '-protocol_whitelist', 'file',
        '-ss', f'{max(0, duration - 600) / 1000:.3f}', '-f', 'mov', '-i', str(path),
        '-map', '0:v:0', '-frames:v', '1', '-f', 'framemd5', '-',
    ], timeout=30, text=True)
    if not any(row.startswith('0,') for row in frames.splitlines()):
        raise ValueError(f'Cannot decode video near {duration} ms in {path.name}')


def published_video(doc, series_id, page, *, include_metadata=False):
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
    if not episode or not isinstance(episode.get('video'), dict) or not episode['video'].get('@id'):
        return None
    video = next((n for n in doc.nodes if n.get('@type') == 'VideoObject' and n.get('url') == page
                  and n.get('@id') == episode['video']['@id'] and n.get('about', {}).get('@id') == episode['@id']), None)
    if not video:
        return None
    ids = {match[1]} if match[1] else set()
    public = doc.public_video
    if public:
        if public.get('available') is not True or str(public.get('seriesId')) != series_id:
            return None
        ids.add(str(public.get('itemId')))
    primary = video.get('contentUrl')
    if isinstance(primary, str):
        canonical = re.fullmatch(re.escape(HONGGUO) + r'/video/public/(\d+)/\d+p\.mp4', primary)
        if canonical:
            ids.add(canonical[1])
    if len(ids) != 1 or not re.fullmatch(r'[0-9]+', item_id := ids.pop()):
        return None
    # JSON-LD allows a VideoObject to refer to MediaObjects elsewhere in its graph.
    entries = video.get('encoding') or []
    encodings = []
    for entry in entries if isinstance(entries, list) else [entries]:
        if not isinstance(entry, dict):
            continue
        if set(entry) == {'@id'}:
            matches = [n for n in doc.nodes if n.get('@id') == entry['@id']]
            if len(matches) != 1:
                continue
            entry = matches[0]
        about = entry.get('about')
        if about is None or isinstance(about, dict) and about.get('@id') == episode['@id']:
            encodings.append(entry)
    video = {**video, 'encoding': encodings}
    if include_metadata or public_encodings(video, item_id):
        return item_id, episode['episodeNumber'], video
    return None


def public_encodings(video, item_id):
    urls = []
    entries = video.get('encoding') or []
    for entry in [video, *(entries if isinstance(entries, list) else [entries])]:
        if not isinstance(entry, dict):
            continue
        url = entry.get('contentUrl')
        if (not isinstance(url, str) or not url.isascii() or '\\' in url or any(c.isspace() for c in url)
                or not re.match(r'^https://(?:[a-zA-Z0-9-]+\.)*hongguoduanju\.com/', url)):
            continue
        uri = urlsplit(url)
        if uri.query or uri.fragment or not uri.path.lower().endswith('.mp4'):
            continue
        canonical = re.fullmatch(r'/video/public/(\d+)/\d+p\.mp4', uri.path)
        if (not canonical or canonical[1] == item_id) and url not in urls:
            urls.append(url)
    return urls


def listed_ms(video):
    declared = re.fullmatch(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?', video.get('duration', ''))
    return round(1000 * sum(float(v or 0) * unit for v, unit in zip(declared.groups(), (3600, 60, 1)))) if declared else 0


def published_series(detail):
    match = re.fullmatch(re.escape(HONGGUO) + r'/detail\?series_id=(\d+)', detail)
    if not match:
        return None
    doc = publication(detail)
    seasons = [n for n in doc.nodes if n.get('url') == detail and n.get('@type') in ('TVSeries', 'TVSeason')
               and type(n.get('numberOfEpisodes')) is int]
    series = next((n for n in seasons if n.get('episode')), seasons[0] if seasons else None)
    if series is None:
        return None
    metadata = doc.series_detail
    ids = metadata.get('vid_list')
    if (metadata.get('series_id') != match[1] or not isinstance(ids, list)
            or len(ids) != series.get('numberOfEpisodes') or not ids
            or not all(isinstance(item, str) and re.fullmatch('[0-9]+', item) for item in ids)
            or len(set(ids)) != len(ids)):
        raise ValueError(f'Invalid published episode list for {detail}')
    # Only follow player links the publisher actually includes on the detail page.
    listed = series.get('episode') or []
    entries = [e for e in (listed if isinstance(listed, list) else [listed])
               if isinstance(e, dict) and isinstance(e.get('url'), str) and type(e.get('episodeNumber')) is int
               and e.get('@id') == e['url'] + '#episode']
    known = {entry['url'] for entry in entries}
    base = f'{HONGGUO}/player/{match[1]}'
    numbers = {item: i for i, item in enumerate(ids, start=1)}
    for link in sorted(doc.player_links - known):
        player = re.fullmatch(re.escape(base) + r'(?:/([0-9]+))?', link)
        if player and (number := numbers.get(player[1] or ids[0])):
            entries.append({'url': link, '@id': link + '#episode', 'episodeNumber': number})
    return {**series, 'episode': entries, 'published_ids': ids}


def quality_files(primary, verified, listed):
    """Keep one interchangeable file per decoded size, with the default first."""
    _, duration, _, _, _, _ = primary
    sizes = set()
    files = []
    for candidate in [primary, *sorted(verified, key=lambda v: v[5] != 'avc1')]:
        url, actual, width, height, evidence, codec = candidate
        if ((width, height) in sizes or abs(actual - duration) > 250
                or (listed and (abs(actual - listed) <= 1000) != (abs(duration - listed) <= 1000))
                or (candidate != primary and codec != 'avc1' and codec not in COMPATIBILITY_CODECS)):
            continue
        files.append({'width': width, 'height': height, 'url': url, **evidence})
        sizes.add((width, height))
    return files if len(files) > 1 else []


def playable_encodings(verified, listed, folder):
    from transcode_bytevc2 import prepare_rendition
    candidates = [v for v in verified if v[5] == 'avc1' or v[5] in COMPATIBILITY_CODECS]
    converted = {}
    while candidates:
        primary = max(candidates, key=lambda v: (
            bool(listed) and abs(v[1] - listed) <= 1000,
            min(v[2:4]) >= 1080 and max(v[2:4]) >= 1920, v[2] * v[3], v[5] == 'avc1', v[1]))
        choices = quality_files(primary, candidates, listed)
        urls = {primary[0], *(file['url'] for file in choices)}
        needed = {}
        for candidate in candidates:
            url, _, _, _, evidence, tag = candidate
            if url not in urls or tag not in COMPATIBILITY_CODECS:
                continue
            digest = evidence['sha256']
            try:
                if digest not in converted:
                    converted[digest] = prepare_rendition(url, evidence, folder, tag)
                needed[digest] = converted[digest]
            except (ValueError, subprocess.SubprocessError, OSError) as error:
                print(f'Cannot prepare {tag} file {digest}: {error}', flush=True)
                candidates = [c for c in candidates if c != candidate]
                break
        else:
            return primary, choices, needed
    raise ValueError('No verified encoding could be prepared for playback')


def episode_sources(resolved, item_id, number, delivery):
    video = {}
    if resolved:
        if resolved[:2] != (item_id, number):
            raise ValueError(f'Published episode identity changed for {item_id}')
        video = resolved[2]
    total = listed_ms(video)
    urls = public_encodings(video, item_id)
    if delivery:
        if number != delivery.number or (total and abs(total - delivery.duration_ms) > 1000):
            raise ValueError(f'Publisher feed disagrees with the episode listing for {item_id}')
        total = total or delivery.duration_ms
        urls = list(dict.fromkeys([*urls, *delivery.hashes]))
    return total, urls


def hongguo_title(item, feed=None):
    detail = item['url']
    series = published_series(detail)
    if not series:
        return None
    series_id = detail.rsplit('=', 1)[1]
    episodes = []
    tags = []
    used = set()
    supplied = (feed or {}).get(series_id, {})
    entries = list(series['episode'])
    listed_numbers = {entry['episodeNumber'] for entry in entries}
    for item_id, delivery in supplied.items():
        number = delivery.number
        if number > len(series['published_ids']) or series['published_ids'][number-1] != item_id:
            raise ValueError(f'Publisher feed disagrees with the episode order for {series_id}/{item_id}')
        if number not in listed_numbers:
            page = f'{HONGGUO}/player/{series_id}/{item_id}'
            entries.append({'url': page, '@id': page + '#episode', 'episodeNumber': number})
    for entry in sorted(entries, key=lambda e: e['episodeNumber']):
        page = entry['url']
        match = re.fullmatch(re.escape(f'{HONGGUO}/player/{series_id}') + r'(?:/(\d+))?', page)
        number = entry['episodeNumber']
        if not match or type(number) is not int or not 1 <= number <= len(series['published_ids']):
            continue
        item_id = series['published_ids'][number-1]
        if (match[1] or series['published_ids'][0]) != item_id or entry['@id'] != page + '#episode':
            raise ValueError(f'Episode order changed for {page}')
        if item_id in used:
            continue
        delivery = supplied.get(item_id)
        resolved = (published_video(publication(page), series_id, page, include_metadata=delivery is not None)
                    if number in listed_numbers else None)
        total, urls = episode_sources(resolved, item_id, number, delivery)
        if not urls:
            continue
        verified = []
        for url in urls:
            supplied_file = delivery is not None and url in delivery.hashes
            try:
                with media_snapshot(url) as path:
                    actual, width, height, codec = video_track(path)
                    evidence = fingerprint(path)
                    if supplied_file:
                        if (evidence['sha256'] != delivery.hashes[url] or abs(actual - delivery.duration_ms) > 1000
                                or abs(actual - total) > 1000 or codec not in {'avc1', *COMPATIBILITY_CODECS}):
                            raise ValueError(f'Publisher file does not match the full episode {item_id}')
                        decode_end(path, actual)
                    verified.append((url, actual, width, height, evidence, codec))
            except (subprocess.SubprocessError, ValueError, KeyError) as error:
                if supplied_file:
                    raise
                print(f'Unavailable published media on {page}: {error}', flush=True)
        if not verified:
            raise ValueError(f'No usable published media on {page}')
        primary, choices, converted = playable_encodings(verified, total, ROOT.parent / 'renditions')
        media, actual, _, _, evidence, _ = primary
        if delivery:
            selected_sizes = {(primary[2], primary[3]), *((f['width'], f['height']) for f in choices)}
            if abs(actual - total) > 1000 or any(v[2:4] not in selected_sizes for v in verified if v[0] in delivery.hashes):
                raise ValueError(f'Incomplete publisher renditions for {item_id}')
        mirrors = [url for url, _, _, _, other, _ in verified if url != media and other == evidence][:3]
        label = f'第{number}集'
        if not total or abs(actual - total) > 1000:
            label += f' · {round(actual / 1000)} 秒片段'
        episodes.append({'id': item_id, 'title': label, 'url': media, 'page': page,
                         'durationMs': actual, 'listedMs': total, **evidence,
                         **({'mirrors': mirrors} if mirrors else {})})
        if choices:
            episodes[-1]['encodings'] = choices
        if converted:
            episodes[-1]['_renditions'] = converted
        used.add(item_id)
        if resolved:
            tags.extend(resolved[2].get('genre') or [])
    if episodes:
        return {'id': series_id, 'title': series['name'], 'tags': list(dict.fromkeys(tags)) or ['短剧'],
                'cover': item.get('image'), 'episode_count': series.get('numberOfEpisodes'),
                'published_ids': series['published_ids'], 'episodes': episodes}
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
    prepared = {}
    feed_url = os.environ.get('SABLEEN_PUBLISHER_FEED')
    feed = load_feed(feed_url)
    existing = {}
    if feed_url:
        for category in RANKS:
            existing[category] = json.loads((ROOT / f'{category}.json').read_bytes())['dramas']
        unknown = feed.keys() - {d['id'] for dramas in existing.values() for d in dramas}
        if unknown:
            raise ValueError(f'Publisher feed contains series outside these catalogs: {sorted(unknown)}')
    with (concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool,
          concurrent.futures.ThreadPoolExecutor(max_workers=2) as images):
        for category, slug in RANKS.items():
            if feed_url:
                items = [{'url': f'{HONGGUO}/detail?series_id={d["id"]}', 'image': d.get('cover')}
                         for d in existing[category]]
            else:
                rank = publication(f'{HONGGUO}/rank/{slug}')
                items = next(n['itemListElement'] for n in rank.nodes if n.get('@type') == 'ItemList')
            titles, pending, primary = [], [], {}
            for drama in pool.map(lambda item: hongguo_title(item, feed), items):
                if drama is None:
                    continue
                for episode in drama['episodes']:
                    renditions.update(episode.pop('_renditions', {}))
                titles.append(drama)
                url = drama.get('cover')
                if url not in primary:
                    primary[url] = images.submit(cover_image, url)
                pending.append(images.submit(poster, category, drama, primary[url]))
            for future in pending:
                future.result()
            if not titles or (feed_url and len(titles) != len(items)):
                raise ValueError(f'Incomplete refresh for {category}')
            prepared[category] = titles
            covers.update(f"{category}-{d['episodes'][0]['id']}.webp" for d in titles)
    folder = ROOT.parent / 'renditions'
    # Keep both generations playable while the two catalogs are being replaced.
    folder.mkdir(parents=True, exist_ok=True)
    index = folder / 'index.json'
    previous = json.loads(index.read_bytes()) if index.exists() else {}
    write_renditions(folder, {**previous, **renditions})
    for category, titles in prepared.items():
        save(category, titles)
    write_renditions(folder, renditions)
    retained = {r['sha256'] for r in renditions.values()}
    for old in folder.glob('*.mp4'):
        if re.fullmatch('[a-f0-9]{64}', old.stem) and old.stem not in retained:
            old.unlink()
    for category in RANKS:
        for old in (ROOT.parent / 'posters').glob(f'{category}-*.webp'):
            if old.name not in covers:
                old.unlink()


def write_renditions(folder, renditions):
    with tempfile.NamedTemporaryFile(dir=folder, delete=False, mode='w', encoding='utf-8') as index:
        json.dump(renditions, index, indent=2, sort_keys=True)
        index.write('\n')
    os.replace(index.name, folder / 'index.json')


if __name__ == '__main__':
    main()
