#!/usr/bin/env python3
"""Create a deterministic, checksummed local source release, without Git mutations.

The archive uses an explicit source allowlist: local settings, credentials,
launcher history, build outputs and agent state cannot enter it.
"""
import argparse
import gzip
import hashlib
import io
from pathlib import Path
import re
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
version = re.search(r'project\(Dynis VERSION ([\d.]+)', (ROOT / 'CMakeLists.txt').read_text()).group(1)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--commit', help='Published full GitHub commit ID; downloads and pins that immutable source')
args = parser.parse_args()
if args.commit and not re.fullmatch(r'[0-9a-f]{40}', args.commit):
    parser.error('--commit must be a full 40-character lowercase commit ID')
prefix = f'dynis-{args.commit or version}'
files = [
    'CMakeLists.txt', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'shell.qml', 'DynamicIslandWindow.qml',
    'LauncherWindow.qml', 'WorkspaceIslandWindow.qml', 'IslandGlassCarrier.qml',
    'RoundedScreenCornersWindow.qml', 'dynis-launcher', 'dynis.desktop',
    'dynis.service.in', 'dynis.install', 'run-local.sh', 'README.md',
    'scripts/install-debian-ubuntu.sh', 'scripts/install-fonts.sh', 'scripts/prepare-source.py',
]
extensions = {
    'backend': {'.cpp', '.h'}, 'lyricsmpris': {'.cpp', '.h'},
    'qml': {'.qml', '.frag', '.qsb'}, 'tests': {'.cpp'}, 'tools': {'.cpp'},
    'fonts': {'.ttf', '.txt'}, 'docs': {'.md', '.jpg', '.png'},
}
for directory, suffixes in extensions.items():
    files.extend(str(p.relative_to(ROOT)) for p in (ROOT / directory).rglob('*')
                 if p.is_file() and p.suffix in suffixes)
files.extend(['config/userconfig.example.json', 'fonts/SymbolsNerdFont-LICENSE'])
archive = ROOT / f'dynis-{version}.tar.gz'
source = '"$pkgname-$pkgver.tar.gz"'
if args.commit:
    url = f'https://codeload.github.com/fanat-sira/dynis/tar.gz/{args.commit}'
    with urllib.request.urlopen(url, timeout=60) as response:
        payload = response.read()
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:gz') as tar:
        cmake = tar.extractfile(f'{prefix}/CMakeLists.txt').read().decode()
        actual = re.search(r'project\(Dynis VERSION ([\d.]+)', cmake).group(1)
        if actual != version:
            raise SystemExit(f'Refusing version mismatch: commit has {actual}, checkout has {version}')
    archive.write_bytes(payload)
    source = f'"$pkgname-$pkgver.tar.gz::$url/archive/{args.commit}.tar.gz"'
else:
    # Fixed timestamps, ordering, uid/gid and modes make repeated output identical.
    with archive.open('wb') as output, gzip.GzipFile(filename='', mode='wb', fileobj=output, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as tar:
            for name in sorted(files):
                path = ROOT / name
                if path.is_symlink():
                    raise SystemExit(f'Refusing symlink in release sources: {name}')
                if '__pycache__' in path.parts or path.suffix in {'.pyc', '.log'}:
                    continue
                if name.startswith('config/') and name != 'config/userconfig.example.json':
                    raise SystemExit(f'Unexpected configuration in source archive: {name}')
                data = path.read_bytes()
                info = tarfile.TarInfo(f'{prefix}/{name}')
                info.size = len(data)
                info.mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
                tar.addfile(info, io.BytesIO(data))
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
recipe = ROOT / 'PKGBUILD'
text = re.sub(r'^pkgver=.*$', f'pkgver={version}', recipe.read_text(), flags=re.M)
text = re.sub(r'^_srcdir=.*$', f'_srcdir={prefix}', text, flags=re.M)
text = re.sub(r'^source=.*$', f'source=({source})', text, flags=re.M)
text = re.sub(r"^sha256sums=.*$", f"sha256sums=('{checksum}')", text, flags=re.M)
recipe.write_text(text)
result = subprocess.run(['makepkg', '--printsrcinfo'], cwd=ROOT, capture_output=True, text=True)
if result.returncode:
    raise SystemExit(result.stderr)
(ROOT / '.SRCINFO').write_text(result.stdout)
print(f'{checksum}  {archive.name}')
print('Source archive ready. Run makepkg from the repository root.')
