---
type: "query"
date: "2026-08-22T05:56:17.983742+00:00"
question: "Make the graph good as a base-repo reference: extract remaining in-scope docs and clean noise"
contributor: "graphify"
outcome: "useful"
source_nodes: ["README.md", "docker-compose.yml", "goat/v1/router", "specs_fix_plan.md"]
---

# Q: Make the graph good as a base-repo reference: extract remaining in-scope docs and clean noise

## Answer

Scope chosen by the user: backend/, frontend/ and root project docs only - .trae/ (119 files) and tools/ stay excluded, and the 247 isolated backend/spec nodes are left alone rather than linked by RSpec filename convention (that inference is the same class of guessing that produced the false TIME edges). Two parallel subagents covered 25 files. Injected 175 nodes, 298 edges, 6 hyperedges with full validation (id charset, file_type enum, source_file must resolve on disk, both endpoints must exist, no duplicate (source,target) pairs, hyperedge members must exist and number >= 3); zero rejected. Edges were applied only after all nodes from BOTH chunks were present, so cross-chunk references resolve. Also pruned 137 source-less noise nodes (Path, str, Any, BaseModel - Python stdlib/pydantic type names leaked in from out-of-scope files). FINAL: directed=true, 7043 nodes, 10476 edges, 13 hyperedges, 998 communities, 0 dangling hyperedge members, 0 nodes without source_file, 0 nodes whose source_file is missing on disk, 0 cross-language edges, 0 false cross-file calls out of 1116, reask correction retained. Coverage: files with >=1 node 91.9% -> 93.6%; isolated nodes 429 -> 314; connected components 847 -> 731. NEW CONTRADICTIONS THE DOCS SURFACED (all real, worth acting on): results_new.json shows 24.75% line coverage against a documented 90% CI gate; PROJECT_STANDARDIZATION.md mandates /auth/v1/... while also telling the team to use only /api/v1/* (emitted AMBIGUOUS 0.3 for human review); config/goat-robot.json still calls Meta Graph API v22.0 while specs_fix_plan.md Group 1 describes an Instagram v22->v25 migration; goat-robot.json hardcodes an ngrok tunnel host alongside production api-goat.polemk.com; AI9-29.md documents a ?lead_id= IDOR sitting on the tracking convention. Locales en and pt-BR verified at exact parity (277 keys, 25 namespaces, no asymmetry). filters.json/filters2.json are NOT filter definitions - they are captured API error responses.

## Outcome

- Signal: useful

## Source Nodes

- README.md
- docker-compose.yml
- goat/v1/router
- specs_fix_plan.md