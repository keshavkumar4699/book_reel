"""Wraps plain text literals in tr(...) in the given Dart files.

  python3 tool/l10n_wrap.py FILE [--skip TEXT ...] [--skip-line N ...] [--dry]

Literals on lines with ${ (interpolation) are left for hand conversion and
listed. The file gets `import '.../l10n/l10n.dart';` if it needs it."""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from l10n_candidates import candidates, LIT

GLOBAL_SKIP = {'Reader', 'Cloro', '·', '…'}

def main():
    args = sys.argv[1:]
    path = args.pop(0)
    skips, skip_lines, dry = set(GLOBAL_SKIP), set(), False
    while args:
        a = args.pop(0)
        if a == '--skip': skips.add(args.pop(0))
        elif a == '--skip-line': skip_lines.add(int(args.pop(0)))
        elif a == '--dry': dry = True
    lines = open(path, encoding='utf-8').read().split('\n')
    wanted = {}
    for no, body, _ in candidates(path):
        wanted.setdefault(no, set()).add(body)
    manual = []
    changed = 0
    for no, bodies in wanted.items():
        line = lines[no - 1]
        if no in skip_lines:
            continue
        if '${' in line or re.search(r"\$[a-zA-Z_]", line):
            manual.append((no, line.strip()))
            continue
        out, last = [], 0
        for m in LIT.finditer(line):
            body = m.group('body')
            if body in bodies and body not in skips and not re.search(r"\b(tr|trn|tk)\($", line[:m.start()].rstrip()):
                out.append(line[last:m.start()])
                out.append(f"tr({m.group(0)})")
                last = m.end()
                changed += 1
        out.append(line[last:])
        lines[no - 1] = ''.join(out)
    if changed and not dry:
        src = '\n'.join(lines)
        if "l10n/l10n.dart'" not in src:
            depth = path.count('/') - 1  # lib/x/y.dart -> ../
            rel = '../' * (depth) + 'l10n/l10n.dart' if depth else 'l10n/l10n.dart'
            imports = [i for i, l in enumerate(lines) if l.startswith('import ')]
            lines.insert(imports[-1] + 1, f"import '{rel}';")
            src = '\n'.join(lines)
        open(path, 'w', encoding='utf-8').write(src)
    print(f"{path}: wrapped {changed}")
    for no, l in manual:
        print(f"  MANUAL {no}: {l[:160]}")

main()
