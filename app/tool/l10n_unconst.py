"""Removes the `const` around each tr(...) the analyzer reports as a method
call in a constant expression. Reads `flutter analyze` machine output on
stdin. Run it again until no such errors remain."""
import re, sys
from collections import defaultdict

OPEN, CLOSE = '([{', ')]}'


def expr_end(s, i):
    """End of the expression starting at s[i] (after `const `)."""
    n = len(s)
    while i < n and (s[i].isalnum() or s[i] in '_.<>, ?'):
        if s[i] in '([{':
            break
        i += 1
    if i >= n or s[i] not in OPEN:
        return i
    depth, q = 0, None
    while i < n:
        c = s[i]
        if q:
            if c == '\\':
                i += 2
                continue
            if c == q:
                q = None
        elif c in '\'"':
            q = c
        elif c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


errors = defaultdict(list)
for line in sys.stdin:
    p = line.strip().split('|')
    if len(p) >= 8 and p[0] == 'ERROR' and p[2] in ('CONST_EVAL_METHOD_INVOCATION', 'INVALID_CONSTANT', 'CONST_WITH_NON_CONSTANT_ARGUMENT', 'NON_CONSTANT_LIST_ELEMENT', 'NON_CONSTANT_MAP_VALUE', 'CONST_INITIALIZED_WITH_NON_CONSTANT_VALUE'):
        errors[p[3]].append((int(p[4]), int(p[5])))

for path, locs in errors.items():
    s = open(path, encoding='utf-8').read()
    starts = [0]
    for m in re.finditer('\n', s):
        starts.append(m.end())
    removed = set()
    for ln, col in locs:
        off = starts[ln - 1] + col - 1
        for m in reversed(list(re.finditer(r'\bconst\s+', s[:off]))):
            if expr_end(s, m.end()) > off:
                removed.add((m.start(), m.end()))
                break
    for a, b in sorted(removed, reverse=True):
        s = s[:a] + s[b:]
    open(path, 'w', encoding='utf-8').write(s)
    print(path, 'unconst', len(removed))
