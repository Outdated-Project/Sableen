"""Verify the bundled Hongguo media against its public player metadata."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from refresh_catalogs import HONGGUO, RANKS, ROOT, duration, publication


def check(record):
    series, episode = record
    page = episode['page']
    if not re.fullmatch(re.escape(HONGGUO) + rf'/player/{re.escape(series)}(?:/{re.escape(episode["id"])})?', page):
        raise ValueError('Invalid player page')
    media = episode['url']
    if not re.fullmatch(re.escape(HONGGUO) + rf'/video/public/{re.escape(episode["id"])}/\d+p\.mp4', media):
        raise ValueError(f'Unexpected media origin on {page}')
    video = next(n for n in publication(page).nodes if n.get('@type') == 'VideoObject'
                 and n.get('url') == page and n.get('contentUrl') == media and n.get('about', {}).get('@id') == page + '#episode')
    declared = re.fullmatch(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?', video.get('duration', ''))
    listed = round(1000 * sum(float(n or 0) * unit for n, unit in zip(declared.groups(), (3600, 60, 1)))) if declared else 0
    measured = round(duration(media) * 1000)
    if abs(measured - episode['durationMs']) > 250 or listed != episode['listedMs']:
        raise ValueError(f'Media duration changed on {page}')
    # The duration in the MP4 header can outlast the decodable video.
    last_frame = subprocess.check_output([
        'ffmpeg', '-nostdin', '-v', 'error', '-xerror', '-rw_timeout', '12000000',
        '-protocol_whitelist', 'https,tls,tcp', '-ss', f'{max(0, measured - 600) / 1000:.3f}',
        '-i', media, '-map', '0:v:0', '-frames:v', '1', '-f', 'framemd5', '-',
    ], timeout=30, text=True)
    if not any(row.startswith('0,') for row in last_frame.splitlines()):
        raise ValueError(f'Cannot decode video near the declared end of {page}')
    full = listed > 0 and abs(listed - measured) <= 1000
    if ('片段' in episode['title']) == full:
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
