"""Merges tr('a') tr('b') (adjacent literals split by l10n_wrap) into tr('a' 'b')."""
import re, sys
L = r"""(?:'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*")"""
pat = re.compile(r"tr\(((?:" + L + r"\s*)+)\)(\s*)tr\((" + L + r")\)")
for path in sys.argv[1:]:
    s = open(path, encoding='utf-8').read()
    n = 0
    while True:
        s2, k = pat.subn(lambda m: f"tr({m.group(1)}{m.group(2)}{m.group(3)})", s)
        if not k:
            break
        s, n = s2, n + k
    # tr('a') followed by a plain literal (the rest was left for hand work)
    open(path, 'w', encoding='utf-8').write(s)
    print(path, 'merged', n)
