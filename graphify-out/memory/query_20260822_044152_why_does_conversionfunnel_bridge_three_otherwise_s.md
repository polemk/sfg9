---
type: "query"
date: "2026-08-22T04:41:52.413337+00:00"
question: "Why does ConversionFunnel bridge three otherwise-separate communities with betweenness 0.124?"
contributor: "graphify"
outcome: "corrected"
correction: "The genuine edge is get_dashboard_data.rb:41 -> backend/app/services/analytics/conversion_funnel.rb:13 (Analytics::ConversionFunnel), entirely within the backend. The frontend TS interface ConversionFunnel is a payload contract, not a caller."
source_nodes: ["ConversionFunnel", "Analytics::ConversionFunnel", "ConversionFunnelSection.tsx"]
---

# Q: Why does ConversionFunnel bridge three otherwise-separate communities with betweenness 0.124?

## Answer

Expanded from original query via vocab: [conversion, funnel, analytics, dashboard]. Traced via explain + neighborhood expansion on all 25 ConversionFunnel-labelled nodes. FINDING: the bridge is a FALSE EDGE. The graph draws 'ConversionFunnel' (frontend/src/features/metrics/types.ts L28, a TypeScript interface, community 9) --references--> '.call()' (backend/app/services/analytics/get_dashboard_data.rb L8, community 72). Source verification shows get_dashboard_data.rb:41 actually calls Analytics::ConversionFunnel.call(scope, @params) - a Ruby class at backend/app/services/analytics/conversion_funnel.rb:13 (community 86). The AST resolved the bare name 'ConversionFunnel' to the TS interface instead of the Ruby class, a cross-language name-collision, same failure mode as the TIME edges in Surprising Connections. CONSEQUENCE: the real backend call edge is missing, so Analytics::ConversionFunnel sits in community 86 with only intra-file 'contains'/'method' edges and zero inbound callers, despite being called by GetDashboardData. The frontend/backend relationship is real but is a JSON payload contract (TS interface mirrors the Ruby service output), not a call edge - graphify has no edge for that. Communities 9, 72 and 86 are NOT genuinely coupled by this node.

## Outcome

- Signal: corrected
- Correction: The genuine edge is get_dashboard_data.rb:41 -> backend/app/services/analytics/conversion_funnel.rb:13 (Analytics::ConversionFunnel), entirely within the backend. The frontend TS interface ConversionFunnel is a payload contract, not a caller.

## Source Nodes

- ConversionFunnel
- Analytics::ConversionFunnel
- ConversionFunnelSection.tsx