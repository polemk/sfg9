---
type: "query"
date: "2026-08-22T04:47:54.030216+00:00"
question: "Cross-language edge audit: how many graphify edges survive verification against source, and is the graph trustworthy for architecture questions?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["DashboardChannel", "PermissionsChannel", "AuthSession", "TIME", "ConversionFunnel"]
---

# Q: Cross-language edge audit: how many graphify edges survive verification against source, and is the graph trustworthy for architecture questions?

## Answer

Audited every cross-language (ruby<->ts) edge and every cross-file 'calls' edge against the actual source. RESULT 1 - cross-language: 87 edges, all relation=references, all EXTRACTED. 86 are the Ruby stdlib 'Time' case-folded to match a TypeScript const TIME at frontend/src/app/pages/BrazilianSoftware/screens/BrswSobre.tsx L27 (which is Portuguese for 'team', a staff roster - no backend file defines a TIME constant). The 87th is ConversionFunnel, already corrected separately. 87/87 false, 0 real. RESULT 2 - cross-file calls edges: 1116 checked by testing whether the callee name appears anywhere in the caller's source. 449 proven false (40.2%), a lower bound since a present name can still resolve to the wrong file. Split by side: backend Ruby 428/739 false (57.9%), frontend TS 21/377 false (5.6%). Worst: backend/app/models 74% false, backend/app/services 61% false, frontend/src/NavKit 62% false. Best: frontend/src/app 0%, frontend/src/features 1%, frontend/src/components 3%. Confirmed false examples read in source: DashboardChannel (only stream_from, no perform) --calls--> DashboardKpisBroadcastJob.perform; PermissionsChannel (only stream_for) --calls--> PermissionsSyncService.broadcast; Api::Entities::AuthSession (a Grape::Entity with only 'expose' declarations, calls nothing) --calls--> six different Auth service methods. CONCLUSION: the extractor fabricates Ruby 'calls' edges from domain/naming affinity between files rather than actual invocation. imports/imports_from are path-resolved and verified sound. The graph is reliable for TypeScript frontend structure and for imports/contains/method on both sides; Ruby call-graph edges must not be trusted without source verification.

## Outcome

- Signal: useful

## Source Nodes

- DashboardChannel
- PermissionsChannel
- AuthSession
- TIME
- ConversionFunnel