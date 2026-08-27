"""Step 03b - recover the TypeScript cross-file edges the extractor misses.

O passo 03 faz isto para Ruby e leva a cobertura a 100%. Para TypeScript **nao havia
passo nenhum**, e o portao do `verify.py` exigia 99%: 873 simbolos importados-e-usados,
259 ligados, **29,7%**. O portao era inatingivel por construcao, entao o pipeline curado
reprovava em TODO commit — e um portao que sempre reprova para de ser lido.

Este passo fecha a lacuna com a MESMA regra que o `verify.py` usa para medir, de
proposito: se a medicao considera o par `(arquivo que importa, arquivo importado)`
ligado quando existe aresta entre qualquer no dos dois, e isso que se cria. Regra de
medicao e regra de construcao divergentes produzem um portao que passa sem o grafo
melhorar.

Tres detalhes que custam um ciclo de depuracao cada:

  * **Comentario em bloco sai antes de procurar uso.** Codigo comentado nao e uso, e
    `/* ... */` engoliria linhas inteiras de import morto como se fossem vivas.
  * **O alvo preferido e o NO DO SIMBOLO**, nao o do arquivo. `import { useTheme }` deve
    apontar para o no `useTheme`, e so cair no no do arquivo quando o simbolo nao foi
    extraido — senao o grafo diz "App.tsx depende de useTheme.ts" e perde qual simbolo.
  * **A aresta e verificada contra a propria linha citada** antes de ser escrita, como no
    passo 03. Additive only: nada e removido.
"""
import collections
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'lib'))
from tsindex import load_all                                    # noqa: E402

GRAPH = Path('graphify-out/graph.json')
if not GRAPH.is_file():
    sys.exit('graph.json not found')

graph = json.loads(GRAPH.read_text(encoding='utf-8'))

# ---- indice de nos --------------------------------------------------------------------
nodes_by_file = collections.defaultdict(list)
symbol_node = {}
for node in graph['nodes']:
    source_file = node.get('source_file') or ''
    if not source_file.endswith(('.ts', '.tsx')):
        continue
    nodes_by_file[source_file].append(node['id'])
    name = (node.get('label') or '').strip().rstrip('()').lstrip('.')
    if re.match(r'^[A-Za-z_$][\w$]*$', name):
        symbol_node.setdefault((source_file, name), node['id'])

# Pares JA ligados, nos DOIS sentidos. O `verify` mede sem direcao (`pair_nodes` recebe
# `(u,v)` e `(v,u)`), entao propor uma aresta onde ja existe a inversa nao aumentaria
# recall nenhum e so inflaria o grafo.
existing = set()
for link in graph['links']:
    existing.add((link['source'], link['target']))
    existing.add((link['target'], link['source']))

BLOCK_COMMENT = re.compile(r'/\*.*?\*/', re.S)

ts_files = sorted(nodes_by_file)
ts = load_all(ts_files)

candidates = []
kinds = collections.Counter()
sem_no_de_origem = 0

for path, tsfile in ts.items():
    body = BLOCK_COMMENT.sub('', tsfile.src)
    origem = nodes_by_file.get(path) or []
    if not origem:
        continue

    for name, target, line in tsfile.imports:
        # Mesmo padrao do `verify.py`: o simbolo tem de ser CHAMADO, instanciado como
        # JSX ou acessado (`(`, `<`, `.`). Import so declarado nao e dependencia.
        if not re.search(r'(?<![.\w$])%s\s*[(<.]' % re.escape(name), body):
            continue

        alvo = symbol_node.get((target, name))
        kind = 'symbol'
        if alvo is None:
            alvos = nodes_by_file.get(target) or []
            if not alvos:
                sem_no_de_origem += 1
                continue
            alvo = alvos[0]
            kind = 'file'

        # O no de origem: o simbolo que CONTEM a linha do uso seria o ideal, mas o
        # `verify` liga por arquivo, e o no do arquivo e o unico que existe sempre.
        src = symbol_node.get((path, Path(path).stem)) or origem[0]
        if src == alvo or (src, alvo) in existing:
            continue

        candidates.append({'source': src, 'target': alvo, 'relation': 'imports',
                           'confidence': 'EXTRACTED', 'confidence_score': 1.0,
                           'source_file': path, 'source_location': 'L%d' % line,
                           'weight': 1.0, 'recovered': 'ts_%s' % kind, '_name': name})
        existing.add((src, alvo))
        existing.add((alvo, src))
        kinds[kind] += 1

# ---- auto-verificacao: a linha citada precisa MESMO conter o import -------------------
_lines = {}


def lines_of(path):
    if path not in _lines:
        _lines[path] = Path(path).read_text(encoding='utf-8', errors='ignore').splitlines()
    return _lines[path]


confirmed, rejected = [], 0
for edge in candidates:
    body = lines_of(edge['source_file'])
    i = int(edge['source_location'][1:])
    # A DECLARACAO inteira, nao so a linha citada. O indice guarda a linha em que o
    # `import` COMECA, e uma lista longa de simbolos quebra em varias linhas:
    #
    #     import {
    #       availabilityEntriesApi,      <- o nome esta AQUI
    #       formatarValor,
    #     } from '@/lib/api/availability'
    #
    # Conferir so `lines[i-1]` reprovava todo simbolo que nao fosse o primeiro. Eram
    # as 39 rejeicoes que seguravam o recall em 96,4%: importe bom, conferencia curta.
    trecho = []
    for linha in body[i - 1:i + 19]:
        trecho.append(linha)
        if 'from' in linha or linha.rstrip().endswith(';'):
            break
    code = '\n'.join(trecho)
    if re.search(r'\b%s\b' % re.escape(edge['_name']), code):
        edge.pop('_name')
        confirmed.append(edge)
    else:
        rejected += 1

graph['links'].extend(confirmed)
GRAPH.write_text(json.dumps(graph, ensure_ascii=False), encoding='utf-8')
print('03b ts imports     : %d candidates | %d line-confirmed, %d rejected | by kind %s%s'
      % (len(candidates), len(confirmed), rejected, dict(kinds),
         ' | %d sem no de destino' % sem_no_de_origem if sem_no_de_origem else ''))
