import re
import json
import os
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


def wait_for_downloads(count, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        labels = [' '.join(node.get(key, '') for key in ('text', 'content-desc')) for node in screen().iter('node')]
        failure = next((label for label in labels if '下载失败' in label), None)
        if failure:
            raise RuntimeError(failure)
        if sum('已保存' in label for label in labels) >= count:
            return
    raise RuntimeError(f'Expected {count} saved downloads')


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
    best_screen = None
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
        if errors[frame] < best:
            best = errors[frame]
            best_screen = raw
        if errors[frame] < 20:
            if first is None:
                first = frame
            elif frame >= max(9, first + 3) and sum(abs(a - b) for a, b in zip(signatures[first], signatures[frame])) / len(actual) > 6:
                print(f'Decoded publisher frames at {first / 4:.2f}s and {frame / 4:.2f}s', flush=True)
                return w, h
    if best_screen and os.environ.get('RUNNER_TEMP'):
        (Path(os.environ['RUNNER_TEMP']) / 'android-playback.png').write_bytes(best_screen)
    raise RuntimeError(f'No advancing publisher frames detected. Minimum RGB difference {best:.1f}, first match {first}')


def main(check_offline=False):
    downloaded = []
    for label, key in [('红果短剧', 'hongguo'), ('红果漫剧', 'comic')]:
        title = json.loads(Path(f'assets/catalogs/{key}.json').read_text('utf8'))['dramas'][0]
        aspect, frames = reference_frames(title['episodes'][0])
        tap(wait_for_node(lambda text: label in text, 60))
        tap(wait_for_node(lambda text: title['title'] in text, 60))
        width, height = observe_video(aspect, frames)
        center = ['adb', 'shell', 'input', 'tap', str(width // 2), str(height // 2)]
        subprocess.run(center, check=True)
        wait_for_node(playing, 30)
        if check_offline:
            tap(wait_for_node(lambda text: '离线下载' in text, 15))
            action = '下载 ' + title['episodes'][0]['title']
            tap(wait_for_node(lambda text: action in text, 15))
            wait_for_downloads(len(downloaded) + 1)
            subprocess.run(['adb', 'shell', 'input', 'keyevent', '4'], check=True)
            wait_for_node(lambda text: '离线下载' in text, 15)
            downloaded.append((label, title['title'], aspect, frames))
        subprocess.run(['adb', 'shell', 'input', 'keyevent', '4'], check=True)
        print(f'Installed release APK played {key}', flush=True)
    if downloaded:
        # The caller explicitly opts in on a disposable CI emulator.
        if subprocess.check_output(['adb', 'shell', 'getprop', 'ro.kernel.qemu']).strip() != b'1':
            raise RuntimeError('Disconnected playback test requires an emulator')
        def shell(*args):
            return subprocess.check_output(['adb', 'shell', *args], timeout=20)
        try:
            shell('svc', 'wifi', 'disable')
            shell('svc', 'data', 'disable')
            deadline = time.monotonic() + 15
            while not re.search(rb'Active default network:\s*(none|null)', shell('dumpsys', 'connectivity'), re.I):
                if time.monotonic() >= deadline:
                    raise RuntimeError('Emulator still has a default network')
                time.sleep(0.5)
            for label, title, aspect, frames in downloaded:
                shell('am', 'force-stop', 'com.example.sableen')
                shell('am', 'start', '-W', '-n', 'com.example.sableen/.MainActivity')
                tap(wait_for_node(lambda text: label in text, 30))
                tap(wait_for_node(lambda text: title in text, 30))
                observe_video(aspect, frames)
                print(f'Cold-start offline playback verified: {title}', flush=True)
        finally:
            shell('svc', 'wifi', 'enable')
            shell('svc', 'data', 'enable')


if __name__ == '__main__':
    try:
        main(check_offline='--check-offline' in sys.argv[1:])
    except Exception:
        try:
            print('Current screen:', [n.get('content-desc') or n.get('text') for n in screen().iter('node')][:60], file=sys.stderr)
        except (ValueError, subprocess.SubprocessError, ElementTree.ParseError):
            pass
        raise
