import sys
from pathlib import Path
from zipfile import ZipFile


def main():
    target = Path(sys.argv[1])
    sources = sorted(Path('assets/catalogs').glob('*.json')) + sorted(Path('assets/posters').glob('*.webp'))
    if not sources or not any(path.suffix == '.webp' for path in sources):
        raise ValueError('Bundled catalog or posters missing')
    if target.suffix == '.apk':
        with ZipFile(target) as apk:
            for source in sources:
                if apk.read('assets/flutter_assets/' + source.as_posix()) != source.read_bytes():
                    raise ValueError(source)
            for abi in ('arm64-v8a', 'armeabi-v7a', 'x86_64'):
                for name in ('libapp.so', 'libflutter.so', 'librust_lib_sableen.so', 'libmpv.so'):
                    if apk.getinfo(f'lib/{abi}/{name}').file_size == 0:
                        raise ValueError(f'{abi}/{name}')
    else:
        for source in sources:
            if (target / source).read_bytes() != source.read_bytes():
                raise ValueError(source)
    print(f'Verified {len(sources)} bundled catalog and poster files in {target}')


if __name__ == '__main__':
    main()
