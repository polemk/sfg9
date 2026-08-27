"""Step 02 - remove the four classes of edge/node that graphify's extractor gets wrong here.

Each rule below was verified against source before being turned into a rule. Nothing is
pruned on suspicion.

  1. cross-language edges (ruby <-> ts). All 87 seen were case-folding collisions: Ruby's
     stdlib `Time` matched against a TypeScript `const TIME` (which is Portuguese for
     "team", a staff roster). No Ruby file in this repo defines a TIME constant.
  2. nodes with no source_file. External symbol names (Path, str, Any, BaseModel) leaked
     in from out-of-scope Python files; they carry no repo information.
  3. out-of-scope trees (see EXCLUDED_PREFIXES). `.trae/**` is obsolete specs; `.agent/**`
     is agent scaffolding, 2217 files that would dominate the graph without describing the
     application. This is also what keeps the hook honest: graphify's own rebuild scans the
     whole repo, so without this rule the graph grows past 18k nodes on every commit.
  4. self-loops. Both seen were `class X < ExternalGem::X` where the extractor resolved the
     bare parent name back onto the child. No class inherits from itself.

Direction is preserved: links are filtered in place, never round-tripped through networkx
(iteration order on an undirected graph does NOT preserve source/target).
"""
import json
import os
import re
import sys
from pathlib import Path

GRAPH = Path('graphify-out/graph.json')
if not GRAPH.is_file():
    sys.exit('graph.json not found')

graph = json.loads(GRAPH.read_text(encoding='utf-8'))
nodes = {n['id']: n for n in graph['nodes']}

LANG = {'.rb': 'ruby', '.erb': 'ruby', '.rake': 'ruby',
        '.ts': 'ts', '.tsx': 'ts', '.js': 'ts', '.jsx': 'ts', '.mjs': 'ts', '.cjs': 'ts',
        '.py': 'python'}
CODE = {'ruby', 'ts', 'python'}


def language(node_id):
    source_file = nodes.get(node_id, {}).get('source_file') or ''
    return LANG.get(os.path.splitext(source_file)[1].lower(), 'other')


EXCLUDED_PREFIXES = ('.trae/', '.agent/', 'node_modules/')


def out_of_scope(source_file):
    source_file = source_file or ''
    return any(source_file.startswith(p) or ('/' + p) in source_file
               for p in EXCLUDED_PREFIXES)


def source_sumiu(source_file):
    """O arquivo citado nao existe mais no disco.

    O `verify.py` reprova `source_file missing on disk`, e este passo so descartava
    no SEM `source_file` — as duas regras discordavam, entao o portao cobrava algo
    que nenhum passo fazia. Ficou reprovando por `backend/plans_dump.txt`, um arquivo
    apagado ha semanas cujos 2 nos ninguem tinha como remover.

    No que descreve arquivo apagado nao e no incompleto: e no MENTIROSO — quem
    consulta o grafo recebe um caminho para abrir e nao acha nada la.
    """
    return bool(source_file) and not Path(source_file).exists()


drop_ids = {nid for nid, n in nodes.items()
            if not (n.get('source_file') or '')
            or out_of_scope(n.get('source_file'))
            or source_sumiu(n.get('source_file'))}
before_nodes = len(graph['nodes'])
graph['nodes'] = [n for n in graph['nodes'] if n['id'] not in drop_ids]

_texto = {}


def texto_de(path):
    if path not in _texto:
        try:
            _texto[path] = Path(path).read_text(encoding='utf-8', errors='ignore')
        except OSError:
            _texto[path] = ''
    return _texto[path]


def chamada_morta(edge, src, tgt):
    """Aresta `calls` cujo metodo NAO aparece mais no arquivo do chamador.

    Mesma regra do `verify.py`, de proposito — inclusive a excecao do `Foo.new`, que
    e chamada ao no `initialize` e nao divergencia. Regra de medicao e regra de
    limpeza diferentes dariam um portao que reprova o que nenhum passo remove.

    Era o caso das 4 arestas presas no portao: `formatted_city`, `declared_names` e
    `with_audit_reason` nao existem mais nos arquivos citados (conferido: zero
    ocorrencia). O passo 03 e ADITIVO por contrato, entao nada as removia — aresta
    de codigo que ja foi apagado sobrevive a todas as reconstrucoes.
    """
    if edge.get('relation') != 'calls':
        return False

    arquivo_chamador = nodes[src].get('source_file') or ''
    if not arquivo_chamador or arquivo_chamador == (nodes[tgt].get('source_file') or ''):
        return False

    rotulo = (nodes[tgt].get('label') or '').strip().rstrip('()').lstrip('.')
    if not re.match(r'^[A-Za-z_][A-Za-z0-9_]*[?!]?$', rotulo):
        return False

    fonte = texto_de(arquivo_chamador)
    if not fonte:
        return False

    nome = rotulo.rstrip('?!')
    if re.search(r'\b%s\b' % re.escape(nome), fonte):
        return False
    # `Foo.new` chama `initialize`: presenca do `.new` confirma a aresta.
    return not (nome == 'initialize' and re.search(r'\.new\b', fonte))


kept, dropped_xlang, dropped_loop, dropped_dead = [], 0, 0, 0
for edge in graph['links']:
    src, tgt = edge.get('source'), edge.get('target')
    if src in drop_ids or tgt in drop_ids:
        continue
    if src == tgt:
        dropped_loop += 1
        continue
    ls, lt = language(src), language(tgt)
    if ls != lt and ls in CODE and lt in CODE:
        dropped_xlang += 1
        continue
    if chamada_morta(edge, src, tgt):
        dropped_dead += 1
        continue
    kept.append(edge)
before_links = len(graph['links'])
graph['links'] = kept

graph.setdefault('hyperedges', [])
before_hyper = len(graph['hyperedges'])
graph['hyperedges'] = [h for h in graph['hyperedges']
                       if not any(m in drop_ids for m in h.get('nodes', []))]

# ---- hand-verified retargets ---------------------------------------------------------
# A manual fix applied straight to graph.json is lost the next time the hook rebuilds.
# corrections.json is where they live so they survive.
CORRECTIONS = Path('tools/graphify/corrections.json')
applied = stale = 0
if CORRECTIONS.is_file():
    node_ids = {n['id'] for n in graph['nodes']}
    for rule in json.loads(CORRECTIONS.read_text(encoding='utf-8')).get('retarget', []):
        when, new_target = rule['when'], rule['new_target']
        if new_target not in node_ids:
            stale += 1
            print('   ! correction target missing from graph: %s' % new_target)
            continue
        hit = False
        for edge in graph['links']:
            if (edge.get('source_file') == when.get('source_file')
                    and edge.get('relation') == when.get('relation')
                    and edge.get('target') == when.get('target')):
                edge['target'] = new_target
                edge['corrected'] = rule.get('reason', '')[:200]
                applied += 1
                hit = True
        if not hit:
            stale += 1
            print('   ! correction no longer matches anything (extractor may have changed): %s'
                  % when.get('target'))

GRAPH.write_text(json.dumps(graph, ensure_ascii=False), encoding='utf-8')
if applied or stale:
    print('02 corrections     : %d applied, %d stale' % (applied, stale))
print('02 prune           : nodes %d -> %d (dropped %d source-less/out-of-scope) | '
      'links %d -> %d (%d cross-language, %d self-loop, %d chamada-morta) | hyperedges %d -> %d'
      % (before_nodes, len(graph['nodes']), len(drop_ids),
         before_links, len(graph['links']), dropped_xlang, dropped_loop, dropped_dead,
         before_hyper, len(graph['hyperedges'])))
