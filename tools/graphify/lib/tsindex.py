"""TypeScript source model: imports (with @/ alias + extension resolution), top-level
declaration ranges, and call sites. Regex-based, deliberately conservative."""
import re
from pathlib import Path

IMPORT = re.compile(
    r'import\s+(?:type\s+)?(?P<clause>[^\'"]+?)\s+from\s+[\'"](?P<mod>[^\'"]+)[\'"]',
    re.M)
DECL = re.compile(
    r'^(?P<ind>\s*)(?:export\s+)?(?:export\s+default\s+)?'
    r'(?:async\s+)?(?:function|const|let|class|interface|type|enum)\s+'
    r'(?P<name>[A-Za-z_$][\w$]*)', re.M)

ALIAS_PREFIX = '@/'
ALIAS_ROOT = 'frontend/src/'
EXTS = ('.ts', '.tsx', '.d.ts')


def resolve_module(mod, from_file):
    """Return a repo-relative file path, or None for a package/unresolvable import."""
    if mod.startswith(ALIAS_PREFIX):
        base = ALIAS_ROOT + mod[len(ALIAS_PREFIX):]
    elif mod.startswith('.'):
        base = str((Path(from_file).parent / mod).as_posix())
        # normalise .. segments
        parts = []
        for seg in base.split('/'):
            if seg == '..':
                if parts:
                    parts.pop()
            elif seg not in ('.', ''):
                parts.append(seg)
        base = '/'.join(parts)
    else:
        return None                      # npm package
    for cand in [base + e for e in EXTS] + [base + '/index' + e for e in EXTS] + [base]:
        if Path(cand).is_file():
            return cand
    return None


def parse_clause(clause):
    """Return list of locally-bound names from an import clause."""
    clause = clause.strip()
    names = []
    m = re.search(r'\{(?P<inner>[^}]*)\}', clause)
    if m:
        for part in m.group('inner').split(','):
            part = part.strip()
            if not part:
                continue
            part = re.sub(r'^type\s+', '', part)
            if ' as ' in part:
                part = part.split(' as ')[-1]
            part = part.strip()
            if re.match(r'^[A-Za-z_$][\w$]*$', part):
                names.append(part)
        clause = clause[:m.start()] + clause[m.end():]
    for part in clause.split(','):
        part = part.strip().rstrip(',')
        if not part or part.startswith('*'):
            continue
        if ' as ' in part:
            part = part.split(' as ')[-1].strip()
        if re.match(r'^[A-Za-z_$][\w$]*$', part):
            names.append(part)
    return names


class TsFile:
    __slots__ = ('path', 'lines', 'src', 'decls', 'imports')

    def __init__(self, path, src):
        self.path = path
        self.src = src
        self.lines = src.splitlines()
        self.decls = []       # (name, start_line, end_line)
        self.imports = []     # (local_name, module_file, line)
        self._parse()

    def _parse(self):
        starts = []
        for m in DECL.finditer(self.src):
            line = self.src[:m.start()].count('\n') + 1
            starts.append((line, m.group('name'), len(m.group('ind'))))
        for i, (line, name, ind) in enumerate(starts):
            end = starts[i + 1][0] - 1 if i + 1 < len(starts) else len(self.lines)
            self.decls.append((name, line, end))
        for m in IMPORT.finditer(self.src):
            line = self.src[:m.start()].count('\n') + 1
            tgt = resolve_module(m.group('mod'), self.path)
            if not tgt:
                continue
            for nm in parse_clause(m.group('clause')):
                self.imports.append((nm, tgt, line))

    def decl_at(self, line):
        best = None
        for name, s, e in self.decls:
            if s <= line <= e and (best is None or s > best[1]):
                best = (name, s, e)
        return best


def load_all(paths):
    out = {}
    for p in paths:
        try:
            out[p] = TsFile(p, Path(p).read_text(encoding='utf-8', errors='ignore'))
        except Exception:
            continue
    return out
