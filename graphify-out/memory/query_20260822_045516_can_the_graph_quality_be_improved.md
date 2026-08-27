---
type: "query"
date: "2026-08-22T04:55:16.816206+00:00"
question: "Can the graph quality be improved?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Analytics::ConversionFunnel", "Analytics::GetDashboardData", "TokenService", "AgentService"]
---

# Q: Can the graph quality be improved?

## Answer

Yes - built a repair pass (graphify-out/repair_edges.py) run against graph.pre-repair.json. THREE STEPS: (1) prune all 87 cross-language ruby<->ts reference edges, proven false; (2) prune 449 cross-file 'calls' edges whose callee name appears nowhere in the caller source; (3) rebuild real Ruby call edges by scanning source for constant-receiver calls (Const::Path.method) and resolving the target class by which candidate file actually defines that method - refusing 562 ambiguous cases rather than guessing. Added 427 edges (305 method-verified, 122 unique-candidate). Caller attribution uses a def-block scanner over the Ruby source, falling back to the file node when graphify has no node for the enclosing def, instead of mis-attributing to a neighbouring method. RESULT: cross-language edges 87 -> 0. Cross-file calls proven-false 40.2% -> 13.3%. Backend Ruby 57.9% -> 20.5%. Frontend TS 5.6% -> 0%. The lost Analytics::ConversionFunnel call edge from GetDashboardData is restored. TIME dropped out of the god-nodes list. Communities went 835 -> 1051 because fabricated edges had been fusing unrelated communities. REMAINING KNOWN LIMITS: ~134 backend false calls edges survive because the callee name happens to appear somewhere in the caller file (e.g. AgentService --calls--> InboundProcessorService.process is still false); instance-vs-class method nodes are not distinguished when both are labelled the same; 562 ambiguous constant calls were refused rather than added, so backend call coverage is deliberately incomplete.

## Outcome

- Signal: useful

## Source Nodes

- Analytics::ConversionFunnel
- Analytics::GetDashboardData
- TokenService
- AgentService