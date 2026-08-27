
import { Node } from '@xyflow/react';

export type TextNodeData = {
    content: string;
};

export type InputNodeData = {
    content: string;
    variable: string;
    inputType: 'text' | 'email' | 'phone';
};

export type OptionNodeData = {
    content: string;
    options: string[];
};

export type ConditionNodeData = {
    variable: string;
    operator: string;
    value: string;
};

export type TriggerNodeData = {
    flowName: string;
    keywords: string[];
    isDefault: boolean;
    personaName?: string;
    personaAvatar?: string;
};

export type HandoffNodeData = {
    targetFlowId: string;
    targetFlowName?: string; // Optional for display
};

export type RedirectNodeData = {
    action: 'navigate' | 'scroll_to' | 'auth';
    url?: string;
    target?: string;
};

export type ChatNodeData = TextNodeData | InputNodeData | OptionNodeData | ConditionNodeData | TriggerNodeData | HandoffNodeData | RedirectNodeData;

export type ChatNode = Node & {
    data: ChatNodeData;
};
