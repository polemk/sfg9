"""Verify the graph. Exits non-zero on regression, so rebuild.sh fails loudly.

Measures BOTH sides, because they fail independently and one hides the other:

  * precision - do the edges that exist correspond to real calls in source?
  * recall    - do the real calls in source have edges?

The graph once had 100% precision and 31% recall: everything it said was true, and absence
of an edge meant nothing. Only a recall check catches that.

Two traps this file encodes so nobody falls into them again:
  * Direction MUST come from the DiGraph / the links' source-target, never from networkx
    edge iteration order on an undirected graph.
  * `Foo.new` in source is a call to the `initialize` node. A naive name-presence check
    reports those as false edges; they are correct.
"""
import collections
import json
import os
import re
import sys
from pathlib import Path

import networkx as nx
from networkx.readwrite import json_graph

sys.path.insert(0, str(Path(__file__).resolve().parent / 'lib'))
from rbindex import load_all as load_ruby          # noqa: E402
from tsindex import load_all as load_ts            # noqa: E402

THRESHOLDS = {
    'max_false_call_edges': 0,
    'max_cross_language_edges': 0,
    'min_ruby_recall_pct': 99.0,
    'min_ts_recall_pct': 99.0,
}

GRAPH = Path('graphify-out/graph.json')
if not GRAPH.is_file():
    sys.exit('graph.json not found')

data = json.loads(GRAPH.read_text(encoding='utf-8'))
graph = json_graph.node_link_graph(data, edges='links')
nodes = {n['id']: n for n in data['nodes']}
ids = set(nodes)
failures = []

_text = {}


def text(path):
    if path not in _text:
        try:
            _text[path] = Path(path).read_text(encoding='utf-8', errors='ignore')
        except Exception:
            _text[path] = ''
    return _text[path]


def bare(label):
    return (label or '').strip().lstrip('.').rstrip('()').strip()


print('== artifact')
print('   directed=%s  nodes=%d  edges=%d  hyperedges=%d  communities=%d'
      % (data.get('directed'), graph.number_of_nodes(), graph.number_of_edges(),
         len(data.get('hyperedges', [])), len({n.get('community') for n in data['nodes']})))
if not data.get('directed'):
    failures.append('graph is not directed')

print('== integrity')
checks = [
    ('nodes without source_file', sum(1 for n in data['nodes'] if not (n.get('source_file') or ''))),
    ('source_file missing on disk', sum(1 for n in data['nodes']
                                        if (n.get('source_file') or '') and not Path(n['source_file']).is_file())),
    ('links with unknown endpoint', sum(1 for e in data['links']
                                        if e['source'] not in ids or e['target'] not in ids)),
    ('hyperedges with dangling member', sum(1 for h in data.get('hyperedges', [])
                                            if any(m not in ids for m in h.get('nodes', [])))),
    ('self-loops', nx.number_of_selfloops(graph)),
    ('edges missing confidence_score', sum(1 for e in data['links']
                                           if not isinstance(e.get('confidence_score'), (int, float)))),
    ('out-of-scope nodes remaining', sum(1 for n in data['nodes']
                                         if any((n.get('source_file') or '').startswith(p)
                                                for p in ('.trae/', '.agent/', 'node_modules/')))),
]
for name, value in checks:
    print('   %-34s %d' % (name, value))
    if value:
        failures.append('%s = %d (expected 0)' % (name, value))

print('== precision')
LANG = {'.rb': 'ruby', '.ts': 'ts', '.tsx': 'ts', '.js': 'ts', '.jsx': 'ts', '.py': 'python'}
cross_language = 0
side = collections.defaultdict(lambda: collections.Counter())
examples = []
for u, v, edge in graph.edges(data=True):
    lu = LANG.get(os.path.splitext(nodes[u].get('source_file') or '')[1].lower(), 'other')
    lv = LANG.get(os.path.splitext(nodes[v].get('source_file') or '')[1].lower(), 'other')
    if lu != lv and lu in ('ruby', 'ts', 'python') and lv in ('ruby', 'ts', 'python'):
        cross_language += 1
    if edge.get('relation') != 'calls':
        continue
    caller_file = nodes[u].get('source_file') or ''
    if caller_file == (nodes[v].get('source_file') or ''):
        continue
    callee = bare(nodes[v].get('label'))
    if not callee or not re.match(r'^[A-Za-z_][A-Za-z0-9_]*[?!]?$', callee):
        continue
    source = text(caller_file)
    if not source:
        continue
    name = callee.rstrip('?!')
    found = re.search(r'\b%s\b' % re.escape(name), source) is not None
    if not found and name == 'initialize' and re.search(r'\.new\b', source):
        found = True                      # Foo.new -> initialize; not a mismatch
    bucket = 'backend' if caller_file.startswith('backend') else 'frontend'
    side[bucket]['ok' if found else 'bad'] += 1
    if not found and len(examples) < 5:
        examples.append('%s (%s) -> %s' % (nodes[u].get('label'), caller_file, nodes[v].get('label')))

checked = sum(c['ok'] + c['bad'] for c in side.values())
false_edges = sum(c['bad'] for c in side.values())
print('   cross-language edges              %d' % cross_language)
print('   cross-file calls checked          %d, false %d (%.2f%%)'
      % (checked, false_edges, 100.0 * false_edges / max(checked, 1)))
for bucket, counter in sorted(side.items()):
    print('     %-8s %5d checked | %d false' % (bucket, counter['ok'] + counter['bad'], counter['bad']))
for example in examples:
    print('     ! %s' % example)
if cross_language > THRESHOLDS['max_cross_language_edges']:
    failures.append('cross-language edges = %d' % cross_language)
if false_edges > THRESHOLDS['max_false_call_edges']:
    failures.append('false call edges = %d' % false_edges)

print('== recall (ruby)')
nodes_by_file = collections.defaultdict(list)
for node in data['nodes']:
    if node.get('source_file'):
        nodes_by_file[node['source_file']].append(node['id'])
connected_pairs = set()
for u, v in graph.edges():
    a, b = nodes[u].get('source_file') or '', nodes[v].get('source_file') or ''
    if a and b and a != b:
        connected_pairs.add((a, b))
        connected_pairs.add((b, a))

ruby_files = sorted(f for f in nodes_by_file if f.endswith('.rb'))
ruby, const_index = load_ruby(ruby_files)
CONST_CALL = re.compile(
    r'(?<![:.\w])((?:::)?[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*)\.([a-z_][A-Za-z0-9_]*[!?]?)')


def resolve(ref, caller, line):
    if ref.startswith('::'):
        candidates = [ref[2:]]
    else:
        candidates = []
        rf = ruby.get(caller)
        if rf is not None:
            for namespace in rf.nesting_at(line):
                candidates.append(namespace + '::' + ref)
        candidates.append(ref)
    for candidate in candidates:
        hit = const_index.get(candidate)
        if hit is not None:
            return (candidate, hit[0]) if len(hit) == 1 else (None, None)
    return None, None


real_pairs = collections.defaultdict(int)
for source_file in ruby_files:
    rf = ruby.get(source_file)
    if rf is None:
        continue
    for i, raw in enumerate(rf.lines, 1):
        code = raw.split('#', 1)[0]
        if not code.strip():
            continue
        for ref, method in CONST_CALL.findall(code):
            fqn, decl = resolve(ref, source_file, i)
            if fqn is None or decl[0] == source_file:
                continue
            real_pairs[(source_file, decl[0])] += 1

linked = sum(1 for pair in real_pairs if pair in connected_pairs)
ruby_recall = 100.0 * linked / max(len(real_pairs), 1)
print('   cross-file call relationships     %d' % len(real_pairs))
print('   connected in graph                %d (%.1f%%)' % (linked, ruby_recall))
if ruby_recall < THRESHOLDS['min_ruby_recall_pct']:
    failures.append('ruby recall %.1f%% < %.1f%%' % (ruby_recall, THRESHOLDS['min_ruby_recall_pct']))

print('== recall (typescript)')
BLOCK_COMMENT = re.compile(r'/\*.*?\*/', re.S)
symbol_node = {}
for node in data['nodes']:
    source_file = node.get('source_file') or ''
    if not source_file.endswith(('.ts', '.tsx')):
        continue
    name = (node.get('label') or '').strip().rstrip('()').lstrip('.')
    if re.match(r'^[A-Za-z_$][\w$]*$', name):
        symbol_node.setdefault((source_file, name), node['id'])

pair_nodes = set()
for u, v in graph.edges():
    pair_nodes.add((u, v))
    pair_nodes.add((v, u))

ts_files = sorted(f for f in nodes_by_file if f.endswith(('.ts', '.tsx')))
ts = load_ts(ts_files)
used = ts_linked = 0
ts_missing = []
for path, tsfile in ts.items():
    body = BLOCK_COMMENT.sub('', tsfile.src)      # commented-out code is not a usage
    for name, target, line in tsfile.imports:
        pattern = re.compile(r'(?<![.\w$])%s\s*[(<.]' % re.escape(name))
        hits = [m for m in pattern.finditer(body)]
        if not hits:
            continue
        used += 1
        target_id = symbol_node.get((target, name))
        candidates = [target_id] if target_id else nodes_by_file.get(target, [])
        if any((s, t) in pair_nodes for s in nodes_by_file.get(path, []) for t in candidates if t):
            ts_linked += 1
        else:
            ts_missing.append('%s uses %s from %s' % (path, name, target))

ts_recall = 100.0 * ts_linked / max(used, 1)
print('   imported-and-used symbols         %d' % used)
print('   linked in graph                   %d (%.1f%%)' % (ts_linked, ts_recall))
for m in ts_missing[:5]:
    print('     ! %s' % m)
if ts_recall < THRESHOLDS['min_ts_recall_pct']:
    failures.append('typescript recall %.1f%% < %.1f%%' % (ts_recall, THRESHOLDS['min_ts_recall_pct']))

undirected = graph.to_undirected()
components = sorted((len(c) for c in nx.connected_components(undirected)), reverse=True)
print('== connectivity')
print('   isolated nodes %d | components %d | largest %d (%.1f%%)'
      % (sum(1 for n in graph if graph.degree(n) == 0), len(components),
         components[0], 100.0 * components[0] / graph.number_of_nodes()))

print()
if failures:
    print('FAILED (%d):' % len(failures))
    for f in failures:
        print('  - %s' % f)
    sys.exit(1)
print('OK - all checks passed')
