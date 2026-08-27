# frozen_string_literal: true

# **DEC-117** — as **6 colunas de escala 6** de `receivable_entries` voltam a ser
# `float`, exatamente como o legado as declara.
#
# ## Por que esta migration existe
#
# A **DEC-02** liberou o `decimal` no ai9 — *"o tipo de coluna no ai9 **pode** ser
# `decimal`, mas a sequência de operações replica a do legado"* —, mas a liberação
# tinha uma condição escrita na primeira linha da própria DEC: *"de forma que os
# totais fiquem **idênticos** aos do legado"*.
#
# A medição contra o dump de **31/05/2025** (`spec/lib/sfg/etl/values_precision_spec.rb`,
# `ETL-S14-01` do `improvements-log.md`) mostrou que a condição vale para 39
# colunas e **falha para 6**:
#
# | Colunas | Escala | Divergências em 5.321 comparações |
# | --- | ---: | ---: |
# | dinheiro e taxas | 2 e 4 | **0** |
# | `recompra_percent`, `retencao_percent`, `fomento_percent`, `outros_percent`, `float_calculado`, `diferenca_float` | 6 | **48** |
#
# Nessas 6 a fórmula do legado **não arredonda** (`../sfg/app/models/receivable_entry.rb:50-52,59-62`):
# `recompra_percent` é `100 * (recompra / valor_liquido)` cru, e produção guardou
# `19.704917111218396`. O `decimal(15,6)` do ai9 **acrescenta um ponto de
# arredondamento que o legado não tinha** — que é justamente o que a DEC-02 proibia.
#
# ## As outras 19 `float` do legado NÃO mudam, e isso é decisão
#
# O legado tem **25** colunas `float` em `receivable_entries`
# (`../sfg/db/migrate/20210315183541_create_receivable_entries.rb:32-38,64-77`).
# Nas outras 19 a própria fórmula do legado arredonda antes de gravar (`.round(2)`,
# `.round(4)`), então o `decimal(12,4)`/`decimal(15,2)` do ai9 **não introduz
# arredondamento novo** — medido, **0 divergências**. Trocá-las seria risco sem
# ganho, e a DEC-117 diz isso com todas as letras: *"Migration nas 6 colunas, e só
# nelas."*
#
# ## O momento é seguro
#
# A carga está adiada pela **DEC-102**, então esta mudança de esquema acontece
# **longe do cutover**. Adiar é que seria arriscado: depois da carga a correção
# exigiria recarregar 28.131 borderôs.
#
# ## O risco que ANDA JUNTO com esta troca, e continua barrado
#
# O **D-10** (`Infinity`/`NaN` gravados porque a guarda de divisão por zero só
# existe no cliente) fica **mais perto** com `float`, não mais longe: `Float('NaN')`
# não levanta e `double precision` aceita NaN, do mesmo jeito que `BigDecimal('NaN')`
# e `numeric` aceitavam. Quem barra continua sendo o conversor
# (`Sfg::Etl::Converters::ReceivableEntries::NAN_SENSITIVE`) e o `InputGuard` do
# `Receivables::Calculator` — e o exemplo que trava isso NÃO foi afrouxado junto
# com o tipo (`values_precision_spec.rb`).
class RevertScale6ColumnsToFloat < ActiveRecord::Migration[8.0]
  # As 6, e só elas. `comment` é reaplicado porque `change_column` reescreve a
  # coluna inteira e o comentário se perderia em silêncio.
  COLUNAS = {
    float_calculado: {
      default: 0.0, null: false,
      comment: 'DERIVADO: `prz_med_pond_bco − prz_med_pond_emp`. **`float`, como o legado** (DEC-117): a fórmula não arredonda e o ruído binário (`79.7 - 76.7` = `3.0000000000000057`) é o valor que produção guardou.'
    },
    diferenca_float: {
      default: 0.0, null: false,
      comment: 'DERIVADO: `max(float_calculado − float_acordado, 0)`. Piso em zero replicado. **`float`, como o legado** (DEC-117).'
    },
    recompra_percent: {
      default: nil, null: true,
      comment: 'DERIVADO: `100 × (recompra / valor_liquido)`, **sem arredondamento**. `float`, como o legado (DEC-117) — produção guardou `19.704917111218396`.'
    },
    retencao_percent: {
      default: nil, null: true,
      comment: 'DERIVADO, sem arredondamento. `float`, como o legado (DEC-117).'
    },
    fomento_percent: {
      default: nil, null: true,
      comment: 'DERIVADO, sem arredondamento. `float`, como o legado (DEC-117).'
    },
    outros_percent: {
      default: nil, null: true,
      comment: 'DERIVADO, sem arredondamento. `float`, como o legado (DEC-117).'
    }
  }.freeze

  # O estado anterior, para o `down` — tipo **e** comentário. Escrito à mão de
  # propósito: um `down` que adivinha o estado antigo é um `down` que mente no
  # dia em que for usado, e reverter o tipo mantendo o texto "`float`, como o
  # legado" deixaria a coluna `decimal` afirmando o contrário de si mesma.
  ESCALA_6 = { precision: 15, scale: 6 }.freeze

  COMENTARIOS_ANTERIORES = {
    float_calculado: 'DERIVADO: `prz_med_pond_bco − prz_med_pond_emp`. Ver a nota de precisão no cabeçalho.',
    diferenca_float: 'DERIVADO: `max(float_calculado − float_acordado, 0)`. Piso em zero replicado.',
    recompra_percent: 'DERIVADO: `100 × (recompra / valor_liquido)`.',
    retencao_percent: 'DERIVADO.',
    fomento_percent: 'DERIVADO.',
    outros_percent: 'DERIVADO.'
  }.freeze

  def up
    COLUNAS.each do |coluna, opcoes|
      change_column :receivable_entries, coluna, :float, **opcoes
    end
  end

  def down
    COLUNAS.each do |coluna, opcoes|
      change_column :receivable_entries, coluna, :decimal, **ESCALA_6,
                    default: opcoes[:default], null: opcoes[:null],
                    comment: COMENTARIOS_ANTERIORES.fetch(coluna)
    end
  end
end
