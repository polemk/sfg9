# frozen_string_literal: true

require_relative 'support/rng'
require_relative 'support/br'
require_relative 'support/money'
require_relative 'ledger/records'
require_relative 'ledger/cast'
require_relative 'ledger/timeline'
require_relative 'ledger/controls'
require_relative 'ledger/receivables'
require_relative 'ledger/operations'
require_relative 'ledger/ancillary'
require_relative 'ledger/availability'
require_relative 'ledger/service_desk'
require_relative 'ledger/billing'

module Demo
  # **O razão do seed de demonstração.**
  #
  # Ruby puro, zero ActiveRecord: constrói a história inteira em memória e devolve
  # `Struct`s. Quem grava é o escritor de cada agregado, e é lá — e só lá — que
  # nome de campo vira nome de coluna.
  #
  # Por que assim, e não um seed que escreve direto no banco:
  #
  # 1. **Roda hoje.** A S20 precede S3..S11 (DEC-64). O razão não depende de
  #    nenhum model de domínio existir, então as 7 regras de coerência já são
  #    testáveis — e testadas — antes de a primeira tabela nascer.
  # 2. **A cadeia fecha por construção.** O saldo que o painel mostra e o borderô
  #    que o produziu saem do **mesmo objeto**. Não há como divergirem, porque não
  #    são dois cálculos.
  # 3. **Schema muda barato.** `order` virou `sequence` (DB-236): uma linha no
  #    escritor de movimentos, zero no razão.
  class Ledger
    # A data-base é **parametrizável e relativa**. Nenhuma data literal no razão:
    # o seed não pode envelhecer se a apresentação mudar de dia
    # (`demo-seed-design.md` §10).
    def self.base_date_from_env
      raw = ENV.fetch('DEMO_SEED_BASE_DATE', nil)
      raw.present? ? Date.parse(raw) : Date.current
    rescue ArgumentError
      Date.current
    end

    def initialize(base_date: self.class.base_date_from_env, seed: Support::Rng::SEED,
                   span: Timeline::SPAN)
      @base_date = base_date
      @rng = Support::Rng.new(seed)
      @span = span
      build!
    end

    attr_reader :base_date, :rng, :carriers, :clients, :companies, :controls,
                :months, :borderos, :operations, :structured_operations,
                :renegotiations, :guarantees, :indicator_entries, :providers,
                :static_transfers,
                :remunerations,
                :availability_templates, :availability_entries,
                :admin_messages, :observers, :charges, :span

    def companies_by_client
      @companies_by_client ||= @companies.group_by { |c| c.client.slug }
    end

    def controls_by_client
      @controls_by_client ||= @controls.group_by { |c| c.client.slug }
    end

    def movements
      @movements ||= @operations.flat_map(&:movements)
    end

    def renegotiation_installments
      @renegotiation_installments ||= @renegotiations.flat_map(&:installments)
    end

    def message_notes
      @message_notes ||= @admin_messages.flat_map(&:notes)
    end

    def charge_receipts
      @charge_receipts ||= @charges.flat_map(&:receipts)
    end

    # Os projetos que recebem a árvore de padrões de disponibilidade — todos.
    # Quem fica sem **lançamento** é outra lista (`Availability::WITHOUT_ENTRIES`):
    # grade com as linhas certas e nenhum valor é o estado vazio honesto do
    # painel; grade sem linha nenhuma é tela quebrada.
    def availability_entries_by_client
      @availability_entries_by_client ||= @availability_entries.group_by { |e| e.client.slug }
    end

    # O elenco de usuários de `demo-seed-design.md` §9. Trocar de usuário ao vivo
    # é a forma mais rápida de demonstrar governança — que costuma ser o que
    # decide compra em ferramenta de crédito.
    #
    # A base ai9 **não tem senha**: a entrada é por magic login. Em
    # desenvolvimento o `request_code` devolve o código no corpo da resposta, e é
    # assim que se troca de usuário na apresentação.
    #
    # Os e-mails ficam em domínios `.test` (reservado pela RFC 2606): em
    # desenvolvimento o SMTP é real e `raise_delivery_errors` está ligado —
    # domínio entregável no seed é uma forma de mandar e-mail para estranhos por
    # engano.
    CAST = [
      { key: :og, email: 'suporte@livetat.test', name: 'Suporte Livetat',
        role: 'og', phone: '5548930000001', readonly: false,
        purpose: 'Fornecedor. Permissões e impersonação auditada. NÃO usar na apresentação ao cliente. ' \
                  'Único SEM projeto corrente: demonstra a tela de escolha (409 PROJECT_NOT_SELECTED).' },
      { key: :admin, email: 'helena.moreira@safegold.test', name: 'Helena Prado Moreira',
        role: 'admin', phone: '5511930000002', readonly: false,
        purpose: 'Protagonista da demo. Vê tudo do cliente e administra hierarquia inferior.' },
      { key: :gerente, email: 'gustavo.lins@safegold.test', name: 'Gustavo Lins',
        role: 'gerente', phone: '5511930000003', readonly: false,
        purpose: 'Prova a matriz: vê Cadastro, não vê Admin.' },
      { key: :colab_a, email: 'camila.duarte@safegold.test', name: 'Camila Duarte',
        role: 'colaborador', phone: '5511930000004', readonly: false,
        purpose: 'Escopo por participação — carteira de clientes A.' },
      { key: :colab_b, email: 'rafael.antunes@safegold.test', name: 'Rafael Antunes',
        role: 'colaborador', phone: '5511930000005', readonly: false,
        purpose: 'Escopo por participação — carteira de clientes B, sem interseção com a A.' },
      { key: :readonly, email: 'tereza.machado@safegold.test', name: 'Tereza Machado',
        role: 'colaborador', phone: '5511930000006', readonly: true,
        purpose: 'Prova o modificador `user_is_readonly`: mesmos dados, nenhum botão de escrita.' }
    ].freeze

    # Quem participa de quê. As duas carteiras de colaborador **não se cruzam**:
    # é o que prova, ao vivo, que o escopo vem de `memberships` e não de uma flag.
    MEMBERSHIP_PLAN = {
      admin: { slugs: :all, role: 'responsavel' },
      gerente: { slugs: (1..6), role: 'gestor' },
      colab_a: { slugs: (1..4), role: 'participante' },
      colab_b: { slugs: (7..12), role: 'participante' },
      readonly: { slugs: (1..2), role: 'participante' }
    }.freeze

    def cast
      CAST
    end

    def membership_pairs
      MEMBERSHIP_PLAN.flat_map do |key, plan|
        selected = plan[:slugs] == :all ? clients : clients.select { |c| plan[:slugs].include?(c.index) }
        selected.map { |client| { user_key: key, client: client, role: plan[:role] } }
      end
    end

    def summary
      {
        carriers: carriers.size, clients: clients.size, companies: companies.size,
        controls: controls.size, months: months.size, borderos: borderos.size,
        operations: operations.size, movements: movements.size,
        structured_operations: structured_operations.size,
        static_transfers: static_transfers.size,
        providers: providers.size,
        renegotiations: renegotiations.size,
        renegotiation_installments: renegotiation_installments.size,
        guarantees: guarantees.size, indicator_entries: indicator_entries.size,
        availability_templates: availability_templates.size,
        availability_entries: availability_entries.size,
        admin_messages: admin_messages.size, message_notes: message_notes.size,
        observers: observers.size,
        remunerations: remunerations.size,
        charges: charges.size, charge_receipts: charge_receipts.size
      }
    end

    private

    def build!
      @carriers = Cast.carriers
      @clients = Cast.clients(@base_date)
      @companies = @clients.flat_map { |client| Cast.companies_for(client) }
      @controls = Controls.build(@clients, companies_by_client, @rng)
      @months = Timeline.months(@base_date, @rng, span: @span)
      @borderos = Receivables.build(@clients, @controls, @months, @base_date, @rng)
      @operations = Operations.build(@controls, @months, @base_date, @rng)
      @structured_operations = Operations.build_structured(@controls, @months, @base_date, @rng)
      @static_transfers = Operations.static_transfers(@controls, @base_date, @rng)
      @renegotiations = Ancillary.renegotiations(@clients, companies_by_client, @base_date, @rng)
      @renegotiations.each { |r| r.installments.each { |i| i.renegotiation = r } }
      @providers = Ancillary.providers(@clients, @renegotiations, @rng)
      @guarantees = Ancillary.guarantees(@clients, @controls, @rng)
      @indicator_entries = Ancillary.indicator_entries(@clients, @months, @borderos, @operations)
      @availability_templates = Availability.templates
      # Janela curta = grade de amostra. Ver `Availability.entries`: a cascata de
      # derivados do model custa ~10 gravações por folha, e o spec que roda o
      # seed inteiro por exemplo não pode pagar 1.716 delas.
      @availability_entries = Availability.entries(
        @clients, companies_by_client, @base_date, @rng,
        sample: @span < Timeline::SPAN
      )
      @admin_messages = ServiceDesk.messages(@base_date, CAST)
      @observers = ServiceDesk.observers
      # A tabela de preço vem **antes** dos pacotes: é dela que sai a taxa de
      # cada recibo (`Billing.fee_for`), como no `Charges::ReceiptGenerator`.
      @remunerations = Billing.remunerations(@clients, @controls, @structured_operations, @rng)
      @charges = Billing.build(@clients, @operations, @base_date, @rng,
                               remunerations: @remunerations,
                               structured_operations: @structured_operations)
    end
  end
end
