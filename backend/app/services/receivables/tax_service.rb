# frozen_string_literal: true

module Receivables
  # S6 / **BE-184** — a sincronia da lista de tarifas de um borderô.
  #
  # ## DEC-72 substitui o comportamento do legado, e a tarefa 3.19 fica anulada
  #
  # A tarefa 3.19 e a Q-B16 diziam "a exclusão de tarifa não é transacional com
  # o formulário — como hoje". A **DEC-72** decidiu o contrário: o botão de
  # remover marca a exclusão como **pendente no formulário**, e ela só acontece
  # no **Salvar**, dentro da mesma transação que recalcula os agregados.
  # Cancelar desfaz.
  #
  # A DEC vence a tarefa. O motivo está escrito nela: no legado o botão
  # (`receivables/new/_body.html.erb:484`) dispara um `DELETE` direto
  # (`new/_body.js.erb:674`), **fora de qualquer submit**; o servidor apaga
  # (`receivable_taxes_controller.rb:15-24`) e **não recalcula o borderô pai**.
  # Entre uma coisa e outra o borderô exibe total errado. *"O que se preserva
  # não é um número, é uma janela em que o número está errado."*
  #
  # Consequência prática: **não existe endpoint de exclusão de tarifa.** A lista
  # inteira viaja no payload do borderô, e este serviço faz o diff.
  #
  # ## Denormalização
  #
  # Título e classificadores vêm do `MovementKind` **na gravação** e ficam
  # congelados (D-B13) — quem faz isso é o `before_validation` de
  # `ReceivableTax`, não este serviço.
  class TaxService
    class << self
      # Monta as tarifas **em memória**, sem gravar. É o que permite calcular
      # com a lista definitiva antes de existir um único `INSERT` (fecha D-11).
      #
      # `payload` `nil` → devolve as tarifas já persistidas, intocadas.
      def build(entry:, payload:)
        return entry.taxes.to_a if payload.nil?

        existentes = entry.persisted? ? entry.taxes.index_by { |t| t.id.to_s } : {}
        Array(payload).map do |linha|
          atributos = linha.symbolize_keys
          registro = existentes[atributos[:id].to_s] || entry.taxes.build
          registro.movement_kind_id = atributos[:movement_kind_id] if atributos.key?(:movement_kind_id)
          registro.value = atributos[:value] if atributos.key?(:value)
          # Denormaliza agora para que o cálculo enxergue os classificadores
          # corretos ANTES do save — o `before_validation` roda de novo no
          # `save!` e chega ao mesmo resultado.
          registro.valid?
          registro
        end
      end

      # Grava a lista e **apaga o que saiu** — a exclusão pendente da DEC-72.
      def persist!(entry:, taxes:, payload:)
        return if payload.nil?

        taxes.each do |tax|
          tax.receivable_entry = entry
          tax.save!
        end

        mantidos = taxes.filter_map { |t| t.id }
        removidos = entry.taxes.where.not(id: mantidos)
        removidos = entry.taxes if mantidos.empty?
        removidos.destroy_all

        entry.taxes.reset
      end
    end
  end
end
