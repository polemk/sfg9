# frozen_string_literal: true

# S11 / BE-122..131, DB-123..127, DB-567 — **o lançamento de disponibilidade**:
# a célula da grade (padrão × data × empresa).
#
# ## Este arquivo é o motor de números da fatia, e ele é uma RÉPLICA
#
# Quatro decisões do usuário governam tudo aqui, e as quatro dizem **replicar**:
#
# | DEC | O que ficou como está no legado |
# | --- | ------------------------------- |
# | **DEC-24** | o **decaimento composto** da correção por dias úteis (D-02): `original_value` é regravado a cada alteração de `value`, e a correção multiplica de novo. Salvar a mesma célula duas vezes produz números diferentes |
# | **DEC-26** | as **duas semânticas de soma** na mesma tela (D-08): a consolidação geral soma **bruto**; o nó com filhos aplica `is_cumulative` e o sinal de débito. A tela **rotula** cada uma — o rótulo não é cosmético, ele **é** a decisão |
# | **DEC-27** | as **duas métricas de "total"**: o total geral usa `value`, o card de padrão base usa `virtual_value`. Nenhum número muda; muda o rótulo ("Total bruto" × "Saldo acumulado") |
# | **DEC-28** | **dias úteis sem feriados** (D-03) |
#
# Todas amparadas pelo **DEC-30** (princípio governante: o legado é sistema
# validado). Os golden tests em `spec/models/availability_entry_spec.rb` não
# existem para provar que as fórmulas estão certas — existem para **reprovar
# quem as "consertar"** sem passar por uma DEC nova.
#
# ## O que MUDA em relação ao legado, e por quê
#
# 1. **Ler a grade nunca cria registro** (DC-30, BE-130). Os derivados —
#    consolidação, nó pai, níveis seguintes — continuam sendo materializados,
#    mas **só na gravação**, que é onde o legado também os materializava. O que
#    sai é o `parent_entry` chamado **antes** do `destroy` no controller
#    (`availability_entries_controller.rb:58`), que criava o pai justamente
#    quando o usuário estava apagando (DC-26).
# 2. **A cascata é atômica e tem guarda de ciclo** (BE-129). O legado fazia
#    saves recursivos + `import … validate: false` **sem transação**.
# 3. **A marca de consolidação é explícita** (`is_consolidation`, DB-126), não
#    inferida de `company_id IS NULL` — a rotina `fix__7412` do legado
#    reatribuiu empresa nula à primeira empresa e destruiu essa inferência.
# 4. **`operation_type` é conjunto fechado** (DC-28): no legado qualquer código
#    fora de `C`/`D`/`S`/`M` era somado como **crédito**.
#
# ## `Entry`, a base de lançamento (DB-567) — FECHADA em 26/08/2026
#
# O contrato **C4** dá a base abstrata `Entry` e o vocabulário de situação à
# **S6** (`ReceivableEntry`). A S6 entregou `app/models/entry.rb`, e a tarefa
# **F.2** da S11 passou a ser o que sempre foi: **uma linha**. Esta classe
# herda de `Entry` e continua **sem definir situação nenhuma** — nem coluna,
# nem enum, nem uma segunda cópia das strings.
#
# **O que a herança dá, e o que ela deliberadamente NÃO dá:**
#
# - dá o de-para único `Entry::LEGACY_STATUS_LABELS` (`OK` / `Diferença`), o
#   mesmo objeto congelado que `ReceivableEntry` usa. É isso que a tarefa pede
#   ao dizer "o valor persistido é o mesmo dos recebíveis": não existe uma
#   segunda tabela de tradução que possa divergir da primeira;
# - **não** dá coluna `status` a `availability_entries`, que não tem nem nunca
#   teve situação — a célula da grade é valor, não título a conferir. Criar a
#   coluna para "usar a herança" seria feature nova travestida de paridade
#   (DEC-09), e a tarefa manda o contrário: herdar **sem** redefinir situação.
#
# `Entry` é `abstract_class`, então a herança não traz STI nem coluna `type`:
# a tabela continua sendo `availability_entries`.
class AvailabilityEntry < Entry
  include SafegoldStamped
  safegold_stamp_source :project

  include ProjectScoped

  belongs_to :company, optional: true
  belongs_to :availability_template, class_name: 'ProjectAvailabilityTemplate',
                                     inverse_of: :entries
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :date, presence: true
  validates :value, presence: true, numericality: true
  validates :availability_template_id, presence: true

  validate :template_must_belong_to_project
  validate :company_must_belong_to_project

  # **Chave do ETL — mesmo desenho de `preserve_safegold_stamp` (DEC-112).**
  #
  # `true` desliga os três callbacks que **derivam** valor nesta classe. Existe
  # porque o ETL grava por `record.save!`, e os callbacks daqui foram escritos
  # para o uso INTERATIVO (o usuário digita uma célula, o resto da grade se
  # ajusta) — não para carregar verdade histórica.
  #
  # Na carga eles fazem três estragos, medidos no dump de 31/05/2025:
  #
  #  1. `propagate_derived_values` **cria linhas que a origem já tem**. Gravar o
  #     lançamento `id=3` fazia o `refresh_next_base_entries` materializar o
  #     padrão base seguinte (`Saldo Liquido 2`, 01/03/2022) com `legacy_id`
  #     NULO; logo depois o motor lia o `id=4` — que É aquela linha —, não a
  #     encontrava pelo `legacy_id` e inseria a segunda, batendo no
  #     `index_availability_entries_unique_consolidation`. A origem NÃO tem
  #     duplicata (0 grupos em 23.674 linhas): a duplicata era fabricada aqui.
  #  2. `recompute_and_save!` **recalcula** `virtual_value` — e a DEC-24 manda
  #     COPIAR. Reaplicar a correção por dias úteis sobre um valor já corrigido
  #     N vezes, com N desconhecido, é exatamente o que a decisão proíbe.
  #  3. `mark_consolidation` marcaria **todas** as 23.674 linhas como
  #     consolidação (em produção não existe a coluna `company_id`), anulando a
  #     regra do conversor. Consolidação no ai9 é derivada e **não editável**: o
  #     cliente abriria a grade e não conseguiria digitar em célula nenhuma.
  #
  # Desligar é fiel, e não uma facilidade: a origem já contém CADA linha
  # derivada como linha própria — foi este mesmo callback que as gravou, no
  # legado, ao longo de três anos. Copiá-las reproduz o estado de produção;
  # recalculá-las o substitui por um estado que nunca existiu.
  #
  # Ligada por `Sfg::Etl::Converters::Base#write!`. Nenhum caminho de aplicação
  # a liga — o `title` continua sendo reescrito pelo padrão, porque ele é
  # `derived` declarado do conversor e não depende de valor.
  attr_accessor :etl_loading

  before_validation :mark_consolidation
  before_validation :copy_title_from_template
  before_validation :apply_legacy_value_pipeline

  after_save :propagate_derived_values

  scope :for_date, ->(date) { where(date: date) }
  scope :consolidation, -> { where(is_consolidation: true) }
  scope :by_company, ->(company_id) { where(company_id: company_id) }

  # Chave de recursão do `propagate_derived_values`. `Thread.current` porque a
  # cascata acontece dentro de uma requisição ou de um job, e o conjunto precisa
  # morrer com ela.
  CASCADE_GUARD_KEY = :sfg_availability_cascade_guard

  # ---------------------------------------------------------------------
  # Papéis da célula
  # ---------------------------------------------------------------------

  # A linha de **consolidação geral** do projeto (`mirror?` no legado). Marca
  # explícita, não inferência por `company_id` nulo (DB-126).
  def consolidation? = is_consolidation?

  def adjusted? = availability_template&.is_adjusted?

  # ---------------------------------------------------------------------
  # As fórmulas — réplicas de `availability_entry.rb:186-215`
  # ---------------------------------------------------------------------

  # **DEC-26, metade 1: a consolidação geral soma BRUTO.** Ignora
  # `is_cumulative` e ignora o sinal de débito, ao contrário do nó com filhos
  # logo abaixo. É o **D-08**, preservado de propósito; o que impede a
  # divergência de virar defeito silencioso é o rótulo na tela.
  def sibling_company_entries
    return AvailabilityEntry.none unless consolidation?

    AvailabilityEntry.where(project_id: project_id, date: date,
                            availability_template_id: availability_template_id)
                     .where.not(company_id: nil)
  end

  # Os filhos que entram na soma deste nó: padrões **ativos ignorando bloqueio**
  # (`ignore_lock_active_child_templates` no legado), mesma data, mesmo projeto,
  # mesma empresa.
  def child_entries
    filhos = availability_template&.children_for_sum
    return AvailabilityEntry.none if filhos.nil?

    AvailabilityEntry.where(availability_template_id: filhos.select(:id),
                            date: date, project_id: project_id, company_id: company_id)
  end

  def children?
    return false if availability_template.nil?

    availability_template.has_children? || child_entries.exists?
  end

  # `update_value` do legado, linha a linha.
  def recompute_value
    if consolidation?
      # Soma bruta — DEC-26.
      self.value = sibling_company_entries.sum(:value)
    elsif children?
      # **DEC-26, metade 2**: aqui `is_cumulative` e o sinal de débito valem.
      # Nó não cumulativo contribui **zero**; nó folha de débito entra negativo;
      # nó intermediário entra pelo próprio `value`, **sem** o sinal — que é o
      # que `availability_entry.rb:191` faz, e é replicado como está.
      self.value = child_entries.includes(:availability_template).sum do |filho|
        padrao = filho.availability_template
        next 0 unless padrao&.is_cumulative?
        next filho.value if filho.children?

        filho.value * (padrao.debit? ? -1 : 1)
      end
    elsif adjusted?
      # **DEC-24 / D-02** — a correção por dias úteis. `original_value` acabou de
      # ser regravado com o valor digitado pelo `apply_legacy_value_pipeline`,
      # e o formulário preenche o campo com o valor **já corrigido**: salvar de
      # novo multiplica de novo. Replicado conscientemente.
      self.value = original_value.to_d * Sfg::BusinessDays.multiplier(date)
    end

    value
  end

  # `update_virtual_value` do legado. **DEC-27**: `virtual_value` é o *saldo
  # acumulado* do 1º nível; `value` é o *total bruto*. Duas métricas, dois
  # rótulos, nenhum número mudado.
  def recompute_virtual_value
    recompute_value

    self.virtual_value =
      if consolidation?
        sibling_company_entries.sum(:virtual_value)
      elsif availability_template&.base_level?
        signed_value + previous_base_entries_total
      else
        value
      end
  end

  # O saldo acumulado depende **das células que existem**, não do conjunto de
  # padrões — e padrão desativado cujo lançamento existe **continua contando**
  # (`previous_level_templates` do legado não filtra por `is_active`).
  #
  # A fila desta fatia (tarefa 5.6 / 6.5.9) pedia "determinístico, desativados
  # fora da conta". **Anulado pelo DEC-30**, que nomeia o saldo entre as regras
  # a replicar, e pela família DEC-24/26/27/28, que respondeu "replicar" a todas
  # as perguntas vizinhas. Fica travado por golden test.
  def previous_base_entries_total
    padrao = availability_template
    return 0 if padrao.nil? || !padrao.base_level?

    anteriores = padrao.previous_base_templates
    return 0 if anteriores.blank?

    AvailabilityEntry.where(availability_template_id: anteriores.select(:id),
                            date: date, project_id: project_id, company_id: company_id)
                     .includes(:availability_template)
                     .sum { |entrada| entrada.signed_value }
  end

  # O valor com o sinal da natureza da operação. **Compara o CÓDIGO** (DC-28).
  def signed_value
    padrao = availability_template
    return value.to_d if padrao.nil?

    value.to_d * (padrao.debit? ? -1 : 1)
  end

  # Recalcula e grava. É o `update_values!` do legado, e o único caminho pelo
  # qual os jobs tocam um lançamento.
  def recompute_and_save!
    recompute_virtual_value
    save!
  end

  private


  def mark_consolidation
    # O conversor já decidiu, e com mais informação do que existe aqui: ele sabe
    # se a coluna `company_id` EXISTE na origem. Ver `etl_loading`.
    return if etl_loading

    self.is_consolidation = company_id.blank?
  end

  def copy_title_from_template
    self.title = availability_template&.title
  end

  # **O pipeline do legado, na ordem exata** (`availability_entry.rb:17-24`).
  #
  # A linha do meio é o **D-02**: `original_value` recebe o valor que chegou —
  # que a tela preencheu com o resultado **já corrigido** da última gravação.
  # Não é um bug a consertar aqui; é a DEC-24.
  def apply_legacy_value_pipeline
    # DEC-24: na carga os valores são COPIADOS, nunca recalculados. Ver `etl_loading`.
    return if etl_loading

    self.original_value = value if will_save_change_to_value? && adjusted?
    recompute_virtual_value
  end

  # `after_save` do legado (`:28-38`), com transação e guarda de ciclo (BE-129).
  #
  # A guarda não muda resultado nenhum numa árvore bem formada — ela existe para
  # que um ciclo em dado migrado (`parent_template_id` apontando para trás) vire
  # uma cascata que **termina** em vez de estourar a pilha.
  def propagate_derived_values
    # A origem já traz cada linha derivada como linha própria. Ver `etl_loading`.
    return if etl_loading

    raiz_da_cascata = Thread.current[CASCADE_GUARD_KEY].nil?
    guarda = (Thread.current[CASCADE_GUARD_KEY] ||= Set.new)

    # Já visitado nesta cascata: nada a fazer, e **nada a limpar** — quem
    # colocou o id no conjunto é que o retira.
    return if guarda.include?(id)

    guarda << id

    begin
      executar = lambda do
        if consolidation?
          refresh_next_base_entries
        else
          refresh_parent_entry
          refresh_next_base_entries
          refresh_consolidation_entry
        end
      end

      raiz_da_cascata ? self.class.transaction(requires_new: true) { executar.call } : executar.call
    ensure
      raiz_da_cascata ? Thread.current[CASCADE_GUARD_KEY] = nil : guarda.delete(id)
    end
  end

  # `parent_entry.save if has_parent?` — o pai é **criado se não existir**, na
  # gravação. É materialização por gravação explícita, que a DC-30 permite; o
  # que ela proíbe é criar na **leitura**.
  def refresh_parent_entry
    pai_template_id = availability_template&.parent_template_id
    return if pai_template_id.blank?

    pai = self.class.find_or_initialize_by(project_id: project_id, company_id: company_id,
                                           availability_template_id: pai_template_id, date: date)
    pai.user_id ||= user_id
    pai.recompute_and_save!
  end

  # `update_virtual_value_for_next_levels` — os padrões base **seguintes** têm o
  # saldo acumulado recalculado, porque ele soma os anteriores.
  def refresh_next_base_entries
    padrao = availability_template
    return if padrao.nil? || !padrao.base_level?

    seguintes = padrao.next_base_templates.to_a
    return if seguintes.empty?

    seguintes.each do |proximo|
      entrada = self.class.find_or_initialize_by(project_id: project_id, company_id: company_id,
                                                 availability_template_id: proximo.id, date: date)
      entrada.user_id ||= user_id
      entrada.recompute_and_save!
    end
  end

  # `update_mirror!` — a linha de consolidação geral do projeto.
  def refresh_consolidation_entry
    espelho = self.class.find_or_initialize_by(project_id: project_id, company_id: nil,
                                               availability_template_id: availability_template_id,
                                               date: date)
    espelho.user_id ||= user_id
    espelho.recompute_and_save!
  end

  # Contrato **C1**: o padrão tem de ser do mesmo projeto. No legado o
  # `permit` aceitava `project_id` e `availability_template_id` soltos do corpo.
  def template_must_belong_to_project
    return if availability_template_id.blank? || project_id.blank?

    padrao = availability_template
    return if padrao.nil? || padrao.project_id == project_id

    errors.add(:availability_template_id, 'pertence a outro projeto')
  end

  def company_must_belong_to_project
    return if company_id.blank? || project_id.blank?
    return if Company.where(id: company_id, project_id: project_id).exists?

    errors.add(:company_id, 'não pertence a este projeto')
  end
end
