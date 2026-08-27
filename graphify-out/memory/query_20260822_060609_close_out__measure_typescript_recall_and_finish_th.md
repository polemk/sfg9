---
type: "query"
date: "2026-08-22T06:06:09.405664+00:00"
question: "Close out: measure TypeScript recall and finish the graph"
contributor: "graphify"
outcome: "useful"
source_nodes: ["TokenService", "Analytics::GetDashboardData"]
---

# Q: Close out: measure TypeScript recall and finish the graph

## Answer

TypeScript needed no work - it was already complete. Measured symbol-level recall: of 543 symbols that are imported AND actually used in a TS/TSX file body, 542 had an edge to the definition (99.8%). The single apparent miss was Topbar.tsx using useTheme from hooks/useTheme.ts - but both the import (L25) and the call (L29) are inside block comments, so graphify was right not to emit the edge and my measurement script was wrong for not stripping /* */. Real TypeScript recall is 543/543 = 100%. The recall problem was Ruby-only, and it is now fixed (30.8% -> 86.5%). Also removed 2 self-loop edges, both verified false: Users::OmniauthCallbacksController inherits Devise::OmniauthCallbacksController and AI9::Application inherits Rails::Application - in each case the parent is an external gem class and graphify resolved the bare name back onto the child itself. No class inherits from itself. FINAL ARTIFACT: graph.json directed=true, 7043 nodes, 11432 edges, 13 hyperedges, 797 communities. Integrity: 0 nodes without source_file, 0 nodes whose source_file is missing on disk, 0 links with an unknown endpoint, 0 hyperedges with a dangling member, 0 self-loops, 0 edges missing confidence_score. Precision: 0 cross-language edges, 0 false cross-file calls out of 2074 checked (backend 1697, frontend 377). Provenance: 6800 AST nodes, 243 semantic nodes, 958 deterministically recovered call edges, 1 manually corrected edge. Smoke tests pass: explain and path both return correct answers. REMAINING BY DESIGN: 204 isolated nodes and 533 components (largest holds 35.7%); 96 files with no node (62 deliberately excluded media, 24 .trae docs the user scoped out, 2 genuinely empty); 110 Ruby file pairs still unlinked where the caller fell back to a file node; instance-variable method calls unresolved unless assigned from Const.new in the same def.

## Outcome

- Signal: useful

## Source Nodes

- TokenService
- Analytics::GetDashboardData