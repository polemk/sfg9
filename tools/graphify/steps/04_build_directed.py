"""Step 04 - rebuild graph.json as a DiGraph, losslessly, and recompute communities.

Two things this deliberately does NOT do:

  * It does not use graphify's build_from_json(directed=True). That re-derives node ids from
    source_file + label and collides on repeated namespace segments; on this repo it silently
    dropped 201 nodes, 176 of them inside backend/ or frontend/ (Api::Auth::V1::Checkout,
    Api::Entities::Category, ...). Ids are preserved verbatim here instead.
  * It does not round-trip edges through an undirected graph. networkx edge iteration order
    does not preserve source/target, and reading direction from it produced a completely
    bogus "40% of call edges are fabricated" finding once. Direction comes from the links.
"""
import collections
import json
import os
import sys
from pathlib import Path

# Louvain iterates string-keyed sets, whose order depends on PYTHONHASHSEED. Without
# pinning it, every run reshuffles community ids - 3226 of 5768 nodes changed community
# between two runs of the same input, producing a huge meaningless diff on every commit.
# The seed is read at interpreter startup, so it has to be set before we re-exec.
if os.environ.get('PYTHONHASHSEED') != '0':
    os.environ['PYTHONHASHSEED'] = '0'
    os.execv(sys.executable, [sys.executable] + sys.argv)

import networkx as nx
from networkx.readwrite import json_graph

from graphify.analyze import god_nodes, suggest_questions, surprising_connections
from graphify.cluster import cluster, score_all
from graphify.report import generate

GRAPH = Path('graphify-out/graph.json')
if not GRAPH.is_file():
    sys.exit('graph.json not found')

data = json.loads(GRAPH.read_text(encoding='utf-8'))
print('04 build directed  : source %d nodes, %d links' % (len(data['nodes']), len(data['links'])))

digraph = nx.DiGraph()
for node in data['nodes']:
    digraph.add_node(node['id'], **{k: v for k, v in node.items() if k not in ('id', 'community')})
skipped = 0
for edge in data['links']:
    src, tgt = edge.get('source'), edge.get('target')
    if src not in digraph or tgt not in digraph:
        skipped += 1
        continue
    digraph.add_edge(src, tgt, **{k: v for k, v in edge.items() if k not in ('source', 'target')})

assert digraph.is_directed(), 'expected a directed graph'
assert digraph.number_of_nodes() == len(data['nodes']), 'node loss during build'

undirected = digraph.to_undirected()          # Louvain needs an undirected view
communities = cluster(undirected)
try:
    cohesion = score_all(digraph, communities)
except Exception:
    cohesion = score_all(undirected, communities)

out = json_graph.node_link_data(digraph, edges='links')
out['hyperedges'] = data.get('hyperedges', [])
out['built_at_commit'] = data.get('built_at_commit')
node_community = {m: cid for cid, members in communities.items() for m in members}
for node in out['nodes']:
    node['community'] = node_community.get(node['id'])
assert out['directed'] is True
GRAPH.write_text(json.dumps(out, ensure_ascii=False), encoding='utf-8')

# a placeholder report; step 05 rewrites it with real community labels
manifest = json.loads(Path('graphify-out/manifest.json').read_text(encoding='utf-8'))
manifest = [f for f in manifest if not (f.startswith('.trae/') or '/.trae/' in f)]
EXT = {'.rb': 'code', '.ts': 'code', '.tsx': 'code', '.js': 'code', '.jsx': 'code',
       '.py': 'code', '.sh': 'code', '.json': 'code', '.md': 'document', '.txt': 'document',
       '.yml': 'document', '.yaml': 'document', '.html': 'document'}
files = collections.defaultdict(list)
words = 0
for f in manifest:
    files[EXT.get(os.path.splitext(f)[1].lower(), 'code')].append(f)
    try:
        words += len(Path(f).read_text(encoding='utf-8', errors='ignore').split())
    except Exception:
        pass
detection = {'files': dict(files), 'total_files': len(manifest), 'total_words': words,
             'scan_root': str(Path('.').resolve()), 'skipped_sensitive': [], 'unclassified': [],
             'walk_errors': [], 'warning': None, 'needs_graph': True, 'graphifyignore_patterns': []}
labels = {cid: 'Community %d' % cid for cid in communities}
report = generate(digraph, communities, cohesion, labels, god_nodes(digraph),
                  surprising_connections(digraph, communities), detection,
                  {'input': 0, 'output': 0}, '.',
                  suggested_questions=suggest_questions(digraph, communities, labels))
Path('graphify-out/GRAPH_REPORT.md').write_text(report, encoding='utf-8')

print('04 build directed  : DiGraph %d nodes, %d edges, %d communities (skipped %d links)'
      % (digraph.number_of_nodes(), digraph.number_of_edges(), len(communities), skipped))
