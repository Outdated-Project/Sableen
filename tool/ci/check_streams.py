import json
import subprocess
from pathlib import Path
from urllib.parse import urljoin, urlsplit


def fetch(url, limit):
    response = subprocess.run(['curl', '--fail', '--show-error', '--silent', '--location',
                               '--proto', '=https', '--proto-redir', '=https', '--retry', '2',
                               '--connect-timeout', '10', '--max-time', '35', '--range', f'0-{limit - 1}', url],
                              check=True, capture_output=True)
    if not response.stdout:
        raise ValueError('Empty media response')
    return response.stdout


def main():
    errors = []
    for path in sorted(Path('assets/catalogs').glob('*.json')):
        item = json.loads(path.read_text(encoding='utf-8'))['dramas'][0]['episodes'][0]
        url = item['url']
        try:
            for depth in range(4):
                data = fetch(url, 8192)
                if depth == 0 and urlsplit(url).path.endswith('.mp4'):
                    if data[4:8] != b'ftyp':
                        raise ValueError('Expected an MP4 header')
                    break
                if not data.startswith(b'#EXTM3U'):
                    if depth == 0 or not (data.startswith(b'\x47') or data[4:8] in (b'ftyp', b'styp', b'moof') or data.startswith(b'ID3')):
                        raise ValueError('Expected an HLS playlist or video segment')
                    break
                line = next(line for line in data.decode().splitlines() if line and not line.startswith('#'))
                url = urljoin(url, line.strip())
            else:
                raise ValueError('HLS playlist did not resolve to media')
            print(path.stem, 'media reachable', flush=True)
        except (ValueError, StopIteration, subprocess.CalledProcessError) as error:
            reason = error.stderr.decode(errors='replace') if isinstance(error, subprocess.CalledProcessError) else str(error)
            errors.append(f'{path.stem} ({urlsplit(url).hostname}): {reason}')
    if errors:
        raise SystemExit('\n'.join(errors))


if __name__ == '__main__':
    main()
