# frozen_string_literal: true

# S6 / **BE-445** — a classe base abstrata dos lançamentos.
#
# No legado `Entry` (`../sfg/app/models/entry.rb`) é uma classe abstrata com
# quatro `belongs_to` (usuário, projeto, portador, carteira) e **duas strings em
# pt-BR guardadas em `mattr_accessor`**:
#
#     @@STATUS__DIFFERENCE = "Diferença"
#     @@STATUS__OK         = "OK"
#
# Elas são **gravadas na coluna** `receivable_entries.status` e comparadas por
# igualdade de texto. Em 28.131 linhas de produção há exatamente esses dois
# valores — e trocar o rótulo na tela quebraria toda comparação, em silêncio,
# num sistema financeiro.
#
# ## O que muda no ai9
#
# O valor **persistido** passa a ser estável (`ok` / `difference`) e o rótulo
# pt-BR vive na apresentação. Verificável: renomear o rótulo não muda nenhuma
# comparação, e o `check_constraint` de `receivable_entries` recusa um terceiro
# valor. A conversão dos textos legados é tarefa do ETL, **linha a linha e com
# relatório** (tarefa F.2) — nenhum texto sem correspondência é convertido em
# silêncio.
#
# ## Fronteira com a S11
#
# `AvailabilityEntry` (S11) é o outro lançamento do sistema e **consome** esta
# base sem redefini-la. Desde 26/08/2026 ela **herda** daqui (S11, tarefa F.2 /
# DB-567), e continua sem situação própria: `availability_entries` não tem
# coluna `status` e não deve ganhar uma. O contrato é o de sempre: quem
# precisar de "OK"/"Diferença" usa {STATUSES} e {status_label}, nunca uma
# segunda cópia das strings.
class Entry < ApplicationRecord
  self.abstract_class = true

  # O domínio fechado. Dois estados e **nenhum terceiro**: não existe baixa,
  # liquidação nem vencimento de recebível no legado (D-19, DEC-09, Q-B9), e
  # inventá-los seria feature nova travestida de paridade.
  STATUS_OK = 'ok'
  STATUS_DIFFERENCE = 'difference'
  STATUSES = [STATUS_OK, STATUS_DIFFERENCE].freeze

  # O de-para com o texto que o legado grava. É o ÚNICO lugar do sistema onde
  # essas duas strings aparecem — o ETL lê daqui, e a apresentação também.
  LEGACY_STATUS_LABELS = { STATUS_OK => 'OK', STATUS_DIFFERENCE => 'Diferença' }.freeze

  def self.status_from_legacy(text)
    LEGACY_STATUS_LABELS.key(text.to_s.strip)
  end

  def self.status_label(value)
    LEGACY_STATUS_LABELS[value.to_s]
  end

  def status_label = self.class.status_label(status)
end
