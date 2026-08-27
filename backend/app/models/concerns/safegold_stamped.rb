# frozen_string_literal: true

# **DEC-112 / DB-051 / DB-090** — o carimbo de `has_safegold_management`.
#
# Seis tabelas do legado copiam a marca "Gerido pela Safegold" num
# `before_validation` **sem `on:`** — recopiada em todo save, não só na criação:
#
# | model | linha no legado | origem |
# | --- | --- | --- |
# | `Company` | `company.rb:13` | `project` |
# | `AvailabilityEntry` | `availability_entry.rb:17` | `project` |
# | `ReceivableEntry` | `receivable_entry.rb:40` | `project` |
# | `Renegotiation` | `renegotiation.rb:24` | `project` |
# | `RiskControl` | `risk_control.rb:15` | **`company`** |
# | `RiskEntry` | `risk_entry.rb:32` | **`company`** |
#
# Quando a marca do projeto muda, **só `companies` é ressincronizada**
# (`project.rb:298-303`). As outras cinco ficam com o carimbo velho para sempre.
# É o **D-30**, replicado de propósito: o valor é a foto do momento, não há
# leitor interno nenhum, e o consumidor é externo (BI/planilha do cliente), que
# quer justamente o histórico.
#
# ## Por que existe `preserve_safegold_stamp`
#
# Porque o carimbo **é** o dado histórico, e o ETL grava por `record.save!` —
# que dispara este callback. Sem a chave, carregar o dump de produção
# sobrescreveria o carimbo de cada linha pelo valor **de hoje** do projeto e
# apagaria exatamente a inconsistência que a DEC-112 mandou preservar. São
# 28.131 recebíveis e 642.447 posições de risco de valor histórico, perdidas em
# silêncio e sem erro nenhum.
#
# Ligada por `Sfg::Etl::Converters::Base#write!` **só quando o valor veio da
# origem**. Nenhum caminho de aplicação a liga.
module SafegoldStamped
  extend ActiveSupport::Concern

  included do
    # `true` faz o callback **não** recarimbar: o valor atribuído fica como está.
    # É do ETL, e de mais ninguém.
    attr_accessor :preserve_safegold_stamp

    before_validation :stamp_safegold_management
  end

  class_methods do
    # `:project` ou `:company` — de qual associação a marca é copiada. É o que
    # difere `RiskControl`/`RiskEntry` (copiam da empresa) das outras quatro.
    def safegold_stamp_source(nome)
      @safegold_stamp_source = nome
    end

    def safegold_stamp_source_name = @safegold_stamp_source || :project
  end

  private

  def stamp_safegold_management
    return if preserve_safegold_stamp

    origem = self.class.safegold_stamp_source_name
    return if public_send(:"#{origem}_id").blank?

    self.has_safegold_management = public_send(origem)&.has_safegold_management || false
  end
end
