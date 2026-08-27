"""Step 03 - recover the Ruby cross-file call edges graphify's extractor misses.

Out of the box the graph connected only 31% of the real cross-file Ruby call relationships.
This resolves every constant receiver (`Const::Path.method`, `Const.new(...).method`, and
locals typed by `x = Const.new`) the way Ruby does - through the enclosing module nesting -
and refuses genuinely ambiguous constants rather than guessing.

Two details that matter and cost a debugging cycle each:

  * The caller is attributed to the `def` block that ACTUALLY contains the line. Falling
    back to "nearest preceding method node" silently blames the wrong method.
  * In Rails models the class node and the file node both sit on line 1. A naive
    by-line lookup returns the FILE node, so the target becomes `credential.rb` instead of
    `Credential`. Class-labelled nodes win here.

Every candidate edge is verified against its own cited source line before being written.
Additive only: nothing is removed.
"""
import collections
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'lib'))
from rbindex import load_all                                    # noqa: E402

GRAPH = Path('graphify-out/graph.json')
if not GRAPH.is_file():
    sys.exit('graph.json not found')

graph = json.loads(GRAPH.read_text(encoding='utf-8'))
nodes = {n['id']: n for n in graph['nodes']}

by_line = {}
method_at_line = {}
class_by_name = collections.defaultdict(dict)
file_node = {}
files_seen = set()
for node in graph['nodes']:
    source_file = node.get('source_file') or ''
    if not source_file:
        continue
    files_seen.add(source_file)
    label = node.get('label') or ''
    match = re.match(r'^L(\d+)$', str(node.get('source_location') or ''))
    line = int(match.group(1)) if match else None
    if line is not None:
        by_line.setdefault((source_file, line), node['id'])
        if re.match(r'^\.?[a-z_][A-Za-z0-9_]*[?!]?\(\)$', label):
            method_at_line.setdefault((source_file, line), node['id'])
    if label.endswith('.rb') and line == 1:
        file_node[source_file] = node['id']
    if source_file.endswith('.rb') and re.match(r'^[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*$', label):
        class_by_name[source_file][label.split('::')[-1]] = node['id']
        class_by_name[source_file].setdefault('__any__', node['id'])

ruby_files = sorted(f for f in files_seen if f.endswith('.rb'))
sources, const_index = load_all(ruby_files)


def resolve_const(ref, caller_file, line):
    """Ruby constant lookup: innermost enclosing module first, then top level."""
    if ref.startswith('::'):
        candidates = [ref[2:]]
    else:
        candidates = []
        rf = sources.get(caller_file)
        if rf is not None:
            for namespace in rf.nesting_at(line):
                candidates.append(namespace + '::' + ref)
        candidates.append(ref)
    for candidate in candidates:
        hit = const_index.get(candidate)
        if hit is not None:
            return (candidate, hit[0]) if len(hit) == 1 else (None, None)
    return None, None


def caller_node(source_file, line):
    rf = sources.get(source_file)
    if rf is not None:
        enclosing = rf.method_at(line)
        if enclosing:
            nid = method_at_line.get((source_file, enclosing[2])) or by_line.get((source_file, enclosing[2]))
            if nid:
                return nid
        nesting = rf.nesting_at(line)
        if nesting:
            nid = class_by_name.get(source_file, {}).get(nesting[0].split('::')[-1])
            if nid:
                return nid
    return file_node.get(source_file) or class_by_name.get(source_file, {}).get('__any__')


def target_node(fqn, decl, method):
    """Defined method node first, then the CLASS node, then the file node."""
    target_file, class_line, _end = decl
    rf = sources.get(target_file)
    if rf is None:
        return None
    wanted = 'initialize' if method == 'new' else method
    line = rf.method_line(wanted, fqn, prefer_self=None)
    if line is not None:
        nid = method_at_line.get((target_file, line)) or by_line.get((target_file, line))
        if nid:
            return nid
    simple = fqn.split('::')[-1]
    return (class_by_name.get(target_file, {}).get(simple)
            or class_by_name.get(target_file, {}).get('__any__')
            or file_node.get(target_file))


CONST_CALL = re.compile(
    r'(?<![:.\w])((?:::)?[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*)\.([a-z_][A-Za-z0-9_]*[!?]?)')
CHAIN_NEW = re.compile(
    r'(?<![:.\w])((?:::)?[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*)\.new\([^()]*\)\.([a-z_][A-Za-z0-9_]*[!?]?)')
ASSIGN_NEW = re.compile(r'^\s*([a-z_][A-Za-z0-9_]*)\s*=\s*((?:::)?[A-Z][A-Za-z0-9_:]*)\.new\b')
VAR_CALL = re.compile(r'(?<![.\w])([a-z_][A-Za-z0-9_]*)\.([a-z_][A-Za-z0-9_]*[!?]?)')

existing = {(e['source'], e['target']) for e in graph['links']}
candidates = []
kinds = collections.Counter()


def propose(source_file, line, src, tgt, kind, const):
    if not src or not tgt or src == tgt or (src, tgt) in existing:
        return
    candidates.append({'source': src, 'target': tgt, 'relation': 'calls',
                       'confidence': 'EXTRACTED', 'confidence_score': 1.0,
                       'source_file': source_file, 'source_location': 'L%d' % line,
                       'weight': 1.0, 'recovered': kind, '_const': const})
    existing.add((src, tgt))
    kinds[kind] += 1


for source_file in ruby_files:
    rf = sources.get(source_file)
    if rf is None:
        continue

    local_types = {}
    for _name, _is_self, start, end, _owner in rf.methods:
        found, ambiguous = {}, set()
        for idx in range(start, min(end, len(rf.lines)) + 1):
            if idx - 1 >= len(rf.lines):
                break
            m = ASSIGN_NEW.match(rf.lines[idx - 1].split('#', 1)[0])
            if m:
                var, const = m.group(1), m.group(2)
                if var in found and found[var] != const:
                    ambiguous.add(var)
                found[var] = const
        for var in ambiguous:
            found.pop(var, None)
        local_types[(start, end)] = found

    for i, raw in enumerate(rf.lines, 1):
        code = raw.split('#', 1)[0]
        if not code.strip():
            continue
        src_node = None

        for ref, method in CONST_CALL.findall(code):
            fqn, decl = resolve_const(ref, source_file, i)
            if fqn is None or decl[0] == source_file:
                continue
            src_node = src_node or caller_node(source_file, i)
            propose(source_file, i, src_node, target_node(fqn, decl, method), 'const_receiver', fqn)

        for ref, method in CHAIN_NEW.findall(code):
            fqn, decl = resolve_const(ref, source_file, i)
            if fqn is None or decl[0] == source_file:
                continue
            src_node = src_node or caller_node(source_file, i)
            propose(source_file, i, src_node, target_node(fqn, decl, method), 'chained_new', fqn)

        block = rf.method_at(i)
        if block:
            known = local_types.get((block[2], block[3]), {})
            for var, method in (VAR_CALL.findall(code) if known else []):
                const = known.get(var)
                if not const:
                    continue
                fqn, decl = resolve_const(const, source_file, i)
                if fqn is None or decl[0] == source_file:
                    continue
                src_node = src_node or caller_node(source_file, i)
                propose(source_file, i, src_node, target_node(fqn, decl, method), 'local_var', fqn)

# ---- self-verification: the cited line must actually contain the call ----------------
_lines = {}


def lines_of(path):
    if path not in _lines:
        _lines[path] = Path(path).read_text(encoding='utf-8', errors='ignore').splitlines()
    return _lines[path]


confirmed, rejected = [], 0
for edge in candidates:
    body = lines_of(edge['source_file'])
    i = int(edge['source_location'][1:])
    code = body[i - 1].split('#', 1)[0] if i - 1 < len(body) else ''
    if re.search(r'\b%s\b' % re.escape(edge['_const'].split('::')[-1]), code):
        edge.pop('_const')
        confirmed.append(edge)
    else:
        rejected += 1

graph['links'].extend(confirmed)
GRAPH.write_text(json.dumps(graph, ensure_ascii=False), encoding='utf-8')
print('03 ruby calls      : %d candidates | %d call-site confirmed, %d rejected | by kind %s'
      % (len(candidates), len(confirmed), rejected, dict(kinds)))
