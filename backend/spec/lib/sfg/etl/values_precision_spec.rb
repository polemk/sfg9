# frozen_string_literal: true

require 'rails_helper'

# S14 / tarefa **4.8** — **DB-ETL-06: replicação de precisão financeira.**
# *"Mesma sequência de operações, mesmos casts, mesmos pontos de arredondamento."*
#
# ## Por que este arquivo existe, e o que estava faltando
#
# A tarefa mandava explicitamente **não inventar oráculo**: *"o oráculo são os
# testes golden de C2"*. Ela ficou aberta porque, quando a S14 foi escrita, o
# golden de C2 do borderô ainda não existia. **Hoje existe** — a S6 entregou
# `spec/fixtures/receivables/producao_28131.json`, extraído do dump de
# **31/05/2025**, com os 33 derivados **como o legado os gravou**, e o motor da
# S6 bateu contra as 28.099 linhas limpas em **927.267 comparações**.
#
# O que continuava sem uma única linha de teste era o **outro lado**: o
# `Sfg::Etl::Values.to_decimal`, que é o cast por onde **todo** número
# financeiro do legado passa na carga. O golden da S6 prova que o *cálculo*
# reproduz o legado; ele não diz nada sobre o *transporte*. Este arquivo prova
# o transporte, e usa o mesmo oráculo — dado de produção, não valor inventado.
#
# ## O que exatamente é medido
#
# Para cada valor financeiro que produção gravou, a sequência **completa** que a
# carga executa:
#
#     string do dump → Values.to_decimal → coluna decimal(p,s) do ai9 → leitura
#     string do dump → Values.to_float   → coluna float        do ai9 → leitura
#
# O cast final é feito pelo **próprio PostgreSQL**, com o tipo, a precisão e a
# escala **lidos do `columns_hash` do model** — não de uma tabela transcrita à
# mão, que é a forma de o teste passar a mentir no dia em que alguém mudar a
# coluna.
#
# Um valor que não sobreviver a essa ida e volta é dinheiro alterado no
# transporte, em silêncio, num sistema financeiro.
#
# ## DEC-117 — a segunda linha do trajeto é nova, e o resultado é 5.321/5.321
#
# As 6 colunas de escala 6 (`recompra_percent`, `retencao_percent`,
# `fomento_percent`, `outros_percent`, `float_calculado`, `diferenca_float`)
# voltaram a ser `float`, como no legado. Antes disso a varredura media **48
# divergências**; agora mede **zero**, e o exemplo central passa a exigir zero em
# vez de exigir exatamente aquelas seis.
RSpec.describe Sfg::Etl::Values, 'precisão financeira na carga (DB-ETL-06 / DEC-02)' do
  # **O golden vem do dump de PRODUCAO e por isso NAO e versionado** (DEC-123).
  # Ele fica na maquina de quem tem o dump; o repositorio nunca o carrega.
  #
  # Sem essa guarda, a ausencia do arquivo derruba a SUITE INTEIRA no
  # carregamento — e nao apenas os exemplos que dependem dele. Com ela, os
  # exemplos sao PULADOS e a ausencia aparece no relatorio, em vez de sumir em
  # silencio (zero exemplo gerado tambem passaria, o que seria pior).
  GOLDEN_PRODUCAO = Rails.root.join('spec/fixtures/receivables/producao_28131.json')
  GOLDEN_DISPONIVEL = GOLDEN_PRODUCAO.exist?
  FIXTURE_PRODUCAO = (GOLDEN_DISPONIVEL ? JSON.parse(GOLDEN_PRODUCAO.read) : { 'linhas' => [] }).freeze

  before do
    unless GOLDEN_DISPONIVEL
      skip("golden de producao ausente em #{GOLDEN_PRODUCAO}. " \
           'Dado real de cliente nao e versionado (DEC-123): copie o arquivo ' \
           'na maquina que tem o dump para rodar estes exemplos.')
    end
  end

  DECIMAIS_DO_BORDERO = ReceivableEntry.columns_hash
                                       .select { |_, c| c.type == :decimal }
                                       .transform_values { |c| [c.precision, c.scale] }
                                       .freeze

  # **DEC-117** — as 6 de escala 6 saíram de `decimal` e voltaram a ser `float`,
  # como o legado. A varredura passa a cobrir os **dois** tipos: se ela olhasse
  # só `decimal`, as 6 sumiriam da conta e o teste ficaria verde por **deixar de
  # medir** — que é a forma mais silenciosa de um teste passar a mentir.
  FLOATS_DO_BORDERO = ReceivableEntry.columns_hash
                                     .select { |_, c| c.type == :float }
                                     .keys
                                     .freeze

  # Toda coluna numérica do borderô, com o tipo SQL de destino. É `columns_hash`
  # quem responde, nunca uma tabela transcrita à mão.
  NUMERICAS_DO_BORDERO = ReceivableEntry.columns_hash
                                        .select { |_, c| %i[decimal float].include?(c.type) }
                                        .transform_values do |c|
                                          c.type == :decimal ? "numeric(#{c.precision},#{c.scale})" : 'double precision'
                                        end.freeze

  def cast_sql(valor_sql, tipo)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(["SELECT CAST(? AS #{tipo})", valor_sql])
    )
  end

  def cast_do_banco(valor, precision, scale)
    BigDecimal(cast_sql(valor.to_s('F'), "numeric(#{precision},#{scale})").to_s)
  end

  # O mesmo trajeto, pelo lado `float`: `double precision` do Postgres devolve
  # `Float` pelo adaptador, sem string decimal no meio.
  def cast_float_do_banco(valor)
    cast_sql(valor.to_s, 'double precision').to_f
  end

  it 'a fixture é mesmo o dump de produção, e não um valor inventado' do
    expect(FIXTURE_PRODUCAO['fonte']).to include('dump de PRODUCAO')
    expect(FIXTURE_PRODUCAO['linhas'].size).to eq(131)
  end

  # ---------------------------------------------------------------------------
  # O exemplo central da tarefa — e o que ele MEDIU, ANTES e DEPOIS da DEC-117.
  # ---------------------------------------------------------------------------
  #
  # ## O que a primeira medição achou (e que a DEC-117 mandou corrigir)
  #
  # Com as 45 colunas numéricas armazenadas em `decimal`, a varredura das 5.321
  # comparações sobre 131 borderôs reais achou **48 divergências, todas nas 6
  # colunas de escala 6** — os quatro `*_percent`, `float_calculado` e
  # `diferenca_float`. Zero divergência nas 39 de dinheiro e de taxa.
  #
  # A causa não era o cast do ETL: é que no legado **essas 6 são `float`**
  # (`../sfg/db/migrate/20210315183541_create_receivable_entries.rb:32-38`) e a
  # fórmula delas **não arredonda** — `recompra_percent` é
  # `100 × recompra / valor_liquido` cru (`../sfg/app/models/receivable_entry.rb:59`),
  # e produção guardou `19.704917111218396`. As outras 19 colunas `float` do
  # legado chegam com no máximo 4 casas porque a própria fórmula do legado as
  # arredonda, então o `decimal` do ai9 as recebe inteiras.
  #
  # ## A DEC-117 — e por que este exemplo INVERTEU de sentido
  #
  # O usuário decidiu devolver as 6 para `float`
  # (`20260826235200_seis_colunas_de_escala_6_voltam_a_float.rb`), porque a
  # DEC-02 liberou o `decimal` **com uma condição** — *"de forma que os totais
  # fiquem idênticos aos do legado"* — e nessas 6 a condição falhava.
  #
  # Antes, este exemplo travava a lista das que perdem dígito como **fechada**:
  # uma sétima coluna divergindo reprovava. Agora **nenhuma pode divergir**, e é
  # isso que ele exige. A trava ficou mais forte, não mais fraca: uma divergência
  # nova nunca mais entra por omissão, seja em coluna de dinheiro ou não.
  #
  # As outras 19 `float` do legado **continuam `decimal` de propósito** — medido,
  # 0 divergências —, e a lista abaixo existe para que trocá-las por engano seja
  # visível, não para autorizar exceção.
  ESCALA_6_DO_LEGADO_FLOAT = %w[
    recompra_percent retencao_percent fomento_percent outros_percent
    float_calculado diferenca_float
  ].freeze

  it 'TODO valor de produção atravessa o cast + a coluna SEM MUDAR — nenhuma exceção' do
    comparacoes = 0
    divergentes = Hash.new(0)

    FIXTURE_PRODUCAO['linhas'].each do |linha|
      linha['input'].merge(linha['expected']).each do |coluna, texto|
        next if texto.nil?

        tipo = NUMERICAS_DO_BORDERO[coluna]
        next if tipo.nil? # coluna inteira, string ou inexistente — não é número

        comparacoes += 1
        divergentes[coluna] += 1 unless sobrevive_ao_transporte?(texto, tipo)
      end
    end

    # A contagem entra na asserção de propósito: um `each` que deixe de iterar
    # passaria calado, e um teste que não compara nada é pior que teste nenhum.
    # **O mesmo número de antes da DEC-117** — as 6 mudaram de tipo, não saíram
    # da varredura.
    expect(comparacoes).to eq(5_321)

    # **NENHUMA coluna pode divergir.** Antes da DEC-117 a lista das divergentes
    # era fechada em 6; agora é fechada em **zero**. Qualquer nome que apareça
    # aqui é número mudando no transporte — e tem de reprovar, não de ser
    # acrescentado a uma lista de exceções.
    detalhe = divergentes.sort_by { |_, n| -n }.map { |c, n| "#{c} (#{n})" }.join(', ')
    expect(divergentes).to(
      eq({}),
      "5.321 comparações contra o dump de 31/05/2025 deveriam ter 0 divergências. Divergiram: #{detalhe}"
    )
    expect(divergentes.values.sum).to eq(0)
  end

  # Como cada tipo atravessa. **`decimal` compara em `BigDecimal`, `float`
  # compara em `Float`** — comparar um `double` contra `BigDecimal` reintroduz,
  # no teste, exatamente a conversão que a DEC-117 tirou da carga.
  def sobrevive_ao_transporte?(texto, tipo)
    if tipo == 'double precision'
      # Igualdade EXATA de `double` — de propósito, e é o ponto da DEC-117:
      # `text -> to_float -> double precision -> text` tem de devolver o mesmo
      # `double` que produção gravou. Tolerância aqui esconderia o defeito que
      # este arquivo existe para medir.
      cast_sql(Sfg::Etl::Values.to_float(texto).to_s, tipo).to_f == Float(texto) # rubocop:disable Lint/FloatComparison
    else
      BigDecimal(cast_sql(Sfg::Etl::Values.to_decimal(texto).to_s('F'), tipo).to_s) == BigDecimal(texto)
    end
  end

  it 'as 6 são `float` no ai9 porque são `float` no legado (DEC-117)' do
    ESCALA_6_DO_LEGADO_FLOAT.each do |coluna|
      expect(ReceivableEntry.columns_hash[coluna].type).to eq(:float), coluna
      # E não sobrou nenhuma delas como `decimal`: a troca foi das seis.
      expect(DECIMAIS_DO_BORDERO).not_to have_key(coluna)
    end
    # A troca foi **só** dessas seis. As outras 19 `float` do legado continuam
    # `decimal` (DEC-117: *"Migration nas 6 colunas, e só nelas"*).
    expect(FLOATS_DO_BORDERO.sort).to eq(ESCALA_6_DO_LEGADO_FLOAT.sort)

    # Um valor real de produção, do borderô legado 4. **Volta inteiro.**
    de_producao = '19.704917111218396'
    expect(cast_float_do_banco(described_class.to_float(de_producao))).to eq(Float(de_producao))
    expect(described_class.to_float(de_producao).to_s).to eq(de_producao)
  end

  it 'a medição que ORIGINOU a DEC-117 continua reproduzível: `decimal(15,6)` cortava' do
    # Este exemplo é o registro da causa, não uma regra viva. Ele prova que a
    # coluna antiga **cortava** — se um dia alguém propuser voltar ao `decimal`,
    # aqui está o número que a proposta precisa responder.
    de_producao = '19.704917111218396'
    expect(cast_do_banco(described_class.to_decimal(de_producao), 15, 6))
      .to eq(BigDecimal('19.704917'))
    # O cast do ETL, sozinho, nunca perdeu nada — quem cortava era a coluna.
    expect(described_class.to_decimal(de_producao)).to eq(BigDecimal(de_producao))
  end

  it 'a tarifa de `receivable_taxes` também sobrevive à ida e volta' do
    precision, scale = ReceivableTax.columns_hash['value'].then { |c| [c.precision, c.scale] }
    valores = FIXTURE_PRODUCAO['linhas'].flat_map { |l| Array(l['taxes']).map { |t| t['value'] } }.compact

    expect(valores).not_to be_empty
    valores.each do |texto|
      expect(cast_do_banco(described_class.to_decimal(texto), precision, scale))
        .to eq(BigDecimal(texto)), texto
    end
  end

  # ---------------------------------------------------------------------------
  # O cast NÃO arredonda. Quem arredonda é a coluna — e isso é o ponto do DEC-02.
  # ---------------------------------------------------------------------------
  describe 'onde está o ponto de arredondamento' do
    it '`to_decimal` é exato: não trunca, não arredonda, não perde escala' do
      exato = described_class.to_decimal('7769.99922299999')
      expect(exato).to eq(BigDecimal('7769.99922299999'))
      expect(exato.to_s('F')).to eq('7769.99922299999')

      # Quem corta é a coluna, no INSERT — e corta com ROUND_HALF_UP, que é o
      # que o `Charges::ReceiptGenerator` replica explicitamente (golden E5).
      expect(cast_do_banco(exato, 15, 2)).to eq(BigDecimal('7770.00'))
    end

    it 'a sequência `decimal × float` do legado NÃO é a mesma que `decimal × decimal`' do
      # `../sfg/app/models/receipt.rb:41-66` multiplica por um float. Trocar por
      # aritmética exata muda o número na terceira casa, e é justamente isso que
      # o DEC-02 mandou **não** consertar.
      pela_via_do_legado = BigDecimal('99999.99') * (BigDecimal('7.77').to_f / 100.0)
      exata = BigDecimal('99999.99') * (BigDecimal('7.77') / 100)

      expect(pela_via_do_legado).not_to eq(exata)
      expect(pela_via_do_legado.to_s('F')).to start_with('7769.99922299999')
      expect(exata).to eq(BigDecimal('7769.999223'))
      # **Medido, e o resultado contraria a intuição:** as duas convergem depois da
      # coluna, tanto em escala 2 quanto em escala 6. O erro do float está na 11ª
      # casa decimal, muito abaixo de qualquer escala usada aqui — que é a razão
      # de a divergência nunca ter aparecido nas 927.267 comparações do borderô.
      # A diferença é real e está travada acima (`not_to eq`); ela simplesmente
      # não alcança a coluna. Registrar isso importa: sem medir, alguém "corrige"
      # o float por segurança e muda um número por conta própria (DEC-02).
      expect(cast_do_banco(pela_via_do_legado, 15, 2)).to eq(cast_do_banco(exata, 15, 2))
      expect(cast_do_banco(pela_via_do_legado, 15, 6)).to eq(cast_do_banco(exata, 15, 6))
      expect((pela_via_do_legado - exata).abs).to be < BigDecimal('0.0000001')
    end
  end

  # ---------------------------------------------------------------------------
  # Os dois casos que o dump tem e uma fixture bonita não teria.
  # ---------------------------------------------------------------------------
  describe 'o que o cast faz com o dado sujo que produção realmente tem' do
    # D-10: 32 das 28.131 linhas têm `NaN` GRAVADO numa coluna de dinheiro.
    #
    # ⚠ **Achado ao escrever este arquivo, e ele é contraintuitivo:**
    # `BigDecimal('NaN')` **não levanta** — devolve `BigDecimal::NAN`. Logo
    # `Values.to_decimal('NaN')` devolve NaN, e `numeric` do PostgreSQL
    # **aceita** NaN. Ou seja: o cast, sozinho, deixaria NaN entrar no banco.
    #
    # Isto **não** é defeito porque o bloqueio existe uma camada acima — é o
    # conversor que recusa, com relatório. Mas fica travado aqui para que
    # ninguém remova aquela camada achando que "o cast já trata".
    it 'o cast NÃO barra `NaN` sozinho — quem barra é o conversor, com relatório' do
      expect(described_class.to_decimal('NaN')).to be_a(BigDecimal)
      expect(described_class.to_decimal('NaN')).to be_nan
      # E o `numeric` do Postgres aceita: sem a camada de cima, NaN entraria.
      expect(cast_do_banco(described_class.to_decimal('NaN'), 15, 2)).to be_nan

      # A camada que de fato barra, e que por isso não pode sumir:
      expect(Sfg::Etl::Converters::ReceivableEntries::NAN_SENSITIVE).to be_present
    end

    # ⚠ **DEC-117 — com `float` o D-10 fica MAIS PERTO, não mais longe.**
    #
    # A DEC-02 marcou o D-10 como *"não alcançado, continua corrigir"*, e a
    # DEC-117 repetiu o aviso ao trocar o tipo. Este exemplo existe para que a
    # troca de tipo **não** possa levar a guarda junto: ele prova que o
    # `double precision` do Postgres aceita `NaN` exatamente como o `numeric`
    # aceitava, e que quem barra continua sendo a camada de cima.
    it 'o `float` NÃO fecha o D-10: `double precision` aceita `NaN` igual ao `numeric`' do
      expect(cast_sql('NaN', 'double precision').to_f).to be_nan
      expect(cast_sql('Infinity', 'double precision').to_f).to be_infinite

      # O cast do ETL pelo lado float não INVENTA número — devolve `nil`, que nas
      # duas colunas `null: false` (`float_calculado`, `diferenca_float`) estoura
      # alto no `save!` em vez de gravar lixo calado.
      expect(described_class.to_float('NaN')).to be_nil
      expect(described_class.to_float('Infinity')).to be_nil

      # **E os quatro `*_percent` continuam na lista que o conversor inspeciona.**
      # Esta é a trava que importa: eles passaram para o caminho `to_float`, e sem
      # esta asserção sair da lista de NaN seria uma omissão invisível.
      conversor = Sfg::Etl::Converters::ReceivableEntries
      %w[recompra_percent retencao_percent fomento_percent outros_percent].each do |coluna|
        expect(conversor::FLOAT_COLUMNS).to include(coluna), coluna
        expect(conversor::NAN_SENSITIVE).to include(coluna), coluna
      end
    end

    it 'nulo e vazio continuam nulos — não viram zero em silêncio' do
      expect(described_class.to_decimal(nil)).to be_nil
      expect(described_class.to_decimal('')).to be_nil
      expect(described_class.to_decimal('   ')).to be_nil
      # Zero é zero, e é diferente de ausente: `valor_bruto = 0` é aceito no
      # legado (Q-B11) e não pode ser confundido com "não informado".
      expect(described_class.to_decimal('0.00')).to eq(BigDecimal('0'))
    end
  end
end
