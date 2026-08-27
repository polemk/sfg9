# ai9 feature selection — Safegold (`sfg`)

> As features que existem na **base ai9** mas **não** existem no app legado.
> Para cada uma, o cliente escolhe **manter** (fica) ou **remover** (é retirada
> por completo). Nada aqui é removido sem decisão explícita.

## Metadata
- Target (repo/branch da base ai9): `/home/vinao/workspace/ai9` (branch `sfg9`, diretório atual)
- Legado comparado: `../sfg` (Safegold — Rails 6.1 monolito, crédito/risco) — somente leitura
- Grafo ai9: `graphify-out/` (`graph.json`, 6.086 nós / 10.693 arestas, commit `d6d51174`)
- Inventário do legado: `.migration-ai9/feature-inventory.md` (1.439 IDs)
- Decidido por: _(pendente — Vinícius)_   ·   Data: 2026-08-24

**Como esta lista foi montada.** Enumerei a superfície do ai9 a partir dos módulos Grape em
`backend/app/controllers/api/**`, dos models em `backend/app/models/`, dos services em
`backend/app/services/`, das rotas em `frontend/src/app/App.tsx`, das páginas em
`frontend/src/app/pages/` + `frontend/src/features/` e dos recursos de
`frontend/src/lib/api/endpoints.ts`. Depois subtraí, **por significado**, tudo que o inventário do
legado cobre (auth/usuários, permissões/abilities, impersonation, console admin, temas, help/FAQ,
feedback, uploads/Paperclip, mailer, tracking de auditoria, geolocalização, projetos, empresas,
portadores, recebíveis, renegociações, risco, operações estruturadas, disponibilidade, indicadores,
contratos, site público legado). O que sobrou está abaixo. A coluna **LOC** é volume de código
próprio da feature (`.rb`/`.ts`/`.tsx`/`.css`, sem testes e sem migrations) e serve só para dar
noção de tamanho.

---

## ai9-only features

| ID | Feature / módulo | LOC | Onde vive no ai9 (rotas/models/services/páginas) | Depende de / compartilha com | Recomendação | Decisão (manter/remover) | Motivo (se remover) |
| ------- | ---------------- | ---: | ----------------------------------------------- | ---------------------------- | ------------ | ------------------------ | ------------------- |
| AI9-001 | **Pagamentos e cobranças Asaas** (gateway, faturas, assinaturas recorrentes, webhooks, cartão) | 2.666 | `backend/app/controllers/api/asaas/v1/{base,payments,invoices,sales,subscriptions,webhooks}.rb`; `backend/app/services/{asaas_connection,asaas_query_service,asaas_webhook_service,asaas_charge_webhook_service,asaas_payment_webhook_service,sales_service,pricing_calculator}.rb`; `backend/app/services/payments/create_charge.rb`; `backend/app/models/{purchase,pricing}.rb`; `backend/app/channels/payments_channel.rb`; `frontend/src/app/pages/PaymentsPage.tsx`; `frontend/src/components/CreditCardForm.tsx`; `paymentsApi`/`salesApi`/`chargesApi` em `endpoints.ts` | `Purchase` ← AI9-002 (planos), AI9-003 (cupons), AI9-010 (funil/conversão), AI9-029 (checkout-session); rota `/payments` e `/vendas` no `Sidebar` | **remover** — o legado não cobra nada online; crédito/risco não tem gateway de venda no fluxo | | |
| AI9-002 | **Planos, assinaturas, checkout e feature-gating por plano** (planos, features de plano, escassez, upgrade, limites de uso) | 7.347 | `backend/app/controllers/api/v1/{plans,plan_features,my_subscription,checkout,support_plans}.rb`; `backend/app/controllers/public/v1/plans.rb`; `backend/app/models/{plan,plan_feature,plan_feature_assignment,plan_feature_permission,subscription,user_feature_usage,support_plan}.rb`; `backend/app/services/{plans_service,plan_features_service,subscription_management_service,feature_usage_service,support_plans_service,scope_calculator}.rb`; `backend/app/jobs/plan_scarcity_reset_job.rb`; `frontend/src/app/pages/{AdminPlansPage,AdminPlanFormPage,AdminFeaturesPage,CheckoutPage,PlansRedirectPage,MobilePlansPage,MobilePlanFormPage,MobileFeaturesList}.tsx`; `frontend/src/components/{PlanSelector,UpgradeModal,UpgradeRequiredModal}.tsx`; `frontend/src/hooks/{usePlanFeatures,usePlanPreview}.ts` | `User#plan`, `PermissionsSyncService`, `Permission`/`UserPermission` (infra compartilhada), `Sidebar` (`MENU_KEY_MAP` monta o menu a partir das features do plano), AI9-001, AI9-003 | **remover** — SaaS self-service; o legado é licenciado por contrato, sem planos. **Mas** o `Sidebar` deriva o menu de `plan_features`: exige refatorar a navegação junto | | |
| AI9-003 | **Cupons e programa de parceiros/afiliados** (cupom, redirect por código, painel do parceiro, comissão) | 1.754 | `backend/app/controllers/api/v1/{coupons,public/coupons}.rb`; `backend/app/controllers/api/v1/partner/dashboard.rb`; `backend/app/models/coupon.rb`; `backend/app/services/coupon_service.rb`; `frontend/src/app/pages/admin/CouponsPage.tsx`; `frontend/src/app/pages/partner/{DashboardPage,SalesPage,CouponsPage}.tsx`; `frontend/src/app/pages/CouponRedirectPage.tsx`; `frontend/src/components/PartnerMenu.tsx`; `frontend/src/store/couponStore.ts` | `Purchase`, `Plan`, `users_service`, `analytics_service`; **rota catch-all `/:code`** em `App.tsx` (linha 179) — remover exige limpar o catch-all | **remover** — canal de venda por afiliado não existe no legado | | |
| AI9-004 | **Blog: posts, rascunhos, categorias, tags, comentários, curadoria e ingestão por WhatsApp/Drive** | 6.591 | `backend/app/controllers/api/v1/{posts,post_drafts,categories,tags,comments,blog_settings,superadmin_phones}.rb`; `.../api/v1/public/{posts,brazilian_posts,categories,tags}.rb`; `backend/app/models/{post,post_draft,post_tag,tag,category,comment,blog_setting,blog_intake_session,superadmin_phone}.rb`; `backend/app/services/blog/*`, `{post_creation_service,post_body_generator_service,post_transcription_service,comments_service,blog_chat_service}.rb`; `backend/app/jobs/{publish_scheduled_drafts,purge_discarded_drafts,post_draft_transcription,blog_intake_session_expiry}_job.rb`; `frontend/src/app/pages/posts/*`, `PostsPage.tsx`, `admin/{BlogSettingsPage,CurationQueuePage,SuperadminPhonesPage}.tsx` | AI9-005 (intake por WhatsApp), AI9-008 (credenciais de IA para gerar corpo do post), AI9-018 (transcrição), AI9-017 (Drive), AI9-010 (`hub_*` espelha posts) | **remover** — o legado não publica conteúdo; é um produto inteiro sem relação com crédito/risco | | |
| AI9-005 | **WhatsApp via Evolution API ("Polemk")**: instâncias, QR/pareamento, chats, grupos, mensagens, webhooks | 2.460 | `backend/app/controllers/api/whats/v1/{base,instances,chats,groups,messages,webhooks}.rb`; `backend/app/models/{polemk_instance,polemk_instance_group,polemk_chat_message,polemk_webhook}.rb`; `backend/app/services/{evolution_connection,polemk_instance_service,polemk_chat_service,polemk_group_service,polemk_webhook_service,whats_message_service,whats_app_webhook_service,whatsapp_notification_service}.rb`; `backend/app/services/whatsapp/admin_auth_resolver.rb`; `backend/app/jobs/evolution_reconnect_job.rb`; `backend/app/channels/whatsapp_instance_channel.rb`; `frontend/src/app/pages/WhatsappPage.tsx` | AI9-006 (inbox/omnichannel), AI9-004 (curadoria por WhatsApp), AI9-029 (código de login por WhatsApp), AI9-019 (notificações de agenda) | **remover** — canal de atendimento/marketing; o legado notifica só por e-mail. **Atenção**: o login por código do ai9 usa esse canal (ver AI9-029) | | |
| AI9-006 | **Leads e omnichannel** (lead, jornada, mensagens, canais/origens, inbox estilo Chatwoot, dispatch e inbound) | 10.784 | `backend/app/controllers/api/v1/{leads,lead_messages,origens,public/leads}.rb`; `backend/app/models/{lead,lead_message,canal}.rb`; `backend/app/models/concerns/filtravel_por_origem.rb`; `backend/app/services/{lead_service,lead_message_service,lead_cross_channel_service,lead_sandbox_service}.rb`, `services/leads/upsert_from_chat.rb`, `services/omnichannel/{dispatch_service,inbound_processor_service}.rb`; `backend/app/jobs/{omnichannel_dispatch,process_inbound_reply,link_events_to_lead}_job.rb`; `backend/app/channels/lead_chat_channel.rb`; `frontend/src/features/leads/*`, `frontend/src/components/leads/*`, `frontend/src/app/pages/{LeadsChatPage,admin/CanaisPage}.tsx` | **Hub do ai9**: `Lead` é referenciado por AI9-001 (checkout), AI9-007 (chat), AI9-009 (Meta), AI9-010 (tracked_events/funil), AI9-013 (Operation), AI9-012 (hub brsw) | **remover** (em bloco com AI9-007/009/010/013) — CRM de marketing; o legado não tem lead. Piecemeal quebra meia dúzia de módulos — ver *Risco de remoção* | | |
| AI9-007 | **Chatbot: flow builder visual + motor de IA multi-provider** (nós, execuções, agente, ferramentas, telemetria, widget de chat no site) | 16.581 | `backend/app/controllers/api/v1/{chat,chat_flows,flow_executions,comment_keywords}.rb`, `.../public/{chat,chat_callback}.rb`; `backend/app/models/{chat_flow,chat_session,flow_execution,agent_run}.rb`; `backend/app/services/ai/{agent_service,flow_engine,flow_matcher,telemetry}.rb` + `ai/nodes/*` + `ai/tools/*` + `ai/providers/{anthropic,openai,google,base}_provider.rb`; `backend/app/services/{chat_flows_service,public_chat_service}.rb`; `backend/app/channels/public_chat_channel.rb`; `frontend/src/features/chat-builder/*` (5 páginas + 22 componentes); `frontend/src/components/chat/*` (`AIChatWidget.tsx` sozinho = 2.657 LOC); `frontend/src/contexts/ChatContext.tsx`; `frontend/src/hooks/{useChatFlow,useChatActions,useAgentRouter}.ts` | AI9-008 (credenciais), AI9-006 (`Lead`, `save_to_lead`, handoff), AI9-013 (`Operation`/knowledge/embeddings), AI9-009 (fluxos disparados por comentário), AI9-005 (handoff p/ WhatsApp) | **remover** — maior módulo do ai9 e 100% orientado a captação/atendimento; sem paralelo em crédito/risco | | |
| AI9-008 | **Credenciais de provedores de IA** (chaves OpenAI/Anthropic/Google/Drive por escopo) | 727 | `backend/app/controllers/api/v1/credentials.rb`; `backend/app/models/credential.rb`; `backend/app/controllers/api/entities/credential.rb`; `frontend/src/features/credentials/*`; `frontend/src/app/pages/admin/CredentialsPage.tsx`; `frontend/src/lib/api/credentials.ts` | **Infra compartilhada**: consumida por AI9-004, AI9-007, AI9-009, AI9-013, AI9-017, AI9-018 | **manter** — é infra transversal barata; remover só faz sentido se **todas** as features de IA saírem juntas | | |
| AI9-009 | **Integrações Meta (Instagram/Facebook)**: automação de comentário, resposta pública, DM privada, webhooks, saúde do token | 4.781 | `backend/app/controllers/api/v1/integrations.rb`, `.../api/v1/webhooks/meta.rb`; `backend/app/models/{integration,instagram_comment_keyword,instagram_comment_reply_sent}.rb`; `backend/app/services/meta/{instagram_comment_automation_service,public_comment_reply_service,private_reply_service,send_message_service}.rb`; `backend/app/jobs/{process_meta_webhook,meta_token_health}_job.rb`; `frontend/src/app/pages/admin/{IntegrationsPage,InstagramSettingsPage}.tsx`; `frontend/src/features/integrations/*` | AI9-013 (`Operation` + keywords), AI9-007 (`ChatFlow`), AI9-006 (`Lead`), AI9-008 (tokens em `Credential`) | **remover** — automação de redes sociais; nada equivalente no legado | | |
| AI9-010 | **Analytics próprio**: tracking de eventos, funil de conversão, dashboard de KPIs, resultados por origem, viewers, GA4 + Meta CAPI server-side | 14.269 | `backend/app/controllers/api/v1/analytics.rb`; `backend/app/services/analytics/*` (14 arquivos, incl. `ga4/send_event.rb` e `providers/meta_capi.rb`); `backend/app/models/{tracked_event,viewer}.rb`; `backend/app/jobs/{viewer_track,dashboard_kpis_broadcast}_job.rb` + `jobs/analytics/*`; `backend/app/channels/{dashboard_channel,event_logger_channel,public_events_channel}.rb`; `frontend/src/features/metrics/*` (26 arquivos); `frontend/src/lib/analytics/*`; `frontend/src/app/pages/admin/{AnalyticsPage,AnalyticsPageDesktop,AnalyticsPageMobile,ConversionFunnelSection,MobileMiniKpi}.tsx`; `frontend/src/components/{charts,kpi,alerts}/*`; `frontend/src/components/GlobalDateRangeSelector.tsx` | `TrackedEvent` é o segundo hub do ai9: `Lead`, `Purchase`, `Canal`, `Viewer`, AI9-012 (hub), AI9-011/AI9-012 abaixo. **Não confundir** com o `Tracking` do legado (trilha de auditoria, `misc-ops / Tracking`) — não é a mesma coisa | **remover** — é analytics de funil de marketing. O legado usa Google Analytics externo e tem trilha de auditoria própria (que continua sendo migrada como legacy-only) | | |
| AI9-011 | **Painel TV (métricas em tela cheia)** | 1.770 | `frontend/src/features/metrics/PainelTV.tsx` (+ `MosaicoParede`, `LiveFeed`, `ScoreRing`) | AI9-010 (mesmo backbone de `tracked_events`) | **remover** — tela de vitrine para escritório de marketing | | |
| AI9-012 | **Logger de eventos ao vivo + Heatmap de cliques** | 938 | `frontend/src/app/pages/admin/{EventLoggerPage,HeatmapPage}.tsx`; `backend/app/services/analytics/get_heatmap_data.rb`; `frontend/src/lib/analytics/useHeatmapTracker.ts`; `backend/app/channels/event_logger_channel.rb`; rotas `/admin/logger` e `/admin/heatmap` | AI9-010 | **remover** — ferramenta de otimização de landing page | | |
| AI9-013 | **Espelhamento no hub "brsw"** (push de leads/eventos/posts para app externo) | 431 | `backend/app/jobs/{hub_push,hub_metricas,hub_forward_events}_job.rb`; ENVs `HUB_URL` / `HUB_SOURCE_TOKEN` | AI9-006, AI9-010, AI9-004 | **remover** — integração com infraestrutura interna da agência, não do cliente. Já é no-op sem as ENVs | | |
| AI9-014 | **Operations** (agrupador de campanha/marketing) + base de conhecimento e embeddings | 2.729 | `backend/app/controllers/api/v1/operations.rb`, `.../public/operation_assets.rb`; `backend/app/models/{operation,operation_asset,operation_knowledge}.rb`; `backend/app/services/{operation_service}.rb`, `services/operations/{intent_detector_service,embeddings/generate_service}.rb`; `backend/app/jobs/generate_embedding_job.rb`; `frontend/src/app/pages/admin/{OperationsPage,OperationManagerPanel}.tsx`; `frontend/src/lib/api/operationAssets.ts`; `frontend/src/hooks/useAssetsResolver.ts` | AI9-006 (`Lead#operation`), AI9-007 (`ChatFlow#operation`, `flow_matcher`), AI9-009 (keywords/replies), AI9-015 (assets) | **remover** — ⚠️ **colisão de nome**: `Operation` no ai9 **não** é operação financeira. Se ficar, vira armadilha semântica para "operações de risco"/"operações estruturadas" do legado | | |
| AI9-015 | **Showrooms** (vitrines públicas de mídia por identificador) | 1.860 | `backend/app/controllers/api/v1/showrooms.rb`, `.../public/showrooms.rb`; `backend/app/models/showroom.rb`; `backend/app/services/showroom_service.rb`; `frontend/src/app/pages/ShowroomsPage.tsx`; `frontend/src/features/marketing/ShowroomPostWidget.tsx` | AI9-016 (`Medium`), AI9-004 (widget de post) | **remover** — vitrine de portfólio; sem paralelo no legado | | |
| AI9-016 | **Galeria de mídia, uploads e downloads** (`Medium`, thumbnails, crop, proxy de Drive) | 1.777 | `backend/app/controllers/api/v1/{media,uploads,downloads}.rb`, `.../public/media.rb`; `backend/app/models/medium.rb`; `backend/app/services/medium_service.rb`; `frontend/src/app/pages/MediaPage.tsx`; `frontend/src/components/{ThumbnailPicker}.tsx`, `components/ui/ImageCropper.tsx`; `frontend/src/lib/api/downloads.ts`; `frontend/src/lib/utils/driveMedia.ts` | **Infra compartilhada**: AI9-015 (showroom), AI9-007 (assets do chat), AI9-014, AI9-004. O legado tem upload/anexo (`Picture`, Paperclip) — a **capacidade** é compartilhada; só a **galeria como produto** é ai9-only | **manter** — o legado precisa de upload/anexo (avatar, anexos de renegociação, logos). Remover só a tela `/media` se o cliente não quiser a galeria | | |
| AI9-017 | **Pedidos, entregas, milestones, requisitos e especificações** (workflow de entrega de conteúdo) | 1.148 | `backend/app/controllers/api/v1/{orders,deliveries,order_milestones,requirements,specifications}.rb`, `.../public/deliveries.rb`; `backend/app/models/{order,order_milestone,delivery,delivery_item,delivery_attachment,requirement,specification,project}.rb`; `backend/app/services/{orders_service,deliveries_service,order_milestones_service,requirements_service,specifications_service}.rb` | `AccessCode` (AI9-029), `Project` (ai9) | **remover** — ⚠️ segunda **colisão de nome**: o `Project` do ai9 é projeto de entrega de conteúdo, **não** o `Project` de crédito do legado. Manter os dois lado a lado confunde a migração de `projects` | | |
| AI9-018 | **Onboarding guiado + templates de onboarding** | 1.526 | `backend/app/controllers/api/v1/{setup,onboarding_templates}.rb`; `backend/app/models/onboarding_template.rb`; `backend/app/services/onboarding_templates_service.rb`; `frontend/src/app/pages/{SetupPage,AdminOnboardingTemplatesPage}.tsx`; item `/setup` no `Sidebar` | AI9-002 (plano define o template), AI9-005 (passos de WhatsApp) | **remover** — wizard de ativação de SaaS; o legado provisiona conta por administrador | | |
| AI9-019 | **Transcrição de áudio/vídeo por IA** | 338 | `backend/app/controllers/api/v1/transcriptions.rb`; `backend/app/services/{audio_converter_service,post_transcription_service}.rb`, `services/ai/audio_transcription_service.rb`, `services/blog/{draft_transcription_service,video_converter_service}.rb`; `backend/app/jobs/{process_audio_transcription,post_transcription,post_draft_transcription}_job.rb`; `frontend/src/app/pages/TranscriptPage.tsx` | AI9-008, AI9-004 | **remover** — ferramenta de produção de conteúdo | | |
| AI9-020 | **Agenda / Google Calendar / ingestão do Drive / briefing diário** | 905 | `backend/app/services/agenda/{memory_service,phone_normalizer,tools/calendar_tool,tools/plane_tool}.rb`; `backend/app/services/google_drive_connection.rb`; `backend/app/services/ai/tools/calendar_guard.rb`; `backend/app/models/agenda_memory.rb`; `backend/app/jobs/{agenda_briefing,calendar_event_notify,drive_ingestion}_job.rb` | AI9-007 (ferramentas do agente), AI9-008, AI9-005 (notificação) | **remover** — assistente pessoal de agenda; nada equivalente no legado | | |
| AI9-021 | **Landing pública "campfire"** (home institucional, nichos `/n/:niche`, manifesto, ticker, timeline) | 5.026 | `frontend/src/components/campfire/*` (16 componentes + `sections/`); `frontend/src/app/pages/HomePage.tsx`; `frontend/src/styles/tokens-campfire.css`; `frontend/src/wireframes/HomeCampfire.tsx`; rotas `/` e `/n/:niche` | AI9-010 (tracking da home), AI9-007 (widget de chat), AI9-002 (planos na home) | **remover** — site institucional da agência ai9. **Atenção**: libera a rota `/`, que precisa de destino novo (login ou dashboard) | | |
| AI9-022 | **Cenas 3D / WebGL** (three.js: wormhole, portal, salas, galeria) | 1.876 | `frontend/src/components/3d/*` (11 cenas + `chat/`) | AI9-021 (usadas na home) | **remover** — enfeite de marketing; sai junto com AI9-021 | | |
| AI9-023 | **UI de terminal / typewriter** | 404 | `frontend/src/components/terminal/{TerminalWindow,TypewriterText}.tsx`; `frontend/src/stores/useTerminalStore.ts` | AI9-021, AI9-007 (canal "terminal" de chat) | **remover** — efeito visual da home | | |
| AI9-024 | **Easter egg sazonal (caça aos ovos)** | 1.184 | `frontend/src/components/seasonal/{EasterEggHunt,EasterEggModal,EasterOverlay,EasterProgressPanel}.tsx`; `frontend/src/styles/easter-theme.css` | AI9-021 | **remover** — gamificação de campanha; folha isolada | | |
| AI9-025 | **Página "Brazilian Software"** (landing de conteúdo separada) | 3.225 | `frontend/src/app/pages/BrazilianSoftware/BrazilianSoftwarePage.tsx`; `backend/app/controllers/api/v1/public/brazilian_posts.rb` | AI9-004 (posts) | **remover** — landing de marca própria da ai9 | | |
| AI9-026 | **NavKit** (kit de navegação matricial: demo, landing, overview) | 1.851 | `frontend/src/NavKit/*`; `frontend/src/app/NavKitDemo.tsx`; `frontend/src/app/pages/{NavKitHome,NavKitOverview}.tsx`; `frontend/src/app/pages/NavKitLanding/*`; `frontend/src/app/styles/NavKitHome.css`; rota `/navkit/*` | Nenhuma feature de produto consome — é showcase | **remover** — o legado tem a engine `navkit`, mas ela **não carrega** lá (`engines / navkit`); aqui é vitrine do kit, não navegação real do app | | |
| AI9-027 | **Preview de site / "Vem com site" (BuildPage)** | 430 | `frontend/src/app/pages/{SitePreviewPage,BuildPage}.tsx`; `frontend/src/components/preview/*`; item `/preview-site` no `Sidebar` | AI9-002 (oferta atrelada ao plano) | **remover** — upsell de site incluído no plano | | |
| AI9-028 | **Design demo / playground de tokens** | 56 | `frontend/src/app/pages/DesignDemoPage.tsx`; rota `/design-demo` | Design system (`components/ui`, compartilhado) | **remover** — página de desenvolvimento exposta em rota pública | | |
| AI9-029 | **Guia de rastreamento (docs de UTM/GTM na app)** | 475 | `frontend/src/app/pages/TrackingGuidePage.tsx`; `backend/docs/{TRACKING_GUIDE,UTM_STANDARDS,GTM_SETUP}.md`; rota `/guia-rastreamento` | AI9-010 | **remover** — documentação de onboarding de analytics | | |
| AI9-030 | **Login por magic link, código via WhatsApp, OAuth Google** (~~access codes~~ — **CORRIGIDO no Bloco 3: `AccessCode` NÃO pertence a esta feature**, ver nota abaixo da tabela) (registro em duas etapas, pré-registro, visitante) | 3.087 | `backend/app/controllers/api/auth/v1/{magic_link,magic_login,code_validation,oauth,registration,checkout}.rb`; `backend/app/controllers/{oauth_redirects_controller,users/omniauth_callbacks_controller}.rb`; `backend/app/models/{login_code,login_attempt,client_application}.rb`; `backend/app/services/auth/{magic_link_verify_service,magic_login_service,code_validation_service,verify_code_service,oauth_service,pre_register_service,complete_registration_service,visitor_auth_service,visitor_signup_with_link_service,checkout_session_service}.rb`; `backend/app/jobs/cleanup_login_codes_job.rb`; `frontend/src/features/auth/*` | **Infra de autenticação**: `LoginPage`/`AuthFlow` são o **único** caminho de login do ai9; `authStore`, `ProtectedRoute`, JWT. O legado tem Devise + senha (+ Facebook desativado) | **manter** — é o mecanismo de login vivo do ai9. Remover exige construir o login por senha antes; senão o app fica sem porta de entrada | | |
| AI9-031 | **Audio visualizer / componentes áudio-reativos** | 905 | `frontend/src/app/experiments/audio-visualizer/*`; `frontend/src/components/chat/AudioVisualizerPlayer.tsx`; `frontend/src/components/ui/{AudioReactiveButton,AudioReactiveText}.tsx`; `frontend/src/components/experiments/NeonOscilloscope.tsx`; `frontend/src/hooks/useAudioAnalyzer.ts`; `frontend/src/store/audioPlayerStore.ts`; rota `/audio-visualizer` | AI9-007 (player no chat) | **remover** — experimento visual | | |
| AI9-032 | **Servidor MCP do n8n + scripts de workflow** | 1.575 | `tools/n8n-mcp-server/` (src + patches + scripts `dump_*`, `fix_*`) | Nenhum código da app depende | **remover** — ferramenta interna de automação da ai9, fora do produto | | |
| AI9-033 | **Modos de navegação (negócio / conteúdo / plataforma / blog), Agentic Mode e shell mobile** | 1.723 | `frontend/src/store/sidebarModeStore.ts`; `frontend/src/components/{SidebarModeToggle,Sidebar}.tsx`; `frontend/src/hooks/useNavItems.ts`; `frontend/src/components/mobile/*` (9 componentes); `frontend/src/app/pages/{DashboardPage,ClientDashboardPage}.tsx` | Toda a navegação do app; `MENU_KEY_MAP` amarra os itens às features de plano (AI9-002) | **manter** — é o shell de navegação; a versão para o Safegold nasce daqui. O que se remove são os **itens de menu** das features descartadas, não o shell | | |
| AI9-034 | **Países / DDI e endpoints de defaults** | 341 | `backend/app/controllers/api/v1/{countries,defaults}.rb`; `frontend/src/components/PhoneInputGroup.tsx` | Formulários de usuário/lead | **manter** — utilitário barato; o legado tem cadastro de telefone/endereço e reaproveita | | |
| AI9-035 | **Docs OpenAPI in-app e proxy de assets** | 37 | `backend/app/controllers/{docs_controller,assets_proxy_controller}.rb` | — | **manter** — infraestrutura de documentação da API, útil na migração | | |

---

## Bulk decision (opcional)
- [ ] Manter tudo (default seguro — aparar depois)
- [ ] Remover tudo que não existe no legado
- [ ] Decidir item a item (tabela acima)

---

## Risco de remoção

Classificação do que quebra ao remover cada item. **baixo** = folha isolada, sai sozinha;
**médio** = tem dependentes, mas removíveis no mesmo bloco; **alto** = infra compartilhada,
remover não é recomendado.

### Alto — remover **não é recomendado** (mesmo se o cliente pedir)

| ID | Por quê |
| -- | ------- |
> **Correcao ao catalogo — descoberta no Bloco 3 (24/08/2026).** Eu tinha listado
> `backend/app/models/access_code.rb` como parte do **AI9-030**. **Estava errado.** O
> `AccessCode` nao aparece em nenhum arquivo de autenticacao: o codigo de login e
> `LoginCode` + `LoginAttempt`. Os unicos consumidores do `AccessCode` eram os `as:
> :resource` de `Delivery` e `Project` — ambos do **AI9-017**, removido no Bloco 3. Ele
> saiu junto, corretamente, e o repo ficou com **zero** referencia residual (conferido).
>
> **A licao vale alem deste caso:** eu inferi o pertencimento pelo **nome do arquivo**
> ("access code" soa como autenticacao) em vez de seguir quem o consome. O agente do
> bloco checou os consumidores e me corrigiu. Em catalogo de features, **quem importa
> define o dono, nao o nome.**

| **AI9-030** auth (magic link / código / OAuth) | É o **único** fluxo de login do ai9. `LoginPage`, `AuthFlow`, `authStore`, `ProtectedRoute`/`ClientRoute`/`OgRoute`/`VisitorRoute` e o JWT do `api/v1/base.rb` dependem dele. Remover antes de existir um login por senha equivalente deixa o app inacessível. **Recomendação: manter e adaptar**, não remover. |
| **AI9-033** modos de navegação / shell | `Sidebar`, `Topbar`, `Layout` e o shell mobile são a casca de todas as telas — inclusive das telas que virão do legado. O correto é **podar itens de menu**, não excluir o shell. |
| **AI9-016** mídia / uploads / downloads | O legado usa anexos em 7 pontos (avatar de usuário e projeto, anexos de renegociação, logos de fornecedor/portador, imagens polimórficas, identidade visual do tema). O backend de upload/download é a única implementação disponível no ai9. **Manter o backend**; a tela `/media` pode sair. |
| **AI9-008** credenciais de IA | Modelo de 1 tabela consumido por 6 features. Se todas as features de IA saírem, ele fica órfão e aí sim é removível — mas removê-lo **antes** delas quebra blog, chat, transcrição, embeddings e agenda de uma vez. Remover **por último**, nunca primeiro. |
| **AI9-034** países / defaults | Baixo custo, alto reuso em formulários (o legado tem telefone, CPF/CNPJ, endereço, estado/cidade). Remover só cria retrabalho. |
| **AI9-006** leads / omnichannel · **AI9-010** analytics | Não são infra "boa" a preservar, mas são os **dois hubs do grafo**: `Lead` e `TrackedEvent` aparecem em 14+ arquivos cada, atravessando checkout, chat, Meta, WhatsApp, funil e hub. Remover é legítimo — mas **só em bloco coordenado** com AI9-001/004/005/007/009/011/012/013/014. Remoção isolada = alto risco de quebra em cascata. |

### Médio — tem dependentes, removível junto com o bloco

| ID | Bloco / ordem sugerida |
| -- | ---------------------- |
| AI9-001 pagamentos Asaas | Sai com AI9-002 e AI9-003 (`Purchase` é compartilhado com o funil de AI9-010). |
| AI9-002 planos e feature-gating | **Antes de remover**, refatorar `Sidebar`/`useNavItems`: hoje o menu é montado a partir de `plan_features`. Também mexe em `PermissionsSyncService`. |
| AI9-003 cupons / parceiros | Limpar a rota catch-all `/:code` em `App.tsx`. |
| AI9-004 blog | Depende de AI9-005 (intake), AI9-008, AI9-019 e AI9-020. Remover depois deles ou junto. |
| AI9-005 WhatsApp / Evolution | ⚠️ o **código de login por WhatsApp** (AI9-030) usa esse canal. Verificar antes de cortar. |
| AI9-007 chatbot / flow builder | Maior bloco; sai junto com AI9-006, AI9-008 (depois), AI9-014, AI9-009. |
| AI9-009 Meta / Instagram | Sai com AI9-014 (keywords vivem em `Operation`) e AI9-007. |
| AI9-011 Painel TV · AI9-012 logger/heatmap · AI9-013 hub | Só dependem de AI9-010; podem sair **antes** dele, sem risco. |
| AI9-014 Operations | Precisa sair **antes ou junto** de AI9-006/007/009 (todos têm FK para `Operation`). Prioridade alta pela colisão de nome com "operações de risco". |
| AI9-015 showrooms | Depende de AI9-016 (`Medium`); remover só o Showroom é seguro. |
| AI9-017 pedidos/entregas | Colisão de nome com `Project` do legado — resolver antes de migrar `projects`. |
| AI9-018 onboarding | Depende de AI9-002; sai junto. |
| AI9-019 transcrição · AI9-020 agenda | Folhas do bloco de IA; podem sair antes de AI9-007/008. |
| AI9-021 landing campfire | Libera a rota `/` — definir destino novo (login ou dashboard) na mesma tarefa. |

### Baixo — folha isolada, remoção segura em 1 commit

AI9-022 (3D), AI9-023 (terminal), AI9-024 (easter egg), AI9-025 (BrazilianSoftware),
AI9-026 (NavKit), AI9-027 (preview de site), AI9-028 (design demo), AI9-029 (guia de
rastreamento), AI9-031 (audio visualizer), AI9-032 (n8n MCP), AI9-035 (docs/proxy — se o
cliente quiser mesmo).

### Ordem sugerida de remoção (se a decisão for "remover quase tudo")

1. **Folhas visuais** (baixo risco): AI9-022→AI9-029, AI9-031, AI9-032.
2. **Telas dependentes de analytics**: AI9-011, AI9-012, AI9-013.
3. **Bloco de conteúdo**: AI9-025, AI9-021, AI9-015, AI9-019, AI9-020, AI9-004.
4. **Bloco comercial**: AI9-027, AI9-018, AI9-003, AI9-001, AI9-002 (com refactor do `Sidebar`).
5. **Bloco de marketing/IA**: AI9-009, AI9-005, AI9-007, AI9-014, AI9-006, AI9-010.
6. **Por último, se órfão**: AI9-008.
7. **Nunca sem substituto pronto**: AI9-030, AI9-033, AI9-016 (backend), AI9-034.

---

## Notas
- Comparação por significado, não por nome literal (legado "orders" ≈ ai9 "sales").
- **Duas colisões de nome documentadas**: `Operation` (ai9 = agrupador de marketing ≠ operação de
  risco/estruturada do `sfg`) e `Project` (ai9 = projeto de entrega de conteúdo ≠ projeto de
  crédito do `sfg`). Ambas foram sinalizadas em `.migration-ai9/ai9-conventions.md` §9.
- "remover" = telas + rotas + endpoints + services + models + migrations + nav + config + i18n +
  testes + docs exclusivos da feature. Infra compartilhada permanece.
- Não são ai9-only (existem no legado, entram em *shared* e não nesta lista): autenticação/usuários,
  permissões e trilha de permissão, impersonation, console administrativo, temas, help/FAQ,
  feedback, mailer, upload/anexo, Action Cable, Redis, design system (`components/ui`).
- As remoções são registradas em `.migration-ai9/removed-features.md` e são reversíveis
  (uma task/commit por item).
- Nenhum código foi alterado na produção deste documento.
