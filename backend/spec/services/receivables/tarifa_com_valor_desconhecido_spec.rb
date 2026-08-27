# frozen_string_literal: true

require 'rails_helper'

# **DEC-120 — a tarifa com `NaN` entra como NULO, não como zero.**
#
# ## A decisão, nas palavras dela
#
# > *"o valor `NaN` (D-10) entra como **NULO**, nao como zero. Preserva a
# > informacao de que o valor e DESCONHECIDO, em vez de afirmar que e zero. […]
# > carrega a tarifa com valor NULO e LISTA a linha e o borderô pai. As somas do
# > borderô IGNORAM tarifa nula (nao propagam nulo, nao contam como zero na
# > media), e a tela sinaliza que o borderô tem tarifa desconhecida"*
#
# ## O dado real que a motivou
#
# **Uma** linha, no dump de 31/05/2025: `receivable_taxes.id = 47391`, deságio
# do borderô `22424`. Em float o `NaN` se propaga por toda soma que o encontre —
# essa única linha deixou **nove colunas** do borderô pai com `NaN`.
#
# ## Por que cada exemplo abaixo existe
#
# São quatro afirmações independentes, e nenhuma delas é provável por leitura:
#
# 1. o **transporte** não devolve mais `NaN` (`BigDecimal("NaN")` NÃO levanta —
#    devolve `NaN`, e foi por aí que o valor entrou);
# 2. o **banco** aceita o nulo (a coluna nascia `null: false`);
# 3. a **soma** ignora a tarifa nula, e o borderô continua gravável — antes o
#    registro nem chegava a ser salvo;
# 4. a **tela** recebe a marca (`has_unknown_tax`), porque um total parcial sem
#    aviso é pior do que um total ausente.
RSpec.describe 'DEC-120 — tarifa de valor desconhecido' do
  # ------------------------------------------------------------------
  # 1. O transporte
  # ------------------------------------------------------------------
  describe 'Sfg::Etl::Values.to_decimal_finite' do
    it 'devolve NULO para os três textos que `numeric` aceita e que não são número' do
      %w[NaN Infinity -Infinity].each do |texto|
        expect(described_class_values.to_decimal_finite(texto)).to be_nil, "#{texto} deveria virar nulo"
      end
    end

    it 'não mexe em número válido — inclusive negativo e com centavos' do
      expect(described_class_values.to_decimal_finite('1234.56')).to eq(BigDecimal('1234.56'))
      expect(described_class_values.to_decimal_finite('-0.01')).to eq(BigDecimal('-0.01'))
      expect(described_class_values.to_decimal_finite(nil)).to be_nil
    end

    # A prova de que a mudança era necessária: o conversor genérico continua
    # devolvendo `NaN`, **de propósito** — as 32 linhas de `receivable_entries`
    # com `NaN` em coluna de dinheiro ainda não têm disposição do usuário, e
    # decidir por ele em 32 lugares não é o que a DEC-120 autorizou.
    it 'o `to_decimal` genérico continua devolvendo NaN — o escopo da decisão é a tarifa' do
      generico = described_class_values.to_decimal('NaN')

      expect(generico).to be_a(BigDecimal)
      expect(generico).to be_nan
    end

    def described_class_values = Sfg::Etl::Values
  end

  # ------------------------------------------------------------------
  # 2. O conversor da tarifa, e a listagem que a decisão exige
  # ------------------------------------------------------------------
  describe 'Sfg::Etl::Converters::ReceivableTaxes' do
    # O conversor é exercitado pela conversão PURA, sem subir o motor: `ref`
    # resolve por um duplo do `run`, que é o que o motor faz com o de-para.
    # Mesmo desenho de `spec/lib/sfg/etl/structure_converters_spec.rb`.
    let(:run) do
      duplo = instance_double(Sfg::Etl::Run)
      allow(duplo).to receive(:resolve_reference) { |tabela, pk| "#{tabela}-#{pk}" }
      duplo
    end
    let(:converter) { Sfg::Etl::Converters::ReceivableTaxes.new(run) }
    let(:linha) do
      {
        'id' => 47_391, 'receivable_entry_id' => 22_424, 'movement_kind_id' => 7,
        'value' => 'NaN', 'title' => 'Desagio',
        'is_advalorem' => 0, 'is_desagio' => 1, 'is_iof' => 0,
        'created_at' => '2023-05-10 09:00:00', 'updated_at' => '2023-05-10 09:00:00'
      }
    end

    it 'converte o valor para NULO, e não para zero' do
      expect(converter.convert(linha)[:value]).to be_nil
    end

    # *"LISTA a linha e o borderô pai"*: quem for conferir abre a tela **pelo
    # borderô**, então o id do pai precisa estar escrito na linha do relatório.
    it 'reporta a anomalia nomeando a linha E o borderô pai' do
      texto = converter.anomalies(linha).join("\n")

      expect(texto).to include('47391')
      expect(texto).to include('22424')
      expect(texto).to match(/NULO/i)
      expect(texto).to include('DEC-120')
    end

    it 'não reporta anomalia nenhuma quando o valor é número' do
      expect(converter.anomalies(linha.merge('value' => '250.00'))).to be_empty
    end
  end

  # ------------------------------------------------------------------
  # 3. O banco, a soma e a gravação
  # ------------------------------------------------------------------
  describe 'o borderô com tarifa de valor desconhecido' do
    let(:project) { create(:project) }
    let(:desagio) { create(:movement_kind, :desagio) }
    let(:outra) { create(:movement_kind) }

    # Sem `:calculado`: o registro é gravado pelo serviço logo abaixo, que é o
    # mesmo caminho da tela.
    let(:entry) { create(:receivable_entry, project: project) }

    before { create(:iof_rate) }

    it 'a coluna ACEITA nulo — era `null: false` e a decisão não cabia no banco' do
      tarifa = ReceivableTax.new(receivable_entry: entry, movement_kind: desagio, value: nil)

      expect(tarifa.save).to be(true)
      expect(tarifa.reload.value).to be_nil
    end

    it 'continua RECUSANDO `NaN` — nulo é "não sei", NaN é registro corrompido' do
      tarifa = ReceivableTax.new(receivable_entry: entry, movement_kind: desagio,
                                 value: BigDecimal('NaN'))

      expect(tarifa.save).to be(false)
      expect(tarifa.errors[:value]).to be_present
    end

    # O coração da decisão: *"as somas do borderô IGNORAM tarifa nula (não
    # propagam nulo, não contam como zero na média)"*.
    it 'a soma das tarifas ignora a nula e vale o total do que se SABE' do
      resultado = Receivables::Calculator.call(
        Receivables::Calculator::Input.new(
          valor_bruto: BigDecimal('100000.00'), vlr_bruto_recusado: 0,
          qtd_titulos: 10, qtd_recusada: 0,
          prz_med_pond_emp: 30, prz_med_pond_bco: 32,
          float_acordado: 2, cst_efetivo_acordado: 2.5,
          recompra: 0, retencao: 0, fomento: 0, outros: 0,
          taxes: [
            Receivables::Calculator::Tax.new(value: BigDecimal('300.00'), is_desagio: true),
            Receivables::Calculator::Tax.new(value: nil, is_desagio: true)
          ]
        )
      )

      expect(resultado[:valor_total_tarifas]).to eq(BigDecimal('300.00'))
      expect(resultado[:tarifas_desagio]).to eq(BigDecimal('300.00'))
      # Nenhum derivado sai contaminado — era isto que o `NaN` fazia com nove
      # colunas do borderô 22424.
      expect(Receivables::InputGuard.result_errors(resultado)).to be_empty
    end

    it 'a guarda deixa o borderô com tarifa nula ser GRAVADO' do
      entry.taxes.create!(movement_kind: desagio, value: nil)
      entry.taxes.create!(movement_kind: outra, value: BigDecimal('120.00'))

      erros = Receivables::InputGuard.check(entry.reload.calculator_input)

      expect(erros).to be_empty
    end

    it 'o borderô se declara: `unknown_tax?`' do
      entry.taxes.create!(movement_kind: outra, value: BigDecimal('120.00'))
      expect(entry.reload.unknown_tax?).to be(false)

      entry.taxes.create!(movement_kind: desagio, value: nil)
      expect(entry.reload.unknown_tax?).to be(true)
    end

    # `taxes.loaded?` tem dois ramos e os dois precisam responder igual: o
    # detalhe carrega a coleção, a listagem a traz por `includes`.
    it 'responde o mesmo com a coleção carregada e sem ela' do
      entry.taxes.create!(movement_kind: desagio, value: nil)

      carregado = ReceivableEntry.includes(:taxes).find(entry.id)
      cru = ReceivableEntry.find(entry.id)

      expect(carregado.taxes).to be_loaded
      expect(carregado.unknown_tax?).to be(true)
      expect(cru.unknown_tax?).to be(true)
    end
  end

  # ------------------------------------------------------------------
  # 4. A tela
  # ------------------------------------------------------------------
  describe 'o que a tela recebe' do
    let(:project) { create(:project) }
    let(:entry) { create(:receivable_entry, project: project) }

    it 'expõe `has_unknown_tax` — sem ele a tela mostra total parcial sem aviso' do
      entry.taxes.create!(movement_kind: create(:movement_kind), value: nil)

      json = Api::Entities::ReceivableEntry.represent(entry.reload).as_json

      expect(json[:has_unknown_tax]).to be(true)
    end

    it 'é `false` no borderô normal — o aviso não pode virar ruído de fundo' do
      entry.taxes.create!(movement_kind: create(:movement_kind), value: BigDecimal('10.00'))

      json = Api::Entities::ReceivableEntry.represent(entry.reload).as_json

      expect(json[:has_unknown_tax]).to be(false)
    end
  end
end
