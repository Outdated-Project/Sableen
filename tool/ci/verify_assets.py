import sys
import json
import hashlib
from pathlib import Path
from zipfile import ZipFile


def main():
    target = Path(sys.argv[1])
    sources = sorted(Path('assets/catalogs').glob('*.json')) + sorted(Path('assets/posters').glob('*.webp'))
    expected = {f'assets/catalogs/{name}.json' for name in ('hongguo', 'comic')}
    index = Path('assets/renditions/index.json')
    sources.extend([index, *index.parent.glob('*.mp4')])
    expected.add(index.as_posix())
    catalog_hashes = set()
    for category in ('hongguo', 'comic'):
        for title in json.loads(Path(f'assets/catalogs/{category}.json').read_bytes())['dramas']:
            expected.add(f"assets/posters/{category}-{title['episodes'][0]['id']}.webp")
            catalog_hashes.update(e['sha256'] for e in title['episodes'])
    for source_hash, rendition in json.loads(index.read_bytes()).items():
        f = index.parent / (rendition['sha256'] + '.mp4')
        if source_hash not in catalog_hashes or f.stat().st_size != rendition['bytes']:
            raise ValueError(f'Unmatched rendition: {f}')
        with f.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != rendition['sha256']:
                raise ValueError(f'Invalid rendition: {f}')
        expected.add(f.as_posix())
    if {source.as_posix() for source in sources} != expected:
        raise ValueError('Source catalog and posters do not match')
    if target.suffix == '.apk':
        with ZipFile(target) as apk:
            prefix = 'assets/flutter_assets/'
            actual = {name[len(prefix):] for name in apk.namelist() if not name.endswith('/') and
                       name.startswith(tuple(prefix + 'assets/' + sub + '/' for sub in ('catalogs', 'posters', 'renditions')))}
            if actual != expected:
                raise ValueError('APK contains stale or missing catalog assets')
            for source in sources:
                if apk.read('assets/flutter_assets/' + source.as_posix()) != source.read_bytes():
                    raise ValueError(source)
            for abi in ('arm64-v8a', 'armeabi-v7a', 'x86_64'):
                for name in ('libapp.so', 'libflutter.so', 'librust_lib_sableen.so', 'libmpv.so'):
                    if apk.getinfo(f'lib/{abi}/{name}').file_size == 0:
                        raise ValueError(f'{abi}/{name}')
    else:
        actual = {p.relative_to(target).as_posix() for sub in ('catalogs', 'posters', 'renditions')
                  for p in (target / 'assets' / sub).rglob('*') if p.is_file()}
        if actual != expected:
            raise ValueError('Package contains stale or missing catalog assets')
        for source in sources:
            if (target / source).read_bytes() != source.read_bytes():
                raise ValueError(source)
    print(f'Verified {len(sources)} bundled catalog and poster files in {target}')


if __name__ == '__main__':
    main()
