# Tarefa 3.1: Operations Metrics Backend API

**Sprint:** 3 - Operations Admin UI & Bulk Upload
**Estimativa:** 1 dia
**Tipo:** Backend

---

## Contexto
A empresa precisa que a gestão da inteligência da IA (o que o bot sabe de cada Operação) seja gerida por não-desenvolvedores através de um painel web super agradável. Antes de fazermos a UI no React (Tarefa 3.2), o backend precisa prover os endpoints (API REST) administrativos. 
Eles listam todas as Operações, exibem quantas mídias (`OperationAsset`) existem por operação, qual o tamanho/volume em bytes dos bancos de conhecimento (`OperationKnowledge`) inseridos e atalho para o volume de `Leads` daquela Operação. As consultas serão agrupadas.

---

## Onde começa
O backend Grape (`backend/app/controllers/api/v1/`) possui endpoints para `leads` e `chat_flows` mas ainda não expõe rotas focadas de CRM Administrativo para as `Operations` profundas.

## Onde termina
Haverá um "namespace" ou arquivo (`base.rb` -> `admin_operations.rb`) dedicado só à gestão das `Operations` onde requisições autenticadas (JWT) com permissão administrativa conseguem: Adicionar Mídia, Apagar Knowledge, Listar Paginação, Ver a Estatística Centralizada.

---

## O que precisa ser feito

### No Backend

1. **Service `Admin::OperationsService`**:
   No padrão arquitetural de Grape + Service Objects explícito no `spec-rules.md`, crie métodos que consultam a tabela `operations` acompanhadas de contadores:
   - `index`: Retorna `[{ id, name, leads_count, assets_count, total_knowledge_paragraphs, active }]`. O cálculo eficiente das counts para UI (evitar N+1).
   - `show`: Retorna os detalhes da operação inteira.
   - `create_asset` / `destroy_asset`: Permite upar/apagar mídias dessa Operação.
   - `upsert_knowledge`: Modificar os parágrafos ou base de texto longo de uma Operação (acoplado às actions assíncronas do Sprint 1).

2. **Rotas e API Controller Grape**:
   Adicionar no Grape Router (ex: `api/v1/operations.rb` restrito para `requires :admin` JWT auth role):
   - `GET /operations/stats`: Lista agrupada para uma tela de Dashboard inicial (ex: Top 5 Operations mais badaladas por Leads).
   - `GET /operations` (Paginação Padrão, Order by ID).
   - `GET /operations/:id`.
   - `POST /operations/:id/assets` (Múltiplo upload aceito, processando as URL do S3/ActiveStorage devolvendo os shortcodes).
   - `PUT /operations/:id/knowledge`.

3. **Validação de Permissões JWT**:
   Confirmar que um usuário comum/visitante tentando chamar os endpoints resultará sempre em Erro 401/403. Só contas `admin` possuem visibilidade.

### No Frontend
Não se aplica, mas servirá a Tarefa 3.2. Assegure a confecção exata no Swagger UI.

---

## Observações importantes
- Ao calcular médias/counters, opte pelas Cached Counters columns (`leads_count` já existe!) ou construa Counter Caches (`assets_count` etc) nas Models em vez de `count()` no banco para não sobrecarregar listas grandes na visualização de UI.
- No `POST /operations/:id/assets`, aceite o formato de array ou de arquivos nativos Multipart e entregue para o ActiveStorage.

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. O Postman / Stoplight Elements chamando `GET /api/v1/operations` com token JWT Admin e recebendo uma resposta contendo `assets_count: N` e `leads_count: X` formatados no Entitie (JSON Grape).
2. Sem token ou com token básico falhando de imediato com Envelope de Errors `{"code": "unauthorized"...}`.
3. Demonstração de requisição Multipart API que crie *DOIS* Assets duma vez, retornando os `shortcodes` (ex: `[SECURE12, BR3A0]`) no Array do Data Body, e chamando a trigger do embedding background via logs do terminal.

---

## Dependências
- Backend (Toda a Sprint 1 executada e Mergeada).

## Próxima tarefa
Tarefa 3.2: Operations Dashboard UI & Bulk Upload (`spec-024-operations-dashboard-ui.md`)
