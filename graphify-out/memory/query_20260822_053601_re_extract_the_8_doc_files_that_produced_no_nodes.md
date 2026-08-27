---
type: "query"
date: "2026-08-22T05:36:01.164052+00:00"
question: "Re-extract the 8 doc files that produced no nodes"
contributor: "graphify"
outcome: "useful"
source_nodes: ["lead_created event (trackEvent)", "EventType union drift", "hybrid_tracking_pipeline"]
---

# Q: Re-extract the 8 doc files that produced no nodes

## Answer

Done for the 6 that have real content; the other 2 are legitimately empty (backend/spec/fixtures/files/test_file.txt contains 'dummy content', backend/start_node_direct.txt is empty) and correctly yield nothing. Added 57 nodes, 75 edges, 3 hyperedges from GA4_SETUP.md, GTM_SETUP.md, META_CAPI_SETUP.md, TRACKING_GUIDE.md, UTM_STANDARDS.md and BrazilianSoftware/DESIGN_BRIEF.md. Injected directly into graph.json with validation (id charset, file_type in the allowed six, source_file must resolve on disk, both edge endpoints must exist, hyperedge members must exist and number >= 3) rather than through build_from_json, which is what silently dropped the roadmap nodes earlier. All 57/75/3 passed; zero rejected. KEY RESULT: the documentation/code contradiction now has nodes to hang on. META_CAPI_SETUP.md:31 prescribes trackEvent('lead_created', {email, phone}) and the graph now carries an edge from that node to frontend_build_log_eventtype_union_drift (INFERRED 0.95), which records that the frontend EventType union rejects 'lead_created'. The subagent also noted UTM_STANDARDS.md labels its behaviour 'Primeira Origem (Last Touch)' while the body describes first-touch-wins - mixed terminology, captured as a node rationale. FINAL GRAPH: directed=true, 7005 nodes, 10201 edges, 7 hyperedges, 0 dangling hyperedge members, 0 cross-language edges, 0 false cross-file calls edges out of 1116, the reask correction retained. Semantic doc files with no node: 20 -> 2 (both genuinely empty). REMAINING GAPS (unchanged, structural): 429 isolated nodes, 847 connected components with the largest holding only 29.2% of nodes, 117 files with no node (62 are the deliberately excluded media, plus 14 .json seed/locale files the AST parser yields nothing for), and 137 of the 157 doc files never went through semantic extraction.

## Outcome

- Signal: useful

## Source Nodes

- lead_created event (trackEvent)
- EventType union drift
- hybrid_tracking_pipeline