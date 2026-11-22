"""Verify the bundled Hongguo media against its public player metadata."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publisher_feed import load_feed
from refresh_catalogs import (COMPATIBILITY_CODECS, HONGGUO, RANKS, ROOT, decode_end, episode_sources, video_track,
                              fingerprint, media_snapshot, publication, published_series, published_video)


def check_file(path, source_hash):
    duration, width, height, codec = video_track(path)
    if codec != 'avc1' and codec not in COMPATIBILITY_CODECS:
        raise ValueError(f'Unsupported playback codec {codec} for {source_hash}')
    decode_end(path, duration)
    if codec in COMPATIBILITY_CODECS:
        record = json.loads((ROOT.parent / 'renditions/index.json').read_bytes())[source_hash]
        asset = ROOT.parent / 'renditions' / (record['sha256'] + '.mp4')
        if fingerprint(asset) != record:
            raise ValueError(f'Converted media changed for {source_hash}')
        actual, w, h, tag = video_track(asset)
        if tag != 'avc1' or abs(duration - actual) > 100 or (width, height) != (w, h):
            raise ValueError(f'Converted track differs from source for {source_hash}')
        decode_end(asset, actual)
    return duration, width, height, codec


def check(record, feed=None, listed_pages=None):
    series, episode = record
    page = episode['page']
    if not re.fullmatch(re.escape(HONGGUO) + rf'/player/{re.escape(series)}(?:/{re.escape(episode["id"])})?', page):
        raise ValueError('Invalid player page')
    media = episode['url']
    item_id = episode['id']
    delivery = (feed or {}).get(series, {}).get(item_id)
    from_page = not delivery or listed_pages is None or page in listed_pages[series]
    resolved = published_video(publication(page), series, page, include_metadata=delivery is not None) if from_page else None
    if not resolved and not delivery:
        raise ValueError(f'Published episode or video changed on {page}')
    number = delivery.number if delivery else resolved[1]
    listed, urls = episode_sources(resolved, item_id, number, delivery)
    if media not in urls:
        raise ValueError(f'Published media changed on {page}')
    for mirror in episode.get('mirrors', []):
        if mirror not in urls:
            raise ValueError(f'Unlisted mirror on {page}')
        with media_snapshot(mirror) as path:
            if (fingerprint(path)['sha256'] != episode['sha256'] or
                    delivery and delivery.hashes.get(mirror, episode['sha256']) != episode['sha256']):
                raise ValueError(f'Mirror bytes changed on {page}')
    with media_snapshot(media) as path:
        if any(episode.get(key) != value for key, value in fingerprint(path).items()):
            raise ValueError(f'Media bytes changed on {page}')
        measured, width, height, codec = check_file(path, episode['sha256'])
    sizes = set()
    checked_urls = {media, *episode.get('mirrors', [])}
    for encoding in episode.get('encodings', []):
        url = encoding['url']
        if url not in urls:
            raise ValueError(f'Unlisted encoding on {page}')
        if url == media:
            fields = {'sha256': episode['sha256'], 'bytes': episode['bytes']}
            w, h = width, height
        else:
            with media_snapshot(url) as path:
                fields = fingerprint(path)
                duration, w, h, tag = check_file(path, fields['sha256'])
                if (abs(duration - measured) > 250 or (tag != 'avc1' and tag not in COMPATIBILITY_CODECS)
                        or (abs(duration - listed) <= 1000) != (abs(measured - listed) <= 1000)):
                    raise ValueError(f'Non-interchangeable encoding on {page}')
        if (w, h) in sizes or encoding != {'url': url, 'width': w, 'height': h, **fields}:
            raise ValueError(f'Encoding dimensions or bytes changed on {page}')
        sizes.add((w, h))
        checked_urls.add(url)
    if sizes and (len(sizes) < 2 or media not in {e['url'] for e in episode['encodings']}):
        raise ValueError(f'Invalid default encoding on {page}')
    if abs(measured - episode['durationMs']) > 250 or listed != episode['listedMs']:
        raise ValueError(f'Media duration changed on {page}')
    full = listed > 0 and abs(listed - measured) <= 1000
    if delivery:
        if not full or abs(measured - delivery.duration_ms) > 1000:
            raise ValueError(f'Incomplete publisher episode on {page}')
        for file in [episode, *episode.get('encodings', [])]:
            if delivery.hashes.get(file['url'], file['sha256']) != file['sha256']:
                raise ValueError(f'Publisher file digest changed on {page}')
    sizes.add((width, height))
    missing_sizes = set()
    for url in urls:
        if url in checked_urls:
            continue
        with media_snapshot(url) as path:
            actual, w, h, _ = video_track(path)
            if delivery and url in delivery.hashes:
                if fingerprint(path)['sha256'] != delivery.hashes[url] or abs(actual - delivery.duration_ms) > 1000:
                    raise ValueError(f'Publisher file differs on {page}')
                if (w, h) not in sizes:
                    missing_sizes.add((w, h))
            if abs(actual - measured) <= 250 and (listed > 0 and abs(actual - listed) <= 1000) == full and (w, h) not in sizes:
                decode_end(path, actual)
                missing_sizes.add((w, h))
    expected = f'第{number}集' + ('' if full else f' · {round(measured / 1000)} 秒片段')
    if episode['title'] != expected:
        raise ValueError(f'Incorrect preview label on {page}')
    return {'series_id': series, 'episode_id': item_id, 'episode_number': number, 'measured_ms': measured,
            'listed_ms': listed, 'width': width, 'height': height, 'codec_tag': codec, 'full': full,
            'full_hd': full and any(min(w, h) >= 1080 and max(w, h) >= 1920 for w, h in sizes),
            'verified_sizes': sorted(sizes), 'missing_published_sizes': sorted(missing_sizes),
            'bytes': episode['bytes'], 'sha256': episode['sha256']}


def complete_series(tracks, count):
    if len(tracks) != count or not all(track['full_hd'] and not track['missing_published_sizes'] for track in tracks):
        return False
    return sorted(track['episode_number'] for track in tracks) == list(range(1, count + 1))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--require-episodes', action='store_true')
    parser.add_argument('--report', type=Path, help='Write the measured tracks and episode identities as JSON')
    args = parser.parse_args()
    feed = load_feed(os.environ.get('SABLEEN_PUBLISHER_FEED'))
    if {p.stem for p in ROOT.glob('*.json')} != set(RANKS):
        raise ValueError('Unexpected bundled catalogs')
    missing = []
    report = {}
    summary = ['| Catalog | Files checked | Duration matched | Full 1080p | Complete series |', '| --- | ---: | ---: | ---: | ---: |']
    with ThreadPoolExecutor(max_workers=4) as pool:
        for category in RANKS:
            dramas = json.loads((ROOT / f'{category}.json').read_bytes())['dramas']
            records = [(d['id'], e) for d in dramas for e in d['episodes']]
            if not records:
                raise ValueError(f'{category} has no media')
            seasons = list(pool.map(published_series, [f'{HONGGUO}/detail?series_id={d["id"]}' for d in dramas]))
            listed_pages = {d['id']: {e['url'] for e in (season or {}).get('episode', [])}
                            for d, season in zip(dramas, seasons)}
            tracks = list(pool.map(lambda record: check(record, feed, listed_pages), records))
            complete = 0
            by_series = {d['id']: [] for d in dramas}
            for track in tracks:
                by_series[track['series_id']].append(track)
            for drama, season in zip(dramas, seasons):
                count = (season or {}).get('numberOfEpisodes')
                if type(count) is not int or count < 1 or drama.get('episode_count') != count:
                    raise ValueError(f'Invalid or stale episode count for {drama["id"]}')
                series_tracks = by_series[drama['id']]
                ids = season['published_ids']
                if drama.get('published_ids') != ids or any(
                        not 1 <= t['episode_number'] <= count or ids[t['episode_number']-1] != t['episode_id']
                        for t in series_tracks):
                    raise ValueError(f'Stale episode identity or order for {drama["id"]}')
                complete += complete_series(series_tracks, count)
                for t in series_tracks:
                    t['listed_episodes'] = count
            report[category] = tracks
            full = sum(track['full'] for track in tracks)
            full_hd = sum(track['full_hd'] for track in tracks)
            summary.append(f'| {category} | {len(records)} | {full} | {full_hd} | {complete}/{len(dramas)} |')
            print(f'{category}: {len(records)} verified, {full} full episodes, {full_hd} at full HD, {complete}/{len(dramas)} complete series', flush=True)
            if complete != len(dramas) or full_hd != len(records):
                missing.append(category)
            for track in tracks:
                if track['missing_published_sizes']:
                    print(f"Episode {track['episode_id']}: missing published resolutions {track['missing_published_sizes']}")
            if full_hd != len(records):
                first = next(t for t in tracks if not t['full_hd'])
                print(f"Episode {first['episode_id']}: decoded {first['width']}x{first['height']}, "
                      f"{first['measured_ms']} ms of {first['listed_ms']} ms listed", flush=True)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    if path := os.getenv('GITHUB_STEP_SUMMARY'):
        with open(path, 'a', encoding='utf-8') as f:
            f.write('\n'.join(summary) + '\n')
    if args.require_episodes and missing:
        raise SystemExit('Full-length 1080p or published resolution coverage incomplete for: ' + ', '.join(missing))


if __name__ == '__main__':
    main()
