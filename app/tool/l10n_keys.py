"""Collects every text the app translates: the English in tr('...'),
trn(n, 'one', 'other') (keyed by "other", with "one" alongside) and tk('...')
calls in lib/, and lib/l10n/keys.dart. Prints JSON {key: one-form or null}.

  python3 tool/l10n_keys.py > /tmp/keys.json
  python3 tool/l10n_keys.py --missing assets/l10n/es.json   # keys without a translation
"""
import glob, json, re, sys

LIT = r"""(?:r?'(?:\\.|[^'\\\n])*'|r?"(?:\\.|[^"\\\n])*")"""
LITS = r"(?:" + LIT + r"\s*)+"


def unquote(group):
    out = []
    for m in re.finditer(LIT, group):
        s = m.group(0)
        raw = s.startswith('r')
        body = s[2:-1] if raw else s[1:-1]
        if not raw:
            body = re.sub(r"\\u([0-9a-fA-F]{4})|\\(.)", lambda e: chr(int(e.group(1), 16)) if e.group(1) else {'n': '\n', 't': '\t'}.get(e.group(2), e.group(2)), body)
        out.append(body)
    return ''.join(out)


def keys():
    found = {}
    for path in sorted(glob.glob('lib/**/*.dart', recursive=True)):
        src = open(path, encoding='utf-8').read()
        if path.endswith('l10n/l10n.dart'):
            continue
        if path.endswith('l10n/keys.dart'):
            for m in re.finditer(LIT, src[src.index('['):]):
                found.setdefault(unquote(m.group(0)), None)
            continue
        for m in re.finditer(r"\b(?:tr|tk)\(\s*(" + LITS + r")\s*[,)]", src):
            found.setdefault(unquote(m.group(1)), None)
        for m in re.finditer(r"\btrn\(\s*[^,]+?,\s*(" + LITS + r")\s*,\s*(" + LITS + r")\s*[,)]", src):
            found[unquote(m.group(2))] = unquote(m.group(1))
    return found


if __name__ == '__main__':
    k = keys()
    if len(sys.argv) > 2 and sys.argv[1] == '--missing':
        have = json.load(open(sys.argv[2], encoding='utf-8'))
        k = {key: one for key, one in k.items() if key not in have}
    json.dump(k, sys.stdout, ensure_ascii=False, indent=1)
    print(f"\n{len(k)} keys", file=sys.stderr)
