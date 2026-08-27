import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import { createPortal } from "react-dom";
import {
  X,
  Minus,
  Image as ImageIcon,
  Smile,
  RefreshCcw,
  ArrowRight,
  Paperclip,
  Loader2,
  ChevronDown,
} from "lucide-react";
import { ParticleButton } from "./ParticleButton";
import { ParticleLoader } from "./ParticleLoader";
import { RewardOverlay } from "./RewardOverlay";
import EmojiPicker, { Theme as EmojiTheme } from "emoji-picker-react";
import { DataSphere } from "./DataSphere";
import { useChatFlow, ExecutionLog } from "@/hooks/useChatFlow";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { useAuthStore } from "@/store/authStore";
import { useAgentRouter } from "@/hooks/useAgentRouter";
import { AgentRouteMapping } from "@/lib/api/publicChat";
import { useChat } from "@/contexts/ChatContext";
import { Button } from "@/components/ui/Button";

interface ChatMessage {
  id: string;
  role: "user" | "agent";
  content: string;
  timestamp: Date;
  options?: string[];
  blocks?: any[];
  delay?: number;
  data?: any;
  type?: string;
  imageUrl?: string;
  persona_name?: string;
  persona_avatar?: string;
  persona_description?: string;
  origin_node_id?: string;
}

// Common markdown components styling for the chat bubbles
const MarkdownComponents = {
  p: ({ node, ...props }: any) => <p className="mb-2 last:mb-0" {...props} />,
  a: ({ node, ...props }: any) => (
    <a
      className="underline font-medium hover:text-primary transition-colors"
      target="_blank"
      rel="noreferrer"
      {...props}
    />
  ),
  ul: ({ node, ...props }: any) => (
    <ul className="list-disc ml-4 mb-2 space-y-1" {...props} />
  ),
  ol: ({ node, ...props }: any) => (
    <ol className="list-decimal ml-4 mb-2 space-y-1" {...props} />
  ),
  li: ({ node, ...props }: any) => <li className="" {...props} />,
  strong: ({ node, ...props }: any) => (
    <strong className="font-bold" {...props} />
  ),
  em: ({ node, ...props }: any) => <em className="italic" {...props} />,
  code: ({ inline, className, children, ...props }: any) => {
    return inline ? (
      <code
        className="bg-muted px-1 py-0.5 rounded text-sm"
        {...props}
      >
        {children}
      </code>
    ) : (
      <pre className="bg-muted p-2 rounded text-sm mb-2 overflow-x-auto">
        <code {...props}>{children}</code>
      </pre>
    );
  },
};

// Helper to render message content (blocks or string)
const renderOneBlock = (
  block: any,
  index: number,
  options: {
    onImageClick?: (url: string) => void;
  } = {},
) => {
  const {
    onImageClick,
  } = options;

  // Bloco 7 do trim (AI9-014): os shortcodes `[asset:XXX]` eram resolvidos contra
  // `OperationAsset` e renderizados como `MediaPreviewCard`. A base de assets saiu
  // com o `Operation`; o bloco de texto continua renderizando normalmente.
  if (block.type === "text") {
    return (
      <div key={index} className="flex flex-col gap-2">
        {block.content?.trim() && (
          <div className="break-words">
            <ReactMarkdown
              remarkPlugins={[remarkGfm]}
              components={MarkdownComponents}
            >
              {block.content}
            </ReactMarkdown>
          </div>
        )}
      </div>
    );
  }
  return null;
};

interface RenderMessageOptions {
  onImageClick?: (url: string) => void;
}

const renderMessageContent = (
  msg: ChatMessage,
  options: RenderMessageOptions = {},
) => {
  const {
    onImageClick,
  } = options;
  const isAgent = msg.role === "agent";

  // Image message: show thumbnail with lightbox
  if (msg.type === "image" && msg.imageUrl) {
    return (
      <div className="flex flex-col gap-1.5">
        <img
          src={msg.imageUrl}
          alt="Imagem enviada"
          className="max-w-[180px] max-h-[180px] rounded-md object-cover cursor-pointer hover:opacity-90 transition-opacity"
          onClick={() => onImageClick?.(msg.imageUrl!)}
        />
        {msg.content && msg.content !== "[Imagem enviada]" && (
          <div className="break-words text-sm opacity-80">{msg.content}</div>
        )}
      </div>
    );
  }

  if (msg.blocks && msg.blocks.length > 0) {
    return (
      <div className="flex flex-col gap-1">
        {msg.blocks.map((block: any, index: number) => {
          return renderOneBlock(block, index, {
            onImageClick,
          });
        })}
      </div>
    );
  }

  // Ensure content is always a string for ReactMarkdown
  let textContent =
    typeof msg.content === "string"
      ? msg.content
      : msg.content != null
        ? String(msg.content)
        : "";

  return (
    <div className="flex flex-col gap-2">
      {textContent.trim() && (
        <div className="break-words">
          <ReactMarkdown
            remarkPlugins={[remarkGfm]}
            components={MarkdownComponents}
          >
            {textContent}
          </ReactMarkdown>
        </div>
      )}

    </div>
  );
};

// Fallback quando o flow não declara persona — o agente da casa é o
// Assistente Safegold.
const DEFAULT_PERSONA = {
  name: "Assistente Safegold",
  // **A marca, e NAO a foto de uma pessoa.**
  //
  // Isto apontava para `/images/team/vini.webp` — uma das fotos do time do ai9
  // que vieram na base (`public/images/team/`, seis pessoas reais). O widget a
  // exibia como "Assistente Safegold" sempre que a persona do fluxo ainda nao
  // tivesse chegado, o que num produto que vai a cliente e pior do que um
  // defeito de tela: apresenta a foto de alguem como se fosse o assistente
  // deste sistema.
  //
  // A pasta `team/` foi removida junto — era conteudo do ai9 viajando no bundle
  // do cliente, com uma unica referencia em todo o codigo: esta linha.
  avatar: "/images/brand/safegold-icon-192.png",
  role: "Guia do Safegold",
};

interface AIChatWidgetProps {
  isOpen: boolean;
  onClose: () => void;
  sessionId?: string;
  flowId?: string;
  initialMessage?: string;
  /** Intent silencioso enviado como mensagem do usuário ao iniciar (ex: troca de plano) */
  pendingIntent?: string;
  /**
   * Bloco 8 do trim (AI9-007): o valor "support" saiu. Ele apontava para o chat
   * público de captação (AI9-006, removido no Bloco 6) e nenhum dos quatro call
   * sites do widget o usava. Sobrou o modo do assistente interno.
   */
  mode?: "flow";
  embedded?: boolean;
  className?: string;
  defaultMinimized?: boolean;
  onLogsChange?: (logs: ExecutionLog[]) => void;
  /** When true, widget is anchored in a sidebar (no floating behavior) */
  anchored?: boolean;
  /** When true, widget is fullscreen (mobile mode) */
  fullscreen?: boolean;
  /** Live preview overrides for the builder page */
  previewPersona?: { name?: string; avatar?: string; description?: string };
}

export function AIChatWidget({
  isOpen,
  onClose,
  sessionId: initialSessionId,
  flowId: initialFlowId,
  initialMessage,
  pendingIntent,
  mode = "flow",
  defaultMinimized = false,
  anchored = false,
  fullscreen = false,
  ...props
}: AIChatWidgetProps) {
  /* Sanitize sessionId to ensure it's a string or null */
  const sanitizedInitialSessionId =
    typeof initialSessionId === "string" ? initialSessionId : null;
  const sanitizedInitialFlowId =
    initialFlowId !== undefined && initialFlowId !== null
      ? String(initialFlowId)
      : null;
  const [message, setMessage] = useState("");
  const [sessionId, setSessionId] = useState<string | null>(
    sanitizedInitialSessionId,
  );
  const [activeFlowId, setActiveFlowId] = useState<string | null>(
    sanitizedInitialFlowId,
  );
  const [showHandoffBanner, setShowHandoffBanner] = useState(false);

  const hasInitialized = useRef(false);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const typingTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  const [isTyping, setIsTyping] = useState(false);
  // Bloco 8 do trim: `isSending` acompanhava o `sendMutation` do "support
  // mode", que saiu. O envio pelo fluxo é imediato e o feedback de espera é o
  // `isTyping` (vindo de `isFlowTyping`); o upload de imagem tem `isUploading`.
  const [showEmoji, setShowEmoji] = useState(false);
  const [showAvatarPreview, setShowAvatarPreview] = useState(false);
  const [showReward, setShowReward] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [previewImageUrl, setPreviewImageUrl] = useState<string | null>(null);
  const [pendingImage, setPendingImage] = useState<File | null>(null);
  const [pendingImagePreview, setPendingImagePreview] = useState<string | null>(
    null,
  );
  const [isDragging, setIsDragging] = useState(false);

  // Mobile keyboard state for fullscreen mode
  const [isKeyboardOpen, setIsKeyboardOpen] = useState(false);
  const [viewportHeight, setViewportHeight] = useState<number | null>(null);
  const fullscreenContainerRef = useRef<HTMLDivElement>(null);

  const isAgentTyping = isTyping;

  const lastProcessedNodeId = useRef<string | null>(null);

  const handleCloseReward = () => setShowReward(false);
  const handleApplyReward = () => setShowReward(false);

  const {
    messages: flowMessages,
    sendMessage: sendFlowMessage,
    sendImage: sendFlowImage,
    initSession: initFlowSession,
    resetSession: resetFlowSession,
    isTyping: isFlowTyping,
    sessionId: currentFlowSessionId,
    logs: flowLogs,
    persona: flowPersona,
    currentNode,
  } = useChatFlow(sessionId, activeFlowId);

  const [prevSanitizedInitialFlowId, setPrevSanitizedInitialFlowId] = useState<string | null>(sanitizedInitialFlowId);

  // Sync com currentAgentId do ChatContext (ex: troca de agente pelo roteador)
  if (sanitizedInitialFlowId !== prevSanitizedInitialFlowId) {
    setPrevSanitizedInitialFlowId(sanitizedInitialFlowId);
    if (sanitizedInitialFlowId && sanitizedInitialFlowId !== activeFlowId) {
      setActiveFlowId(sanitizedInitialFlowId);
      hasInitialized.current = false;
    }
  }

  // Agent Routing Logic
  // Bloco 7 do trim (AI9-014): o segundo argumento era `hasOperation`, lido do
  // `operation_id` da sessão. Sem `Operation`, o roteador de agente decide só
  // pelo fluxo ativo.
  const { matchingAgent, shouldOverride } = useAgentRouter(
    activeFlowId ? Number(activeFlowId) : undefined,
  );

  // Bloco 8 do trim (AI9-007): aqui havia um `useQuery(["chat-session-status"])`
  // chamando `publicChatApi.getSession()` — `/api/v1/public/chat/session`, que
  // saiu no Bloco 6 com o AI9-006 e responde 404 desde então. O resultado
  // (`sessionData`) nunca era lido por ninguém: era uma chamada 404 a cada
  // abertura do widget, silenciosa. A sessão vem do `useChatFlow`.

  // Process Routing match
  useEffect(() => {
    if (shouldOverride && matchingAgent) {
      handleSwitchAgent(matchingAgent.id);
    } else if (matchingAgent && !shouldOverride) {
      // Suggest via banner
      setShowHandoffBanner(true);
    } else {
      setShowHandoffBanner(false);
    }
  }, [matchingAgent, shouldOverride]);

  const handleSwitchAgent = (flowId: string | number) => {
    setActiveFlowId(String(flowId));
    setShowHandoffBanner(false);
    hasInitialized.current = false; // Allow re-initialization for the new flow
  };

  // Handle Redirect/Actions from Flow
  useEffect(() => {
    if (mode !== "flow" || !currentNode || !currentNode.id) return;
    if (currentNode.id === lastProcessedNodeId.current) return;

    lastProcessedNodeId.current = currentNode.id;

    // Process Auth First (Auto-Login)
    if (currentNode.auth) {
      try {
        useAuthStore.getState().setAuth(currentNode.auth.token,
          {
            id: "visitor-" + Date.now(),
            name: currentNode.auth.user_name,
            email: currentNode.auth.user_email,
            user_type: "visitor",
            user_type_slug: "visitor",
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          } as any,
        );

        // Dispatch event for other components to update
        window.dispatchEvent(new Event("auth-change"));
      } catch (e) {
        console.error("Auto-login failed", e);
      }
    }

    // Process Action (Navigate or Scroll)
    // 'auth' action also navigates after authentication is complete
    if (
      (currentNode.action === "navigate" || currentNode.action === "auth") &&
      currentNode.url
    ) {
      if (currentNode.target === "_blank") {
        // Give a slight delay if we just authenticated to ensure tokens are saved properly across tabs if needed
        setTimeout(
          () => window.open(currentNode.url, "_blank"),
          currentNode.auth ? 500 : 0,
        );
      } else {
        setTimeout(
          () => (window.location.href = currentNode.url || "/"),
          currentNode.auth ? 500 : 0,
        );
      }
    } else if (currentNode.action === "scroll_to" && currentNode.target) {
      const element = document.querySelector(currentNode.target);
      if (element) {
        element.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }
  }, [currentNode, mode]);

  // Handle Delays (Effect) - REMOVED: Now handled by SequentialMessageBubble
  // useEffect(() => { ... }, ...);

  // Sync logs back to parent if callback provided
  useEffect(() => {
    if (props.onLogsChange) {
      props.onLogsChange(flowLogs);
    }
  }, [flowLogs, props.onLogsChange]);

  // Sync sessionId back to component state when flow session inits
  useEffect(() => {
    if (currentFlowSessionId && currentFlowSessionId !== sessionId) {
      setSessionId(currentFlowSessionId);
    }
  }, [currentFlowSessionId, sessionId]);


  // Init Flow Session — skip if messages were restored from sessionStorage
  useEffect(() => {
    if (
      isOpen &&
      mode === "flow" &&
      flowMessages.length === 0 &&
      !hasInitialized.current
    ) {
      hasInitialized.current = true;
      initFlowSession();
    } else if (flowMessages.length > 0) {
      // Messages restored from sessionStorage, mark as initialized
      hasInitialized.current = true;
    }
  }, [isOpen, mode, flowMessages.length, initFlowSession]);

  // Envia pendingIntent como mensagem do usuário após o flow inicializar
  const pendingIntentSent = useRef(false);
  useEffect(() => {
    if (
      pendingIntent &&
      hasInitialized.current &&
      !pendingIntentSent.current &&
      mode === "flow"
    ) {
      pendingIntentSent.current = true;
      // Aguarda o flow inicializar antes de enviar
      const timer = setTimeout(() => {
        sendFlowMessage(pendingIntent);
      }, 1500);
      return () => clearTimeout(timer);
    }
  }, [pendingIntent, flowMessages.length, mode]);

  // ---------------------------------------------------------------------------
  // Bloco 8 do trim (AI9-007, DEC-13.2) — o "support mode" saiu inteiro daqui.
  //
  // O que morava neste trecho: um `useQuery(["chat-messages"])` batendo em
  // `publicChatApi.getMessages()` (`/api/v1/public/chat/messages`), um
  // `useChannel("PublicChatChannel")` e a montagem de `supportMessages` a partir
  // do que voltasse de lá.
  //
  // Estava TODO morto, por três motivos somados:
  //   1. o endpoint saiu no Bloco 6 com o AI9-006 (era o chat público de
  //      captação, que gravava `LeadMessage`) e respondia **404**;
  //   2. `PublicChatChannel` não existe em `app/channels/` — saiu junto;
  //   3. os quatro call sites do widget (`Layout`, `ChatBuilderPage` e os dois
  //      do `PublicSplitLayout`) passam `mode="flow"`. Nenhum passa "support".
  //
  // A única fonte de mensagens é o fluxo autenticado (`useChatFlow` →
  // `/chat/{session,input,upload}`), que é o caminho vivo do assistente interno.
  // ---------------------------------------------------------------------------
  const messages = flowMessages;


  const currentPersona = useMemo(() => {
    if (props.previewPersona) {
      return {
        name: props.previewPersona.name || DEFAULT_PERSONA.name,
        avatar: props.previewPersona.avatar || DEFAULT_PERSONA.avatar,
        role: props.previewPersona.description || DEFAULT_PERSONA.role,
      };
    }
    if (mode === "flow" && flowPersona) {
      return {
        // `avatar` do fluxo pode vir vazio — e vem, no `assistente-console`
        // semeado. Sem este `||`, a persona certa aparecia SEM imagem nenhuma.
        name: flowPersona.name || DEFAULT_PERSONA.name,
        avatar: flowPersona.avatar || DEFAULT_PERSONA.avatar,
        role: flowPersona.description || "Assistente Virtual",
      };
    }

    // **Enquanto a persona do fluxo nao chegou, o fallback e a MARCA.**
    //
    // Ele aparece mais do que parece: a persona vem de uma chamada, e qualquer
    // demora ou falha (o 429 de 27/08 fazia isso o tempo todo) deixa o widget
    // aqui. Foi o que produziu "abre um agente que nao tem nada a ver, e so o
    // reload conserta" — o reload nao consertava nada, so dava tempo da busca
    // terminar.
    //
    // Com a marca no lugar da foto, o estado intermediario deixa de afirmar uma
    // identidade falsa: mostra o assistente do sistema, generico, ate saber
    // qual persona e.
    return DEFAULT_PERSONA;
  }, [mode, flowPersona, props.previewPersona]);

  // Publica persona ativa no ChatContext para MobileChatBar e outros consumidores
  const { setActivePersona } = useChat();
  useEffect(() => {
    if (currentPersona) {
      setActivePersona({
        name: currentPersona.name,
        avatar: currentPersona.avatar,
        role: currentPersona.role,
      });
    }
  }, [
    currentPersona.name,
    currentPersona.avatar,
    currentPersona.role,
    setActivePersona,
  ]);

  // Agent persona details state for modal
  const [selectedPersona, setSelectedPersona] = useState<{
    name: string;
    avatar: string;
    description?: string;
  } | null>(null);

  const handleAvatarClick = useCallback(
    (msg: ChatMessage) => {
      setSelectedPersona({
        name: msg.persona_name || currentPersona.name,
        avatar: msg.persona_avatar || currentPersona.avatar,
        description: msg.persona_description || currentPersona.role,
      });
    },
    [currentPersona],
  );

  // O "está digitando" vem do fluxo — única fonte desde o Bloco 8.
  useEffect(() => {
    setIsTyping(isFlowTyping);
  }, [isFlowTyping]);

  // Bloco 8 do trim (AI9-007): aqui vivia o `sendMutation` do "support mode" —
  // `publicChatApi.getSession()` + `publicChatApi.sendMessage()`, os dois 404
  // desde o Bloco 6. Envio de mensagem é `sendFlowMessage` (ver `handleSend`).

  // Timeout for typing (safety fallback).
  // Bloco 8: a guarda era `mode === "support"`, que nunca mais é verdade — o
  // fallback ficava desarmado. Agora vale para a única conversa que existe.
  useEffect(() => {
    if (isTyping) {
      // Clear existing
      if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current);

      // Disable typing after 45 seconds if no response
      typingTimeoutRef.current = setTimeout(() => {
        setIsTyping(false);
      }, 45000);
    }

    return () => {
      if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current);
    };
  }, [isTyping]);

  // Reset typing when a new agent message arrives
  useEffect(() => {
    if (messages.length > 0) {
      const lastMsg = messages[messages.length - 1];
      if (lastMsg.role === "agent") {
        setIsTyping(false);
      }
    }
  }, [messages]);

  // Scroll to bottom when new messages arrive
  const lastMessageId =
    messages.length > 0 ? messages[messages.length - 1].id : null;

  useEffect(() => {
    if (messagesEndRef.current) {
      const container = messagesEndRef.current.closest(
        ".overflow-y-auto",
      ) as HTMLElement;
      if (container) {
        container.scrollTo({ top: container.scrollHeight, behavior: "smooth" });
      }
    }
  }, [lastMessageId, isTyping, isOpen]);

  useEffect(() => {
    if (isOpen) {
      setTimeout(() => inputRef.current?.focus({ preventScroll: true }), 100);
    }
  }, [isOpen]);

  const handleSend = useCallback(
    (optionText?: string, originNodeId?: string) => {
      // If there's a pending image, send it with the caption
      if (pendingImage && sendFlowImage) {
        setIsUploading(true);
        sendFlowImage(pendingImage, message.trim() || undefined).finally(() =>
          setIsUploading(false),
        );
        setMessage("");
        if (pendingImagePreview) URL.revokeObjectURL(pendingImagePreview);
        setPendingImage(null);
        setPendingImagePreview(null);
        return;
      }

      const textToSend = optionText || message.trim();
      if (!textToSend) return;

      sendFlowMessage(textToSend, false, originNodeId);
      setMessage("");
    },
    [
      message,
      sendFlowMessage,
      pendingImage,
      sendFlowImage,
      pendingImagePreview,
    ],
  );

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  /** Maximum allowed file size (5MB) */
  const MAX_FILE_SIZE = 5 * 1024 * 1024;
  const ALLOWED_MIMES = ["image/jpeg", "image/png", "image/webp"];

  /** Validate and stage a file for pre-send preview */
  const stageFile = useCallback((file: File) => {
    if (!ALLOWED_MIMES.includes(file.type)) {
      alert("Tipo de arquivo não suportado. Use JPEG, PNG ou WebP.");
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      alert("Arquivo excede o limite de 5MB.");
      return;
    }
    // Stage for preview — user can add caption before sending
    setPendingImage(file);
    setPendingImagePreview(URL.createObjectURL(file));
  }, []);

  /** Handle file selection from the hidden input */
  const handleFileChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;
      e.target.value = "";
      stageFile(file);
    },
    [stageFile],
  );

  /** Clear pending image preview */
  const clearPendingImage = useCallback(() => {
    if (pendingImagePreview) URL.revokeObjectURL(pendingImagePreview);
    setPendingImage(null);
    setPendingImagePreview(null);
  }, [pendingImagePreview]);

  /** Send the pending image with optional caption */
  const sendPendingImage = useCallback(() => {
    if (!pendingImage || !sendFlowImage) return;
    setIsUploading(true);
    sendFlowImage(pendingImage, message.trim() || undefined).finally(() =>
      setIsUploading(false),
    );
    setMessage("");
    clearPendingImage();
  }, [pendingImage, sendFlowImage, message, clearPendingImage]);

  /** Drag and drop handlers */
  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
  }, []);
  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
  }, []);
  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
      setIsDragging(false);
      const file = e.dataTransfer.files?.[0];
      if (file) stageFile(file);
    },
    [stageFile],
  );

  // Handle iOS keyboard with VisualViewport API (para fullscreen mode)
  // Unificado em um único handler para evitar race conditions
  useEffect(() => {
    if (!fullscreen) return;

    const viewport = window.visualViewport;
    if (!viewport) return;

    let debounceTimer: ReturnType<typeof setTimeout> | null = null;

    const handleViewportChange = () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        const currentHeight = viewport.height;
        const currentWidth = viewport.width;
        const windowHeight = window.innerHeight;
        const offsetTop = viewport.offsetTop;

        // Keyboard é detectado quando viewport é significativamente menor que janela
        const keyboardHeight = windowHeight - currentHeight - offsetTop;
        const keyboardOpen = keyboardHeight > 150;

        setIsKeyboardOpen(keyboardOpen);
        setViewportHeight(currentHeight);

        // Atualiza container style com posição e tamanho corretos
        setContainerStyle({
          top: `${Math.max(0, offsetTop)}px`,
          bottom: `${Math.max(0, keyboardHeight)}px`,
          width: `${currentWidth}px`,
          maxWidth: "100%",
        });

        // Auto-scroll para última mensagem quando teclado abre
        if (keyboardOpen) {
          setTimeout(() => {
            const container = fullscreenContainerRef.current?.querySelector(
              "[data-messages-area]",
            ) as HTMLElement;
            if (container) {
              container.scrollTo({
                top: container.scrollHeight,
                behavior: "smooth",
              });
            }
          }, 100);
        }
      }, 80); // 80ms debounce — rápido o bastante para parecer fluido
    };

    viewport.addEventListener("resize", handleViewportChange);
    viewport.addEventListener("scroll", handleViewportChange);
    handleViewportChange(); // Check inicial

    return () => {
      viewport.removeEventListener("resize", handleViewportChange);
      viewport.removeEventListener("scroll", handleViewportChange);
      if (debounceTimer) clearTimeout(debounceTimer);
    };
  }, [fullscreen]);

  // Handle input focus - scroll to last message (for fullscreen mode)
  const handleInputFocus = useCallback(() => {
    if (!fullscreen) return;
    // Small delay to let keyboard animation start
    setTimeout(() => {
      if (messagesEndRef.current) {
        const container = messagesEndRef.current.closest(
          ".overflow-y-auto",
        ) as HTMLElement;
        if (container) {
          container.scrollTo({
            top: container.scrollHeight,
            behavior: "smooth",
          });
        }
      }
    }, 300);
  }, [fullscreen]);

  const displayMessages = messages;

  const [isMinimized, setIsMinimized] = useState(defaultMinimized);

  // Fullscreen Mode: Mobile fullscreen chat (like WhatsApp)
  // Use VisualViewport API for proper iOS keyboard handling
  const [containerStyle, setContainerStyle] = useState<React.CSSProperties>({
    top: 0,
    bottom: 0,
  });

  // 5C: Body scroll lock removido daqui — agora fica no PublicSplitLayout
  // (AIChatWidget recebe isOpen=true sempre, causando bloqueio permanente)

  // Segundo handler removido — unificado acima
  // (anteriormente havia dois useEffects competindo para VisualViewport)

  const handleMinimize = () => {
    if (mode === "flow" || mode === "support") {
      // Allow minimizing in embedded/flow modes
      setIsMinimized(!isMinimized);
      return;
    }
    onClose();
  };

  // Effect to handle initial minimize state if needed found in props?
  // For now, let's just use the internal state.

  if (!isOpen) return null;

  // Embedded logic: simpler wrapper
  if (props.embedded) {
    return (
      <div
        className={`
          flex flex-col bg-card border border-border/50 shadow-e3 rounded-lg overflow-hidden transition-all duration-300
          ${isMinimized ? "h-[70px]" : "h-[600px] max-h-[80vh]"}
          w-[380px]
          ${props.className || ""}
        `}
      >
        {/* Header */}
        <div
          className="flex items-center justify-between px-4 py-3 border-b border-border/40 bg-card/50 backdrop-blur-sm shadow-e1 z-10 cursor-pointer"
          onClick={() => setIsMinimized(!isMinimized)}
        >
          <div className="flex items-center gap-3">
            {/* Avatar */}
            <div className="relative group">
              <div className="h-10 w-10 rounded-full overflow-hidden border border-border">
                <img
                  key={currentPersona.avatar}
                  src={currentPersona.avatar}
                  alt={currentPersona.name}
                  className="h-full w-full object-cover animate-in fade-in duration-500"
                />
              </div>
              <div className="absolute bottom-0 right-0 h-3 w-3 rounded-full bg-success border-2 border-background"></div>
            </div>

            <div className="flex flex-col">
              <span
                key={currentPersona.name}
                className="font-bold text-sm text-foreground leading-tight flex items-center gap-1 animate-in fade-in duration-500"
              >
                {currentPersona.name}
              </span>
              <span className="text-xs text-muted-foreground animate-in fade-in duration-500">
                {currentPersona.role}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {mode === "flow" && (
              <Button
                variant="ghost"
                size="icon"
                onClick={(e) => {
                  e.stopPropagation();
                  resetFlowSession();
                }}
                className="h-8 w-8 rounded-full"
                title="Reiniciar conversa"
                aria-label="Reiniciar conversa"
              >
                <RefreshCcw className="h-4 w-4" />
              </Button>
            )}
            <Button
              variant="ghost"
              size="icon"
              onClick={(e) => {
                e.stopPropagation();
                setIsMinimized(!isMinimized);
              }}
              className="h-8 w-8 rounded-full"
              aria-label={isMinimized ? "Expandir conversa" : "Minimizar conversa"}
            >
              {isMinimized ? (
                <Minus className="h-5 w-5 rotate-45" />
              ) : (
                <Minus className="h-5 w-5" />
              )}
            </Button>
          </div>
        </div>

        {/* Body (Hidden if minimized) */}
        <div
          className={`flex flex-col flex-1 overflow-hidden transition-opacity duration-300 ${isMinimized ? "opacity-0 pointer-events-none" : "opacity-100"}`}
        >
          {/* Handoff Banner */}
          {showHandoffBanner && matchingAgent && (
            <div className="bg-primary/10 border-b border-primary/20 px-4 py-3 flex items-center justify-between gap-3 animate-in slide-in-from-top duration-300">
              <div className="flex items-center gap-3">
                <div className="h-8 w-8 rounded-full overflow-hidden border border-primary/20 bg-background shrink-0">
                  <img
                    src={
                      matchingAgent.persona_avatar ||
                      "/images/brand/safegold-icon-192.png"
                    }
                    alt={matchingAgent.persona_name}
                    className="h-full w-full object-cover"
                  />
                </div>
                <div className="flex flex-col">
                  <span className="text-xs font-bold text-foreground leading-none">
                    Agente Especializado
                  </span>
                  <span className="text-xs text-muted-foreground leading-tight">
                    {matchingAgent.persona_name} pode ajudar melhor nesta
                    página.
                  </span>
                </div>
              </div>
              <Button
                variant="primary"
                size="sm"
                onClick={() => handleSwitchAgent(matchingAgent.id)}
                className="whitespace-nowrap"
              >
                Conectar
              </Button>
            </div>
          )}

          {/* Messages Area */}
          <div className="flex-1 overflow-y-auto p-4 space-y-2 bg-background/50 scrollbar-thin scrollbar-thumb-border">
            {displayMessages.length === 0 && (
              <div className="flex flex-col items-center justify-center h-full text-center p-6 opacity-60">
                <div
                  className="h-24 w-24 rounded-full overflow-hidden mb-4 border-4 border-background shadow-e2 cursor-pointer hover:scale-105 transition-transform"
                  onClick={() =>
                    setSelectedPersona({
                      name: currentPersona.name,
                      avatar: currentPersona.avatar,
                      description: currentPersona.role,
                    })
                  }
                >
                  <img
                    src={currentPersona.avatar}
                    alt={currentPersona.name}
                    className="h-full w-full object-cover"
                  />
                </div>
                <h3 className="text-lg font-bold text-foreground">
                  {currentPersona.name}
                </h3>
                <p className="text-sm text-muted-foreground">Safegold</p>
                <p className="text-sm text-muted-foreground mt-2">
                  Diga Oi! 👋
                </p>
              </div>
            )}

            {displayMessages.map((msg, idx) => {
              const isUser = msg.role === "user";
              const nextIsSame = displayMessages[idx + 1]?.role === msg.role;

              return (
                <div
                  key={msg.id}
                  className={`flex w-full ${isUser ? "justify-end" : "justify-start"}`}
                >
                  {!isUser && (
                    <div
                      className={`mr-2 flex flex-col justify-end ${nextIsSame ? "invisible" : ""}`}
                    >
                      <div
                        className="h-7 w-7 rounded-full overflow-hidden border border-border cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all"
                        onClick={() => handleAvatarClick(msg)}
                      >
                        <img
                          src={msg.persona_avatar || currentPersona.avatar}
                          alt={msg.persona_name || currentPersona.name}
                          className="h-full w-full object-cover"
                        />
                      </div>
                    </div>
                  )}

                  <div
                    className={`
                         chat-bubble relative max-w-[75%] px-4 py-2.5 text-sm leading-snug break-words shadow-e1
                         ${
                           isUser
                             ? "bg-primary text-primary-foreground rounded-lg rounded-tr-md"
                             : "bg-muted text-foreground rounded-lg rounded-tl-md border border-border/50"
                         }
                         ${nextIsSame ? (isUser ? "mb-1" : "mb-1") : "mb-4"} 
                       `}
                  >
                    {renderMessageContent(msg, {
                      onImageClick: (url) => setPreviewImageUrl(url),
                    })}
                  </div>
                </div>
              );
            })}

            {isAgentTyping && (
              <div className="flex w-full justify-start mb-4 animate-in fade-in zoom-in duration-300">
                <div className="mr-2 flex flex-col justify-end">
                  <div className="h-7 w-7 rounded-full overflow-hidden border border-border">
                    <img
                      src={currentPersona.avatar}
                      alt={currentPersona.name}
                      className="h-full w-full object-cover"
                    />
                  </div>
                </div>
                <div className="bg-muted text-foreground rounded-lg rounded-tl-md border border-border/50 px-4 py-3 shadow-e1 flex items-center justify-center min-h-11 min-w-16">
                  <ParticleLoader />
                </div>
              </div>
            )}

            <div ref={messagesEndRef} />
          </div>

          {/* Footer / Input Area */}
          <div className="p-3 bg-card/50 backdrop-blur-sm border-t border-border/40 z-10">
            {/* Image Preview inside Footer */}
            {pendingImagePreview && (
              <div className="mb-2 relative inline-block animate-in zoom-in-95 duration-200">
                <img
                  src={pendingImagePreview}
                  alt="Preview"
                  className="h-12 w-12 rounded-lg object-cover border border-border/50"
                />
                <Button
                  variant="destructive"
                  size="icon"
                  onClick={clearPendingImage}
                  className="absolute -top-1.5 -right-1.5 h-5 w-5 rounded-full"
                  aria-label="Remover imagem"
                >
                  <X className="h-3 w-3" />
                </Button>
              </div>
            )}
            <div className="flex items-center gap-2">
              <Button
                variant="ghost"
                size="icon"
                onClick={() => fileInputRef.current?.click()}
                className="h-9 w-9 rounded-full"
                title="Enviar imagem"
                aria-label="Enviar imagem"
                disabled={isUploading}
              >
                <Paperclip className="h-5 w-5" />
              </Button>
              <div className="flex-1 relative">
                <input
                  ref={inputRef}
                  type="text"
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  onKeyDown={handleKeyDown}
                  placeholder="Aa"
                  className="w-full bg-muted/50 text-foreground placeholder-muted-foreground px-4 py-2 rounded-full outline-none focus:ring-1 focus:ring-primary/50 transition-all border border-transparent focus:border-primary/20 pr-10"
                />
              </div>

              <div className="relative">
                <ParticleButton
                  onClick={() => handleSend()}
                  isLoading={isUploading}
                  inputValue={message}
                  className={`w-10 h-10 shadow-e2 transition-opacity duration-300`}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Common hidden file input — rendered via portal to avoid scroll jumps
  const HiddenFileInput = createPortal(
    <input
      key="global-file-input"
      type="file"
      ref={fileInputRef}
      onChange={handleFileChange}
      accept="image/*"
      tabIndex={-1}
      aria-hidden="true"
      style={{
        position: "fixed",
        top: 0,
        left: 0,
        width: 1,
        height: 1,
        opacity: 0,
        overflow: "hidden",
        pointerEvents: "none",
        zIndex: -1,
      }}
    />,
    document.body,
  );

  // (Moved hooks to the top of component)

  if (fullscreen) {
    return (
      <div
        ref={fullscreenContainerRef}
        className={`
          fixed inset-x-0
          flex flex-col bg-background
          w-full max-w-[100vw] overflow-x-hidden overflow-hidden
          ${props.className || ""}
          ${isDragging ? "ring-2 ring-primary/50 ring-inset" : ""}
        `}
        style={containerStyle}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        {HiddenFileInput}
        {/* Header - Fixed at top */}
        <div className="flex items-center gap-3 px-4 py-2 bg-card border-b border-border/30 shrink-0">
          <div className="relative" onClick={() => setShowAvatarPreview(true)}>
            <div className="h-9 w-9 rounded-full overflow-hidden border-2 border-primary/20 shadow-e2">
              <img
                src={currentPersona.avatar}
                alt={currentPersona.name}
                className="h-full w-full object-cover"
              />
            </div>
            <div className="absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full bg-success border-2 border-background"></div>
          </div>

          <div className="flex flex-col flex-1 min-w-0">
            <span className="font-bold text-sm text-foreground leading-tight truncate">
              {currentPersona.name}
            </span>
            <span className="text-xs text-muted-foreground truncate">
              {currentPersona.role}
            </span>
          </div>

          <div className="flex items-center gap-1">
            {mode === "flow" && (
              <Button
                variant="ghost"
                size="icon"
                onClick={() => resetFlowSession()}
                className="h-8 w-8 rounded-full"
                title="Reiniciar conversa"
                aria-label="Reiniciar conversa"
              >
                <RefreshCcw className="h-4 w-4" />
              </Button>
            )}
            <Button
              variant="ghost"
              size="icon"
              onClick={onClose}
              className="h-8 w-8 rounded-full"
              aria-label="Fechar conversa"
            >
              <X className="h-5 w-5" />
            </Button>
          </div>
        </div>

        {/* Messages Area - flex-1 to take remaining space */}
        <div
          data-messages-area
          className="flex-1 overflow-y-auto overflow-x-hidden px-4 py-3 space-y-3 bg-background"
          style={{ WebkitOverflowScrolling: "touch" }}
        >
          {displayMessages.length === 0 && (
            <div className="flex flex-col items-center justify-center h-full text-center p-8">
              <div
                className="h-20 w-20 rounded-full overflow-hidden mb-4 border-4 border-primary/10 shadow-e3 cursor-pointer hover:scale-105 transition-transform"
                onClick={() =>
                  setSelectedPersona({
                    name: currentPersona.name,
                    avatar: currentPersona.avatar,
                    description: currentPersona.role,
                  })
                }
              >
                <img
                  src={currentPersona.avatar}
                  alt={currentPersona.name}
                  className="h-full w-full object-cover"
                />
              </div>
              <h3 className="text-xl font-bold text-foreground mb-1">
                {currentPersona.name}
              </h3>
              <p className="text-sm text-muted-foreground mb-4">
                {currentPersona.role}
              </p>
              <p className="text-sm text-foreground/80 max-w-[280px]">
                Olá! Como posso te ajudar hoje?
              </p>
            </div>
          )}

          {displayMessages.map((msg, idx) => {
            const isUser = msg.role === "user";
            const nextIsSame = displayMessages[idx + 1]?.role === msg.role;

            return (
              <div
                key={msg.id}
                className={`flex w-full flex-col ${isUser ? "items-end" : "items-start"}`}
              >
                <div
                  className={`flex w-full ${isUser ? "justify-end" : "justify-start"}`}
                >
                  {!isUser && (
                    <div
                      className={`mr-2 flex flex-col justify-end ${nextIsSame ? "invisible" : ""}`}
                    >
                      <div
                        className="h-7 w-7 rounded-full overflow-hidden border border-border cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all"
                        onClick={() => handleAvatarClick(msg)}
                      >
                        <img
                          src={msg.persona_avatar || currentPersona.avatar}
                          alt={msg.persona_name || currentPersona.name}
                          className="h-full w-full object-cover"
                        />
                      </div>
                    </div>
                  )}

                  <div
                    className={`
                      chat-bubble relative max-w-[85%] px-4 py-2.5 text-sm leading-snug break-words shadow-e1
                      ${
                        isUser
                          ? "bg-primary text-primary-foreground rounded-lg rounded-tr-md"
                          : "bg-secondary text-secondary-foreground rounded-lg rounded-tl-md border border-border/50"
                      }
                      ${nextIsSame ? "mb-1" : "mb-2"}
                    `}
                  >
                    {renderMessageContent(msg, {
                      onImageClick: (url) => setPreviewImageUrl(url),
                    })}
                  </div>
                </div>

                {/* Options / Quick Actions */}
                {!isUser && msg.options && msg.options.length > 0 && (
                  <div className="flex flex-wrap gap-2 mt-3 mb-4 ml-9 max-w-[90%]">
                    {msg.options.map((option: any, optIdx) => (
                      <button
                        key={optIdx}
                        type="button"
                        onClick={() =>
                          handleSend(
                            typeof option === "object" ? option.label : option,
                            msg.origin_node_id,
                          )
                        }
                        className="px-4 py-2.5 text-sm font-semibold bg-secondary hover:bg-secondary/80 border border-border/50 text-foreground rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      >
                        {typeof option === "object" ? option.label : option}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            );
          })}

          {/* Typing Indicator */}
          {(isAgentTyping || isUploading) && (
            <div className="flex w-full justify-start mb-4">
              <div className="mr-2 flex flex-col justify-end">
                <div className="h-7 w-7 rounded-full overflow-hidden border border-border">
                  <img
                    src={currentPersona.avatar}
                    alt={currentPersona.name}
                    className="h-full w-full object-cover"
                  />
                </div>
              </div>
              <div className="bg-secondary text-secondary-foreground rounded-lg rounded-tl-md border border-border/50 px-4 py-3 shadow-e1 flex items-center justify-center min-h-11 min-w-16">
                {isUploading ? (
                  <div className="flex items-center gap-2 text-xs text-muted-foreground">
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>Processando...</span>
                  </div>
                ) : (
                  <ParticleLoader />
                )}
              </div>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>

        {/* Pending Image Preview */}
        {pendingImagePreview && (
          <div className="px-3 pt-2 pb-1 border-t border-border/40 bg-card/50 backdrop-blur-sm">
            <div className="relative inline-block">
              <img
                src={pendingImagePreview}
                alt="Preview"
                className="h-16 w-16 rounded-lg object-cover border border-border/50"
              />
              <Button
                variant="destructive"
                size="icon"
                onClick={clearPendingImage}
                className="absolute -top-1.5 -right-1.5 h-5 w-5 rounded-full"
                aria-label="Remover imagem"
              >
                <X className="h-3 w-3" />
              </Button>
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              Adicione uma legenda e envie
            </p>
          </div>
        )}

        {/* Input Area - shrink-0 to stay fixed at bottom */}
        <div className="px-3 py-2 bg-card border-t border-border/30 shrink-0">
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              onClick={() => fileInputRef.current?.click()}
              className="h-9 w-9 rounded-full"
              title="Enviar imagem"
              aria-label="Enviar imagem"
              disabled={isUploading}
            >
              <Paperclip className="h-5 w-5" />
            </Button>

            <div className="flex-1 relative">
              <input
                ref={inputRef}
                type="text"
                inputMode="text"
                enterKeyHint="send"
                autoComplete="off"
                autoCorrect="off"
                autoCapitalize="sentences"
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                onKeyDown={handleKeyDown}
                onFocus={handleInputFocus}
                placeholder="Digite sua mensagem..."
                className="w-full bg-secondary text-foreground placeholder-muted-foreground px-4 py-2 rounded-full outline-none focus:ring-2 focus:ring-primary/30 border border-border/50 pr-10 text-sm"
              />
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setShowEmoji(!showEmoji)}
                className="absolute right-3 top-1/2 -translate-y-1/2 h-8 w-8 rounded-full"
                aria-label="Inserir emoji"
              >
                <Smile className="h-5 w-5" />
              </Button>

              {showEmoji && (
                <div className="absolute bottom-14 right-0 z-tooltip shadow-e3 rounded-md">
                  <div
                    className="fixed inset-0 z-10"
                    onClick={() => setShowEmoji(false)}
                  />
                  <div className="relative z-20">
                    <EmojiPicker
                      onEmojiClick={(emo) => {
                        setMessage((prev) => prev + emo.emoji);
                        setShowEmoji(false);
                        inputRef.current?.focus();
                      }}
                      width={280}
                      height={350}
                      theme={EmojiTheme.AUTO}
                    />
                  </div>
                </div>
              )}
            </div>

            <div className="relative">
              <ParticleButton
                onClick={() => handleSend()}
                isLoading={isUploading}
                inputValue={message}
                className="w-10 h-10 shadow-e2"
              />
            </div>
          </div>
        </div>

        {/* 5B: Barra "Voltar pro site" — visível quando teclado fechado */}
        {!isKeyboardOpen && (
          <button
            type="button"
            onClick={onClose}
            className="
              w-full min-h-10 shrink-0
              flex items-center justify-center gap-2
              bg-muted/30 hover:bg-muted/50
              text-muted-foreground text-sm
              border-t border-border/20
              transition-colors active:bg-muted/70
              focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset
            "
            aria-label="Voltar pro site"
          >
            <ChevronDown className="h-4 w-4" />
            <span>Voltar pro site</span>
          </button>
        )}

        {/* Avatar Preview Modal */}
        {showAvatarPreview &&
          createPortal(
            <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
              <div
                className="absolute inset-0 bg-brand-ink/70 backdrop-blur-sm"
                onClick={() => setShowAvatarPreview(false)}
              />
              <div className="relative z-10 bg-card rounded-lg shadow-e3 p-2 max-w-[280px]">
                <div className="relative rounded-md overflow-hidden aspect-square w-full">
                  <img
                    src={currentPersona.avatar}
                    alt={currentPersona.name}
                    className="w-full h-full object-cover"
                  />
                </div>
                <div className="mt-3 text-center pb-2">
                  <h4 className="font-bold text-sm">{currentPersona.name}</h4>
                  <p className="text-xs text-muted-foreground">
                    {currentPersona.role}
                  </p>
                </div>
                <Button
                  variant="secondary"
                  size="icon"
                  onClick={() => setShowAvatarPreview(false)}
                  className="absolute top-3 right-3 h-8 w-8 rounded-full"
                  aria-label="Fechar"
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
            </div>,
            document.body,
          )}

        {/* Image Lightbox */}
        {previewImageUrl &&
          createPortal(
            <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
              <div
                className="absolute inset-0 bg-brand-ink/70 backdrop-blur-sm"
                onClick={() => setPreviewImageUrl(null)}
              />
              <div className="relative z-10 max-w-[90vw] max-h-[80vh]">
                <img
                  src={previewImageUrl}
                  alt="Preview"
                  className="max-w-full max-h-[80vh] rounded-lg object-contain shadow-e3"
                />
                <Button
                  variant="secondary"
                  size="icon"
                  onClick={() => setPreviewImageUrl(null)}
                  className="absolute top-3 right-3 h-8 w-8 rounded-full"
                  aria-label="Fechar"
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
            </div>,
            document.body,
          )}
      </div>
    );
  }

  // Anchored Mode: Floating window style chat in sidebar
  if (anchored) {
    return (
      <div
        className={`
          flex flex-col h-full bg-card overflow-hidden relative z-10
          rounded-lg border border-border/50 shadow-e3
          ${props.className || ""}
          ${isDragging ? "ring-2 ring-primary/50 ring-inset" : ""}
        `}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        {/* Agent Header - Floating window header */}
        <div className="flex items-center gap-3 px-5 py-4 bg-card border-b border-border/30 rounded-t-2xl">
          <div
            className="relative cursor-pointer"
            onClick={() => setShowAvatarPreview(true)}
          >
            <div className="h-11 w-11 rounded-full overflow-hidden border-2 border-primary/20 shadow-e2">
              <img
                key={currentPersona.avatar}
                src={currentPersona.avatar}
                alt={currentPersona.name}
                className="h-full w-full object-cover"
              />
            </div>
            <div className="absolute -bottom-0.5 -right-0.5 h-3.5 w-3.5 rounded-full bg-success border-2 border-background"></div>
          </div>

          <div className="flex flex-col flex-1 min-w-0">
            <span className="font-bold text-sm text-foreground leading-tight truncate">
              {currentPersona.name}
            </span>
            <span className="text-xs text-muted-foreground truncate">
              {currentPersona.role}
            </span>
          </div>

          {mode === "flow" && (
            <Button
              variant="ghost"
              size="icon"
              onClick={() => resetFlowSession()}
              className="h-9 w-9 rounded-full"
              title="Reiniciar conversa"
              aria-label="Reiniciar conversa"
            >
              <RefreshCcw className="h-4 w-4" />
            </Button>
          )}
        </div>

        {/* Handoff Banner */}
        {showHandoffBanner && matchingAgent && (
          <div className="bg-primary/10 border-b border-primary/20 px-4 py-3 flex items-center justify-between gap-3 animate-in slide-in-from-top duration-300">
            <div className="flex items-center gap-3">
              <div className="h-8 w-8 rounded-full overflow-hidden border border-primary/20 bg-background shrink-0">
                <img
                  src={
                    matchingAgent.persona_avatar ||
                    "/images/brand/safegold-icon-192.png"
                  }
                  alt={matchingAgent.persona_name}
                  className="h-full w-full object-cover"
                />
              </div>
              <div className="flex flex-col">
                <span className="text-xs font-bold text-foreground leading-none">
                  Agente Especializado
                </span>
                <span className="text-xs text-muted-foreground leading-tight">
                  {matchingAgent.persona_name} pode ajudar melhor nesta página.
                </span>
              </div>
            </div>
            <Button
              variant="primary"
              size="sm"
              onClick={() => handleSwitchAgent(matchingAgent.id)}
              className="whitespace-nowrap"
            >
              Conectar
            </Button>
          </div>
        )}

        {HiddenFileInput}

        {/* Messages Area */}
        <div className="flex-1 overflow-y-auto px-4 py-4 space-y-3 bg-background/50 scrollbar-thin scrollbar-thumb-border">
          {displayMessages.length === 0 && (
            <div className="flex flex-col items-center justify-center h-full text-center p-8">
              <div
                className="h-20 w-20 rounded-full overflow-hidden mb-4 border-4 border-primary/10 shadow-e3 cursor-pointer hover:scale-105 transition-transform"
                onClick={() =>
                  setSelectedPersona({
                    name: currentPersona.name,
                    avatar: currentPersona.avatar,
                    description: currentPersona.role,
                  })
                }
              >
                <img
                  src={currentPersona.avatar}
                  alt={currentPersona.name}
                  className="h-full w-full object-cover"
                />
              </div>
              <h3 className="text-xl font-bold text-foreground mb-1">
                {currentPersona.name}
              </h3>
              <p className="text-sm text-muted-foreground mb-4">
                {currentPersona.role}
              </p>
              <p className="text-sm text-foreground/80 max-w-[280px]">
                Olá! Como posso te ajudar hoje?
              </p>
            </div>
          )}

          {displayMessages.map((msg, idx) => {
            const isUser = msg.role === "user";
            const nextIsSame = displayMessages[idx + 1]?.role === msg.role;

            return (
              <div
                key={msg.id}
                className={`flex w-full flex-col ${isUser ? "items-end" : "items-start"}`}
              >
                <div
                  className={`flex w-full ${isUser ? "justify-end" : "justify-start"}`}
                >
                  {!isUser && (
                    <div
                      className={`mr-2 flex flex-col justify-end ${nextIsSame ? "invisible" : ""}`}
                    >
                      <div
                        className="h-7 w-7 rounded-full overflow-hidden border border-border cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all"
                        onClick={() => handleAvatarClick(msg)}
                      >
                        <img
                          src={msg.persona_avatar || currentPersona.avatar}
                          alt={msg.persona_name || currentPersona.name}
                          className="h-full w-full object-cover"
                        />
                      </div>
                    </div>
                  )}

                  <div
                    className={`
                      chat-bubble relative max-w-[85%] px-4 py-2.5 text-sm leading-snug break-words shadow-e1
                      ${
                        isUser
                          ? "bg-primary text-primary-foreground rounded-lg rounded-tr-md"
                          : "bg-secondary text-secondary-foreground rounded-lg rounded-tl-md border border-border/50"
                      }
                      ${nextIsSame ? "mb-1" : "mb-2"}
                    `}
                  >
                    {renderMessageContent(msg, {
                      onImageClick: (url) => setPreviewImageUrl(url),
                    })}
                  </div>
                </div>

                {/* Options / Quick Actions */}
                {!isUser && msg.options && msg.options.length > 0 && (
                  <div className="flex flex-col gap-2 mt-4 mb-6 ml-9 max-w-[85%] animate-in fade-in slide-in-from-left-4 duration-500">
                    {msg.options.map((option: any, optIdx) => {
                      const label =
                        typeof option === "object" ? option.label : option;
                      return (
                        <button
                          key={optIdx}
                          type="button"
                          onClick={() => handleSend(label, msg.origin_node_id)}
                          className="
                            group
                            flex items-center justify-between
                            px-5 py-3.5 text-sm font-medium
                            bg-background/40 hover:bg-primary/10
                            border border-primary/20 hover:border-primary/50
                            text-foreground/90 hover:text-primary
                            rounded-lg
                            transition-all duration-300
                            shadow-e1 hover:shadow-e2
                            active:scale-[0.98]
                            focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring
                            backdrop-blur-sm
                          "
                        >
                          <span className="flex-1 text-left">{label}</span>
                          <span className="opacity-0 group-hover:opacity-100 transition-opacity translate-x-1 group-hover:translate-x-0 duration-300">
                            →
                          </span>
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}

          {/* Typing Indicator */}
          {(isAgentTyping || isUploading) && (
            <div className="flex w-full justify-start mb-4 animate-in fade-in zoom-in duration-300">
              <div className="mr-2 flex flex-col justify-end">
                <div className="h-7 w-7 rounded-full overflow-hidden border border-border">
                  <img
                    src={currentPersona.avatar}
                    alt={currentPersona.name}
                    className="h-full w-full object-cover"
                  />
                </div>
              </div>
              <div className="bg-secondary text-secondary-foreground rounded-lg rounded-tl-md border border-border/50 px-4 py-3 shadow-e1 flex items-center justify-center min-h-11 min-w-16">
                {isUploading ? (
                  <div className="flex items-center gap-2 text-xs text-muted-foreground">
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>Processando...</span>
                  </div>
                ) : (
                  <ParticleLoader />
                )}
              </div>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>

        {/* Pending Image Preview */}
        {pendingImagePreview && (
          <div className="px-3 pt-2 pb-1 border-t border-border/40 bg-card/50 backdrop-blur-sm">
            <div className="relative inline-block">
              <img
                src={pendingImagePreview}
                alt="Preview"
                className="h-16 w-16 rounded-lg object-cover border border-border/50"
              />
              <Button
                variant="destructive"
                size="icon"
                onClick={clearPendingImage}
                className="absolute -top-1.5 -right-1.5 h-5 w-5 rounded-full"
                aria-label="Remover imagem"
              >
                <X className="h-3 w-3" />
              </Button>
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              Adicione uma legenda e envie
            </p>
          </div>
        )}

        {/* Drag Overlay */}
        {isDragging && (
          <div className="absolute inset-0 z-20 bg-primary/10 backdrop-blur-sm flex items-center justify-center pointer-events-none">
            <div className="text-primary font-semibold text-sm flex flex-col items-center gap-2">
              <Paperclip className="h-8 w-8" />
              Solte a imagem aqui
            </div>
          </div>
        )}

        {/* Input Area */}
        <div className="p-4 bg-card border-t border-border/30">
          <div className="flex items-center gap-3">
            {/* Attachment Button */}
            <Button
              variant="ghost"
              size="icon"
              onClick={() => fileInputRef.current?.click()}
              className="h-9 w-9 rounded-full"
              title="Enviar imagem"
              aria-label="Enviar imagem"
              disabled={isUploading}
            >
              <Paperclip className="h-5 w-5" />
            </Button>

            {/* Message Input */}
            <div className="flex-1 relative">
              <input
                ref={inputRef}
                type="text"
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Digite sua mensagem..."
                className="
                  w-full
                  bg-secondary text-foreground placeholder-muted-foreground
                  px-4 py-3
                  rounded-lg
                  outline-none
                  focus:ring-2 focus:ring-primary/30
                  transition-all
                  border border-border/50 focus:border-primary/30
                  pr-12
                "
              />
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setShowEmoji(!showEmoji)}
                className="absolute right-3 top-1/2 -translate-y-1/2 h-8 w-8 rounded-full"
                aria-label="Inserir emoji"
              >
                <Smile className="h-5 w-5" />
              </Button>

              {showEmoji && (
                <div className="absolute bottom-14 right-0 z-tooltip shadow-e3 rounded-md">
                  <div
                    className="fixed inset-0 z-10"
                    onClick={() => setShowEmoji(false)}
                  />
                  <div className="relative z-20">
                    <EmojiPicker
                      onEmojiClick={(emo) => {
                        setMessage((prev) => prev + emo.emoji);
                        setShowEmoji(false);
                        inputRef.current?.focus();
                      }}
                      width={320}
                      height={400}
                      theme={EmojiTheme.AUTO}
                    />
                  </div>
                </div>
              )}
            </div>

            {/* Send Button */}
            <div className="relative">
              <ParticleButton
                onClick={() => handleSend()}
                isLoading={isUploading}
                inputValue={message}
                className="w-12 h-12 shadow-e2"
              />
            </div>
          </div>
        </div>

        {/* Avatar Preview Modal */}
        {showAvatarPreview &&
          createPortal(
            <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
              <div
                className="absolute inset-0 bg-brand-ink/70 backdrop-blur-sm animate-in fade-in duration-200"
                onClick={() => setShowAvatarPreview(false)}
              />
              <div className="relative z-10 bg-card rounded-lg shadow-e3 p-2 animate-in zoom-in-95 duration-200 max-w-[280px]">
                <div className="relative rounded-md overflow-hidden aspect-square w-full">
                  <img
                    src={currentPersona.avatar}
                    alt={currentPersona.name}
                    className="w-full h-full object-cover"
                  />
                </div>
                <div className="mt-3 text-center pb-2">
                  <h4 className="font-bold text-sm">{currentPersona.name}</h4>
                  <p className="text-xs text-muted-foreground">
                    {currentPersona.role}
                  </p>
                </div>
                <Button
                  variant="secondary"
                  size="icon"
                  onClick={() => setShowAvatarPreview(false)}
                  className="absolute top-3 right-3 h-8 w-8 rounded-full"
                  aria-label="Fechar"
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
            </div>,
            document.body,
          )}

        {/* Image Lightbox */}
        {previewImageUrl &&
          createPortal(
            <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
              <div
                className="absolute inset-0 bg-brand-ink/70 backdrop-blur-sm animate-in fade-in duration-200"
                onClick={() => setPreviewImageUrl(null)}
              />
              <div className="relative z-10 animate-in zoom-in-95 duration-200 max-w-[90vw] max-h-[80vh]">
                <img
                  src={previewImageUrl}
                  alt="Preview"
                  className="max-w-full max-h-[80vh] rounded-lg object-contain shadow-e3"
                />
                <Button
                  variant="secondary"
                  size="icon"
                  onClick={() => setPreviewImageUrl(null)}
                  className="absolute top-3 right-3 h-8 w-8 rounded-full"
                  aria-label="Fechar"
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
            </div>,
            document.body,
          )}
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-drawer pointer-events-none lg:block">
      {/* Backdrop for mobile */}
      <div
        className="fixed inset-0 bg-brand-ink/30 pointer-events-auto lg:hidden backdrop-blur-sm transition-opacity"
        onClick={onClose}
      />

      {/* 
          Messenger Style Chat Window 
          Mobile: Side Drawer (Right)
          Desktop: Floating Card (Bottom aligned to layout)
      */}
      <div
        className={`pointer-events-auto absolute 
          top-0 right-0 h-full w-[85vw] max-w-[400px] 
          rounded-l-2xl border-l border-border/50 shadow-e3
          bg-card/95 backdrop-blur-md animate-in slide-in-from-right duration-300
          
          lg:fixed lg:top-auto lg:bottom-0 lg:right-6
          lg:w-[380px] lg:h-[600px] lg:max-h-[85vh]
          lg:rounded-t-2xl lg:rounded-b-none lg:border lg:border-b-0
          lg:animate-in lg:slide-in-from-bottom-10 lg:fade-in duration-300
          
          flex flex-col overflow-hidden font-sans
          ${isDragging ? "ring-2 ring-primary/50 ring-inset" : ""}
        `}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        {HiddenFileInput}
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-border/40 bg-card/50 backdrop-blur-sm shadow-e1 z-10">
          <div className="flex items-center gap-3">
            <div
              className="h-10 w-10 rounded-full overflow-hidden border-2 border-primary/20 cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all shadow-e2 bg-background"
              onClick={() => setShowAvatarPreview(true)}
            >
              <img
                src={currentPersona.avatar}
                alt={currentPersona.name}
                className="h-full w-full object-contain"
              />
            </div>

            <div className="flex flex-col">
              <span className="font-bold text-sm text-foreground leading-tight flex items-center gap-1 group">
                {currentPersona.name}
                <div className="h-3 w-3 rounded-full overflow-hidden bg-brand-ink flex items-center justify-center transform group-hover:scale-110 transition-transform">
                  <img
                    src="/company_logo.jpg"
                    alt="Safegold"
                    className="h-full w-full object-contain"
                  />
                </div>
              </span>
              <span className="text-xs text-muted-foreground font-medium uppercase tracking-tighter opacity-80">
                {currentPersona.role}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {mode === "flow" && (
              <Button
                variant="ghost"
                size="icon"
                onClick={() => resetFlowSession()}
                className="h-8 w-8 rounded-full"
                title="Reiniciar conversa"
                aria-label="Reiniciar conversa"
              >
                <RefreshCcw className="h-4 w-4" />
              </Button>
            )}
            <Button
              variant="ghost"
              size="icon"
              onClick={handleMinimize}
              className="h-8 w-8 rounded-full"
              aria-label="Minimizar conversa"
            >
              <Minus className="h-5 w-5" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={onClose}
              className="h-8 w-8 rounded-full"
              aria-label="Fechar conversa"
            >
              <X className="h-5 w-5" />
            </Button>
          </div>
        </div>

        {/* Messages Area */}
        <div className="flex-1 overflow-y-auto p-4 space-y-2 bg-background/50 scrollbar-thin scrollbar-thumb-border">
          {displayMessages.length === 0 && (
            <div className="flex flex-col items-center justify-center h-full text-center p-6 opacity-60">
              <div className="h-24 w-24 rounded-full overflow-hidden mb-4 border-4 border-background shadow-e2">
                <img
                  src={currentPersona.avatar}
                  alt={currentPersona.name}
                  className="h-full w-full object-cover"
                />
              </div>
              <h3 className="text-lg font-bold text-foreground">
                {currentPersona.name}
              </h3>
              <p className="text-sm text-muted-foreground">Safegold</p>
              <p className="text-sm text-muted-foreground mt-2">Diga Oi! 👋</p>
            </div>
          )}

          {displayMessages.map((msg, idx) => {
            const isUser = msg.role === "user";
            // Check if next message is same role to group bubbles visually (small margin)
            const nextIsSame = displayMessages[idx + 1]?.role === msg.role;

            return (
              <div
                key={msg.id}
                className={`flex w-full flex-col ${isUser ? "items-end" : "items-start"}`}
              >
                {/* Agent Avatar next to message */}
                <div
                  className={`flex w-full ${isUser ? "justify-end" : "justify-start"}`}
                >
                  {!isUser && (
                    <div
                      className={`mr-2 flex flex-col justify-end ${nextIsSame ? "invisible" : ""}`}
                    >
                      <div
                        className="h-7 w-7 rounded-full overflow-hidden border border-border cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all"
                        onClick={() => handleAvatarClick(msg)}
                      >
                        <img
                          src={msg.persona_avatar || currentPersona.avatar}
                          alt={msg.persona_name || currentPersona.name}
                          className="h-full w-full object-cover"
                        />
                      </div>
                    </div>
                  )}

                  <div
                    className={`
                       chat-bubble relative max-w-[85%] px-4 py-2.5 text-sm leading-snug break-words shadow-e1
                       ${
                         isUser
                           ? "bg-primary text-primary-foreground rounded-lg rounded-tr-md" // User bubble
                           : "bg-secondary text-secondary-foreground rounded-lg rounded-tl-md border border-border/50" // Agent bubble
                       }
                       ${nextIsSame ? (isUser ? "mb-1" : "mb-1") : "mb-2"} 
                     `}
                  >
                    {renderMessageContent(msg, {
                      onImageClick: (url) => setPreviewImageUrl(url),
                    })}
                  </div>
                </div>

                {/* Render Options if any (only for agent) */}
                {!isUser && msg.options && msg.options.length > 0 && (
                  <div className="flex flex-wrap gap-2 mt-2 mb-4 ml-11 max-w-[85%] animate-in fade-in slide-in-from-top-2 duration-300">
                    {msg.options.map((option: any, idx) => (
                      <button
                        key={idx}
                        type="button"
                        onClick={() =>
                          handleSend(
                            typeof option === "object" ? option.label : option,
                            msg.origin_node_id,
                          )
                        }
                        className="px-4 py-2 text-sm font-medium bg-background border border-primary/20 hover:bg-primary/10 text-primary rounded-full transition-colors shadow-e1 hover:shadow-e2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      >
                        {typeof option === "object" ? option.label : option}
                      </button>
                    ))}
                  </div>
                )}

                {/* Render Redirect Action (only for agent) */}
                {!isUser && (msg as any).data?.action === "navigate" && (
                  <div className="mt-2 mb-4 ml-11 animate-in fade-in slide-in-from-top-2 duration-300">
                    <a
                      href={(msg as any).data?.url}
                      target={(msg as any).data?.target || "_self"}
                      className="px-5 py-2.5 text-sm font-bold bg-primary text-primary-foreground rounded-md hover:bg-brand-gold-deep transition-colors shadow-e1 inline-flex items-center gap-2"
                    >
                      <span>Acessar Agora</span>
                      <ArrowRight className="w-4 h-4" />
                    </a>
                  </div>
                )}

                {/* Render Handoff Action (only for agent) */}
                {!isUser && (msg as any).data?.action === "handoff" && (
                  <div className="mt-2 mb-4 ml-11 animate-in fade-in slide-in-from-top-2 duration-300">
                    <p className="text-xs text-muted-foreground italic flex items-center gap-2">
                      <RefreshCcw className="w-3 h-3 animate-spin" />
                      Transferindo para fluxo:{" "}
                      <strong>
                        {(msg as any).data?.target_flow_name || "..."}
                      </strong>
                    </p>
                  </div>
                )}
              </div>
            );
          })}

          {/* Typing / Uploading Indicator */}
          {(isAgentTyping || isUploading) && (
            <div className="flex w-full justify-start mb-4 animate-in fade-in zoom-in duration-300">
              <div className="mr-2 flex flex-col justify-end">
                <div className="h-7 w-7 rounded-full overflow-hidden border border-border">
                  <img
                    src={currentPersona.avatar}
                    alt={currentPersona.name}
                    className="h-full w-full object-cover"
                  />
                </div>
              </div>
              <div className="bg-secondary text-secondary-foreground rounded-lg rounded-tl-md border border-border/50 px-4 py-3 shadow-e1 flex items-center justify-center min-h-11 min-w-16">
                {isUploading ? (
                  <div className="flex items-center gap-2 text-xs text-muted-foreground">
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>Processando imagem...</span>
                  </div>
                ) : (
                  <ParticleLoader />
                )}
              </div>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>

        {/* Pending Image Preview Strip */}
        {pendingImagePreview && (
          <div className="px-3 pt-2 pb-1 border-t border-border/40 bg-card/50 backdrop-blur-sm">
            <div className="relative inline-block">
              <img
                src={pendingImagePreview}
                alt="Preview"
                className="h-16 w-16 rounded-lg object-cover border border-border/50"
              />
              <Button
                variant="destructive"
                size="icon"
                onClick={clearPendingImage}
                className="absolute -top-1.5 -right-1.5 h-5 w-5 rounded-full"
                aria-label="Remover imagem"
              >
                <X className="h-3 w-3" />
              </Button>
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              Adicione uma legenda e envie →
            </p>
          </div>
        )}

        {/* Drag overlay */}
        {isDragging && (
          <div className="absolute inset-0 z-20 bg-primary/10 backdrop-blur-sm flex items-center justify-center rounded-lg pointer-events-none">
            <div className="text-primary font-semibold text-sm flex flex-col items-center gap-2">
              <Paperclip className="h-8 w-8" />
              Solte a imagem aqui
            </div>
          </div>
        )}

        {/* Footer / Input Area */}
        <div className="p-3 bg-card/50 backdrop-blur-sm border-t border-border/40 z-10">
          <div className="flex items-center gap-2">
            {/* Input Actions (Left) — Image upload button */}
            <div className="flex items-center gap-1 text-primary">
              <Button
                variant="ghost"
                size="icon"
                onClick={() => fileInputRef.current?.click()}
                className="h-9 w-9 rounded-full"
                title="Enviar imagem"
                aria-label="Enviar imagem"
                disabled={isUploading}
              >
                <Paperclip className="h-5 w-5" />
              </Button>
            </div>

            {/* Text Input */}
            <div className="flex-1 relative">
              <input
                ref={inputRef}
                type="text"
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Aa"
                className="w-full bg-secondary/50 text-foreground placeholder-muted-foreground px-4 py-2 rounded-full outline-none focus:ring-1 focus:ring-primary/50 transition-all border border-transparent focus:border-primary/20 pr-10"
              />
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setShowEmoji(!showEmoji)}
                className="absolute right-2 top-1/2 -translate-y-1/2 h-8 w-8 rounded-full"
                aria-label="Inserir emoji"
              >
                <Smile className="h-5 w-5" />
              </Button>

              {showEmoji && (
                <div className="absolute bottom-12 right-0 z-tooltip shadow-e3 rounded-md">
                  <div
                    className="fixed inset-0 z-10"
                    onClick={() => setShowEmoji(false)}
                  />
                  <div className="relative z-20">
                    <EmojiPicker
                      onEmojiClick={(emo) => {
                        setMessage((prev) => prev + emo.emoji);
                        setShowEmoji(false);
                        inputRef.current?.focus();
                      }}
                      width={300}
                      height={400}
                      theme={EmojiTheme.AUTO}
                    />
                  </div>
                </div>
              )}
            </div>

            {/* Like / Send Button */}
            <div className="relative">
              <ParticleButton
                onClick={() => handleSend()}
                isLoading={isUploading}
                inputValue={message}
                className={`w-14 h-14 shadow-e2 transition-opacity duration-300`}
              />
            </div>
          </div>
        </div>
      </div>

      {showReward && (
        <RewardOverlay
          onClose={handleCloseReward}
          onRedeem={handleApplyReward}
        />
      )}

      {/* Avatar Preview Modal */}
      {showAvatarPreview &&
        createPortal(
          <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
            {/* Backdrop */}
            <div
              className="absolute inset-0 bg-brand-ink/70 backdrop-blur-sm animate-in fade-in duration-200"
              onClick={() => setShowAvatarPreview(false)}
            />

            {/* Modal Content - 'Not too big' */}
            <div className="relative z-10 bg-card rounded-lg shadow-e3 p-2 animate-in zoom-in-95 duration-200 max-w-[280px]">
              <div className="relative rounded-md overflow-hidden aspect-square w-full">
                <img
                  src={currentPersona.avatar}
                  alt={currentPersona.name}
                  className="w-full h-full object-cover"
                />
              </div>
              <div className="mt-3 text-center pb-2">
                <h4 className="font-bold text-sm">{currentPersona.name}</h4>
                <p className="text-xs text-muted-foreground">
                  {currentPersona.role}
                </p>
              </div>
              <Button
                variant="secondary"
                size="icon"
                onClick={() => setShowAvatarPreview(false)}
                className="absolute top-3 right-3 h-8 w-8 rounded-full"
                aria-label="Fechar"
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
          </div>,
          document.body,
        )}

      {/* Image Lightbox Modal */}
      {previewImageUrl &&
        createPortal(
          <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
            <div
              className="absolute inset-0 bg-brand-ink/70 backdrop-blur-sm animate-in fade-in duration-200"
              onClick={() => setPreviewImageUrl(null)}
            />
            <div className="relative z-10 animate-in zoom-in-95 duration-200 max-w-[90vw] max-h-[80vh]">
              <img
                src={previewImageUrl}
                alt="Preview"
                className="max-w-full max-h-[80vh] rounded-lg object-contain shadow-e3"
              />
              <Button
                variant="secondary"
                size="icon"
                onClick={() => setPreviewImageUrl(null)}
                className="absolute top-3 right-3 h-8 w-8 rounded-full"
                aria-label="Fechar"
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
          </div>,
          document.body,
        )}

      {/* Agent Details Modal */}
      {selectedPersona &&
        createPortal(
          <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
            <div
              className="absolute inset-0 bg-brand-ink/70 backdrop-blur-md animate-in fade-in duration-300"
              onClick={() => setSelectedPersona(null)}
            />
            <div className="relative z-10 w-full max-w-sm bg-card border border-border rounded-lg overflow-hidden shadow-e3 animate-in zoom-in-95 duration-300">
              <div className="relative h-32 bg-secondary">
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => setSelectedPersona(null)}
                  className="absolute top-4 right-4 h-9 w-9 rounded-full z-20"
                  aria-label="Fechar"
                >
                  <X className="h-5 w-5" />
                </Button>
              </div>

              <div className="px-6 pb-8 -mt-16 relative flex flex-col items-center text-center">
                <div className="h-32 w-32 rounded-lg overflow-hidden border-4 border-card shadow-e3 mb-4 bg-background">
                  <img
                    src={selectedPersona.avatar}
                    alt={selectedPersona.name}
                    className="h-full w-full object-cover"
                  />
                </div>

                <h3 className="text-2xl font-bold text-foreground mb-1">
                  {selectedPersona.name}
                </h3>
                <div className="px-3 py-1 bg-primary/10 text-primary text-xs font-bold rounded-full mb-4">
                  AGENTE CERTIFICADO
                </div>

                <div className="w-full space-y-4">
                  <div className="p-4 bg-secondary/50 rounded-lg border border-border/50 text-left">
                    <h4 className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-2">
                      Especialidade
                    </h4>
                    <p className="text-sm text-foreground/80 leading-relaxed">
                      {selectedPersona.description}
                    </p>
                  </div>

                  <div className="grid grid-cols-2 gap-3">
                    <div className="p-3 bg-secondary/30 rounded-lg border border-border/30">
                      <div className="text-xs font-bold text-foreground mb-1">
                        Status
                      </div>
                      <div className="flex items-center gap-1.5 justify-center">
                        <div className="h-1.5 w-1.5 rounded-full bg-success animate-pulse" />
                        <span className="text-xs text-muted-foreground font-medium">
                          Online
                        </span>
                      </div>
                    </div>
                    <div className="p-3 bg-secondary/30 rounded-lg border border-border/30">
                      <div className="text-xs font-bold text-foreground mb-1">
                        Resposta
                      </div>
                      <div className="text-xs text-muted-foreground font-medium">
                        Instantânea
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>,
          document.body,
        )}
    </div>
  );
}

// Floating button triggers with DataSphere
export function AIChatButton({ onClick }: { onClick: () => void }) {
  return (
    <div className="fixed -bottom-16 -right-16 z-fab group pointer-events-none">
      <div className="relative pointer-events-auto">
        <DataSphere
          onClick={onClick}
          className="w-56 h-56 cursor-pointer hover:scale-110 transition-transform duration-500 ease-out"
          theme="dark"
        />
      </div>
    </div>
  );
}

// Helper to handle delays
function useMessageDelay(
  messages: ChatMessage[],
  handleSend: (msg: string) => void,
  setIsTyping: (typing: boolean) => void,
) {
  useEffect(() => {
    const lastMsg = messages[messages.length - 1];
    if (!lastMsg || lastMsg.role !== "agent" || !lastMsg.blocks) return;

    let totalDelay = 0;
    let hasDelay = false;

    lastMsg.blocks.forEach((block) => {
      if (block.type === "delay") {
        hasDelay = true;
        totalDelay += (block.seconds || 0) * 1000;
      }
    });

    if (hasDelay && totalDelay > 0) {
      setIsTyping(true);
      const timer = setTimeout(() => {
        setIsTyping(false);
        // Automatically request next step after delay
        handleSend("next");
      }, totalDelay);
      return () => clearTimeout(timer);
    }
  }, [messages, handleSend, setIsTyping]);
}
