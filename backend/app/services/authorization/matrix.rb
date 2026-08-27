# frozen_string_literal: true

module Authorization
  # S0 / BE-079, BE-506 — a matriz de autorização, **declarativa**.
  #
  # Fonte: `.migration-ai9/authorization-matrix.md`, aprovada como CONTRATO em
  # 24/08/2026 (DEC-18). 45 recursos × 4 papéis + 1 modificador
  # (`user_is_readonly`). A **DEC-38** acrescentou o 46º, `contract_versions`.
  #
  # **Nenhum endpoint decide autorização sozinho.** O endpoint chama
  # `authorize!(recurso, ação)`; quem responde é esta tabela. Foi assim que o
  # legado errou: a única autorização que existia estava nos gates das views
  # (D-23), então qualquer requisição fora da tela fazia tudo (D-34).
  #
  # Notação: `C`riar `R`ler `U`pdate `D`elete; `-` = nenhum acesso.
  # A ordem das colunas é sempre **[og, admin, gerente, colaborador]**.
  #
  # Duas coisas que esta tabela NÃO decide, de propósito:
  #  - **escopo por projeto** — é o contrato C1, aplicado no endpoint com
  #    `current_project!`. Ter acesso ao recurso não é ter acesso ao registro;
  #  - **trava de hierarquia** — quem pode editar o papel de QUEM é
  #    `Authorization::Hierarchy`, porque depende do alvo, não só do ator.
  module Matrix
    ACTIONS = %i[read create update destroy].freeze
    ROLE_ORDER = [UserType::OG, UserType::ADMIN, UserType::GERENTE, UserType::COLABORADOR].freeze

    LETTERS = { 'C' => :create, 'R' => :read, 'U' => :update, 'D' => :destroy }.freeze

    RESOURCES = {
      # --- Grupo "Início" — sem gate --------------------------------------
      'dash' => %w[R R R R],

      # --- Grupo "Gestão" — gate `projects.count > 0`, sem gate de papel ---
      # Os quatro papéis entram, desde que participem de algum projeto. O gate
      # de projeto é o C1, não esta tabela.
      'risk' => %w[CRUD CRUD CRUD CRUD],
      'availability' => %w[CRUD CRUD CRUD CRUD],
      'receivables' => %w[CRUD CRUD CRUD CRUD],
      'receivable_taxes' => %w[CRUD CRUD CRUD CRUD],
      'renegotiations' => %w[CRUD CRUD CRUD CRUD],
      'renegotiation_installments' => %w[CRUD CRUD CRUD CRUD],
      'renegotiation_payments' => %w[CRUD CRUD CRUD CRUD],
      'renegotiation_attachments' => %w[CRUD CRUD CRUD CRUD],
      'indicator_entries' => %w[CRUD CRUD CRUD CRUD],
      'risk_operations' => %w[CRUD CRUD CRUD CRUD],
      'risk_operation_extensions' => %w[CRUD CRUD CRUD CRUD],
      'risk_entries' => %w[CRUD CRUD CRUD CRUD],
      'risk_movements' => %w[CRUD CRUD CRUD CRUD],
      'structured_operations' => %w[CRUD CRUD CRUD CRUD],

      # --- Grupo "Projeto" — gate `projects.count > 0` ---------------------
      # DEC-15.1: os 4 itens `locked` do legado nascem HABILITADOS. Produção é
      # a verdade, não a intenção aparente do código.
      'charges' => %w[CRUD CRUD CRUD CRUD],
      'project_availabilities' => %w[CRUD CRUD CRUD CRUD],
      'availability_entries' => %w[CRUD CRUD CRUD CRUD],
      'companies' => %w[CRUD CRUD CRUD CRUD],
      'providers' => %w[CRUD CRUD CRUD CRUD],
      'project_guarantees' => %w[CRUD CRUD CRUD CRUD],
      'indicator_connections' => %w[CRUD CRUD CRUD CRUD],
      'project_indicator_connections' => %w[CRUD CRUD CRUD CRUD],
      'project_to_carrier_connections' => %w[CRUD CRUD CRUD CRUD],
      'risk_controls' => %w[CRUD CRUD CRUD CRUD],
      'remunerations' => %w[CRUD CRUD CRUD CRUD],

      # --- Grupo "Cadastro" — gate og/admin/gerente no legado --------------
      # DEC-18.4: o Colaborador ganha `R` nos catálogos globais. Regra em uma
      # frase: **o menu esconde a tela de administração do catálogo, não o dado
      # do catálogo.** Sem isso, todo dropdown do Colaborador quebra no dia 1.
      'projects' => %w[CRUD CRUD CRUD R],
      'memberships' => %w[CRUD CRUD CRUD R],
      'wallets' => %w[CRUD CRUD CRUD R],
      # DEC-18.3 / decisão #3: Gerente LÊ usuários e convida; não cria nem remove.
      'users' => %w[CRUD CRUD R -],
      'carrier_groups' => %w[CRUD CRUD CRUD R],
      'carriers' => %w[CRUD CRUD CRUD R],
      'segments' => %w[CRUD CRUD CRUD R],
      'sub_segments' => %w[CRUD CRUD CRUD R],
      'indicators' => %w[CRUD CRUD CRUD R],
      'availability_templates' => %w[CRUD CRUD CRUD R],
      # DEC-18.2: OG e Admin. O Gerente NÃO alcança. O Admin só edita papéis de
      # hierarquia inferior à dele — essa parte é `Authorization::Hierarchy`.
      'permissions' => %w[CRUD CRUD - -],
      'movement_kinds' => %w[CRUD CRUD CRUD R],
      'receivable_kinds' => %w[CRUD CRUD CRUD R],
      'resource_sources' => %w[CRUD CRUD CRUD R],
      'risk_operation_types' => %w[CRUD CRUD CRUD R],
      'structured_operation_types' => %w[CRUD CRUD CRUD R],
      'risk_movement_types' => %w[CRUD CRUD CRUD R],
      'project_guarantee_types' => %w[CRUD CRUD CRUD R],
      # `resource_kinds` **NÃO tem linha aqui — DEC-110.** Ela existiu até
      # 26/08/2026 e foi removida ao fechar a S8: o portão T-D7 foi respondido
      # pelo dump de produção — a tabela tem **0 linhas** e **0 de 28.131**
      # `receivable_entries` têm `resource_kind_id`. Os 10 IDs da família estão
      # `dropped` com a evidência no `parity-ledger.md`, não existe tabela, model,
      # endpoint nem item de menu — e um recurso na matriz sem rota atrás é
      # permissão que a tela de PERMISSÕES exibe para algo inalcançável.

      # --- Grupo "Admin" — gate og/admin. O Gerente NÃO entra --------------
      'help_items' => %w[CRUD CRUD - R],
      'help_categories' => %w[CRUD CRUD - R],
      'help_groups' => %w[CRUD CRUD - R],
      'admin_messages' => %w[CRUD CRUD - R],
      'app_themes' => %w[CRUD CRUD - R],

      # --- "Perfil" e "Ajuda" — sem gate ------------------------------------
      'my_account' => %w[RU RU RU RU],
      'faq' => %w[R R R R],
      'help' => %w[R R R R],
      'contracts' => %w[R R R R],
      # DEC-38 — recurso NOVO, o 46º. Publicar versão de contrato é de OG e
      # Admin; Gerente e Colaborador não alcançam. Isto CRIA um gate que nunca
      # existiu: `contracts_controller.rb` do legado tem 101 linhas e zero
      # `before_action`/`may?`/`admin?`/`og?`/`authorize`, e as rotas não têm
      # constraint (achado A-1). **Qualquer autenticado publicava os Termos de
      # Uso.** O recurso `contracts` acima (ler e aceitar) fica exatamente como
      # a matriz aprovou — a decisão acrescenta, não altera.
      'contract_versions' => %w[CRUD CRUD - -],

      # --- Transversais (sem item de menu) ----------------------------------
      'console' => %w[R R R R],
      # DEC-18.3: OG e Admin, este último limitado a hierarquia inferior.
      'impersonation' => %w[CRUD CRUD - -],
      # DEC-77: a trilha GLOBAL é de OG e Admin. O histórico do próprio objeto
      # fica visível a quem vê o objeto — isso é decidido no endpoint do objeto.
      'audit_trail' => %w[R R - -]
    }.freeze

    # Índice montado uma vez: {recurso => {papel => Set[ações]}}.
    TABLE = RESOURCES.each_with_object({}) do |(resource, cells), acc|
      acc[resource] = ROLE_ORDER.each_with_index.to_h do |role, i|
        letters = cells.fetch(i)
        [role, letters == '-' ? Set.new : letters.chars.map { |c| LETTERS.fetch(c) }.to_set]
      end.freeze
    end.freeze

    class UnknownResource < StandardError; end

    module_function

    def resource?(resource)
      TABLE.key?(resource.to_s)
    end

    def resources
      TABLE.keys
    end

    # Recurso desconhecido LEVANTA em vez de negar em silêncio: um typo em
    # `authorize!('recebiveis', :read)` que só devolvesse 403 viraria uma tela
    # quebrada cuja causa ninguém acha.
    def actions_for(role, resource)
      cells = TABLE[resource.to_s]
      raise UnknownResource, "recurso `#{resource}` não está na matriz de autorização (DEC-18)" if cells.nil?

      cells[role.to_s.downcase] || Set.new
    end

    def allow?(role, resource, action)
      actions_for(role, resource).include?(action.to_sym)
    end
  end
end
