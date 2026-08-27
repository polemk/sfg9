---
type: "query"
date: "2026-08-22T05:12:38.210419+00:00"
question: "Fix the single remaining false backend edge"
contributor: "graphify"
outcome: "useful"
source_nodes: ["IntakeConversationService", "IntakeRouterService"]
---

# Q: Fix the single remaining false backend edge

## Answer

Fixed. The edge was intake_router_service.rb:75 .resolve_dup_choice() --calls--> .re_ask(). The call site reads Blog::IntakeConversationService.reask(session): the real target is the class method reask at intake_conversation_service.rb:35, not the private instance method re_ask at L314. graphify had matched the underscore variant. A node for reask() at L35 already existed (backend_app_services_blog_intake_conversation_service_reask), so the edge was retargeted in place and tagged with a 'corrected' attribute recording the reason. The two other inbound edges to re_ask are correct and were left alone - choose_edit_field (L213) and handle_back (L279) both genuinely call re_ask internally. VERIFIED AFTER FIX: 1116 cross-file calls edges checked, 0 proven false (backend Ruby 0/739, frontend TS 0/377), 0 cross-language edges. reask() L35 now has its inbound call edge from the router.

## Outcome

- Signal: useful

## Source Nodes

- IntakeConversationService
- IntakeRouterService