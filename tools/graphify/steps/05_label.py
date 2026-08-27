"""Step 05 - name every community, and rewrite GRAPH_REPORT.md with those names.

Labels are matched by CONTENT SIGNATURE, never by community id: Louvain reassigns ids on
every re-cluster, so id-keyed names drift silently onto unrelated groups. A community that
contains one of a signature's distinctive members takes that signature's name.

Communities with no signature fall back to their dominant directory at a useful depth plus
their highest-degree member ("Backend Models - Operation"), never a bare "backend" or a
meaningless "Misc 3" - those are what a reader actually has to navigate in graph.html.

To add a name: append (name, [distinctive member labels]) to SIGNATURES.
"""
import collections
import json
import os
import sys
from pathlib import Path

from networkx.readwrite import json_graph

from graphify.analyze import god_nodes, suggest_questions, surprising_connections
from graphify.cluster import score_all
from graphify.report import generate

GRAPH = Path('graphify-out/graph.json')
if not GRAPH.is_file():
    sys.exit('graph.json not found')

data = json.loads(GRAPH.read_text(encoding='utf-8'))
graph = json_graph.node_link_graph(data, edges='links')
nodes = {n['id']: n for n in data['nodes']}

communities = collections.defaultdict(list)
for node in data['nodes']:
    communities[node.get('community')].append(node['id'])
communities = {k: v for k, v in communities.items() if k is not None}

SIGNATURES = [
    ('Client Pages & Auth Routing',         ['ImpersonateSearch.tsx', 'ClientDashboardPage.tsx']),
    ('Admin Plans & Features UI',           ['AdminPlanFormPage.tsx', 'MobileFeaturesList.tsx']),
    ('Public Landing & Plans',              ['SoldOutCountdown.tsx', 'PlansComparison.tsx', 'HomePage.tsx']),
    ('Blog Posts & WhatsApp Admin',         ['WhatsappPage.tsx', 'CategoriesManager.tsx']),
    ('Leads Dashboard & Journey',           ['IdentidadeDoLead.tsx', 'LeadJourneyView.tsx']),
    ('Checkout, Build & Transcript Pages',  ['BuildPage.tsx', 'TranscriptPage.tsx']),
    ('Asaas Payments API',                  ['AsaasConnection', 'AsaasQueryService']),
    ('Auth Services & Entities',            ['CompleteRegistrationService', 'CsrfService']),
    ('Frontend NPM Dependencies',           ['@radix-ui/react-dialog', '@tanstack/react-query']),
    ('App Shell & Route Table',             ['App.tsx', 'VisitorRoute.tsx']),
    ('Lead & Message API',                  ['HubForwardEventsJob', 'LeadMessageService']),
    ('Lead Model & Specs',                  ['lead_hub_push_spec.rb', 'lead_spec.rb']),
    ('Admin Features & Onboarding',         ['AdminOnboardingTemplatesPage.tsx', 'AdminFeaturesPage.tsx']),
    ('3D Design Demo & Terminal',           ['FinalPurpleRoom.tsx', 'FloatingShape.tsx']),
    ('Setup, Site Preview & Blog Settings', ['SitePreviewPage.tsx', 'CurationQueuePage.tsx']),
    ('Metrics Panel TV & Sources',          ['PainelTV.tsx', 'OrigensTable.tsx']),
    ('Dashboard KPIs & Flow Builder',       ['ExecutionViewerPage.tsx', 'FlowListPage.tsx']),
    ('Auth Request Specs',                  ['MagicLinkVerifyService', 'sessions_spec.rb']),
    ('Chat Flows & Deliveries API',         ['ChatFlowsService', 'DeliveriesService']),
    ('Payments, Sales & Plan Selector',     ['PlanSelector.tsx', 'PaymentsPage.tsx']),
    ('Analytics Page & Date Range',         ['AnalyticsPage.tsx', 'dateRangeStore.ts']),
    ('User Model & Code Validation',        ['CodeValidationService', 'user_spec.rb']),
    ('Plan Model & Seeds',                  ['goat_briefing_agent.rb', 'plan_spec.rb']),
    ('Tracking & Attribution Docs',         ['GA4 Measurement Protocol (server-side)',
                                             'Meta Conversions API (server-side)']),
    ('Base Repo Conventions',               ['Secret Isolation via .env.secrets',
                                             'Canonical Project Directory Layout']),
    ('Local Development Topology',          ['docker-compose.yml']),
    ('Agent Flow Seeds',                    ['laura_flow.json', 'maya_flow.json']),
    ('n8n Omnichannel Router',              ['goat-robot.json']),
]

PRETTY = {
    'backend/app/models': 'Backend Models', 'backend/app/services': 'Backend Services',
    'backend/app/controllers': 'API Controllers', 'backend/app/jobs': 'Background Jobs',
    'backend/app/channels': 'ActionCable Channels', 'backend/spec': 'Backend Specs',
    'backend/config': 'Backend Config', 'backend/db': 'Database & Seeds',
    'backend/lib': 'Backend Lib', 'backend/docs': 'Backend Docs',
    'frontend/src/components': 'Frontend Components', 'frontend/src/features': 'Frontend Features',
    'frontend/src/app': 'Frontend Pages', 'frontend/src/lib': 'Frontend Lib',
    'frontend/src/store': 'Frontend Stores', 'frontend/src/stores': 'Frontend Stores',
    'frontend/src/hooks': 'Frontend Hooks', 'frontend/src/NavKit': 'NavKit Navigation',
    'frontend/src/locales': 'Frontend i18n', 'frontend/public': 'Frontend Assets',
    'tools/n8n-mcp-server': 'n8n MCP Server',
}


def deepest_common(paths):
    parts = [p.split('/') for p in paths if p]
    if not parts:
        return None
    common = []
    for i in range(min(len(x) for x in parts)):
        segment = {x[i] for x in parts}
        if len(segment) != 1:
            break
        common.append(segment.pop())
    return '/'.join(common) if common else None


def fallback(members):
    paths = [(nodes[m].get('source_file') or '') for m in members]
    paths = [p for p in paths if p]
    if not paths:
        return None

    def dominant(depth):
        counter = collections.Counter('/'.join(p.split('/')[:depth])
                                      for p in paths if len(p.split('/')) > depth)
        return counter.most_common(1)[0] if counter else (None, 0)

    best = None
    for depth in (4, 3, 2):
        directory, count = dominant(depth)
        if directory and count >= max(2, int(0.35 * len(paths))):
            best = directory
            break
    if not best:
        best = deepest_common(paths) or paths[0]

    name = None
    for prefix, pretty in sorted(PRETTY.items(), key=lambda kv: -len(kv[0])):
        if best.startswith(prefix):
            tail = best[len(prefix):].strip('/')
            name = ('%s / %s' % (pretty, tail)) if tail else pretty
            break
    if name is None:
        name = os.path.basename(best) if Path(best).is_file() else best

    busiest = max(members, key=lambda m: graph.degree(m)) if members else None
    label = (nodes.get(busiest, {}).get('label') or '').strip().rstrip('()') if busiest else ''
    if label and not label.startswith('.') and len(label) <= 28:
        name = '%s - %s' % (name, label)
    return name


labels, claimed = {}, set()
by_size = sorted(communities, key=lambda c: -len(communities[c]))
for cid in by_size:
    member_labels = {(nodes[m].get('label') or '') for m in communities[cid]}
    chosen = None
    for name, signature in SIGNATURES:
        if name in claimed:
            continue
        if any(s in member_labels for s in signature):
            chosen = name
            break
    if chosen:
        labels[cid] = chosen
        claimed.add(chosen)
    else:
        labels[cid] = fallback(communities[cid]) or ('Community %d' % cid)

seen = collections.Counter()
for cid in by_size:
    base = labels[cid]
    seen[base] += 1
    if seen[base] > 1:
        labels[cid] = '%s (%d)' % (base, seen[base])

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

try:
    cohesion = score_all(graph, communities)
except Exception:
    cohesion = score_all(graph.to_undirected(), communities)
report = generate(graph, communities, cohesion, labels, god_nodes(graph),
                  surprising_connections(graph, communities), detection,
                  {'input': 0, 'output': 0}, '.',
                  suggested_questions=suggest_questions(graph, communities, labels))
Path('graphify-out/GRAPH_REPORT.md').write_text(report, encoding='utf-8')
Path('graphify-out/.graphify_labels.json').write_text(
    json.dumps({str(k): v for k, v in labels.items()}, ensure_ascii=False), encoding='utf-8')

generic = sum(1 for v in labels.values() if v.startswith('Community '))
print('05 label           : %d communities | %d matched a signature | %d still generic'
      % (len(labels), len(claimed), generic))
