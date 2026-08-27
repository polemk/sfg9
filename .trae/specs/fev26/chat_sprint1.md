Walkthrough - Advanced Flow Logic (Sprint 1)
This sprint focused on implementing advanced flow control features: Flow Handoffs (switching between chat flows) and Smart Redirects (navigating, scrolling, or authenticating users).

1. Flow Handoff Node
The 
HandoffNode
 allows a chat flow to transfer control to another flow. This is crucial for breaking down complex bots into smaller, manageable modules.

Components
Backend (Ai::Nodes::Handoff):
Updates 
ChatSession
 with the new chat_flow_id.
Resets current_step_id to nil (triggers start of new flow).
Recursively calls FlowEngine#process! to immediately execute the new flow's first step.
Handles "Transparent" logic to ensure seamless transition for the user.
Frontend (
HandoffNode.tsx
):
Displays the target flow name.
Configurable via 
PropertiesPanel
 with a dropdown of available flows.
Verification
Console Test: 
tmp/test_handoff_console.rb
Logic: Simulates a session starting in "Flow A", hitting a handoff node, and verifying the next response comes from "Flow B".
ruby
# Console Output Logic
1. Start Flow A -> Response "Hello from A"
2. Next Step -> Handoff Node -> Response "Hello from B" (Seamless)
2. Smart Redirect & Auth Node
The 
RedirectNode
 enables the chatbot to control the user's browser or session state.

Actions
Navigate (navigate): Redirects the browser to a specific URL (same tab or new tab).
Scroll To (scroll_to): Smoothly scrolls the page to a specific CSS selector (e.g., #pricing).
Auth (
auth
): Authenticates the visitor as a user (creating a lead/user if needed) and returns a JWT token.
Components
Backend (Ai::Nodes::Redirect):
Returns a payload with { type: 'redirect', action: '...', url: '...' }.
For 
auth
, utilizes 
VisitorAuthService
 to generate tokens and attach them to the payload.
Frontend (
AIChatWidget.tsx
):
Listens for redirect nodes.
Executes window.location.href, element.scrollIntoView, or updates localStorage with tokens.
Builder (
RedirectNode.tsx
):
Visual representation with icons for each action type.
Configuration in 
PropertiesPanel
 changes based on selected action.
Verification
Console Test: 
tmp/test_redirect_console.rb
Logic: Simulates a flow with a redirect node and verifies the JSON payload contains the correct action and data.
ruby
# Console Output Logic
Payload: {
  type: "redirect",
  action: "navigate",
  url: "/dashboard"
}
3. Reliability & Bug Fixes
During verification, we encountered and resolved the following issues to ensure stability:

Backend Process Logic (
ChatSession
)
Issue: ActiveRecord::RecordInvalid when switching flows via Triggers because current_step_id was set to nil temporarily.
Fix: Removed validates :current_step_id, presence: true, on: :update from 
ChatSession
 since 
FlowEngine
 is designed to handle this nil state during context switching.
Frontend Runtime Error (
useChatFlow.ts
)
Issue: TypeError: Cannot read properties of null (reading 'substring') when processing nodes without content (e.g., Redirect/Handoff).
Fix: Added safe navigation 
(res.response.content || '').substring(...)
 in the logging logic.
TypeScript Build Errors
Issue: 
ChatNodeData
 union type did not satisfy NodeProps generic definition in strict mode.
Fix: Updated 
ListNode
, 
OptionNode
, 
ConditionNode
, 
TriggerNode
, and 
MessageNode
 to use explicit NodeProps<Node<T>> generics, ensuring correct type inference.
Outcome: npm run build now passes successfully.