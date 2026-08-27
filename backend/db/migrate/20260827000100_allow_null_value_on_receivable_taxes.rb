# frozen_string_literal: true

# **DEC-120** — a tarifa com `NaN` entra como **NULO**, não como zero.
#
# ## O que a decisão diz, e por que a coluna precisa mudar
#
# D-10: há **uma** linha em `receivable_taxes` no dump de produção
# (`id=47391`, deságio do borderô `22424`) com `NaN` gravado no valor. Em float
# o `NaN` se propaga por **toda soma que o encontre** — contamina o total de
# tarifas, o líquido e os quatro percentuais do borderô pai.
#
# O usuário decidiu: carrega com **valor nulo**. Nulo diz *"não sei quanto
# foi"*; zero **afirma** que a tarifa foi de R$ 0,00 — e afirmar é pior do que
# admitir a ignorância, porque some da tela sem deixar rastro.
#
# A coluna nascia `null: false`, então a decisão não tinha como entrar no banco.
#
# ## O `default` de 0.0 FICA, de propósito
#
# Ele cobre o caminho da tela, onde o valor é obrigatório
# (`requires :value` no Grape) e onde uma tarifa sem valor é erro de
# preenchimento, não informação desconhecida. Só o ETL grava `nil`, e o faz
# **explicitamente**.
class AllowNullValueOnReceivableTaxes < ActiveRecord::Migration[8.0]
  def up
    change_column_null :receivable_taxes, :value, true
    change_column_comment(
      :receivable_taxes, :value,
      'Valor da tarifa. NULO = valor DESCONHECIDO (DEC-120): o legado gravou `NaN` e a carga ' \
      'não afirma que foi zero. As somas do borderô ignoram tarifa nula.'
    )
  end

  def down
    # Voltar a `null: false` exigiria decidir o que fazer com as linhas nulas, e
    # essa decisão é do usuário (DEC-120). Zerar aqui reintroduziria exatamente a
    # mentira que a decisão evita.
    execute("UPDATE receivable_taxes SET value = 0 WHERE value IS NULL")
    change_column_null :receivable_taxes, :value, false
    change_column_comment(:receivable_taxes, :value, 'Valor da tarifa.')
  end
end
