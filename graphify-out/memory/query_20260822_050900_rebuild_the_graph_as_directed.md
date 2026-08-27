---
type: "query"
date: "2026-08-22T05:09:00.397836+00:00"
question: "Rebuild the graph as directed"
contributor: "graphify"
outcome: "useful"
source_nodes: ["cn()", "ApiResponseHandler", "useAuthStore", "endpoints.ts"]
---

# Q: Rebuild the graph as directed

## Answer

graph.json is now a DiGraph (directed=true), 6937 nodes / 10114 edges, built losslessly from the corrected undirected export: node ids preserved verbatim, direction taken from each link's source/target. NOTE: graphify's own build_from_json(directed=True) was tried first and DROPPED 201 nodes (176 inside backend/ or frontend/, e.g. Api::Auth::V1::Checkout, Api::Entities::Category, Api::Entities::Analytics::Dashboard) because it re-derives node ids from source_file+label and collides on repeated namespace segments - those nodes did not reappear under any other id. Building the DiGraph directly with networkx avoids that entirely. Communities recomputed on the undirected view (Louvain needs it): 1102. Verification on the directed graph: 0 cross-language edges, 1 false cross-file calls edge out of 1116 (0.1%). Direction now survives networkx iteration, so the orientation bug that produced the bogus 40%-false finding cannot recur. New capability: in-degree/out-degree are meaningful. Most called-into: cn() 185, ApiResponseHandler#success_response 149, useAuthStore 100. Most calling-out: endpoints.ts 85, App.tsx 81, Lead 67. KNOWN GAP: hyperedges are 0 - graphify's to_json never persisted the 3 hyperedges the semantic pass produced, and the original extraction JSON was cleaned up, so they are not recoverable without re-running semantic extraction.

## Outcome

- Signal: useful

## Source Nodes

- cn()
- ApiResponseHandler
- useAuthStore
- endpoints.ts