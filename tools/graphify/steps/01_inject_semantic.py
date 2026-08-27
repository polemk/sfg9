"""Step 01 - re-inject the versioned LLM-extracted semantic layer into graph.json.

The standard graphify pipeline only reproduces the AST layer. The doc/convention concepts
were produced by LLM extraction, so they are versioned in tools/graphify/semantic-layer.json
and injected here. Every item is validated before it is accepted.
"""
import json
import re
import sys
from pathlib import Path

GRAPH = Path('graphify-out/graph.json')
LAYER = Path('tools/graphify/semantic-layer.json')
OK_FILE_TYPE = {'code', 'document', 'paper', 'image', 'rationale', 'concept'}

if not GRAPH.is_file():
    sys.exit('graph.json not found - run graphify first')
if not LAYER.is_file():
    sys.exit('semantic-layer.json not found')

graph = json.loads(GRAPH.read_text(encoding='utf-8'))
layer = json.loads(LAYER.read_text(encoding='utf-8'))
ids = {n['id'] for n in graph['nodes']}

added_nodes = rejected_nodes = 0
for node in layer['nodes']:
    if node['id'] in ids:
        continue
    source_file = node.get('source_file') or ''
    if not re.match(r'^[a-z0-9_]+$', node['id']):
        rejected_nodes += 1
        continue
    if node.get('file_type') not in OK_FILE_TYPE:
        rejected_nodes += 1
        continue
    if not Path(source_file).is_file():
        # the file was deleted since the layer was captured - drop the node, do not guess
        rejected_nodes += 1
        continue
    graph['nodes'].append({
        'id': node['id'],
        'label': node.get('label'),
        'file_type': node.get('file_type'),
        'source_file': source_file,
        'source_location': node.get('source_location') or '',
        '_origin': 'semantic',
        'norm_label': (node.get('label') or '').strip().lower(),
    })
    ids.add(node['id'])
    added_nodes += 1

seen_pairs = {(e['source'], e['target']) for e in graph['links']}
added_edges = present_edges = rejected_edges = 0
for edge in layer['edges']:
    src, tgt = edge.get('source'), edge.get('target')
    if (src, tgt) in seen_pairs:
        present_edges += 1               # already in the graph - expected on a re-run
        continue
    if src not in ids or tgt not in ids or src == tgt:
        rejected_edges += 1
        continue
    score = edge.get('confidence_score')
    if not isinstance(score, (int, float)) or score <= 0:
        rejected_edges += 1
        continue
    graph['links'].append(dict(edge))
    seen_pairs.add((src, tgt))
    added_edges += 1

graph.setdefault('hyperedges', [])
have = {h.get('id') for h in graph['hyperedges']}
added_hyper = present_hyper = rejected_hyper = 0
for hyper in layer.get('hyperedges', []):
    members = hyper.get('nodes') or []
    if hyper.get('id') in have:
        present_hyper += 1
        continue
    if len(set(members)) < 3 or any(m not in ids for m in members):
        rejected_hyper += 1
        continue
    graph['hyperedges'].append(hyper)
    have.add(hyper['id'])
    added_hyper += 1

GRAPH.write_text(json.dumps(graph, ensure_ascii=False), encoding='utf-8')
print('01 inject semantic : nodes +%d | edges +%d | hyperedges +%d '
      '(already present: %d/%d/%d, rejected: %d/%d/%d)'
      % (added_nodes, added_edges, added_hyper,
         len(layer['nodes']) - added_nodes - rejected_nodes, present_edges, present_hyper,
         rejected_nodes, rejected_edges, rejected_hyper))
