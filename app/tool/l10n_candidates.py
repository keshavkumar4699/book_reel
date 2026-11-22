"""Lists string literals in lib/ that look like text people read and aren't
wrapped in tr()/trn()/tk() yet. Usage: python3 tool/l10n_candidates.py [files]"""
import re, sys, glob

LIT = re.compile(r"""(?P<q>'|")(?P<body>(?:\\.|(?!(?P=q)).)*)(?P=q)""")
SKIP_LINE = re.compile(r"^\s*(import|export|part|library|@|//|\*|///)")
SKIP_CTX = re.compile(r"(debugPrint|print|Exception|Error|assert|ValueKey|Key|RegExp|Uri\.parse|Uri\(|loadString|Image\.asset|fontFamily|\bcase\b|tr\(|trn\(|tk\(|jsonDecode|\.doc\(|saveDoc|semanticsLabel:\s*null)\s*\(?\s*$")

def candidates(path):
    out = []
    for no, line in enumerate(open(path, encoding='utf-8').read().split('\n'), 1):
        if SKIP_LINE.match(line):
            continue
        for m in LIT.finditer(line):
            body = m.group('body')
            before = line[:m.start()]
            after = line[m.end():]
            if not re.search(r"[A-Za-z]", body):
                continue
            if re.search(r"(tr|trn|tk)\(\s*$", before) or re.search(r"(tr|trn)\([^()]*$", before) and before.count('(') > before.count(')'):
                pass
            if re.search(r"\b(tr|trn|tk)\($", before.rstrip()):
                continue
            if re.match(r"^\s*:", after) and not re.search(r"\?\s*$", before):  # map key 'x':
                continue
            if before.rstrip().endswith('[') or re.search(r"(\bcase|==|!=)\s*$", before):
                continue
            if body.startswith(('/', 'assets/', 'http', 'package:', 'dart:', 'x-', '#', '%')):
                continue
            if re.fullmatch(r"[a-z_][A-Za-z0-9_.\-]*", body):  # identifiers, keys, codes
                continue
            if re.fullmatch(r"[A-Za-z0-9_.\-]+\.(dart|json|txt|md|png|jpg|mp3|onnx|bin|wav|tsv|gz)", body):
                continue
            if SKIP_CTX.search(before):
                continue
            out.append((no, body, line.strip()[:150]))
    return out

if __name__ == '__main__':
    files = sys.argv[1:] or sorted(glob.glob('lib/**/*.dart', recursive=True))
    total = 0
    for f in files:
        if '/l10n/' in f:
            continue
        c = candidates(f)
        total += len(c)
        for no, body, line in c:
            print(f"{f}:{no}: {line}")
    print('TOTAL', total, file=sys.stderr)
