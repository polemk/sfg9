Refining Chatbot Builder UX & Reliability
 Create 
TriggerNode
 component for chat builder

 Implement keyword editing in 
PropertiesPanel

 Add flow switcher/preview to 
AIChatWidget

 Debug 500 error when trigger keyword matches (Fixed in 
FlowEngine
)

 Resolve duplicate key warnings in 
AIChatWidget

 Improve comma handling in keyword input

 Ensure chat widget correctly initializes with the flow being edited

 Update conversation tracking infrastructure (Backend models and endpoints)

 Fix node data access in backend handlers (data wrapper support)

 Support React Flow edges for backend traversal

 Refine canvas aesthetics (discrete grid)

 Fix backend flow engine reliability (node not found error, edge traversal)

 Support 
Condition
 nodes in backend logic (branching true/false)

 Support multiple source handles in 
find_next_node_id

 Support non-interactive "transparent" nodes (Trigger, Condition)

 Implementar console resizável e minimizável (floating)

 Adicionar barra de info rica (Nós, Edges, Nome do Fluxo)

 Implementar Trilha de Execução (Logs em tempo real)

 Implement "Test Chat" in builder (n8n style)

 Add Test button to toolbar
 Support session reset in widget (Fix: resetSession logic added)
 Ensure automatic save before test
 Resizable bottom console layout (Chat + Logs split)
 Reposition success messages (sonner top-right)
 Phase 4: Flow Intelligence (Triggers & Personas)

 Add keywords, persona_name, persona_avatar to 
ChatFlow
 model (Migration)
 Update 
ChatFlow
 model validations and callbacks
 Update Serializers/API to expose new fields
 Frontend: Create "Flow Settings" modal in Builder
 Frontend: Implement Keywords input (array of strings)
 Frontend: Implement Persona Name & Avatar URL inputs
 Engine: Implement 
FlowMatcher
 service to find flow by keyword
 Fix 500 Error in FlowMatcher (Switch to Ruby-based partial matching)
 Phase 5: Advanced Flow Logic (Sprint 1)

 Task 1.1: Flow Handoff Node
 Backend: Ai::Nodes::Handoff logic & 
ChatSession
 update
 Frontend: 
HandoffNode
 component in Builder (Flow Selector)
 Engine: Logic to reset step and switch flow context
 Verify with seed script/console test
 Task 1.2: Smart Redirect & Auth Node
 Backend: Ai::Nodes::Redirect with 
action
 payload (navigate/scroll)
 Backend: Auto-login logic using 
VisitorAuthService
 Builder: Add 
RedirectNode.tsx
 component
 Builder: Register node type in 
PropertiesPanel
 + 
NodesSidebar
 Frontend: Widget handling for navigate, scroll_to, and 
auth
 events
 Fix JSX syntax error in 
PropertiesPanel.tsx
 Fix duplicate property in 
chatFlow.ts
 Add missing 
RedirectNodeData
 to 
nodes.ts
 Verification: Console test + Frontend build check
 Fix Runtime Error in 
useChatFlow.ts
 (Cannot read properties of null)
 Fix TypeScript Build Errors (NodeProps generic constraints)
 Fix Trigger/Flow Restart Logic (Removed current_step_id validation) test