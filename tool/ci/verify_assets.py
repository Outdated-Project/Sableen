import sys
import json
from pathlib import Path
from zipfile import ZipFile


def main():
    target = Path(sys.argv[1])
    sources = sorted(Path('assets/catalogs').glob('*.json')) + sorted(Path('assets/posters').glob('*.webp'))
    expected = {f'assets/catalogs/{name}.json' for name in ('hongguo', 'comic')}
    for category in ('hongguo', 'comic'):
        for title in json.loads(Path(f'assets/catalogs/{category}.json').read_bytes())['dramas']:
            expected.add(f"assets/posters/{category}-{title['episodes'][0]['id']}.webp")
    if {source.as_posix() for source in sources} != expected:
        raise ValueError('Source catalog and posters do not match')
    if target.suffix == '.apk':
        with ZipFile(target) as apk:
            prefix = 'assets/flutter_assets/'
            actual = {name[len(prefix):] for name in apk.namelist() if not name.endswith('/') and
                      name.startswith((prefix + 'assets/catalogs/', prefix + 'assets/posters/'))}
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
        actual = {p.relative_to(target).as_posix() for sub in ('catalogs', 'posters')
                  for p in (target / 'assets' / sub).rglob('*') if p.is_file()}
        if actual != expected:
            raise ValueError('Package contains stale or missing catalog assets')
        for source in sources:
            if (target / source).read_bytes() != source.read_bytes():
                raise ValueError(source)
    print(f'Verified {len(sources)} bundled catalog and poster files in {target}')


if __name__ == '__main__':
    main()
