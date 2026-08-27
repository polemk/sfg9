---
type: "query"
date: "2026-08-22T05:03:28.077484+00:00"
question: "CORRECTION: were the 40% false calls edges real?"
contributor: "graphify"
outcome: "corrected"
correction: "graphify's Ruby call edges are ~99.9% correct. The 40%/58% false-edge figures were my measurement error. Only the 87 cross-language reference edges were genuinely false. Do not prune calls edges."
source_nodes: ["DashboardChannel", "PermissionsChannel", "AuthSession", "IntakeConversationService"]
---

# Q: CORRECTION: were the 40% false calls edges real?

## Answer

NO. The earlier finding that 40.2% of cross-file calls edges (57.9% in backend Ruby) were fabricated is VOID - it was an artifact of my own audit, not a defect in graphify. Cause: graph.json is an UNDIRECTED graph; networkx G.edges() yields (u,v) in adjacency-iteration order, which does not preserve the source/target direction stored in the JSON. My audit treated u as the caller, so for roughly half the edges it checked the callee's file for the caller's name and declared correct edges fabricated. Re-auditing by reading the explicit source/target fields from graph.json links gives 1 proven-false edge out of 1116 (0.1%); backend Ruby 0.1%, frontend TS 0.0%. Concrete edges I wrongly condemned, now verified real in source: dashboard_kpis_broadcast_job.rb:6 calls DashboardChannel.broadcast_to (job -> channel, direction was correct); permissions_sync_service.rb:164 calls PermissionsChannel.broadcast_to; the Auth services call Api::Entities::AuthSession.represent. The single genuine miss is intake_router_service.rb:75 calling Blog::IntakeConversationService.reask (L35) while the edge targets re_ask (L314) - right file, wrong method node, a near-miss not a fabrication. WHAT SURVIVES: the 87 cross-language ruby<->ts reference edges are still genuinely false (86 are Ruby stdlib Time case-folded onto a TypeScript const TIME, which is Portuguese for 'team'; 1 is ConversionFunnel). Those 87 are pruned from graph.json, preserving every link's direction by editing the JSON links rather than round-tripping through networkx. LESSON: never infer edge direction from networkx iteration order on an undirected graph - read source/target from the JSON, or build with --directed.

## Outcome

- Signal: corrected
- Correction: graphify's Ruby call edges are ~99.9% correct. The 40%/58% false-edge figures were my measurement error. Only the 87 cross-language reference edges were genuinely false. Do not prune calls edges.

## Source Nodes

- DashboardChannel
- PermissionsChannel
- AuthSession
- IntakeConversationService