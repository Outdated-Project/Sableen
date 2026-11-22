"""Read an explicitly configured publisher feed of full episodes for guest playback."""
from dataclasses import dataclass
import json
import re
import subprocess
from urllib.parse import urlsplit


@dataclass(frozen=True)
class PublishedFileSet:
    number: int
    duration_ms: int
    hashes: dict[str, str]


def public_url(url):
    if not isinstance(url, str) or not url.isascii() or re.search(r'[\x00-\x20\x7f\\#]', url):
        return False
    parsed = urlsplit(url)
    return url.startswith('https://') and bool(parsed.hostname) and parsed.username is None


def parse_feed(data):
    doc = json.loads(data)
    if (not isinstance(doc, dict) or type(doc.get('version')) is not int or doc['version'] != 1
            or not isinstance(doc.get('episodes'), list) or not doc['episodes']):
        raise ValueError('Expected a version 1 publisher episode feed')
    shows = {}
    for record in doc['episodes']:
        series, item = record['seriesId'], record['episodeId']
        if not all(isinstance(v, str) and re.fullmatch(r'[0-9]+', v) for v in (series, item)):
            raise ValueError('Invalid publisher episode identity')
        number, duration = record['episodeNumber'], record['durationMs']
        if type(number) is not int or number < 1 or type(duration) is not int or not 0 < duration <= 0xffffffff:
            raise ValueError(f'Invalid publisher episode number or duration for {item}')
        if not isinstance(record['files'], list):
            raise ValueError(f'Expected an array of files for {item}')
        hashes = {}
        for media in record['files']:
            url, digest = media['url'], media['sha256']
            if not public_url(url) or not re.fullmatch('[0-9a-f]{64}', digest) or url in hashes:
                raise ValueError(f'Invalid publisher media record for {item}')
            hashes[url] = digest
        episodes = shows.setdefault(series, {})
        if not hashes or item in episodes:
            raise ValueError(f'Empty or duplicate publisher episode {item}')
        episodes[item] = PublishedFileSet(number, duration, hashes)
    return shows


def load_feed(url):
    if not url:
        return {}
    if not public_url(url):
        raise ValueError('Expected a public HTTPS publisher feed URL')
    result = subprocess.run(['curl', '--disable', '--silent', '--show-error', '--fail', '--proto', '=https',
                             '--max-time', '60', '--max-filesize', str(64 << 20), '--', url],
                            capture_output=True, check=True, timeout=65)
    return parse_feed(result.stdout)
