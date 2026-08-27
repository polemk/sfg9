import React, { useState, useEffect } from "react";
import {
  Save,
  Bot,
  Cpu,
  FileText,
  Loader2,
  Settings,
  Sparkles,
  VenetianMask,
  Image as ImageIcon,
  Key,
  SlidersHorizontal,
  RotateCcw,
  HelpCircle,
  ExternalLink,
  Wrench,
  Building2,
  Map,
  Upload,
} from "lucide-react";
import { toast } from "sonner";
import { AgentConfig } from "../api/builder";
import { KeywordInput } from "./KeywordInput";
import { credentialsApi } from "../../../lib/api/credentials";
import type { Credential } from "../../../lib/api/types";
import { apiClient } from "@/lib/api/client";
import { Button } from "@/components/ui/Button";
import { PageHeader } from "@/components/PageHeader";

// Bloco 8 do trim (AI9-007): as duas últimas opções Anthropic desta lista
// (`claude-3-5-sonnet-20241022` e `claude-3-haiku-20240307`) foram trocadas.
// Conferido EXECUTANDO contra `GET https://api.anthropic.com/v1/models` com a
// chave do projeto: os dois ids **não existem mais** — a API devolve
// `404 - model: ...`, e um agente configurado com eles respondia "ocorreu um
// erro" em todo turno. Não é resíduo de feature removida, é deriva de API.
const AI_MODELS = [
  // Anthropic (mais recentes primeiro)
  { value: "claude-opus-5", label: "Claude Opus 5", provider: "anthropic" },
  { value: "claude-sonnet-5", label: "Claude Sonnet 5", provider: "anthropic" },
  { value: "claude-opus-4-8", label: "Claude Opus 4.8", provider: "anthropic" },
  { value: "claude-sonnet-4-6", label: "Claude Sonnet 4.6", provider: "anthropic" },
  { value: "claude-haiku-4-5-20251001", label: "Claude Haiku 4.5", provider: "anthropic" },
  // OpenAI
  { value: "gpt-4o", label: "GPT-4o", provider: "openai" },
  { value: "gpt-4o-mini", label: "GPT-4o Mini", provider: "openai" },
  { value: "gpt-4.1-mini", label: "GPT-4.1 Mini", provider: "openai" },
  { value: "gpt-4-turbo", label: "GPT-4 Turbo", provider: "openai" },
  { value: "gpt-3.5-turbo", label: "GPT-3.5 Turbo", provider: "openai" },
  // Google
  { value: "gemini-2.5-pro", label: "Gemini 2.5 Pro", provider: "google" },
  { value: "gemini-1.5-pro", label: "Gemini 1.5 Pro", provider: "google" },
  { value: "gemini-1.5-flash", label: "Gemini 1.5 Flash", provider: "google" },
];

/** Default values for advanced AI parameters */
const PARAM_DEFAULTS = {
  temperature: 0.7,
  top_p: 1.0,
  max_tokens: 1024,
  presence_penalty: 0,
  frequency_penalty: 0,
};

/** Configuration for each parameter slider */
const PARAM_CONFIG = [
  {
    key: "temperature" as const,
    label: "Criatividade (Temperature)",
    min: 0,
    max: 2,
    step: 0.1,
    lowLabel: "🎯 Preciso",
    highLabel: "🎨 Criativo",
    tooltip:
      "Controla a aleatoriedade das respostas. Valores baixos = respostas mais focadas e determinísticas. Valores altos = respostas mais criativas e imprevisíveis.",
  },
  {
    key: "top_p" as const,
    label: "Diversidade (Top P)",
    min: 0,
    max: 1,
    step: 0.05,
    lowLabel: "📝 Simples",
    highLabel: "📚 Rico",
    tooltip:
      "Filtra a diversidade do vocabulário. 0.1 = usa apenas palavras comuns. 0.9 = vocabulário mais rico e natural. Recomendação: altere Temperature OU Top P, não ambos.",
  },
  {
    key: "max_tokens" as const,
    label: "Tamanho Máximo (Tokens)",
    min: 64,
    max: 4096,
    step: 64,
    lowLabel: "✂️ Curto",
    highLabel: "📄 Longo",
    tooltip:
      "Limite máximo de tamanho da resposta. 100 tokens ≈ 75 palavras. 1024 tokens ≈ 750 palavras.",
  },
  {
    key: "presence_penalty" as const,
    label: "Novos Tópicos (Presence)",
    min: -2,
    max: 2,
    step: 0.1,
    lowLabel: "🔁 Mesmo assunto",
    highLabel: "🆕 Novos assuntos",
    tooltip:
      "Penaliza tópicos já mencionados. Valores positivos forçam o modelo a explorar novos assuntos. Valores negativos permitem ficar no mesmo tema.",
  },
  {
    key: "frequency_penalty" as const,
    label: "Repetição de Palavras (Frequency)",
    min: -2,
    max: 2,
    step: 0.1,
    lowLabel: "🔄 Pode repetir",
    highLabel: "🚫 Evita repetir",
    tooltip:
      "Penaliza palavras já usadas. Valores positivos forçam vocabulário mais variado. Valores negativos permitem repetição de frases.",
  },
];

interface AIAgentConfigPanelProps {
  flowId: string;
  flowName: string;
  agentConfig: AgentConfig;
  keywords: string[];
  personaName: string;
  personaAvatar: string;
  mappedRoutes: string[];
  overrideActiveChat: boolean;
  onConfigChange: (config: AgentConfig) => void;
  onNameChange: (name: string) => void;
  onKeywordsChange: (keywords: string[]) => void;
  onPersonaNameChange: (name: string) => void;
  onPersonaAvatarChange: (avatar: string) => void;
  onMappedRoutesChange: (routes: string[]) => void;
  onOverrideActiveChatChange: (override: boolean) => void;
  onSave: () => Promise<void>;
  isSaving: boolean;
}

export function AIAgentConfigPanel({
  flowId,
  flowName,
  agentConfig,
  keywords,
  personaName,
  personaAvatar,
  mappedRoutes,
  overrideActiveChat,
  onConfigChange,
  onNameChange,
  onKeywordsChange,
  onPersonaNameChange,
  onPersonaAvatarChange,
  onMappedRoutesChange,
  onOverrideActiveChatChange,
  onSave,
  isSaving,
}: AIAgentConfigPanelProps) {
  const [credentials, setCredentials] = useState<Credential[]>([]);
  const [loadingCredentials, setLoadingCredentials] = useState(true);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [hoveredTooltip, setHoveredTooltip] = useState<string | null>(null);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const fileInputRef = React.useRef<HTMLInputElement | null>(null);

  // Fetch credentials on mount
  useEffect(() => {
    const fetchCredentials = async () => {
      try {
        const data = await credentialsApi.getCredentials();
        setCredentials(Array.isArray(data) ? data : []);
      } catch (error) {
        console.error("Failed to load credentials", error);
        setCredentials([]);
      } finally {
        setLoadingCredentials(false);
      }
    };
    fetchCredentials();
  }, []);

  const handleModelChange = (value: string) => {
    onConfigChange({ ...agentConfig, model: value });
  };

  const handlePromptChange = (value: string) => {
    onConfigChange({ ...agentConfig, system_prompt: value });
  };

  const handleCredentialChange = (credentialId: string) => {
    onConfigChange({
      ...agentConfig,
      credential_id: credentialId ? Number(credentialId) : undefined,
    });
  };

  const handleParamChange = (key: string, value: number) => {
    onConfigChange({ ...agentConfig, [key]: value });
  };

  const handleResetDefaults = () => {
    onConfigChange({
      ...agentConfig,
      ...PARAM_DEFAULTS,
    });
    toast.success("Parâmetros resetados para os valores padrão");
  };

  const handleAvatarFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) {
      toast.error("Arquivo muito grande (máx. 2MB)");
      if (fileInputRef.current) fileInputRef.current.value = "";
      return;
    }
    setUploadingAvatar(true);
    try {
      const form = new FormData();
      form.append("file", file);
      const data: any = await apiClient.post(
        "/api/v1/uploads/avatar",
        form,
        { headers: { "Content-Type": "multipart/form-data" } },
      );
      
      console.log("[Avatar Upload] API Response:", data);
      const url = data?.data?.url || data?.url;
      if (url) {
        onPersonaAvatarChange(url);
        toast.success("Avatar do agente enviado com sucesso!");
      } else {
        throw new Error("Invalid response format: missing url");
      }
    } catch (err: any) {
      console.error("[Avatar Upload] Error:", err);
      toast.error(err?.response?.data?.message || err?.message || "Erro ao enviar avatar");
    } finally {
      if (fileInputRef.current) fileInputRef.current.value = "";
      setUploadingAvatar(false);
    }
  };

  const handleSave = async () => {
    if (!flowName.trim()) {
      toast.error("O nome do agente é obrigatório");
      return;
    }
    if (!(agentConfig.system_prompt || "").trim()) {
      toast.error("O prompt do sistema é obrigatório");
      return;
    }
    if (!agentConfig.credential_id) {
      toast.error("Selecione uma credencial de IA para o agente funcionar");
      return;
    }
    await onSave();
  };

  const selectedModel = AI_MODELS.find(
    (m) => m.value === (agentConfig.model || "gpt-4o"),
  );

  // Filter credentials by selected model's provider
  const selectedProvider = selectedModel?.provider;
  const filteredCredentials = selectedProvider
    ? credentials.filter((c) => c.provider === selectedProvider)
    : credentials;

  return (
    <div className="flex-1 overflow-y-auto px-4 sm:px-8 py-6">
      <div className="max-w-4xl mx-auto space-y-8">
        <PageHeader
          title={flowName || "Novo Agente"}
          subtitle="Configuração do AI Agent"
          rightSlot={
            <Button
              onClick={handleSave}
              disabled={isSaving}
              className="gap-2"
              variant="primary"
            >
              {isSaving ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <Save className="w-4 h-4" />
              )}
              {isSaving ? "Salvando..." : "Salvar"}
            </Button>
          }
        />

        <div className="space-y-8">
          {/* Basic Info */}
          <section className="space-y-4">
            <div className="flex items-center gap-2">
              <Settings className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Configuração Básica
              </h2>
            </div>

            <div className="bg-card border border-border rounded-lg p-5 space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium text-muted-foreground">
                  Nome do Agente
                </label>
                <input
                  type="text"
                  value={flowName}
                  onChange={(e) => onNameChange(e.target.value)}
                  className="w-full px-4 py-2.5 bg-muted/30 border border-border rounded-lg text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                  placeholder="Ex: Assistente de Vendas"
                />
              </div>
            </div>
          </section>

          {/* Keywords/Triggers */}
          <section className="space-y-4">
            <div className="flex items-center gap-2">
              <Sparkles className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Gatilhos (Keywords)
              </h2>
            </div>

            <div className="bg-card border border-border rounded-lg p-5 space-y-3">
              <p className="text-xs text-muted-foreground">
                Palavras-chave que ativam este agente automaticamente durante
                uma conversa.
              </p>
              <KeywordInput
                value={keywords}
                onChange={onKeywordsChange}
                placeholder="Ex: suporte, ajuda, dúvida"
              />
            </div>
          </section>

          {/* Persona Settings */}
          <section className="space-y-4">
            <div className="flex items-center gap-2">
              <VenetianMask className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Persona do Agente
              </h2>
            </div>

            <div className="bg-card border border-border rounded-lg p-5 space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium text-muted-foreground">
                  Nome do Atendente
                </label>
                <input
                  type="text"
                  value={personaName}
                  onChange={(e) => onPersonaNameChange(e.target.value)}
                  className="w-full px-4 py-2.5 bg-muted/30 border border-border rounded-lg text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                  placeholder="Ex: Ana da Silva"
                />
              </div>

              <div className="space-y-2">
                <label className="text-sm font-medium text-muted-foreground">
                  Avatar URL
                </label>
                <div className="flex gap-3">
                  <div className="relative flex-grow">
                    <ImageIcon className="absolute left-3 top-3 w-4 h-4 text-muted-foreground" />
                    <input
                      type="url"
                      value={personaAvatar}
                      onChange={(e) => onPersonaAvatarChange(e.target.value)}
                      className="w-full pl-10 pr-4 py-2.5 bg-muted/30 border border-border rounded-lg text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                      placeholder="https://..."
                    />
                  </div>
                  <div className="relative group shrink-0">
                    <div
                      className="w-10 h-10 rounded-full bg-muted border border-border overflow-hidden flex items-center justify-center cursor-pointer transition-all hover:ring-2 hover:ring-primary/50"
                      onClick={() => fileInputRef.current?.click()}
                    >
                      {uploadingAvatar ? (
                        <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />
                      ) : personaAvatar ? (
                        <img
                          src={personaAvatar}
                          alt="Preview"
                          className="w-full h-full object-cover"
                        />
                      ) : (
                        <VenetianMask className="w-5 h-5 text-muted-foreground" />
                      )}

                      {!uploadingAvatar && (
                        <div className="absolute inset-0 bg-brand-ink/60 text-brand-ink-foreground opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity rounded-full">
                          <Upload className="w-4 h-4 text-background" />
                        </div>
                      )}
                    </div>
                    <input
                      ref={fileInputRef}
                      type="file"
                      accept="image/*"
                      onChange={handleAvatarFile}
                      className="hidden"
                    />
                  </div>
                </div>
              </div>
            </div>
          </section>

          {/* Welcome Message */}
          <section className="space-y-4">
            <div className="flex items-center gap-2">
              <HelpCircle className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Mensagem de Boas-vindas
              </h2>
            </div>

            <div className="bg-card border border-border rounded-lg p-5 space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium text-muted-foreground">
                  Primeira mensagem (Opcional)
                </label>
                <textarea
                  value={agentConfig.welcome_message || ""}
                  onChange={(e) =>
                    onConfigChange({
                      ...agentConfig,
                      welcome_message: e.target.value,
                    })
                  }
                  className="w-full px-4 py-2.5 bg-muted/30 border border-border rounded-lg text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all resize-y min-h-[80px]"
                  placeholder="Ex: Olá! Sou seu assistente de vendas. Como posso te ajudar?"
                />
                <p className="text-xs text-muted-foreground">
                  Mensagem inicial enviada pelo agente quando um novo usuário
                  interage ou quando é invocado por palavra-chave.
                </p>
              </div>
            </div>
          </section>

          {/* Model Selection */}
          <section className="space-y-4">
            <div className="flex items-center gap-2">
              <Cpu className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Modelo de IA
              </h2>
            </div>

            <div className="bg-card border border-border rounded-lg p-5 space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium text-muted-foreground">
                  Selecione o Modelo
                </label>
                <select
                  value={agentConfig.model || "gpt-4o"}
                  onChange={(e) => handleModelChange(e.target.value)}
                  className="w-full px-4 py-2.5 bg-muted/30 border border-border rounded-lg text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all appearance-none cursor-pointer"
                >
                  {AI_MODELS.map((model) => (
                    <option key={model.value} value={model.value}>
                      {model.label} ({model.provider})
                    </option>
                  ))}
                </select>
              </div>

              {selectedModel && (
                <div className="flex items-center gap-2 px-3 py-2 bg-muted/30 rounded-lg">
                  <div className="w-2 h-2 rounded-full bg-primary" />
                  <span className="text-xs text-muted-foreground">
                    Provider:{" "}
                    <span className="font-medium text-foreground">
                      {selectedModel.provider}
                    </span>
                  </span>
                </div>
              )}
            </div>
          </section>

          {/* Credential Selection — Spec 007 */}
          <section className="space-y-4">
            <div className="flex items-center gap-2">
              <Key className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Credencial de IA
              </h2>
            </div>

            <div className="bg-card border border-border rounded-lg p-5 space-y-4">
              {loadingCredentials ? (
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Loader2 className="w-4 h-4 animate-spin" />
                  Carregando credenciais...
                </div>
              ) : filteredCredentials.length === 0 ? (
                <div className="p-4 bg-warning/10 border border-warning/30 rounded-lg">
                  <p className="text-sm text-warning font-medium mb-2">
                    ⚠️{" "}
                    {credentials.length === 0
                      ? "Nenhuma credencial cadastrada"
                      : `Nenhuma credencial ${selectedProvider} encontrada`}
                  </p>
                  <p className="text-xs text-muted-foreground mb-3">
                    {credentials.length === 0
                      ? "Cadastre uma API Key para que o agente possa se comunicar."
                      : `O modelo selecionado requer uma credencial do provider "${selectedProvider}".`}
                  </p>
                  <a
                    href="/admin/credentials"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1.5 text-xs font-medium text-primary hover:underline"
                  >
                    <ExternalLink className="w-3 h-3" />
                    Gerenciar Credenciais
                  </a>
                </div>
              ) : (
                <>
                  <div className="space-y-2">
                    <label className="text-sm font-medium text-muted-foreground">
                      Selecione a Credencial ({selectedProvider})
                    </label>
                    <select
                      value={agentConfig.credential_id?.toString() || ""}
                      onChange={(e) => handleCredentialChange(e.target.value)}
                      className="w-full px-4 py-2.5 bg-muted/30 border border-border rounded-lg text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all appearance-none cursor-pointer"
                    >
                      <option value="">— Selecione —</option>
                      {filteredCredentials.map((cred) => (
                        <option key={cred.id} value={cred.id}>
                          {cred.name} ({cred.api_key_masked})
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-muted-foreground">
                      <span className="font-numeric">
                        {filteredCredentials.length}
                      </span>{" "}
                      credencial(ais) disponível(eis)
                    </span>
                    <a
                      href="/admin/credentials"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-xs text-primary hover:underline"
                    >
                      Gerenciar
                    </a>
                  </div>
                </>
              )}
            </div>
          </section>

          {/* System Prompt */}
          <section className="space-y-4">
            <div className="flex items-center gap-2">
              <FileText className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Prompt do Sistema
              </h2>
            </div>

            <div className="bg-card border border-border rounded-lg p-5 space-y-3">
              <p className="text-xs text-muted-foreground">
                Defina as instruções e a personalidade do agente. Seja
                específico sobre o comportamento esperado.
              </p>
              <textarea
                value={agentConfig.system_prompt || ""}
                onChange={(e) => handlePromptChange(e.target.value)}
                className="w-full h-64 px-4 py-3 bg-muted/30 border border-border rounded-lg text-sm text-foreground font-mono leading-relaxed focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all resize-none"
                placeholder={`Você é um assistente especializado em...

Suas responsabilidades incluem:
- Responder dúvidas sobre produtos
- Ajudar com processos de compra
- Fornecer suporte técnico básico

Mantenha um tom profissional e amigável.`}
              />
              <div className="flex items-center justify-between text-xs text-muted-foreground">
                <span>
                  <span className="font-numeric">
                    {(agentConfig.system_prompt || "").length}
                  </span>{" "}
                  caracteres
                </span>
                <span>Markdown suportado</span>
              </div>
            </div>
          </section>

          {/* Tools Toggle — Enable asset search & listing */}
          <section className="space-y-4">
            <div className="flex items-center gap-2">
              <Wrench className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Ferramentas & Assets
              </h2>
            </div>

            <div className="bg-card border border-border rounded-lg p-5 space-y-3">
              <div className="flex items-center justify-between">
                <div className="space-y-1">
                  <label className="text-sm font-medium text-foreground">
                    Habilitar ferramentas de mídia
                  </label>
                  <p className="text-xs text-muted-foreground max-w-md">
                    Permite que a IA busque e envie fotos, vídeos e documentos
                    da operação vinculada ao fluxo. A IA poderá responder
                    perguntas como "mostra as fotos" ou "tem vídeo disponível?".
                  </p>
                </div>
                <button
                  type="button"
                  role="switch"
                  aria-checked={agentConfig.tools_enabled ?? false}
                  onClick={() =>
                    onConfigChange({
                      ...agentConfig,
                      tools_enabled: !agentConfig.tools_enabled,
                    })
                  }
                  className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring shrink-0 ${
                    agentConfig.tools_enabled ? "bg-primary" : "bg-muted"
                  }`}
                >
                  <span
                    className={`inline-block h-4 w-4 transform rounded-full bg-background shadow-e1 transition-transform ${
                      agentConfig.tools_enabled
                        ? "translate-x-6"
                        : "translate-x-1"
                    }`}
                  />
                </button>
              </div>
            </div>
          </section>


          {/* Route Mapping — Spec 025 */}
          <section className="space-y-4">
            <div className="flex items-center gap-2">
              <Map className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Mapeamento de Rotas
              </h2>
            </div>

            <div className="bg-card border border-border rounded-lg p-5 space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium text-muted-foreground">
                  Rotas Mapeadas
                </label>
                <KeywordInput
                  value={mappedRoutes}
                  onChange={onMappedRoutesChange}
                  placeholder="Ex: /home, /precos, /contato"
                />
                <p className="text-xs text-muted-foreground">
                  URLs onde este agente deve ser ativado automaticamente
                  (Roteamento Espacial).
                </p>
              </div>

              <div className="flex items-center justify-between pt-2">
                <div className="space-y-1">
                  <label className="text-sm font-medium text-foreground">
                    Sobrescrever Chat Ativo
                  </label>
                  <p className="text-xs text-muted-foreground max-w-md">
                    Se ativado, este agente assumirá a conversa mesmo que já
                    exista um atendimento humano ou outro chatbot em andamento
                    nestas rotas.
                  </p>
                </div>
                <button
                  type="button"
                  role="switch"
                  aria-checked={overrideActiveChat}
                  onClick={() =>
                    onOverrideActiveChatChange(!overrideActiveChat)
                  }
                  className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring shrink-0 ${
                    overrideActiveChat ? "bg-primary" : "bg-muted"
                  }`}
                >
                  <span
                    className={`inline-block h-4 w-4 transform rounded-full bg-background shadow-e1 transition-transform ${
                      overrideActiveChat ? "translate-x-6" : "translate-x-1"
                    }`}
                  />
                </button>
              </div>
            </div>
          </section>

          {/* Advanced Parameters — Spec 008 */}
          <section className="space-y-4">
            <button
              type="button"
              onClick={() => setShowAdvanced(!showAdvanced)}
              aria-expanded={showAdvanced}
              className="flex items-center gap-2 w-full group rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <SlidersHorizontal className="w-4 h-4 text-muted-foreground" />
              <h2 className="text-sm font-semibold text-foreground uppercase tracking-wider">
                Configurações Avançadas
              </h2>
              <div
                className={`ml-auto text-xs text-muted-foreground transition-transform ${showAdvanced ? "rotate-180" : ""}`}
              >
                ▼
              </div>
            </button>

            {showAdvanced && (
              <div className="bg-card border border-border rounded-lg p-5 space-y-6">
                <div className="flex items-center justify-between">
                  <p className="text-xs text-muted-foreground">
                    Ajuste fino do comportamento da IA. Passe o mouse em (?)
                    para entender cada parâmetro.
                  </p>
                  <Button
                    onClick={handleResetDefaults}
                    variant="ghost"
                    size="sm"
                  >
                    <RotateCcw className="w-3 h-3" />
                    Resetar
                  </Button>
                </div>

                {PARAM_CONFIG.map((param) => {
                  const value =
                    (agentConfig[param.key as keyof AgentConfig] as number) ??
                    PARAM_DEFAULTS[param.key as keyof typeof PARAM_DEFAULTS];
                  const numValue =
                    typeof value === "number"
                      ? value
                      : PARAM_DEFAULTS[
                          param.key as keyof typeof PARAM_DEFAULTS
                        ];

                  return (
                    <div key={param.key} className="space-y-2">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-1.5">
                          <label className="text-sm font-medium text-foreground">
                            {param.label}
                          </label>
                          <div
                            className="relative"
                            onMouseEnter={() => setHoveredTooltip(param.key)}
                            onMouseLeave={() => setHoveredTooltip(null)}
                          >
                            <HelpCircle className="w-3.5 h-3.5 text-muted-foreground cursor-help" />
                            {hoveredTooltip === param.key && (
                              <div className="absolute left-6 top-0 z-tooltip w-72 p-3 bg-popover border border-border rounded-lg shadow-e2 text-xs text-muted-foreground leading-relaxed">
                                {param.tooltip}
                              </div>
                            )}
                          </div>
                        </div>
                        <input
                          type="number"
                          value={numValue}
                          onChange={(e) =>
                            handleParamChange(
                              param.key,
                              parseFloat(e.target.value) || 0,
                            )
                          }
                          min={param.min}
                          max={param.max}
                          step={param.step}
                          className="w-20 px-2 py-1 bg-muted/30 border border-border rounded-sm text-xs text-foreground text-right font-numeric focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        />
                      </div>
                      <input
                        type="range"
                        value={numValue}
                        onChange={(e) =>
                          handleParamChange(
                            param.key,
                            parseFloat(e.target.value),
                          )
                        }
                        min={param.min}
                        max={param.max}
                        step={param.step}
                        className="w-full h-2 bg-muted rounded-lg appearance-none cursor-pointer accent-primary"
                      />
                      <div className="flex justify-between text-xs text-muted-foreground">
                        <span>{param.lowLabel}</span>
                        <span>{param.highLabel}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </section>

          {/* Info Card */}
          <div className="p-4 bg-primary/5 border border-primary/20 rounded-lg">
            <h4 className="text-xs font-bold text-primary uppercase mb-2">
              Como funciona?
            </h4>
            <p className="text-xs text-muted-foreground leading-relaxed">
              O AI Agent utiliza o modelo selecionado para processar mensagens
              de forma autônoma, seguindo as instruções definidas no prompt do
              sistema. Diferente do Chatbot tradicional, ele não segue um fluxo
              visual fixo. Use <strong>keywords</strong> para alternar entre
              chatbots e agentes de IA com a mesma conversa.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
