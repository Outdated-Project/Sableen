import re
import json
from pathlib import Path
import subprocess
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
    while time.monotonic() < deadline:
        try:
            nodes = screen().iter('node')
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ElementTree.ParseError):
            continue
        for node in nodes:
            label = ' '.join(node.get(key, '') for key in ('text', 'content-desc'))
            if test(label):
                return node
        time.sleep(1)
    raise RuntimeError('Expected release application screen did not appear')


def playing(label):
    clock = re.search(r'(\d+):(\d{2})\s*/\s*(\d+):(\d{2})', label)
    if not clock:
        return False
    minutes, seconds, total_minutes, total_seconds = map(int, clock.groups())
    return minutes * 60 + seconds >= 2 and total_minutes * 60 + total_seconds > 2


def tap(node):
    x1, y1, x2, y2 = map(int, re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib['bounds']).groups())
    subprocess.run(['adb', 'shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2)], check=True)


if __name__ == '__main__':
    for label, key in [('红果短剧', 'hongguo'), ('红果漫剧', 'comic')]:
        title = json.loads(Path(f'assets/catalogs/{key}.json').read_text('utf8'))['dramas'][0]['title']
        tap(wait_for_node(lambda text: label in text, 60))
        tap(wait_for_node(lambda text: title in text, 60))
        # A running clock prevents UiAutomator's idle-based dump. Pause at the
        # center, inspect the stable timeline, then resume and confirm it moved.
        size = subprocess.check_output(['adb', 'shell', 'wm', 'size'], text=True)
        width, height = map(int, re.findall(r'(\d+)x(\d+)', size)[-1])
        center = ['adb', 'shell', 'input', 'tap', str(width // 2), str(height // 2)]
        time.sleep(4)
        subprocess.run(center, check=True)
        wait_for_node(playing, 30)
        subprocess.run(['adb', 'shell', 'input', 'keyevent', '4'], check=True)
        print(f'Installed release APK played {key}', flush=True)
