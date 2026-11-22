"""Verify the bundled Hongguo media against its public player metadata."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from refresh_catalogs import (HONGGUO, RANKS, ROOT, duration, fingerprint, listed_ms,
                              media_snapshot, public_encodings, publication, published_video)


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
        measured = round(duration(path) * 1000)
        # A plausible header can outlast the decodable video.
        last_frame = subprocess.check_output([
            'ffmpeg', '-nostdin', '-v', 'error', '-xerror', '-protocol_whitelist', 'file',
            '-ss', f'{max(0, measured - 600) / 1000:.3f}', '-f', 'mov', '-i', str(path),
            '-map', '0:v:0', '-frames:v', '1', '-f', 'framemd5', '-',
        ], timeout=30, text=True)
    if abs(measured - episode['durationMs']) > 250 or listed != episode['listedMs']:
        raise ValueError(f'Media duration changed on {page}')
    if not any(row.startswith('0,') for row in last_frame.splitlines()):
        raise ValueError(f'Cannot decode video near the declared end of {page}')
    full = listed > 0 and abs(listed - measured) <= 1000
    expected = f'第{number}集' + ('' if full else f' · {round(measured / 1000)} 秒片段')
    if episode['title'] != expected:
        raise ValueError(f'Incorrect preview label on {page}')
    return full


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--require-episodes', action='store_true')
    args = parser.parse_args()
    if {p.stem for p in ROOT.glob('*.json')} != set(RANKS):
        raise ValueError('Unexpected bundled catalogs')
    missing = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for category in RANKS:
            dramas = json.loads((ROOT / f'{category}.json').read_bytes())['dramas']
            records = [(d['id'], e) for d in dramas for e in d['episodes']]
            if not records:
                raise ValueError(f'{category} has no media')
            full = sum(pool.map(check, records))
            print(f'{category}: {len(records)} verified, {full} duration-matched episodes', flush=True)
            if not full:
                missing.append(category)
    if args.require_episodes and missing:
        raise SystemExit('Full Hongguo episodes unavailable in: ' + ', '.join(missing))


if __name__ == '__main__':
    main()
