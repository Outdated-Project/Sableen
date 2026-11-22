"""Stage the catalog's byte-exact MP4s for same-origin browser downloads."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

from refresh_catalogs import RANKS, fingerprint, media_snapshot


def stage_offline_shell(root):
    template = Path(__file__).with_name('offline_worker.js').read_text(encoding='utf8')
    index = root / 'index.html'
    html = index.read_text(encoding='utf8')
    marker = '<meta name="sableen-offline-worker" content="sableen-offline.js">'
    if marker not in html:
        if '</head>' not in html:
            raise ValueError('Web entry point has no HTML head')
        index.write_text(html.replace('</head>', marker + '\n</head>', 1), encoding='utf8')
    assets = []
    for file in sorted(root.rglob('*')):
        relative = file.relative_to(root).as_posix()
        if not file.is_file() or file.name.startswith('.') or file.suffix in ('.symbols', '.mp4'):
            continue
        if relative.split('/')[0] not in ('assets', 'canvaskit', 'icons', 'pkg') and relative not in (
                'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'favicon.png', 'manifest.json'):
            continue
        if relative.startswith('canvaskit/') and file.name not in ('canvaskit.js', 'canvaskit.wasm'):
            continue
        with file.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').digest()
        assets.append((relative, 'sha256-' + base64.b64encode(digest).decode('ascii')))
    worker = template.replace('__SABLEEN_ASSETS__', json.dumps(assets, separators=(',', ':')))
    version = hashlib.sha256(worker.encode()).hexdigest()
    (root / 'sableen-offline.js').write_text(worker.replace('__SABLEEN_VERSION__', version), encoding='utf8')


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
    stage_offline_shell(root)
    print(f'Staged {len(episodes)} verified files in {folder}')


if __name__ == '__main__':
    main()
