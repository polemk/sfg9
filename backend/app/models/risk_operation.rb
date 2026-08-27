# frozen_string_literal: true

# **Model criado na S5, de propriedade compartilhada — leia antes de mexer.**
#
# A tabela `risk_operations` (DB-235) e o comportamento da operação (CRUD,
# renovação, prorrogação, encerramento, recálculo da cadeia de movimentos,
# integração com recebível e recibo, telas) são da **S7**. O que está aqui é o
# mínimo de que a **S5** precisa para existir, porque a S5 roda antes:
#
# | O que | ID | Fatia |
# | ----- | -- | ----- |
# | `#balance_on` — saldo numa data | **BE-266** | **S5** |
# | `is_static` e o predicado da janela | **OPS-233** (B-08) | **S5** |
# | par estático aberto pelo limite | **BE-241** | **S5** |
# | tudo o mais | BE-253..BE-268 | S7 |
#
# **S7: acrescente, não reescreva.** Este arquivo não tem CRUD, não tem
# `after_create` de liberação de recurso, não tem `update_values` e não tem
# renovação — é onde o seu trabalho entra.
#
# ### B-08 — `is_static` no lugar das sentinelas de ±2000 anos
#
# O legado mantém o par pré/antecipação dentro de toda janela de data usando
# `DateTime.dinosaurs` (ano −2000) e `DateTime.mars` (ano +2000)
# (`../sfg/app/models/risk_control.rb:32-33,49-50`). Sentinela é um bug
# esperando o calendário: entra em qualquer consulta por intervalo e produz
# absurdo em qualquer soma de prazo. Aqui as datas do par são **nulas** e o
# predicado da janela é `is_static OR (issue_date <= d AND due_date >= d)` —
# mesmo conjunto de resultados, sem data falsa no banco.
#
# ### DEC-01 — `original_balance` é gravado NEGATIVO
#
# `self.original_balance = (-1) * self.original_balance.abs`
# (`../sfg/app/models/risk_operation.rb:34`). O formulário mostra positivo e o
# banco guarda negativo; é a convenção de sinal do legado, **replicada**. Golden
# `L1` trava.
class RiskOperation < ApplicationRecord
  # DEC-59 / DEC-78 — `Sfg::AuditTrail::VERSIONED` declara esta linha (fatia S7).
  # A inclusão entra junto com o model, e não depois: o spec de contrato da
  # trilha reprova model declarado que exista sem `include Auditable`, e deixar
  # para a S7 significaria a base rodar sem trilha na operação de risco no meio
  # do caminho.
  include Auditable
  # **C1, peça 4** — `for_project` explícito, nunca `default_scope`. Substitui o
  # `belongs_to :project` solto que a S5 declarou: o marcador
  # `RiskOperation.project_scoped?` é o que o spec de contrato do escopo lê, e
  # sem ele a operação de risco ficava de fora da conferência automática.
  include ProjectScoped

  belongs_to :company
  belongs_to :carrier
  belongs_to :risk_control
  belongs_to :operation_type, class_name: 'RiskOperationType',
                              foreign_key: :operation_type_id, inverse_of: false
  belongs_to :operation_subtype, class_name: 'RiskOperationSubtype',
                                 foreign_key: :operation_subtype_id, optional: true, inverse_of: false
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false
  belongs_to :pair_operation, class_name: 'RiskOperation', foreign_key: :pair_id,
                              optional: true, inverse_of: false
  # S7 — a operação nascida de um borderô, e a raiz da cadeia de renovações.
  belongs_to :receivable, class_name: 'ReceivableEntry', foreign_key: :receivable_id,
                          optional: true, inverse_of: :risk_operation
  belongs_to :original_operation, class_name: 'RiskOperation', foreign_key: :original_id,
                                  optional: true, inverse_of: :renovations

  has_many :movements, class_name: 'RiskMovement', foreign_key: :risk_operation_id,
                       dependent: :destroy, inverse_of: :risk_operation
  # `original_id` aponta SEMPRE para a raiz (`create_renovation` faz
  # `original.original_id || original.id`), então esta associação devolve a
  # cadeia inteira, não só o elo seguinte.
  has_many :renovations, class_name: 'RiskOperation', foreign_key: :original_id,
                         dependent: :nullify, inverse_of: :original_operation
  has_many :extensions, class_name: 'RiskOperationExtension', foreign_key: :risk_operation_id,
                        dependent: :destroy, inverse_of: :operation
  # `restrict_with_error` é o legado (`../sfg/app/models/risk_operation.rb:12`):
  # operação já faturada não se apaga. A diferença é que aqui o erro **chega à
  # tela** — no legado o controller respondia `errors.any? ? :ok : :ok` (D-98).
  has_one :receipt, class_name: 'Receipt', foreign_key: :operation_id,
                    dependent: :restrict_with_error, inverse_of: false

  # ---------------------------------------------------------------------
  # S7 — a cascata de criação. A ORDEM destas cinco linhas é o comportamento.
  # ---------------------------------------------------------------------
  # `../sfg/app/models/risk_operation.rb:20-36`: dois `before_validation`, o
  # primeiro só no create e o segundo em TODO save. Estão separados aqui pelo
  # mesmo motivo — carimbar `original_due_date` a cada save apagaria o histórico
  # de prorrogação assim que a operação fosse editada.
  before_validation :resolve_risk_control, on: :create      # BE-261
  before_validation :stamp_original_due_date, on: :create    # BE-261
  before_validation :fallback_title_to_carrier, on: :create  # BE-261
  before_validation :inherit_project_from_company            # legado :28
  before_validation :reconcile_type_and_subtype              # BE-262 (DEC-67)
  before_validation :normalize_original_balance              # BE-263 (DEC-01)
  before_validation :refresh_balance_cache                   # BE-265

  after_create :create_release_movement                      # BE-264

  # **BE-267 — replicar as ausências.** A lista abaixo é literalmente
  # `../sfg/app/models/risk_operation.rb:54-62`. O que **não** está lá é o que
  # importa (**Q-R7**, default "replicar"):
  #
  # - **não há** `due_date >= issue_date` — operação com vencimento anterior à
  #   emissão continua sendo aceita;
  # - **não há** `operation_value > 0` — operação de capital zero entra.
  #
  # As duas ausências são propositais e têm teste que as trava. Acrescentar
  # qualquer uma delas passa a recusar dado que hoje entra, e isso é decisão de
  # usuário, não de implementação.
  # `project_id` já vem do `ProjectScoped`.
  validates :company_id, :carrier_id, :risk_control_id, :operation_type_id, presence: true
  validates :operation_value, presence: true
  # `user_id` é `validates presence` no legado (`:58`). No ai9 ele vem sempre de
  # `current_user` no serviço; o par estático da S5 herda o do limite.
  validates :user_id, presence: true, unless: :is_static?
  # A janela é obrigatória, EXCETO no par estático — o mesmo que o check
  # constraint do banco diz. As duas camadas existem de propósito.
  validates :issue_date, :due_date, presence: true, unless: :is_static?
  validate :static_operations_have_no_dates

  scope :static, -> { where(is_static: true) }
  scope :ended, -> { where(is_ended: true) }
  scope :not_ended, -> { where(is_ended: false) }
  # `../sfg/app/models/risk_operation.rb:2` — o que a S8 usa para listar o que
  # ainda pode ser faturado (`operation_class` da classe LIQ, BE-304/BE-306).
  scope :available_for_receipt, -> { where(receipt_id: nil) }

  # **BE-253** — a busca da lista. `carriers.title` **ou** `risk_operations.title`
  # (`../sfg/app/controllers/pub/risk_operations_controller.rb:30`). O legado
  # interpolava a string direto; aqui é bind + `sanitize_sql_like` (DEC-05).
  # Quem chama precisa ter o `joins(:carrier)` — a lista tem.
  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{sanitize_sql_like(termo)}%"
    where('carriers.title ILIKE :p OR risk_operations.title ILIKE :p', p: padrao)
  }

  # **BE-253 / FE-254 — a allowlist de ordenação.**
  #
  # As chaves são as do legado (`get_ordering_key`, `:169-193`). Duas notas:
  #
  # - `company` e `contract_number` existiam lá e continuam aqui — o `tasks.md`
  #   lista oito chaves e o legado tem dez; tirar duas reduziria a tela sem
  #   motivo, e as duas já vêm com `joins`;
  # - **chave desconhecida devolve 400**, e não 500. No legado
  #   `get_ordering_key` devolve `nil` para o que não está no `case` e a linha
  #   seguinte faz `nil + " "` → `NoMethodError`: um `?ordering_keys[]=x`
  #   digitado na barra de endereço derruba a listagem. O endpoint usa
  #   `ORDERING.rejected` para responder o 400 com a chave nomeada.
  ORDERING = Sfg::Sortable.new(
    allowed: {
      'title' => 'risk_operations.title',
      'company' => 'companies.title',
      'carrier' => 'carriers.title',
      'operation_type' => 'risk_operation_types.title',
      'contract_number' => 'risk_operations.contract_number',
      'issue_date' => 'risk_operations.issue_date',
      'operation_value' => 'risk_operations.operation_value',
      'balance' => 'risk_operations.balance',
      'due_date' => 'risk_operations.due_date',
      'agreed_rate' => 'risk_operations.agreed_rate'
    },
    default: { 'risk_operations.issue_date' => :desc }
  ).freeze

  # **BE-242 / OPS-233** — a janela temporal. Intervalo FECHADO nos dois lados,
  # exatamente como o legado (`DATE(due_date) >= DATE(?) AND DATE(issue_date) <= DATE(?)`),
  # mais o ramo `is_static` que substitui a sentinela.
  #
  # **Operação encerrada (`is_ended`) continua entrando** — não há filtro por
  # encerramento aqui, e isso é DEC-35: o ciclo de vida do legado é replicado.
  scope :on_date, lambda { |date|
    d = date.to_date
    where('risk_operations.is_static = TRUE OR ' \
          '(DATE(risk_operations.due_date) >= DATE(:d) AND DATE(risk_operations.issue_date) <= DATE(:d))',
          d: d)
  }

  # **BE-266 — o saldo numa data.**
  #
  # Réplica literal de `../sfg/app/models/risk_operation.rb:92-96`: o **último**
  # movimento com `DATE(date) <= DATE(d)`, ordenado por `date asc, created_at asc`.
  #
  # **Sem movimento devolve 0 — NÃO `original_balance`.** Esta é a linha mais
  # fácil de "consertar sem querer" do bloco inteiro: parece esquecimento e não
  # é. O par estático nasce sem movimento nenhum, logo o saldo inicial
  # configurado no limite **não entra** em nenhum agregado até que alguém lance
  # um movimento. É assim que o painel calcula hoje. Golden `L2` trava.
  # A leitura em si vive em `Risk::BalanceReader`, e **de propósito**: é a mesma
  # implementação que o agregado usa em lote. Uma versão "de uma operação" e
  # outra "de várias" seriam duas leituras que podem divergir — exatamente o que
  # o contrato C2 existe para impedir.
  def balance_on(date = Date.current)
    Risk::BalanceReader.balance_for(self, date)
  end

  def has_pre_faturamento?
    operation_type&.has_pre_faturamento? || false
  end

  def is_pre?
    operation_subtype&.is_pre? || false
  end

  private

  # **BE-261** — o limite consumido, resolvido pela QUÁDRUPLA
  # (projeto, empresa, portador, tipo). `../sfg/app/models/risk_operation.rb:21`.
  #
  # **Sem filtrar `is_active` — e isso é replicação deliberada.** É possível
  # abrir operação sobre limite desativado, e a DEC-105 acabou de confirmar o
  # critério: 457 dos 767 limites entram desativados na carga, e recusar
  # operação neles mudaria o produto sem ninguém ter decidido.
  #
  # `unless rk.blank?` também é literal: quando não há limite, o campo fica nulo
  # e a validação de presença recusa. O que muda é a **mensagem** — no legado o
  # operador via "Risk control não pode ficar em branco".
  def resolve_risk_control
    return if risk_control_id.present? && is_static?

    rk = RiskControl.where(project_id: project_id, company_id: company_id,
                           carrier_id: carrier_id, risk_operation_type_id: operation_type_id).first
    if rk.blank?
      return if risk_control_id.present?

      errors.add(:risk_control_id,
                 'não existe limite cadastrado para esta combinação de empresa, portador e tipo de operação.')
      return
    end

    self.risk_control_id = rk.id
  end

  # `original_due_date = due_date` **só no create** (`:23`). É a data contra a
  # qual a primeira prorrogação compara.
  def stamp_original_due_date
    self.original_due_date = due_date
  end

  # `:24` — título vazio cai para o nome do portador.
  def fallback_title_to_carrier
    return if title.present?

    self.title = carrier&.title
  end

  # `:28` — o projeto vem da EMPRESA, em todo save. Replicado: é o que mantém
  # coerente o dado histórico. O gate de tenant continua sendo o endpoint (C1),
  # que só aceita empresa do projeto corrente — esta linha não é autorização.
  def inherit_project_from_company
    return if company.nil?

    self.project_id = company.project_id
  end

  # **BE-262 — tipo ↔ subtipo.** `../sfg/app/models/risk_operation.rb:29-33`.
  #
  # Duas metades:
  #
  # 1. **Subtipo informado SOBRESCREVE o tipo** — literal do legado. Mandar
  #    tipo A com subtipo de B grava o tipo de B.
  # 2. **Sem subtipo informado, entra o padrão do tipo (DEC-67).** O legado
  #    fazia `subtypes.where(...).pluck(:id).first` **sem `order`**, ou seja,
  #    ordem de inserção de linhas num cadastro — e o subtipo decide o *bucket*
  #    (liquidável × pré) que aparece somado no painel.
  #
  # **A DEC-67 vence a tarefa 2.2 do `tasks.md`**, que mandava recusar com 422
  # pedindo escolha explícita (T-D3). O usuário decidiu depois: o tipo passa a
  # declarar `is_default_for_type`, e o valor semeado **reproduz o que o
  # `.first` escolhia** (o "pré" nasce antes). Nada muda para quem já opera; o
  # que muda é que a classificação deixa de depender da ordem das linhas.
  # `RiskOperationType#default_subtype` é onde isso mora — implementado na S5.
  #
  # Tipo sem subtipo nenhum continua sendo recusado, e com erro explicativo:
  # sem subtipo a operação não tem bucket.
  def reconcile_type_and_subtype
    if operation_subtype.present?
      self.operation_type_id = operation_subtype.risk_operation_type_id
      return
    end

    return if operation_type.nil?

    padrao = operation_type.default_subtype
    if padrao.nil?
      errors.add(:operation_subtype_id,
                 "o tipo «#{operation_type.title}» não tem nenhum subtipo cadastrado. " \
                 'Sem subtipo a operação não entra em nenhum bucket de limite.')
      return
    end

    self.operation_subtype_id = padrao.id
  end

  # **BE-263 / DEC-01** — `original_balance = -(|original_balance|)` em TODO
  # save (`../sfg/app/models/risk_operation.rb:34`). O formulário mostra
  # positivo, o banco guarda negativo, e o detalhe exibe o negativo (FE-265).
  # A melhoria foi **declinada pelo usuário**; está no `improvements-log.md`.
  def normalize_original_balance
    return if original_balance.nil?

    self.original_balance = -1 * original_balance.abs
  end

  # **BE-265** — `update_values` (`:35`, corpo em `:98-111`): o recálculo roda
  # no `before_validation` de TODO save, e o saldo final vira o cache
  # `risk_operations.balance`.
  def refresh_balance_cache
    self.balance = Risk::Calculator.recalculate_chain(self)
  end

  # **BE-264** — `after_create` (`:39-52`): tipo **sem** pré-faturamento nasce
  # com o movimento "Liberação do Recurso" de `operation_value` na data de
  # emissão.
  #
  # Duas diferenças em relação ao legado, e as duas são decisão registrada:
  #
  # - **a resolução do tipo é por `integration_key`** (B-09, S5), não por título
  #   literal. No legado, renomear "Liberação do Recurso" pela tela de
  #   administração quebrava a criação de operações com `NoMethodError` em
  #   `nil.id`. `RiskMovementType.release` levanta erro de negócio nomeando a
  #   chave — e levanta **dentro** da transação do `create`, então a operação
  #   não fica gravada sem o movimento;
  # - **operação estática nunca ganha movimento**. No legado isso decorria de o
  #   par estático só existir em tipo COM pré-faturamento; aqui está escrito,
  #   porque é o que sustenta `balance_on == 0` do golden `L2` da S5.
  # ### Por que `create` e não `create!` — decisão registrada, não descuido
  #
  # O legado usa `RiskMovement.create` **sem bang** (`:41`). Existe um caminho
  # real em que esse movimento é **inválido**: quando `due_date < issue_date`,
  # que o `BE-267`/Q-R7 manda **continuar aceitando** (o legado não valida a
  # ordem das datas). Nesse caso a janela de `BE-274` recusa o movimento de
  # liberação — e no legado a operação **é gravada mesmo assim, sem movimento**,
  # em silêncio.
  #
  # `create!` aqui recusaria a operação inteira com 422, o que é *mais correto*
  # e **não é o espelho**. A **DEC-103b** manda espelhar o código de 2022 como
  # está, e a **DEC-105** confirmou o critério mesmo quando a consequência é
  # visível. Então: `create`, com o motivo em log — silencioso para o usuário,
  # como no legado, mas rastreável para quem for investigar.
  #
  # **O que continua levantando é o tipo funcional ausente** (B-09): ali o erro
  # é de configuração do sistema, não de dado do usuário, e `RiskMovementType.release`
  # levanta `MissingFunctionalType` **dentro** da transação do `create` — a
  # operação não fica gravada sem o movimento por falta de catálogo.
  def create_release_movement
    return if is_static?
    return if operation_type.nil? || operation_type.has_pre_faturamento?

    movimento = RiskMovement.create(
      user_id: user_id,
      date: issue_date,
      movement_type_id: RiskMovementType.release.id,
      movement_value: operation_value,
      balance: 0,
      project_id: project_id,
      company_id: company_id,
      carrier_id: carrier_id,
      risk_operation_id: id
    )
    return if movimento.persisted?

    Rails.logger.warn(
      "[risk_operation #{id}] movimento de liberação recusado e NÃO gravado " \
      "(espelho do legado, `RiskMovement.create` sem bang): #{movimento.errors.full_messages.to_sentence}"
    )
  end

  def static_operations_have_no_dates
    return unless is_static?
    return if issue_date.nil? && due_date.nil?

    errors.add(:base, 'Operação estática não tem data de emissão nem de vencimento (B-08).')
  end
end
