import re
import json
from pathlib import Path
import subprocess
import sys
import time
from xml.etree import ElementTree


def screen():
    subprocess.run(['adb', 'shell', 'rm', '-f', '/data/local/tmp/sableen-window.xml'], check=True)
    subprocess.run(['adb', 'shell', 'uiautomator', 'dump', '/data/local/tmp/sableen-window.xml'],
                   check=True, stdout=subprocess.DEVNULL, timeout=20)
    xml = subprocess.check_output(['adb', 'exec-out', 'cat', '/data/local/tmp/sableen-window.xml'], timeout=10)
    return ElementTree.fromstring(xml)


def wait_for_node(test, timeout):
    deadline = time.monotonic() + timeout
    labels = []
    while time.monotonic() < deadline:
        try:
            nodes = screen().iter('node')
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ElementTree.ParseError):
            continue
        labels = []
        for node in nodes:
            label = ' '.join(node.get(key, '') for key in ('text', 'content-desc'))
            if label.strip():
                labels.append(label.strip())
            if test(label):
                return node
        time.sleep(1)
    raise RuntimeError(f'Expected screen did not appear. Visible labels: {labels[:24]}')


def playing(label):
    clock = re.search(r'(\d+):(\d{2})\s*/\s*(\d+):(\d{2})', label)
    if not clock:
        return False
    minutes, seconds, total_minutes, total_seconds = map(int, clock.groups())
    return minutes * 60 + seconds >= 2 and total_minutes * 60 + total_seconds > 2


def tap(node):
    x1, y1, x2, y2 = map(int, re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib['bounds']).groups())
    subprocess.run(['adb', 'shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2)], check=True)


def reference_frames(episode):
    url = episode['url']
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-rw_timeout', '15000000',
        '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'json', url], timeout=30))['streams'][0]
    frames = subprocess.check_output(['ffmpeg', '-nostdin', '-v', 'error', '-rw_timeout', '15000000',
        '-i', url, '-t', '12', '-an', '-vf', 'fps=4,scale=32:32:flags=area', '-pix_fmt', 'rgb24',
        '-f', 'rawvideo', '-'], timeout=50)
    stride = 32 * 32 * 3
    if len(frames) % stride or len(frames) < 12 * stride:
        raise RuntimeError('Reference MP4 has insufficient video frames')
    return info['width'] / info['height'], [frames[p:p + stride] for p in range(0, len(frames), stride)]


def observe_video(aspect, frames):
    from PIL import Image
    from io import BytesIO
    # Exclude the controls and letterboxing. Downsample the same central region
    # in the reference and the screenshot to absorb decoder rounding differences.
    region = (4, 8, 28, 24)
    signatures = [Image.frombytes('RGB', (32, 32), frame).crop(region).tobytes() for frame in frames]
    start = time.monotonic()
    first = None
    best = float('inf')
    while time.monotonic() - start < 65:
        raw = subprocess.check_output(['adb', 'exec-out', 'screencap', '-p'], timeout=12)
        with Image.open(BytesIO(raw)) as image:
            w, h = image.size
            vw, vh = min(w, h * aspect), min(h, w / aspect)
            left, top = (w - vw) / 2, (h - vh) / 2
            view = image.convert('RGB').crop((round(left), round(top), round(left + vw), round(top + vh)))
            actual = view.resize((32, 32), Image.Resampling.BOX).crop(region).tobytes()
        errors = [sum(abs(a - b) for a, b in zip(actual, ref)) / len(actual) for ref in signatures]
        frame = min(range(len(errors)), key=errors.__getitem__)
        best = min(best, errors[frame])
        if errors[frame] < 20:
            if first is None:
                first = frame
            elif frame >= max(9, first + 3) and sum(abs(a - b) for a, b in zip(signatures[first], signatures[frame])) / len(actual) > 6:
                print(f'Decoded publisher frames at {first / 4:.2f}s and {frame / 4:.2f}s', flush=True)
                return w, h
    raise RuntimeError(f'No advancing publisher frames detected. Minimum RGB difference {best:.1f}, first match {first}')


def main():
    for label, key in [('红果短剧', 'hongguo'), ('红果漫剧', 'comic')]:
        title = json.loads(Path(f'assets/catalogs/{key}.json').read_text('utf8'))['dramas'][0]
        aspect, frames = reference_frames(title['episodes'][0])
        tap(wait_for_node(lambda text: label in text, 60))
        tap(wait_for_node(lambda text: title['title'] in text, 60))
        width, height = observe_video(aspect, frames)
        center = ['adb', 'shell', 'input', 'tap', str(width // 2), str(height // 2)]
        subprocess.run(center, check=True)
        wait_for_node(playing, 30)
        subprocess.run(['adb', 'shell', 'input', 'keyevent', '4'], check=True)
        print(f'Installed release APK played {key}', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        try:
            print('Current screen:', [n.get('content-desc') or n.get('text') for n in screen().iter('node')][:60], file=sys.stderr)
        except (ValueError, subprocess.SubprocessError, ElementTree.ParseError):
            pass
        raise
