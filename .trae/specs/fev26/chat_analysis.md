Technical Viability Study: Internal AI Agents & Typebot Implementation
1. Executive Summary
This document analyzes the feasibility of removing n8n from the stack and replacing it with native Rails 8 + React solutions. It also proposes an architecture for an internal "Typebot-like" flow builder and "AI Agents" focused on lead maintenance.

Verdict: High Feasibility. The project already hosts the necessary frontend libraries (reactflow, zustand) and a robust backend foundation (Rails 8, PostgreSQL). Moving logic internal will improve performance, security, and integration depth (direct DB access).

2. Replacing n8n with Internal AI Agents
Current State (n8n)
Currently, n8n handles the "LMA" (Lead Management Automation) workflow:

Trigger: Receives data.
Logic: JSON-based nodes (Classifier -> Agents -> Response).
IO: HTTP requests back to Rails.
Proposed Architecture (Rails Services)
We will replace the external n8n workflow with a dedicated Service Layer in Rails.

Tech Stack
Gem: ruby-openai (for LLM interactions).
Pattern: Service Objects + State Machine.
Background Jobs: Sidekiq (for long-running agent tasks without blocking HTTP).
Structure
ruby
# app/services/ai/lma/orchestrator.rb
module Ai
  module Lma
    class Orchestrator
      def call(lead, messages)
        # 1. Classify intent
        intent = Ai::Lma::Classifier.new(lead, messages).call
        
        # 2. Route to specific agent
        response = case intent
                   when :discovery then Ai::Agents::Martha.new(lead).call
                   when :enchantment then Ai::Agents::Anna.new(lead).call
                   when :closing then Ai::Agents::Maju.new(lead).call
                   end
                   
        # 3. Persist & Return
        LeadUpdater.new(lead, response).call
      end
    end
  end
end
Migration Plan
Install ruby-openai.
Port Classifier logic to a Ruby Service.
Port individual Agents (Martha, Anna, Maju) to Ruby Services.
Expose an API endpoint (e.g., POST /api/v1/ai/chat) that calls the Orchestrator directly, bypassing the HTTP round-trip n8n used.
3. Internal Typebot (Chatbot Builder & Engine)
Requirement
A "Typebot-like" experience:

Modules: Fixed flows (Options, Inputs) + AI interaction.
Admin: Drag-and-drop builder.
Client: AiChatWidget functional on the site.
Architecture: Server-Driven Flow
To maintain security and allow complex agent switching, the "State" of the user's conversation should be managed by the server. The Frontend becomes a renderer.

3.1 Database Schema
We need 3 core models:

ChatFlow (chat_flows)

name: string
trigger_keyword: string (optional)
definition: jsonb (The entire React Flow JSON structure)
published: boolean
ChatSession (chat_sessions)

lead_id: reference
flow_id: reference
current_step_id: string (ID of the node in the JSON)
context: jsonb (Variables collected: { name: "John", email: "..." })
3.2 Admin Builder (Frontend)
Library: reactflow (Already in 
package.json
).
Location: frontend/src/features/chat-builder.
Components:
sidebar: List of node types (Text, Input, Email, AI Handoff).
canvas: The flow area.
properties_panel: Edit node details.
3.3 The Engine (Backend)
A service Ai::FlowEngine that takes a ChatSession and an input:

Validates input against current step (e.g., valid email?).
Updates context.
Determines next_step_id based on edges in specific ChatFlow.
Returns the payload for the frontend to render.
3.4 The Widget (Frontend)
Location: 
components/chat/AIChatWidget.tsx
.
Logic:
On Load: Fetch GET /api/v1/chat/session.
Display: Render component based on step.type (e.g., TextBubble, OptionList, Input).
Interaction: User sends data -> POST /api/v1/chat/input -> Backend processes -> Returns new UI state.
4. Integration with AI Agents
The "Typebot" flow will have a specific node type: AI Agent Handoff.

When the flow reaches this node, the FlowEngine switches the session mode to "AI".
Subsequent messages are routed to Ai::Lma::Orchestrator instead of the rigid Flow Engine.
The AI can optionally "hand back" to the flow (e.g., "I have scheduled the meeting, back to flow to collect feedback").
5. Roadmap & Effort
Backend Foundation (1-2 days)

Add ruby-openai.
Create Models (ChatFlow, ChatSession).
Implement FlowEngine logic (Node traversal).
AI Services Implementation (1 day)

Port n8n LMA logic to Ruby services.
Test with db/seeds.
Admin Flow Builder (2-3 days)

Create Interface with React Flow.
Save/Load logic.
Widget Integration (1 day)

Update AIChatWidget to consume the engine API.
Handle "Text" and "Options" rendering.
Total Est: ~1 week for MVP.