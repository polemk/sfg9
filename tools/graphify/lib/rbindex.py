"""Ruby source model: class/module nesting, method ranges, constant index (Zeitwerk-style)."""
import re
from pathlib import Path

DECL = re.compile(r'^(\s*)(class|module)\s+([A-Z][A-Za-z0-9_:]*)')
DEF  = re.compile(r'^(\s*)def\s+(self\.)?([a-z_][A-Za-z0-9_]*[?!=]?)')

def _block_end(lines, start_idx, indent):
    for j in range(start_idx, len(lines)):
        s = lines[j]
        st = s.strip()
        if st == 'end' and (len(s) - len(s.lstrip())) == indent:
            return j + 1
    return len(lines)

class RubyFile:
    __slots__ = ('path','lines','decls','methods')
    def __init__(self, path, src):
        self.path = path
        self.lines = src.splitlines()
        self.decls = []     # (fqn, start, end, indent)
        self.methods = []   # (name, is_self, start, end, owner_fqn)
        self._parse()

    def _parse(self):
        stack = []  # (indent, name)
        for i, ln in enumerate(self.lines, 1):
            m = DECL.match(ln)
            if m:
                indent, _, name = len(m.group(1)), m.group(2), m.group(3)
                while stack and stack[-1][0] >= indent: stack.pop()
                prefix = '::'.join(n for _, n in stack)
                fqn = (prefix + '::' + name) if prefix and not name.startswith('::') else name
                fqn = fqn.lstrip(':')
                end = _block_end(self.lines, i, indent)
                self.decls.append((fqn, i, end, indent))
                stack.append((indent, name))
                continue
            d = DEF.match(ln)
            if d:
                indent, is_self, name = len(d.group(1)), bool(d.group(2)), d.group(3)
                end = _block_end(self.lines, i, indent)
                owner = None
                for fqn, s, e, ind in self.decls:
                    if s <= i <= e and (owner is None or s > owner[1]): owner = (fqn, s)
                self.methods.append((name, is_self, i, end, owner[0] if owner else None))

    def nesting_at(self, line):
        out = [(s, fqn) for fqn, s, e, _ in self.decls if s <= line <= e]
        out.sort(key=lambda t: -t[0])
        return [fqn for _, fqn in out]

    def method_at(self, line):
        best = None
        for name, is_self, s, e, owner in self.methods:
            if s <= line <= e and (best is None or s > best[2]):
                best = (name, is_self, s, e, owner)
        return best

    def has_class_method(self, name, owner_fqn):
        return any(n == name and iss and (owner is None or owner == owner_fqn)
                   for n, iss, s, e, owner in self.methods)

    def has_instance_method(self, name, owner_fqn):
        return any(n == name and not iss and (owner is None or owner == owner_fqn)
                   for n, iss, s, e, owner in self.methods)

    def method_line(self, name, owner_fqn, prefer_self=None):
        cands = [(s, iss) for n, iss, s, e, owner in self.methods
                 if n == name and (owner is None or owner == owner_fqn)]
        if not cands: return None
        if prefer_self is not None:
            for s, iss in cands:
                if iss == prefer_self: return s
        return cands[0][0]

def load_all(paths):
    files, const_index = {}, {}
    for p in paths:
        try: src = Path(p).read_text(encoding='utf-8', errors='ignore')
        except Exception: continue
        rf = RubyFile(p, src)
        files[p] = rf
        for fqn, s, e, _ in rf.decls:
            const_index.setdefault(fqn, []).append((p, s, e))
    return files, const_index
