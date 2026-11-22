"""Stage the catalog's byte-exact MP4s for same-origin browser downloads."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import tempfile

from refresh_catalogs import RANKS, fingerprint, media_snapshot


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('web_root', type=Path)
    root = parser.parse_args().web_root
    catalog = root / 'assets/assets/catalogs'
    renditions = json.loads((catalog.parent / 'renditions/index.json').read_bytes())
    episodes = {e['sha256']: e for name in RANKS
                for d in json.loads((catalog / f'{name}.json').read_bytes())['dramas']
                for e in d['episodes'] if e['sha256'] not in renditions}
    folder = root / 'media'
    folder.mkdir(exist_ok=True)

    def stage(entry):
        digest, episode = entry
        if len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest):
            raise ValueError('Invalid catalog digest')
        expected = {'bytes': episode['bytes'], 'sha256': digest}
        target = folder / f'{digest}.mp4'
        if target.is_file() and fingerprint(target) == expected:
            return
        with media_snapshot(episode['url']) as media, tempfile.TemporaryDirectory(dir=folder) as work:
            if fingerprint(media) != expected:
                raise ValueError(f'Media changed for episode {episode["id"]}')
            copy = Path(work) / 'media.mp4'
            shutil.copyfile(media, copy)
            copy.replace(target)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(stage, episodes.items()))
    print(f'Staged {len(episodes)} verified files in {folder}')


if __name__ == '__main__':
    main()
