"""Verify the bundled Hongguo media against its public player metadata."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from refresh_catalogs import (HONGGUO, RANKS, ROOT, video_track, fingerprint, listed_ms,
                              media_snapshot, public_encodings, publication, published_series, published_video)


def decode_end(path, duration):
    frames = subprocess.check_output([
        os.environ.get('SABLEEN_FFMPEG', 'ffmpeg'), '-nostdin', '-v', 'error', '-xerror', '-protocol_whitelist', 'file',
        '-ss', f'{max(0, duration - 600) / 1000:.3f}', '-f', 'mov', '-i', str(path),
        '-map', '0:v:0', '-frames:v', '1', '-f', 'framemd5', '-',
    ], timeout=30, text=True)
    if not any(row.startswith('0,') for row in frames.splitlines()):
        raise ValueError(f'Cannot decode video near {duration} ms in {path.name}')


def check(record):
    series, episode = record
    page = episode['page']
    if not re.fullmatch(re.escape(HONGGUO) + rf'/player/{re.escape(series)}(?:/{re.escape(episode["id"])})?', page):
        raise ValueError('Invalid player page')
    media = episode['url']
    resolved = published_video(publication(page), series, page)
    if not resolved or resolved[0] != episode['id']:
        raise ValueError(f'Published episode or video changed on {page}')
    item_id, number, video = resolved
    urls = public_encodings(video, item_id)
    if media not in urls:
        raise ValueError(f'Published media changed on {page}')
    for mirror in episode.get('mirrors', []):
        if mirror not in urls:
            raise ValueError(f'Unlisted mirror on {page}')
        with media_snapshot(mirror) as path:
            if fingerprint(path)['sha256'] != episode['sha256']:
                raise ValueError(f'Mirror bytes changed on {page}')
    listed = listed_ms(video)
    with media_snapshot(media) as path:
        if any(episode.get(key) != value for key, value in fingerprint(path).items()):
            raise ValueError(f'Media bytes changed on {page}')
        measured, width, height, codec = video_track(path)
        if codec == 'bvc2':
            record = json.loads((ROOT.parent / 'renditions/index.json').read_bytes())[episode['sha256']]
            asset = ROOT.parent / 'renditions' / (record['sha256'] + '.mp4')
            if fingerprint(asset) != record:
                raise ValueError(f'Converted media changed on {page}')
            duration, w, h, tag = video_track(asset)
            if tag != 'avc1' or abs(measured-duration) > 100 or (width, height) != (w, h):
                raise ValueError(f'Converted track differs from source on {page}')
            decode_end(asset, duration)
        # A plausible header can outlast the decodable video.
        decode_end(path, measured)
    sizes = set()
    for encoding in episode.get('encodings', []):
        url = encoding['url']
        if url not in urls:
            raise ValueError(f'Unlisted encoding on {page}')
        if url == media:
            fields = {'sha256': episode['sha256'], 'bytes': episode['bytes']}
            w, h = width, height
        else:
            with media_snapshot(url) as path:
                duration, w, h, tag = video_track(path)
                if (abs(duration - measured) > 250 or tag != 'avc1'
                        or (abs(duration - listed) <= 1000) != (abs(measured - listed) <= 1000)):
                    raise ValueError(f'Non-interchangeable encoding on {page}')
                decode_end(path, duration)
                fields = fingerprint(path)
        if (w, h) in sizes or encoding != {'url': url, 'width': w, 'height': h, **fields}:
            raise ValueError(f'Encoding dimensions or bytes changed on {page}')
        sizes.add((w, h))
    if sizes and (len(sizes) < 2 or media not in {e['url'] for e in episode['encodings']}):
        raise ValueError(f'Invalid default encoding on {page}')
    if abs(measured - episode['durationMs']) > 250 or listed != episode['listedMs']:
        raise ValueError(f'Media duration changed on {page}')
    full = listed > 0 and abs(listed - measured) <= 1000
    expected = f'第{number}集' + ('' if full else f' · {round(measured / 1000)} 秒片段')
    if episode['title'] != expected:
        raise ValueError(f'Incorrect preview label on {page}')
    return {'series_id': series, 'episode_id': item_id, 'episode_number': number, 'measured_ms': measured,
            'listed_ms': listed, 'width': width, 'height': height, 'codec_tag': codec, 'full': full,
            'full_hd': full and min(width, height) >= 1080 and max(width, height) >= 1920,
            'bytes': episode['bytes'], 'sha256': episode['sha256']}


def complete_series(tracks, count):
    if len(tracks) != count or not all(track['full_hd'] for track in tracks):
        return False
    return sorted(track['episode_number'] for track in tracks) == list(range(1, count + 1))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--require-episodes', action='store_true')
    parser.add_argument('--report', type=Path, help='Write the measured tracks and episode identities as JSON')
    args = parser.parse_args()
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
            tracks = list(pool.map(check, records))
            seasons = pool.map(published_series, [f'{HONGGUO}/detail?series_id={d["id"]}' for d in dramas])
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
        raise SystemExit('Full-length 1080p coverage incomplete for: ' + ', '.join(missing))


if __name__ == '__main__':
    main()
