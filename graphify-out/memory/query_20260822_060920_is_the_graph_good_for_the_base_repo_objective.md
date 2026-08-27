---
type: "query"
date: "2026-08-22T06:09:20.556423+00:00"
question: "Is the graph good for the base-repo objective?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Backend Environment Contract", "bin/switch_env Environment Switcher", "TokenService"]
---

# Q: Is the graph good for the base-repo objective?

## Answer

Yes, and functional testing against that specific objective drove one last fix. Ran the questions a developer starting a new app would actually ask. 'What do I need to configure to run this?' returns the Backend/Frontend Environment Contracts, bin/switch_env, Secret Isolation via .env.secrets, the Canonical Project Directory Layout, the Docker multi-stage build and the Configured Integrations, correctly interlinked - exactly the inheritance checklist a cloned app needs. 'How does auth work?' returns TokenService, SessionsService, LoginCode, MagicLinkVerifyService, ApiResponseHandler and the Magic Login architecture doc across 100 nodes. Both work. WEAKNESS THE TESTS EXPOSED: community labels were mechanical path-prefix derivations, so graph.html - the browsable layer - showed 'Frontend Misc 2', 'Frontend Misc 3', 'App Pages 2'. Useless for navigation in a reference artifact. FIXED: named the 26 largest communities from their actual members (Client Pages & Auth Routing, Admin Plans & Features UI, Public Landing & Plans, Asaas Payments API, Auth Services & Entities, App Shell & Route Table, Lead Model & Specs, Magic Login Architecture, GOAT LMA Agent Specs, 3D Design Demo & Terminal, etc.) and replaced the 'Misc N' fallback with the deepest shared directory of each community's members, prettified. 797 communities labelled, 0 still generic. Also removed 2 self-loop edges verified false (Users::OmniauthCallbacksController and AI9::Application each 'inheriting' themselves - the real parents are Devise and Rails gem classes). TypeScript needed nothing: symbol-level recall is 543/543 = 100% (the one apparent miss, Topbar.tsx using useTheme, has both its import and its call inside block comments - graphify was right, my checker was wrong for not stripping /* */).

## Outcome

- Signal: useful

## Source Nodes

- Backend Environment Contract
- bin/switch_env Environment Switcher
- TokenService