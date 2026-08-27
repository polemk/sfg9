
import { apiClient } from '@/lib/api/client';
import { ChatNode } from '../types/nodes';
import { Edge } from '@xyflow/react';


export type FlowKind = 'chatbot' | 'ai_agent';

export type AgentConfig = {
    model?: string;
    system_prompt?: string;
    welcome_message?: string;
    credential_id?: number;
    temperature?: number;
    top_p?: number;
    max_tokens?: number;
    presence_penalty?: number;
    frequency_penalty?: number;
    tools_enabled?: boolean;  // Enable asset tools (search, list)
    capabilities?: string[];  // Toolsets enabled per-agent (o backend deriva 'assets' do flag legado tools_enabled)
};

export type ChatFlowData = {
    id: string;
    name: string;
    kind: FlowKind;
    trigger_keyword?: string;
    keywords?: string[];
    persona_name?: string;
    persona_description?: string;
    persona_avatar?: string;
    is_default?: boolean;
    definition: {
        nodes: ChatNode[];
        edges: Edge[];
    };
    agent_config: AgentConfig;
    credential_id?: number;
    mapped_routes?: string[];
    override_active_chat?: boolean;
};

export const chatBuilderApi = {
    getDefaultFlow: async (): Promise<ChatFlowData> => {
        const response = await apiClient.get<ChatFlowData>('/api/v1/flows/default');
        return response as ChatFlowData;
    },

    getFlowById: async (id: string): Promise<ChatFlowData> => {
        const response = await apiClient.get<ChatFlowData>(`/api/v1/flows/${id}`);
        return response as ChatFlowData;
    },

    saveFlow: async (id: string, data: {
        definition?: { nodes: ChatNode[]; edges: Edge[] };
        agent_config?: AgentConfig;
        name?: string;
        keywords?: string[];
        persona_name?: string;
        persona_description?: string;
        persona_avatar?: string;
        credential_id?: number;
        mapped_routes?: string[];
        override_active_chat?: boolean;
    }): Promise<ChatFlowData> => {
        const response = await apiClient.put<ChatFlowData>(`/api/v1/flows/${id}`, data);
        return response as ChatFlowData;
    },

    createFlow: async (data: {
        name: string;
        kind: FlowKind;
        definition?: { nodes: ChatNode[]; edges: Edge[] };
        agent_config?: AgentConfig;
            mapped_routes?: string[];
        override_active_chat?: boolean;
    }): Promise<ChatFlowData> => {
        const response = await apiClient.post<ChatFlowData>('/api/v1/flows', data);
        return response as ChatFlowData;
    },

    updateFlowMeta: async (id: string, data: { name?: string; keywords?: string[]; persona_name?: string; persona_description?: string; persona_avatar?: string }): Promise<ChatFlowData> => {
        const response = await apiClient.put<ChatFlowData>(`/api/v1/flows/${id}`, data);
        return response as ChatFlowData;
    },

};
