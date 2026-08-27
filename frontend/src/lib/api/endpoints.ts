import { getCsrfToken } from './tokenStore'
import { apiClient } from "./client";
import {
  sessionId as sessionIdDaVisita,
  visitorId as visitorIdDaPessoa,
} from "@/lib/analytics/identidade";
import type {
  LoginRequest,
  LoginResponse,
  RefreshTokenResponse,
  User,
  UserStats,
  SafegoldRole,
  /* WhatsappMessage, */
  Medium,
} from "./types";

export { credentialsApi } from "./credentials";

import { readPageMeta, pageParams, type PageMeta, type PageRequest } from "./pagination";

/**
 * Uma linha do catálogo de permissões, do jeito que `PermissionsService` serializa.
 *
 * O catálogo tem **7** linhas (DEC-108): `user_is_readonly` mais as 6 abilities do
 * legado que tinham call site real. As outras 10 não tinham nenhum consumidor fora
 * do seed e ficaram de fora. A tela renderiza o que o servidor devolve — não há
 * lista escrita no cliente.
 *
 * **Duas delas são limite, não interruptor** (`max_users_amount`,
 * `max_invitations_amount`): `kind` diz qual é qual, e é o `kind` que decide se a
 * tela mostra um toggle ou um campo numérico.
 */
export interface UserPermissionRow {
  id: number;
  key: string;
  title: string;
  description: string | null;
  sort_order: number;
  granted: boolean;
  /** `conditional` = interruptor; `limit` = teto numérico. */
  kind: PermissionKind;
  /**
   * Só em `kind: "limit"`. **`null` é "sem limite", e é diferente de `0`**, que é
   * "nenhum permitido" — os dois existem no catálogo do legado.
   */
  limit_value?: number | null;
}

export type PermissionKind = "conditional" | "limit";

/**
 * O corpo do `PUT` de permissão. Para uma condicional manda-se `granted`; para uma
 * de limite manda-se `limit_value`. O servidor recusa a combinação errada com 422 —
 * a tela não precisa adivinhar, ela lê o `kind`.
 */
export interface PermissionChange {
  granted?: boolean;
  limit_value?: number | null;
  reason?: string;
}

export interface UserTypeSummary {
  id: number;
  name: string;
  display_name: string;
  hierarchy_level: number;
  description: string | null;
}

export interface UserTypePermissionsPayload {
  user_type: { id: number; name: string; hierarchy_level: number };
  /** Trava de hierarquia (DEC-18.2): o Admin lê o papel do OG e **não** o edita. */
  editable: boolean;
  permissions: UserPermissionRow[];
}

/**
 * BE-040 / BE-041 / BE-042 — papéis e suas permissões padrão.
 *
 * A lista já vem filtrada por hierarquia no servidor (BE-504): o Gerente não enxerga
 * OG nem Admin. Aqui não se refiltra nada — refiltrar no cliente é como as duas
 * listas divergem.
 */
export const userTypesApi = {
  list: () => apiClient.get<{ user_types: UserTypeSummary[] }>("/api/v1/user_types"),

  permissions: (id: number) =>
    apiClient.get<UserTypePermissionsPayload>(`/api/v1/user_types/${id}/permissions`),

  setPermission: (id: number, key: string, change: PermissionChange) =>
    apiClient.put<{ user_type_id: number; key: string; granted: boolean; limit_value: number | null }>(
      `/api/v1/user_types/${id}/permissions/${key}`,
      change,
    ),
};

export const permissionsApi = {
  /** O catálogo. Recurso administrativo: OG e Admin (DEC-18.2); o Gerente recebe 403. */
  catalog: () =>
    apiClient.get<{ permissions: Omit<UserPermissionRow, "granted">[] }>("/api/v1/permissions"),

  /** As PRÓPRIAS permissões. Qualquer sessão lê — é o que o front usa para esconder botão. */
  mine: () =>
    apiClient.get<{ user_id: string; permissions: UserPermissionRow[] }>("/api/v1/permissions/me"),
};

export const authApi = {
  // Magic Login - Request code
  requestMagicCode: (identifier: string, method: "email" | "whatsapp") =>
    apiClient.post<{ success: boolean; message: string }>(
      "/auth/v1/magic_login/request_code",
      { identifier, method },
    ),

  // Magic Login - Validate code and login
  validateMagicCode: (
    identifier: string,
    code: string,
    method: "email" | "whatsapp",
  ) =>
    apiClient.post<LoginResponse>("/auth/v1/magic_login/validate_code", {
      identifier,
      code,
      method,
    }),

  // Check if can resend code
  canResendCode: (identifier: string, method: "email" | "whatsapp") =>
    apiClient.post<{ can_resend: boolean; remaining_time?: number }>(
      "/auth/v1/magic_login/can_resend",
      { identifier, method },
    ),

  // OAuth URLs
  getGoogleAuthUrl: (redirectUri?: string) =>
    apiClient.get<{ url: string }>(
      `/auth/v1/oauth/google_url${redirectUri ? `?redirect_uri=${redirectUri}` : ""}`,
    ),

  getFacebookAuthUrl: (redirectUri?: string) =>
    apiClient.get<{ url: string }>(
      `/auth/v1/oauth/facebook_url${redirectUri ? `?redirect_uri=${redirectUri}` : ""}`,
    ),

  // OAuth callback
  handleOAuthCallback: (
    provider: "google" | "facebook",
    code: string,
    state?: string,
  ) =>
    apiClient.post<LoginResponse>("/auth/v1/oauth/callback", {
      provider,
      code,
      state,
    }),

  // Session management
  // Sem argumento: o refresh token vai no cookie HttpOnly (Path=/auth/v1).
  refresh: () => apiClient.post<RefreshTokenResponse>("/auth/v1/sessions/refresh", {}),

  logout: () => apiClient.delete("/auth/v1/sessions/logout"),

  getSessionStatus: () =>
    apiClient.get<{ valid: boolean; user?: User }>("/auth/v1/sessions/status"),

  // Legacy endpoints (deprecated)
  login: (data: LoginRequest) =>
    apiClient.post<LoginResponse>("/auth/v1/login", data),

  me: () => apiClient.get<User>("/auth/v1/me"),
  updateMe: (data: Partial<User>) =>
    apiClient.patch<User>("/auth/v1/me", data, {
      headers: { "X-CSRF-Token": getCsrfToken() || "" },
    }),
};

export const usersApi = {
  list: (params?: {
    page?: number;
    perPage?: number;
    q?: string;
    // Os papéis do Safegold (DEC-41). `client` saiu junto com o tipo.
    type?: SafegoldRole;
  }) => {
    const page = params?.page ?? 1;
    const perPage = params?.perPage ?? 20;
    const q = params?.q ? `&q=${encodeURIComponent(params.q)}` : "";
    const type = params?.type ? `&type=${params.type}` : "";
    return apiClient.get<{ users: User[]; total: number; total_pages: number }>(
      `/api/v1/users?page=${page}&per_page=${perPage}${q}${type}`,
    );
  },

  get: (id: string) => apiClient.get<User>(`/api/v1/users/${id}`),

  create: (data: Partial<User> & { user_type?: string }) =>
    apiClient.post<User>("/api/v1/users", data),

  update: (id: string, data: Partial<User> & { user_type?: string }) =>
    apiClient.patch<User>(`/api/v1/users/${id}`, data),

  /**
   * Remoção. `code` só é exigido na AUTO-remoção: o legado confirmava por senha, e
   * num produto sem senha (DEC-14) a confirmação passa a ser o código enviado ao
   * destino cadastrado.
   */
  delete: (id: string, code?: string) =>
    apiClient.delete(`/api/v1/users/${id}${code ? `?code=${encodeURIComponent(code)}` : ""}`),

  /** DEC-39 — bloquear revoga a sessão ativa na hora; não apaga a conta. */
  block: (id: string, reason?: string) =>
    apiClient.post<User>(`/api/v1/users/${id}/block`, { reason }),

  unblock: (id: string) => apiClient.delete<User>(`/api/v1/users/${id}/block`),

  /** BE-012 — reenvia o magic link de primeiro acesso. Nenhuma senha (D-38). */
  invite: (id: string) => apiClient.post<{ message: string }>(`/api/v1/users/${id}/invite`, {}),

  /**
   * BE-034 — participações do usuário, **paginadas e escopadas**.
   *
   * O envelope vem em cabeçalho (DEC-62) e quem o traduz é `readPageMeta`, um lugar
   * só — por isso `getRaw`. O legado fazia `Project.all` aqui: sem paginação e sem
   * filtro, a aba "Projetos" de qualquer pessoa listava a carteira inteira.
   *
   * ⚠ **Existe um segundo endpoint com o mesmo propósito**:
   * `GET /api/v1/users/:id/projects` (S4 / BE-100, `projectsApi.ofUser`), que é
   * escopado mas **não paginado**. Os dois nasceram em fatias diferentes para a
   * mesma aba. Este é o que a tela `/users/:id` consome, porque a paginação é
   * requisito da tarefa; a duplicação está registrada para o orquestrador colapsar,
   * e não é colapsada aqui porque `BE-100` é ID de outra fatia (contrato C4).
   */
  memberships: async (
    id: string,
    params: PageRequest = {},
  ): Promise<{ items: Array<{ id: number; name: string; slug: string; is_active: boolean }>; meta: PageMeta }> => {
    const res = await apiClient.getRaw<{ projects: Array<{ id: number; name: string; slug: string; is_active: boolean }> }>(
      `/api/v1/users/${id}/memberships?${new URLSearchParams(
        Object.entries(pageParams(params)).map(([k, v]) => [k, String(v)]),
      ).toString()}`,
    )
    return {
      items: res.data?.projects ?? [],
      meta: readPageMeta({ body: res.data, headers: res.headers as any }, params),
    }
  },

  /**
   * BE-018 / D-34 — permissões efetivas de UM usuário.
   *
   * O `:id` **manda**: no legado `fetch_permission` fazia
   * `Ability.find(params[:id] || params[:ability_id])` e descartava o id do usuário,
   * de modo que qualquer linha de `Ability` era alcançável por URL. Era o vetor mais
   * direto de escalação de privilégio do sistema.
   *
   * Fora do alcance de hierarquia o servidor responde **403 `HIERARCHY_LOCKED`** —
   * a tela mostra o painel em leitura, não uma tela de erro: "existe e você não pode
   * mexer" é informação diferente de "não existe".
   */
  permissions: (id: string) =>
    apiClient.get<{ user_id: string; permissions: UserPermissionRow[] }>(`/api/v1/users/${id}/permissions`),

  setPermission: (id: string, key: string, change: PermissionChange) =>
    apiClient.put<{ user_id: string; key: string; granted: boolean; effective: boolean }>(
      `/api/v1/users/${id}/permissions/${key}`,
      change,
    ),

  /** BE-035 — 422 para CPF inválido, 409 para CPF já cadastrado (não 405/406). */
  validateCpf: (cpf: string, id?: string) =>
    apiClient.get<{ cpf: string; valid: boolean }>(
      `/api/v1/users/validate_cpf?cpf=${encodeURIComponent(cpf)}${id ? `&id=${id}` : ""}`,
    ),

  stats: () => apiClient.get<UserStats>(`/api/v1/users/stats`),
};

export const impersonateApi = {
  /**
   * DEC-18.3 — **`reason` é obrigatório.** O backend recusa sem ele (422).
   *
   * Não é burocracia: a trilha guarda quem personificou, quem foi personificado,
   * quando e **por quê**, e sem o motivo a trilha responde três perguntas de quatro.
   * A sessão personificada também expira em 1 hora — não são mais os 30 dias do
   * refresh comum.
   */
  start: (userId: string, reason: string) =>
    apiClient.post<{
      access_token: string;
      refresh_token: string;
      expires_in: number;
      impersonated_user: User;
      true_user: { id: string; name: string; email: string };
    }>("/auth/v1/impersonate/start", { user_id: userId, reason }),

  stop: () =>
    apiClient.post<{
      access_token: string;
      refresh_token: string;
      user: User;
    }>("/auth/v1/impersonate/stop"),
};

export const countriesApi = {
  list: (q?: string) =>
    apiClient.get<{
      countries: { name: string; iso2: string; dial_code: string }[];
    }>(`/api/v1/countries${q ? `?q=${encodeURIComponent(q)}` : ""}`),
};

export const whatsappApi = {
  sendMessage: (
    number: string,
    text: string,
    options?: {
      delay?: number;
      presence?: string;
      link_preview?: boolean;
      quoted?: Record<string, unknown>;
      mentions?: Record<string, unknown>;
    },
  ) =>
    apiClient.post<{ status: string; message: string; data: unknown }>(
      "/whats/v1/messages/send_message",
      { number, text, ...(options || {}) },
    ),
};

export const instancesApi = {
  create: (data: Record<string, unknown>) =>
    apiClient.post<{ status: string; message: string; data: unknown }>(
      "/whats/v1/instances/create_instance",
      data,
    ),
  delete: () =>
    apiClient.delete<{ status: string; message: string; data: unknown }>(
      "/whats/v1/instances/delete_instance",
    ),
  logout: () =>
    apiClient.get<{ status: string; message: string; data: unknown }>(
      "/whats/v1/instances/logout_instance",
    ),
  list: () =>
    apiClient.get<{ status: string; message: string; data: unknown }>(
      "/whats/v1/instances/list_instances",
    ),
  connect: (number?: string) =>
    apiClient.get<{ status: string; message: string; data: any }>(
      `/whats/v1/instances/connect_instance${number ? `?number=${number}` : ""}`,
    ),
  status: () =>
    apiClient.get<{ status: string; message: string; data: any }>(
      "/whats/v1/instances/instance_connect_status",
    ),
  connectionStatus: (instance_id?: string) =>
    apiClient.get<any>(
      `/whats/v1/instances/instance/connection-status${instance_id ? `?instance_id=${instance_id}` : ""}`,
    ),
  getInstance: () => apiClient.get<any>("/whats/v1/instances/instance"),
  restart: () =>
    apiClient.post<{ status: string; message: string; data: any }>(
      "/whats/v1/instances/restart_instance",
    ),
};

export const webhooksApi = {
  config: (data: {
    url: string;
    events?: string[];
    webhookByEvents?: boolean;
    webhookBase64?: boolean;
  }) =>
    apiClient.post<{ status: string; message: string; data: any }>(
      "/whats/v1/webhooks/config",
      data,
    ),
  list: () =>
    apiClient.get<{ status: string; message: string; data: any }>(
      "/whats/v1/webhooks/config",
    ),
  test: (url: string) =>
    apiClient.post<{ status: string; message: string; data: any }>(
      "/whats/v1/webhooks/config/test",
      { url },
    ),
};

// Flow Executions API (Execution Viewer)
export interface FlowExecutionSession {
  id: number;
  flow_name: string;
  flow_id: number;
  steps_count: number;
  started_at: string;
  last_activity_at: string;
  current_step: string;
  context: Record<string, any>;
}

export interface FlowExecutionStep {
  id: number;
  node_id: string;
  node_type: string;
  input_data: Record<string, any>;
  output_data: Record<string, any>;
  context_snapshot: Record<string, any>;
  summary: string;
  created_at: string;
}

export interface FlowExecutionDetail {
  session: {
    id: number;
    flow_name: string;
    flow_id: number;
    current_step: string;
    context: Record<string, any>;
    created_at: string;
  };
  timeline: FlowExecutionStep[];
}

export const flowExecutionsApi = {
  list: (params?: { flow_id?: number; page?: number; per_page?: number }) => {
    const page = params?.page ?? 1;
    const perPage = params?.per_page ?? 20;
    const flowId = params?.flow_id ? `&flow_id=${params.flow_id}` : "";
    return apiClient.get<{
      sessions: FlowExecutionSession[];
      meta: {
        total: number;
        page: number;
        per_page: number;
        total_pages: number;
      };
    }>(`/api/v1/flow_executions?page=${page}&per_page=${perPage}${flowId}`);
  },

  get: (sessionId: number) =>
    apiClient.get<FlowExecutionDetail>(`/api/v1/flow_executions/${sessionId}`),

  stats: (params?: { flow_id?: number; days?: number }) => {
    const days = params?.days ?? 7;
    const flowId = params?.flow_id ? `&flow_id=${params.flow_id}` : "";
    return apiClient.get<{
      total_executions: number;
      unique_sessions: number;
      by_node_type: Record<string, number>;
      by_day: Record<string, number>;
    }>(`/api/v1/flow_executions/stats?days=${days}${flowId}`);
  },
};

// ChatFlows API (Agents/Bots)
export interface ChatFlowSummary {
  id: number;
  name: string;
  kind: "chatbot" | "ai_agent";
  persona_name?: string;
  persona_avatar?: string;
  is_default?: boolean;
}

export const chatFlowsApi = {
  list: async (params?: {
    limit?: number;
    offset?: number;
    search?: string;
  }) => {
    const limit = params?.limit ?? 50;
    const offset = params?.offset ?? 0;
    const search = params?.search
      ? `&search=${encodeURIComponent(params.search)}`
      : "";
    const res = await apiClient.get<any>(
      `/api/v1/flows?limit=${limit}&offset=${offset}${search}`,
    );
    const data = (res as any)?.data ?? res;
    return Array.isArray(data)
      ? (data as ChatFlowSummary[])
      : ((data?.flows ?? data?.chat_flows ?? []) as ChatFlowSummary[]);
  },

  getFlowByContext: async (userType: string, path: string) => {
    const res = await apiClient.getPublic<any>(
      `/api/v1/flows/contextual?user_type=${userType}&route_path=${path}`,
    );
    return (res as any)?.data ?? res;
  },
};
