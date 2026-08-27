# Tarefa 028.3: Gerenciamento de Canais na UI

**Sprint:** 1 - Fundações Omnichannel (Hub Meta)
**Estimativa:** 1.5 dia(s)
**Tipo:** Frontend + Backend (API Simples)

---

## Contexto
O usuário precisará conectar ativamente as diferentes plataformas que sua clínica ou negócio operam. O Admin precisa informar o Access Token da Meta, o identificador do Instagram e/ou do Whatsapp, bem como ter sua instância velha da Evolution migrada visualmente. Em vez de hardcodar ou deixar no Level Global de ENV, cada workspace gerenciará suas chaves via plataforma React do AI9. Isso prepara o terreno para clientes Self-Service conectarem suas páginas sem depender da equipe técnica.

---

## Onde começa
- Tabela `Integrations` no DB Backend. (Spec 028.1)
- O React Frontend não possui tela para gerenciar os canais conectadores. Toda a lógica era implícita ligada diretamente a 'Devices/Instances' da Evolution.

## Onde termina
- O Frontend possuirá a tela `/admin/integrations`.
- Essa tela lista os Canais Ativos do Bot/Account em "Cards".
- Botão "Adicionar Canal" com forms para meta e evolution.
- API REST Grape `GET/POST/PUT /api/v1/integrations` funcionando e amarrando com a UI.

---

## O que precisa ser feito

### No Backend (Grape API)
1. **CRUD Simples:**
   - Criar `app/controllers/api/v1/integrations.rb`.
   - `GET /api/v1/integrations`: Listar todas da conta.
   - `POST /api/v1/integrations`: Criar nova (validando enum provider/platform e obrigatoriedade de token/external_id dependendo da plataforma).
   - `PUT /api/v1/integrations/:id`: Atualizar status ou atualizar o token de acesso.
   - `DELETE /api/v1/integrations/:id`: Soft delete ou Hard delete pra desligar o canal.

### No Frontend (React)
1. **Criação da Página:**
   - Gerar os types/interfaces a partir do Swagger (usando a padronização do projeto `lib/api/endpoints.ts`).
   - Implementar rota `/admin/integrations`.
2. **Design Visual (Cards):**
   - Utilizar Tailwind + Shadcn/ui existentes.
   - Card individual com a logo da plataforma (WhatsApp, Meta/Ig, Evolution), indicando status ativo/inativo e o `external_id` cadastrado.
3. **Formulários de Conexão:**
   - "Conectar Instagram": Abre um Drawer ou Dialog (`shadcn`) solicitando 2 campos para digitação manual: "Access Token (Meta System User)" e "Instagram Page ID".
   - "Conectar WhatsApp Oficial": Drawer que pede "Access Token" e "Phone Number ID".
   - (Atenção: Não implementaremos OAUTH completo Meta login nesta sprint, é input manual).
4. **Estado / Mutators:**
   - Usar Hooks do `react-query` (mutations) com Feedback visual (Toasts de sucesso/erro).

---

## Observações importantes
- Essa modelagem elimina o código customizado solto e unifica no painel do administrador como Canais.
- Tokens gerados via Meta Business Manager são Strings LONGAS (text no DB). O campo input do frontend deve ser tipo password ou ocultável (simulando chave de segurança).

---

## Critérios de aceite
O dev deve demonstrar que:
1. Ao abrir o painel `/admin/integrations`, ele carrega os registros vazios e uma opção para adicionar Canais.
2. Conseguimos criar um novo canal "Instagram" informando os valores arbitrários via interface web.
3. Ao recarregar a tela, a lista de integrações reflete corretamente os dados cadastrados vindo da API e salvos no Database (validando a integração FB>DB>API>UI).

---

## Dependências
- Backend Spec 028.1 Migration rodada.

## Próxima tarefa
- **Fim da Sprint 1.** 
- Início da Sprint 2 com **Tarefa 029.1** em diante para injetar novos tipos de mensagens (Comments) no Hub desenvolvido aqui.
