import re
import subprocess
import time
from xml.etree import ElementTree


def screen():
    subprocess.run(['adb', 'shell', 'uiautomator', 'dump', '/data/local/tmp/sableen-window.xml'],
                   check=True, stdout=subprocess.DEVNULL, timeout=20)
    xml = subprocess.check_output(['adb', 'exec-out', 'cat', '/data/local/tmp/sableen-window.xml'], timeout=10)
    return ElementTree.fromstring(xml)


def wait_for_node(test, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for node in screen().iter('node'):
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
    return minutes * 60 + seconds >= 2 and total_minutes * 60 + total_seconds >= 500


if __name__ == '__main__':
    card = wait_for_node(lambda label: '梦笔不能停' in label, 75)
    x1, y1, x2, y2 = map(int, re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', card.attrib['bounds']).groups())
    subprocess.run(['adb', 'shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2)], check=True)
    wait_for_node(playing, 90)
    print('Installed release APK played the CCTV episode past two seconds')
