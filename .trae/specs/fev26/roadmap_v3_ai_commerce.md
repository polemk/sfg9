# Roadmap V3: Intelligence, Conversion & Flow Mastery
Version: 3.0
Last Updated: February 2026
Focus: Flow Connections, Intelligence (OCR), Seamless Lead Generation, and Account Creation.

---

## 📅 Sprint 1: Flow Connections & User Continuity
*Focus: Enabling complex architectures, seamless redirection, and instant account creation without losing conversation context.*

- [ ] **Tarefa 1.1**: End Node - Flow Handoff (`spec-010-flow-handoff.md`)
  - Conectar fluxos, mantendo variáveis e alterando a mensagem de boas-vindas do novo fluxo.
- [ ] **Tarefa 1.2**: End Node - Redirect & Account Creation (`spec-011-redirect-auth.md`)
  - Redirecionar usuário para páginas/links externos via chat e gerar conta "shadow" para autologin.

## 📅 Sprint 2: Intelligence & Lead Generation
*Focus: Connecting chat data directly to business value and leveraging Claude for image reading.*

- [ ] **Tarefa 2.1**: Save to Lead Node (`spec-012-save-to-lead.md`)
  - Persistir variáveis do chat na tabela `Leads` automaticamente.
- [ ] **Tarefa 2.2**: Image Input & OCR com Claude (`spec-013-image-ocr.md`)
  - Permitir envio de imagem no chat, interpretada e refinada pelo Claude Vision.
- [ ] **Tarefa 2.3**: AI Chat Lead Generator (`spec-014-ai-lead-generation.md`)
  - Permitir que a própria conversa com a IA crie ou atualize Leads no banco de dados com os dados coletados.

## 📅 Sprint 3: Lead Management UI
*Focus: Making the collected leads easy to find, filter, and analyze.*

- [ ] **Tarefa 3.1**: New Lead List Dashboard (`spec-015-lead-list-ui.md`)
  - Interface remodelada para busca de leads recentes, ordenação por tempo, e volume de mensagens.

---

## Documentação de Referência
As especificações detalhadas de cada tarefa encontram-se na pasta `.trae/specs/` seguindo o padrão de nomenclatura `spec-XXX-nome.md`.
