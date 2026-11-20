"""Report lab PNGs that no tracked text file mentions, and guide image references to missing files.

Read-only: lists, prints two counts, changes nothing in the checkout.
Exit codes: 0 report complete (1 with --strict when anything is listed), 2 no module-* directory found.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

REF = re.compile(r'!\[[^\]]*\]\(\s*<?([^)\s>]+)|<img\b[^>]*?\bsrc\s*=\s*["\']([^"\']+)["\']', re.I)
IMAGE_EXT = {'.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'}


def tracked_files(root):
    out = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'], capture_output=True, check=True).stdout
    return [p for p in out.decode('utf-8').split('\0') if p]


def read_text(root, rel):
    try:
        data = (root / rel).read_bytes()
    except OSError:
        return None
    return None if b'\0' in data else data.decode('utf-8', errors='replace')


def unused_pngs(root, files):
    pngs = [f for f in files if re.fullmatch(r'module-[^/]+/[^/]+/images/[^/]+\.png', f)]
    texts = [t for f in files if not f.endswith('.png') and (t := read_text(root, f)) is not None]
    return sorted(p for p in pngs if not any(PurePosixPath(p).name in t for t in texts))


def resolve(guide, ref):
    parts = []
    for seg in (PurePosixPath(guide).parent / ref).parts:
        if seg == '..':
            if parts:
                parts.pop()
        elif seg != '.':
            parts.append(seg)
    return '/'.join(parts)


def missing_refs(root, files):
    tracked, found = set(files), []
    for guide in (f for f in files if re.fullmatch(r'module-[^/]+/.+/lab-guide-[^/]+\.md', f)):
        for m in REF.finditer(read_text(root, guide) or ''):
            ref = (m.group(1) or m.group(2)).split('#')[0].split('?')[0]
            if re.match(r'[a-z][a-z0-9+.-]*:', ref, re.I) or PurePosixPath(ref).suffix.lower() not in IMAGE_EXT:
                continue
            if resolve(guide, ref) not in tracked:
                found.append((guide, ref))
    return sorted(found)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--root', default='.', help='git checkout to read (default: current directory)')
    ap.add_argument('--strict', action='store_true', help='exit 1 when anything is listed')
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    files = tracked_files(root)
    if not any(re.match(r'module-[^/]+/', f) for f in files):
        print(f'No module-* directory found under {root}', file=sys.stderr)
        return 2
    unused, missing = unused_pngs(root, files), missing_refs(root, files)
    print('Unused PNGs (file name mentioned by no tracked text file):')
    for p in unused:
        print(f'  {p}')
    print('Image references to files that do not exist:')
    for guide, ref in missing:
        print(f'  {guide}: {ref}')
    print(f'Unused PNGs: {len(unused)}')
    print(f'Missing image references: {len(missing)}')
    return 1 if args.strict and (unused or missing) else 0


if __name__ == '__main__':
    sys.exit(main())
