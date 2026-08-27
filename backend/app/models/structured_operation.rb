# frozen_string_literal: true

# S8 / **BE-280**…**BE-295**, **DB-280**…**DB-282**, **DB-297**, **DB-581** — a
# **operação estruturada**. Escopada por projeto (contrato C1).
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `20220701125757_create_structured_operations` é uma das **24 migrations que
# nunca subiram** (`analise-dump-producao.md` §1): a última aplicada em produção
# é de **25/05/2022** e o sistema rodou em uso até **31/05/2025**. **Nenhuma
# operação estruturada existiu em produção.**
#
# Tudo abaixo é espelho de `../sfg/app/models/structured_operation.rb`, com
# arquivo e linha, **sem corrigir o que parecer errado** (DEC-103b, confirmada
# pela DEC-105). Onde há golden, ele tem uma **fonte** — a leitura do código de
# 2022 — e **não um oráculo**.
#
# ## As três derivações do `before_validation`, na ordem em que acontecem
#
# `structured_operation.rb:31-39`:
#
# 1. **só no create** (`on: [:create]`): `title` em branco recebe
#    `carrier.title`. Renomear o portador depois **não** mexe no título — é
#    fotografia, não referência;
# 2. **em todo save**: `project_id = company.project_id`. O `project_id` que
#    vier do formulário é sobrescrito, sempre;
# 3. **em todo save**: `original_balance = (-1) * |original_balance|` e, em
#    seguida, `balance = original_balance`.
#
# ## O `balance` é DECORATIVO, e isto é a decisão T-D6 / BE-292
#
# O passo 3 não tem `on:` restrito: **qualquer** update de **qualquer** campo —
# até editar somente a observação — devolve o saldo corrente ao inicial. E a
# varredura do legado inteiro não achou **nenhum** caminho que dê baixa nesse
# saldo: não existe movimento, liquidação nem baixa de operação estruturada
# (diferente de `RiskOperation`, que tem `RiskMovement`).
#
# Ou falta uma feature inteira, ou a coluna é enfeite. **Replicar** é o default
# registrado na tarefa 0.1 e é o que a DEC-103b manda, e o golden **E6** trava
# exatamente isso: editar só a observação faz o `balance` voltar a −50.000,00.
#
# ## O sinal negativo é convenção do legado, REPLICADA (DEC-01)
#
# `original_balance` é sempre gravado negativo. A tela mostra o número com o
# sinal (FE-299, Q-R20). Não "corrija" isso: é a mesma decisão do
# `limite_utilizado_on` do painel de risco.
#
# ## Validações — as AUSÊNCIAS também são replicadas (BE-293)
#
# São obrigatórios empresa, projeto, portador, tipo, usuário, emissão, capital e
# vencimento (`structured_operation.rb:13-20`). **Não** existe, e continua não
# existindo: `due_date >= issue_date`, `operation_value > 0`, faixa de
# `agreed_rate` e unicidade de `contract_number` (Q-R7).
#
# ## `agreed_rate` NÃO é a taxa que remunera
#
# Quem remunera é `remunerations.value`, casada por (projeto, classe, tipo). A
# `agreed_rate` é persistida e exibida e **não entra em nenhum cálculo, filtro,
# relatório ou job** — varredura em BE-295, e há teste documentando a ausência
# (Q-R14). O mesmo vale para `is_on_variable` e `is_ended`; em especial,
# **operação encerrada continua candidata a recibo** (Q-R18, golden E7).
class StructuredOperation < ApplicationRecord
  include ProjectScoped
  include BlockingDependents
  include Auditable

  # `structured_operation.rb:23-27` — os rótulos pt-BR dos dois flags. No legado
  # eram `mattr_accessor` com os pares `[texto, 0|1]` que alimentavam o `select`
  # da tela. Aqui as colunas são boolean (DB-295) e o rótulo vive na
  # apresentação; ficam como constantes porque a tela e o seed os usam.
  ENDED_LABELS = { true => 'Encerrado', false => 'Não encerrado' }.freeze
  ON_VARIABLE_LABELS = { true => 'Considerar no variável', false => 'Não considerar no variável' }.freeze

  belongs_to :company
  belongs_to :carrier
  belongs_to :operation_type, class_name: 'StructuredOperationType', inverse_of: :operations
  # **DB-297 — o autor e o último editor são colunas separadas.** No legado
  # `current_user.id` era forçado no create **e** no update
  # (`structured_operations_controller.rb:71`), então o campo "autor" virava, na
  # prática, "último editor" e a informação original se perdia no primeiro save
  # de outra pessoa. Aqui `user_id` é o autor e `updated_by_id` é o último
  # editor; os dois vêm da SESSÃO e nenhum é aceito no corpo.
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false
  belongs_to :editor, class_name: 'User', foreign_key: :updated_by_id, optional: true, inverse_of: false
  belongs_to :receipt, optional: true, inverse_of: false

  # `structured_operation.rb:10` — a coluna que decide quem pode virar recibo.
  scope :available_for_receipt, -> { where(receipt_id: nil) }

  # `structured_operation.rb:13-20`, uma a uma. A ausência é tão deliberada
  # quanto a presença — ver o cabeçalho.
  validates :company_id, presence: true
  validates :carrier_id, presence: true
  validates :operation_type_id, presence: true
  validates :user_id, presence: true
  validates :issue_date, presence: true
  validates :operation_value, presence: true
  validates :due_date, presence: true

  # BE-290 — `carrier_id` inválido devolve 422, não `NoMethodError`.
  #
  # No legado a derivação de título faz `self.carrier.title` **antes** de
  # qualquer validação (`structured_operation.rb:32`): com um id de portador que
  # não existe, o callback levanta `NoMethodError` em `nil` e a validação de
  # presença — que existe e daria a mensagem amigável — **nunca chega a rodar**.
  # Aqui os dois callbacks toleram a associação ausente e deixam a validação
  # falar.
  before_validation :derive_title_from_carrier, on: :create
  before_validation :derive_project_from_company
  before_validation :reset_balance_from_original

  # BE-287 / FE-292 — operação com recibo emitido **não** é excluída.
  # `structured_operation.rb:7` já declara `dependent: :restrict_with_error`; o
  # que muda é o status: no legado o ternário degenerado
  # `errors.any? ? :ok : :ok` (`structured_operations_controller.rb:108`)
  # respondia **200**, a tela recarregava a lista e a operação continuava lá.
  def self.blocking_dependents
    { 'Receipt' => { foreign_key: :operation_id, label: 'recibo(s)' } }
  end

  # BE-283 / OPS-288 — a allowlist de ordenação.
  #
  # **A chave `company` SAI** (decisão B-13): `structured_operation.rb:76-77` a
  # mapeia para `companies.title`, mas **não há coluna "Empresa" na tela** — nem
  # na lista do legado, nem na do ai9. Chave que nenhuma coluna oferece é chave
  # que só serve para quem monta URL à mão.
  ORDERING = Sfg::Sortable.new(
    allowed: {
      'title' => 'structured_operations.title',
      'operation_type' => 'structured_operation_types.title',
      'carrier' => 'carriers.title',
      'contract_number' => 'structured_operations.contract_number',
      'issue_date' => 'structured_operations.issue_date',
      'operation_value' => 'structured_operations.operation_value',
      'balance' => 'structured_operations.balance',
      'due_date' => 'structured_operations.due_date',
      'agreed_rate' => 'structured_operations.agreed_rate'
    },
    default: { 'structured_operations.issue_date' => :desc }
  ).freeze

  # BE-281 — a busca alcança **portador OU título da operação**, sempre "contém".
  # `structured_operations_controller.rb:30`.
  #
  # **O alcance é replicado, e a limitação junto** (Q-R12): não busca por
  # `contract_number` nem por empresa, embora as duas apareçam na tabela. O que
  # muda é o SQL: o legado interpolava o operador (`Dev.ilike`) e o padrão
  # dentro da string, então `100%` e `a'b` viravam curinga. Aqui o termo é
  # escapado e entra por bind (mesma correção de OPS-056).
  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    joins(:carrier).where('carriers.title ILIKE :q OR structured_operations.title ILIKE :q', q: padrao)
  }

  # BE-282 / OPS-283 — o predicado de período.
  #
  # `structured_operations_controller.rb:31`:
  # `DATE(due_date) >= DATE(from) AND DATE(issue_date) <= DATE(to)` — a operação
  # aparece quando o período **intersecta** o intervalo dela. É a mesma regra de
  # `BE-242` (recebíveis), e a coincidência é a evidência de que não é typo.
  #
  # **A sentinela morre aqui.** O legado, sem `from`/`to`, mandava
  # `DateTime.dinosaurs` e `DateTime.mars` — um monkey-patch de ±2000 anos
  # (`config/initializers/date_time.rb`). O efeito é idêntico para dados com
  # data preenchida; o que muda é que **operação com data nula passa a aparecer**
  # quando não há filtro, em vez de ser excluída em silêncio pelo `DATE(NULL)`
  # (melhoria **IMP-R4**).
  scope :in_period, lambda { |from, to|
    escopo = all
    escopo = escopo.where('DATE(structured_operations.due_date) >= DATE(?)', from) if from.present?
    escopo = escopo.where('DATE(structured_operations.issue_date) <= DATE(?)', to) if to.present?
    escopo
  }

  def has_receipt? = receipt_id.present?

  def ended_label = ENDED_LABELS[is_ended?]
  def on_variable_label = ON_VARIABLE_LABELS[is_on_variable?]

  private

  # `structured_operation.rb:31-33` — **só no create**.
  def derive_title_from_carrier
    return if title.present?
    return if carrier.nil?

    self.title = carrier.title
  end

  # `structured_operation.rb:36` — em TODO save. O `project_id` do corpo é
  # ignorado; quem manda é a empresa.
  #
  # BE-291 registra a consequência: trocar a empresa **move a operação de
  # projeto**, e pode deixar para trás remuneração e recibo emitidos em outro
  # tenant. O mecanismo é replicado; o que o ai9 acrescenta é a **confirmação
  # explícita** no serviço (operação nomeada, não efeito colateral).
  def derive_project_from_company
    return if company.nil?

    self.project_id = company.project_id
  end

  # `structured_operation.rb:37-38` — em TODO save, sem `on:`. Golden **E6**.
  def reset_balance_from_original
    self.original_balance = -(original_balance.to_d.abs)
    self.balance = original_balance
  end
end
