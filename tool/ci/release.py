import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


PACKAGES = ('Sableen-android-universal.apk', 'Sableen-ubuntu24-amd64.deb',
            'Sableen-web.zip', 'Sableen-windows-x64-setup.exe')


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify(incoming, output):
    if {p.name for p in incoming.iterdir()} != {'tested-' + name for name in PACKAGES}:
        raise ValueError('Unexpected set of build artifacts')
    output.mkdir(exist_ok=False)
    checksums = []
    for name in PACKAGES:
        folder = incoming / ('tested-' + name)
        if folder.is_symlink() or {p.name for p in folder.iterdir()} != {name, name + '.sha256'}:
            raise ValueError(f'Unexpected artifact contents for {name}')
        package = folder / name
        check = folder / (name + '.sha256')
        if any(p.is_symlink() or not p.is_file() for p in (package, check)) or not package.stat().st_size:
            raise ValueError(f'Invalid package {name}')
        checksum = digest(package)
        # GNU sha256sum marks binary mode with '*', the default on Windows.
        records = (f'{checksum}  {name}\n', f'{checksum} *{name}\n')
        if check.read_text(encoding='ascii') not in records:
            raise ValueError(f'Checksum mismatch for {name}')
        shutil.copyfile(package, output / name)
        checksums.append(f'{checksum}  {name}\n')
    (output / 'SHA256SUMS').write_bytes(''.join(checksums).encode('ascii'))


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True).strip()


def publish():
    repo = os.environ['GITHUB_REPOSITORY']
    sha = os.environ['GITHUB_SHA']
    tag = 'v' + os.environ['APP_VERSION']
    run = f'https://github.com/{repo}/actions/runs/{os.environ["GITHUB_RUN_ID"]}'
    api = f'repos/{repo}'
    existing = json.loads(gh('api', '--paginate', '--slurp', api + '/releases?per_page=100'))
    release = next((r for page in existing for r in page if r['tag_name'] == tag), None)
    if release and not release['draft']:
        print(f'{tag} is already published. A new version in pubspec.yaml creates the next release.')
        return
    if gh('api', api + '/git/ref/heads/main', '--jq', '.object.sha') != sha:
        raise RuntimeError('main advanced during this build')
    if release:
        if release['target_commitish'] != sha or release['author']['login'] != 'github-actions[bot]':
            raise RuntimeError('A draft for this version belongs to a different build')
    else:
        refs = json.loads(gh('api', api + '/git/matching-refs/tags/' + tag))
        if any(ref['ref'] == 'refs/tags/' + tag for ref in refs):
            raise RuntimeError('Tag already exists without a published release')
        notes = (f'由 [GitHub Actions]({run}) 编译并测试。提交 `{sha}`。\n\n'
                 'Android 请下载通用 APK，Windows x64 请下载安装程序，Ubuntu 24.04 x64 请下载 DEB。'
                 'Web ZIP 用于自行部署。安装包的 SHA-256 见 `SHA256SUMS`。\n\n'
                 f'验证构建来源：`gh attestation verify <file> --repo {repo}`。')
        gh('release', 'create', tag, '--draft', '--target', sha, '--title', 'Sableen ' + tag, '--notes', notes)
    paths = sorted(Path('dist').iterdir())
    local = {p.name: 'sha256:' + digest(p) for p in paths}

    def assets():
        found = json.loads(gh('release', 'view', tag, '--json', 'assets'))['assets']
        return {a['name']: a['digest'] for a in found}

    previous = assets()
    if previous.keys() - local.keys():
        raise RuntimeError('Draft contains unexpected assets')
    for path in paths:
        if previous.get(path.name) != local[path.name]:
            gh('release', 'upload', tag, str(path), '--clobber')
    if assets() != local:
        raise RuntimeError('GitHub draft asset hashes differ from the tested bytes')
    if gh('api', api + '/git/ref/heads/main', '--jq', '.object.sha') != sha:
        raise RuntimeError('main advanced before publication')
    gh('release', 'edit', tag, '--draft=false', '--latest')
    print(gh('release', 'view', tag, '--json', 'url', '--jq', '.url'))


if __name__ == '__main__':
    if sys.argv[1:] == ['verify']:
        verify(Path('incoming'), Path('dist'))
    elif sys.argv[1:] == ['publish']:
        publish()
    else:
        sys.exit('Expected verify or publish')
