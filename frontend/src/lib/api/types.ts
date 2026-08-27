export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  access_token: string;
  refresh_token: string;
  user: {
    id: string;
    email: string;
    name: string;
  };
}

export interface RefreshTokenResponse {
  access_token: string;
  // O refresh nunca vem no corpo — sai em cookie HttpOnly (Path=/auth/v1).
  user?: any;
}

export interface User {
  id: string;
  email: string;
  name: string;
  phone?: string;

  avatar_url?: string;
  cpf_cnpj?: string;
  cep?: string;
  street?: string;
  number?: string;
  complement?: string;
  district?: string;
  city?: string;
  state?: string;
  user_type_id?: number;
  user_type?: string;
  last_login_at?: string;
  login_count?: number;
  created_at: string;
  updated_at: string;
  biography?: string;
  biography_html?: string;
  biography_text?: string;
  is_og?: boolean;
  permissions?: Array<{
    key: string;
    title?: string;
    granted_at?: string;
    revoked_at?: string | null;
  }>;
  user_type_slug?: string;
  custom_variables?: Record<string, string>;
  /** DEC-45 — identificador alternativo. IDENTIFICA, não recebe. */
  username?: string | null;
  /** BE-048 — código curto A-Z0-9 que o usuário dita por telefone. */
  identifier?: string | null;
  /** DEC-39 — conta bloqueada. */
  blocked_at?: string | null;
  blocked_reason?: string | null;
  is_blocked?: boolean;
  /** DEC-74 — indicador "Verificação: {nível}". Decorativo. */
  confiability_level?: "baixa" | "media" | "alta" | "maxima";
  is_default_member?: boolean;

  // --- Perfil estendido (DEC-74 / S1 tarefa 1.1) -----------------------------
  // As seis colunas vinham do `livetat_auth_user_infos` do legado (41 campos, tipos
  // errados) e entraram em `users` com o TIPO certo: aniversário é `date`, não
  // string; a emissão do documento fiscal é `date`, e o legado aceitava "00/00/0000".
  gender?: "male" | "female" | "other" | "undisclosed" | null;
  birthday?: string | null;
  cnpj?: string | null;
  fiscal_document_number?: string | null;
  fiscal_document_issued_at?: string | null;
  graduation?: string | null;
  /** DEC-74 — degrau "Máxima" da verificação. **Não** trava a edição do telefone. */
  is_phone_checked?: boolean;
}

/** Papéis do Safegold (DEC-41). Menor = mais poder: OG=1 … Colaborador=4. */
export type SafegoldRole = "og" | "admin" | "gerente" | "colaborador";

export interface UserStats {
  total: number;
  active: number;
  recent: number;
  og_count: number;
  /**
   * Contagem por papel. **Contrato único** desde 25/08/2026.
   *
   * Substituiu o alias depreciado `client_count`, que apontava `client` (tipo
   * removido pela DEC-41) para Colaborador. O alias existia só porque esta tela
   * ainda o lia — sem ele o card mostraria zero em silêncio, que é pior que quebrar.
   */
  by_role: Record<SafegoldRole, number>;
}

export interface WhatsappMessage {
  id: string;
  message: string;
  phone: string;
  status: "sent" | "delivered" | "read" | "failed";
  created_at: string;
}

export type ConnectionStatus =
  | "unknown"
  | "connecting"
  | "connected"
  | "disconnected"
  | "waiting_qr";

export interface ConnectionUpdateEvent {
  type: "connection_update";
  instance_id: string;
  status: ConnectionStatus | "open" | "close" | "qr";
  data: {
    connection?: string;
    qr?: string | null;
    lastDisconnect?: { error?: string; code?: number } | null;
    receivedPendingNotifications?: boolean;
  };
  timestamp: string;
}

export interface LogoutInstanceEvent {
  type: "logout_instance";
  instance_id: string;
  reason: string;
  timestamp: string;
}

export interface QrcodeUpdatedEvent {
  type: "qrcode_updated";
  instance_id: string;
  qr_code: string;
  /**
   * Validade do código, em segundos. Chega `null` quando a Evolution não
   * informa validade no payload QRCODE_UPDATED — que é o caso hoje. A tela
   * trata nulo como "sem prazo conhecido" e mostra frescor em vez de contagem.
   */
  expires_in?: number | null;
  /** Mesmo prazo, absoluto (ISO 8601), como gravado na instância. */
  qr_expires_at?: string | null;
  session?: string | null;
  timestamp: string;
}

export type WhatsRealtimeEvent =
  | ConnectionUpdateEvent
  | LogoutInstanceEvent
  | QrcodeUpdatedEvent;

export interface Medium {
  id: string;
  title: string;
  description?: string;
  identifier?: string;
  active: boolean;
  media_type: "image" | "video";
  display_order: number;
  file_url: string;
  external_url?: string;
  optimized_url?: string;
  small_url?: string;
  thumbnail_url?: string;
  width?: number;
  height?: number;
  created_at: string;
}

export interface Credential {
  id: string;
  name: string;
  provider: "openai" | "anthropic" | "google" | "openai_whisper";
  api_key_masked: string;
  created_at: string;
  updated_at: string;
}

export interface CreateCredentialRequest {
  name: string;
  provider: "openai" | "anthropic" | "google" | string;
  api_key: string;
}

export interface UpdateCredentialRequest {
  name?: string;
  api_key?: string;
}

