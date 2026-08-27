---
type: "query"
date: "2026-08-22T06:02:09.966128+00:00"
question: "Is the graph ready?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Analytics::GetDashboardData", "Analytics::ConversionFunnel", "TokenService"]
---

# Q: Is the graph ready?

## Answer

Not until this pass. A functional test exposed a real defect the precision audits could not see: graphify path 'Analytics::GetDashboardData' 'Analytics::ConversionFunnel' returned NO PATH even undirected, despite the call existing at get_dashboard_data.rb:41. Measured RECALL (the thing never measured before): of 816 distinct cross-file Ruby (caller file -> callee file) constant-receiver call relationships present in source, the graph connected only 251 by any edge - 30.8%. 565 pairs (1289 call sites) had no edge at all. Precision was 100% and recall was 31%: you could trust what the graph said, but absence of an edge meant nothing. FIX (purely additive, nothing pruned): resolved each constant receiver Ruby-style through the enclosing module nesting, refused genuinely ambiguous constants, attributed the caller to the innermost def actually containing the line via a def-range parser, and self-verified every candidate edge against its cited source line before committing. 1136 candidates generated, 958 confirmed and added, 178 rejected by that self-check. RESULT: recall 30.8% -> 86.5%; isolated nodes 314 -> 204; connected components 533; largest component 28.9% -> 35.7% of nodes; communities 998 -> 788. Precision held at 0 false out of 2074 cross-file calls edges checked. The path query now returns the correct 3-hop answer. AUDIT NOTE: a naive name-presence check reports 72 false edges pointing at .initialize(); those are correct - Foo.new in source maps to the initialize method node - so the checker needs a new->initialize reconciliation or it slanders 72 good edges. REMAINING: 110 file pairs (245 call sites) still unlinked, mostly cases where the caller node fell back to a file node and the self-check could not confirm; instance-method calls through variables not assigned from Const.new are not resolved at all.

## Outcome

- Signal: useful

## Source Nodes

- Analytics::GetDashboardData
- Analytics::ConversionFunnel
- TokenService