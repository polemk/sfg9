# frozen_string_literal: true

# **Exclusão bloqueia, nunca cascateia** (D-24) — declarada por NOME de classe.
#
# Este concern nasceu dentro do `GlobalCatalog` (S3) e foi extraído aqui na S4,
# quando o segundo grupo de models precisou exatamente da mesma regra: `Company`,
# `Provider` e `Project` também bloqueiam exclusão por dependente, e metade dos
# dependentes deles (limites de risco, recebíveis, renegociações) nasce em
# S5..S9. Copiar o mecanismo teria dado **duas** semânticas de bloqueio, que é o
# jeito de acabar com uma delas respondendo `:ok` — o D-24 outra vez.
#
# **Por que por nome, e não por `has_many … dependent: :restrict_with_error`:**
# uma associação declarada contra classe inexistente levanta `NameError` na hora
# do `destroy`. Assim a regra fica escrita HOJE e passa a valer sozinha no dia em
# que a fatia dona entregar a tabela.
#
# A segunda camada é o banco: as FKs nascem `NO ACTION`, então o Postgres recusa
# mesmo que alguém contorne o model.
#
# Formato:
#   { 'ClasseDependente' => { foreign_key: :coluna, label: 'texto pt-BR' } }
module BlockingDependents
  extend ActiveSupport::Concern

  # Resolve a classe de um dependente **declarado por nome**, ou `nil` se a
  # fatia dona ainda não entregou a tabela. É o mesmo cuidado que os escritores
  # do seed de demonstração tomam: numa base recém-clonada a constante pode
  # existir sem a tabela ter sido migrada.
  def self.dependent_class(class_name)
    return nil unless Object.const_defined?(class_name)

    klass = Object.const_get(class_name)
    return nil unless klass.respond_to?(:table_exists?) && klass.table_exists?

    klass
  rescue StandardError
    nil
  end

  # Igual, mas exigindo também que a COLUNA de ligação exista.
  #
  # Não é preciosismo: `projects` nasceu na S0 com `segment_id` e **sem**
  # `sub_segment_id`. Sem esta checagem a listagem de subsegmentos responderia
  # **500** com `PG::UndefinedColumn` — model presente, tabela presente, coluna
  # ausente. Foi assim que apareceu, rodando o teste.
  def self.dependent_class_with_column(class_name, foreign_key)
    klass = dependent_class(class_name)
    return nil if klass.nil?
    return nil unless klass.column_names.include?(foreign_key.to_s)

    klass
  end

  # Contagem de dependentes **por classe**, numa consulta por dependente para a
  # página inteira. Devolve `{ id_do_dono => { 'RiskControl' => 4, ... } }`.
  #
  # Existe porque a versão anterior somava TUDO num número só, e as entities
  # expunham esse total como se fosse de um dependente específico. Na tela de
  # Empresas a coluna "LIMITES" mostrava **43** onde o banco tinha **4**: o total
  # incluía renegociações e operações. Número errado na tela de um sistema de
  # crédito é pior que tela quebrada — tela quebrada alguém reporta.
  #
  # O `Provider` acertava por acaso, por ter um dependente só. Somar continuaria
  # certo até o dia em que ele ganhasse o segundo, e aí quebraria em silêncio.
  # Contar por classe tira o acaso da conta.
  #
  # Dependente cuja tabela ainda não nasceu simplesmente não conta — é o que
  # deixa a contagem funcionar antes de a fatia dona entregar.
  def self.counts_by_dependent(model, ids)
    ids = Array(ids).compact
    return {} if ids.empty?

    model.blocking_dependents.each_with_object({}) do |(class_name, config), acc|
      coluna = config.fetch(:foreign_key)
      klass = dependent_class_with_column(class_name, coluna)
      next if klass.nil?

      klass.where(coluna => ids).group(coluna).count.each do |id, total|
        (acc[id] ||= Hash.new(0))[class_name] = total
      end
    end
  end

  included do
    before_destroy :restrict_blocking_dependents!
  end

  class_methods do
    def blocking_dependents
      {}
    end
  end

  # Relatório dos dependentes que existem e bloqueiam. Vazio = pode excluir.
  # Ignora, com silêncio deliberado, o dependente cuja tabela ainda não nasceu.
  def blocking_dependents_report
    self.class.blocking_dependents.filter_map do |class_name, config|
      klass = BlockingDependents.dependent_class_with_column(class_name, config.fetch(:foreign_key))
      next if klass.nil?

      count = klass.where(config.fetch(:foreign_key) => id).count
      next if count.zero?

      { label: config.fetch(:label), count: count }
    end
  end

  # Frase pt-BR do bloqueio, já pronta para o 422. **Nomeia o vínculo** — o
  # legado dizia só "não foi possível excluir" (e, pior, respondia `:ok`).
  def blocking_dependents_message
    report = blocking_dependents_report
    return nil if report.empty?

    vinculos = report.map { |d| "#{d[:count]} #{d[:label]}" }.to_sentence(locale: :'pt-BR')
    "Não é possível excluir: este registro tem #{vinculos} vinculado(s). " \
      'Remova ou realoque o vínculo antes de excluir.'
  end

  private

  def restrict_blocking_dependents!
    mensagem = blocking_dependents_message
    return if mensagem.nil?

    errors.add(:base, mensagem)
    throw(:abort)
  end
end
