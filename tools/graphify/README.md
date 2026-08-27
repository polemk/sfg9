# graphify pipeline

The knowledge graph in `graphify-out/` is **not** reproducible by running `/graphify` alone.
Out of the box the extractor connects only ~31% of the real cross-file Ruby call
relationships and emits a class of false cross-language edges. This directory holds the
post-processing that turns its output into the artifact we actually rely on.

```bash
tools/graphify/rebuild.sh              # post-process the existing graphify-out/graph.json
tools/graphify/rebuild.sh --extract    # run graphify's AST extraction first, then post-process
```

Run from the repo root. `rebuild.sh` fails loudly if verification regresses, and keeps the
previous graph at `graphify-out/graph.prev.json` when it does.

## Why each step exists

| Step | What it does | Why |
|---|---|---|
| `01_inject_semantic.py` | Re-injects `semantic-layer.json` | The doc/convention concepts came from LLM extraction. Versioning them means a rebuild costs no tokens. |
| `02_prune.py` | Drops cross-language edges, source-less nodes, `.trae/**`, self-loops | Each rule was verified against source first. See the docstring. |
| `03_add_ruby_calls.py` | Recovers Ruby cross-file call edges | The extractor misses ~69% of them. Every added edge is checked against its own cited source line. |
| `04_build_directed.py` | Rebuilds as a DiGraph, re-clusters | Direction makes fan-in/fan-out meaningful and `path` queries work. |
| `05_label.py` | Names every community | `graph.html` groups by community; unnamed groups are unnavigable. |
| `verify.py` | Precision + recall + integrity gate | Exits non-zero on regression. |

## The git hooks

`post-commit` and `post-checkout` auto-rebuild the graph on every commit and branch switch,
which is what we want — the graph should track the code. But graphify's own rebuild produces
the **naive** graph: ~31% Ruby call recall, false cross-language edges, undirected, unnamed
communities, and the whole repo in scope (18k+ nodes). Left unpatched, the hook silently
reverts the curated artifact every time anyone commits.

```bash
tools/graphify/install-hook.sh     # make the hooks run this pipeline after the raw rebuild
```

Run it once, and again any time `graphify hook install` runs — that regenerates the hooks
from graphify's template and drops the patch. `install-hook.sh` is idempotent and tells you
if the anchor it patches has moved.

To skip a rebuild for a single command: `GRAPHIFY_SKIP_HOOK=1 git commit ...`

Scope is enforced in `02_prune.py` (`EXCLUDED_PREFIXES`), not at extraction time, precisely
so a full-repo hook rebuild gets narrowed back down deterministically.

## Current numbers

| | |
|---|---|
| Ruby cross-file call recall | 816/816 — 100% |
| TypeScript symbol recall | 543/543 — 100% |
| False cross-file call edges | 0 of 2,234 |
| Cross-language edges | 0 |
| Integrity checks | all zero |

## Three traps that cost real debugging time

**Never read edge direction from `networkx` iteration order.** `G.edges()` on an undirected
graph yields `(u, v)` in adjacency order, not the stored source/target. Reading direction
from it once produced a completely bogus "40% of call edges are fabricated" finding, and
three edges were "confirmed against source" by checking the wrong endpoint as the caller.
Direction comes from the DiGraph, or from the links' `source`/`target` fields. Nothing else.

**Never key community labels by community id.** Louvain reassigns ids on every re-cluster,
so id-keyed names drift silently onto unrelated groups. `05_label.py` matches by content
signature instead.

**Pin `PYTHONHASHSEED=0` and `PYTHONUTF8=1` for every rebuild.** Without the first, Louvain
reshuffles community ids between runs — 3226 of 5768 nodes moved between two runs of the
same input, so every commit produced a thousands-of-lines diff nobody could review. Without
the second, the extractor reads `.md` with the locale encoding and accented Portuguese
headings become double-encoded (`critérios` → `critÃ©rios`); since node ids derive from
labels, the ids themselves were corrupt. Both are set in `rebuild.sh`, in the hooks, and
`04_build_directed.py` re-execs itself if the seed is missing. When you see the graph churn,
check these before suspecting anything else.

**Don't use `graphify.build.build_from_json(directed=True)`.** It re-derives node ids from
`source_file` + `label` and collides on repeated namespace segments. On this repo it
silently dropped 201 nodes, 176 of them inside `backend/` or `frontend/`
(`Api::Auth::V1::Checkout`, `Api::Entities::Category`, ...), and they did not reappear under
any other id. `04_build_directed.py` preserves ids verbatim and asserts the node count.

## Known limits

These are measured and deliberate, not oversights:

- **Instance-variable calls are unresolved.** 247 `@ivar.method` sites exist, but the ivars
  come from constructor parameters (`@session = session`), so the receiver type is whatever
  the caller passed. Resolving them needs whole-program type inference; guessing would
  reintroduce fabricated edges. The two ivars typed from a class method
  (`@user = User.find_by`) are already covered as constant-receiver calls.
- **`.trae/**` is excluded** as obsolete specs.
- **Images and video are excluded** — brand and marketing assets with no architectural signal.
- **Scope is `backend/` + `frontend/`.** `tools/` and `.agent/` are not mapped.
- The graph stays fragmented (largest component ~45%). Connecting the islands would require
  inferring relationships that are not in the source. We do not do that here.

## Adding a community name

Append to `SIGNATURES` in `05_label.py`:

```python
('My Area Name', ['SomeDistinctiveMember.tsx', 'AnotherOne']),
```

Pick members distinctive to that group; the first signature whose member appears wins.
