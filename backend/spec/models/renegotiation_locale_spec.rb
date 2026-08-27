# frozen_string_literal: true

require 'rails_helper'

# **BE-199 — os nomes de campo da renegociação em português.**
#
# O legado traduzia cada um à mão, um `translate_keys` por linha, no
# `renegotiations_controller.rb:144-186` — 43 chamadas. A migração não portou
# nenhuma: `grep -c renegotiation config/locales/pt-BR.yml` dava **zero**, e a
# mensagem de erro saía com o nome cru da coluna em inglês
# (`installments_main_value_with_interest_cm não pode ficar em branco`) numa
# tela que fala português. Achado pela conferência de paridade da Phase 4.
#
# **Este spec pergunta ao model, não ao YAML.** Conferir que a chave existe no
# arquivo provaria só que alguém digitou a chave; o que interessa é a frase que
# o usuário lê, e ela depende de o Rails achar a chave no caminho certo
# (`activerecord.attributes.renegotiation.*`). Uma chave no lugar errado passa
# num teste de YAML e falha na tela.
RSpec.describe 'Nomes de campo da renegociação (pt-BR)' do
  # As traduções que o legado tinha e que o ai9 também tem como coluna. Ficam
  # escritas aqui, e não lidas do YAML, para o teste comparar com a FONTE (o
  # legado) em vez de consigo mesmo.
  ESPERADOS = {
    provider_name: 'Fornecedor',
    kind: 'Tipo de renegociação',
    original_value: 'Valor da renegociação',
    original_pending_value: 'Valor a vencer',
    additional_value: 'Despesas adicionais (exceto juros)',
    total_debt: 'Valor com juros projetados',
    remaining_value: 'Valor a pagar',
    installments_main_value: 'Valor principal',
    renegotiation_date: 'Data da negociação',
    interest_rate_correction: 'Taxa Juro Correção',
    correct_value: 'Valor Atualizado até data Correção',
    grace_period: 'Carência (em dias)',
    operation_interest_rate: 'Taxa de Juros Acordada',
    observation: 'Observação',
    origin: 'Origem',
    installments_count: 'Quantidade Parcelas',
    paid_installments: 'Parcelas pagas',
    overdue_installments: 'Parcelas vencidas',
    due_installments: 'Parcelas a vencer',
    state: 'Estado',
    paid_percent: 'Porcentagem paga',
    current_installment_value: 'Valor da próxima parcela',
    current_value: 'Valor presente',
    first_due_date: 'Primeiro vencimento',
    last_due_date: 'Último vencimento',
    title: 'Nome da renegociação',
    monetary_correction: 'Correção monetária',
    installments_interest_value: 'Valor juros das parcelas',
    installments_main_value_with_interest: 'Valor principal + juros',
    installments_monetary_correction_value: 'Valor correção monetária das parcelas',
    installments_main_value_with_interest_cm: 'Valor principal c/ juros e correção monetária',
    main_value: 'Valor total da renegociação',
    paid_value_with_interest_cm: 'Valor pago c/ juros e correção monetária',
    pending_main_value: 'Valor pendente',
    late_payment_value: 'Valor pago mora e juros por atraso',
    desagio_value: 'Valor do deságio',
    total_value_with_desagio: 'Valor após deságio',
  }.freeze

  ESPERADOS.each do |campo, texto|
    it "`#{campo}` se chama \"#{texto}\"" do
      expect(Renegotiation.human_attribute_name(campo)).to eq(texto)
    end
  end

  # `paid_value` tinha DUAS traduções no legado — "Valor pago" (`:150`) e "Valor
  # pago total" (`:181`). As chamadas eram sequenciais, então a última vencia e
  # o usuário via "Valor pago total". A primeira era código morto por
  # sobrescrita, não uma segunda tradução legítima.
  it '`paid_value` usa a tradução que VENCIA no legado, não a primeira escrita' do
    expect(Renegotiation.human_attribute_name(:paid_value)).to eq('Valor pago total')
  end

  # O `belongs_to` obrigatório do Rails reporta o erro no nome da ASSOCIAÇÃO
  # (`project`), não na coluna (`project_id`). Sem os dois verbetes a mensagem
  # sai "Project é obrigatório(a)", com o nome da classe em inglês.
  it 'traduz a associação, e não só a coluna `_id`' do
    %i[project provider company].each do |assoc|
      esperado = { project: 'Projeto', provider: 'Fornecedor', company: 'Empresa' }[assoc]
      expect(Renegotiation.human_attribute_name(assoc)).to eq(esperado)
      expect(Renegotiation.human_attribute_name(:"#{assoc}_id")).to eq(esperado)
    end
  end

  # O caso que motivou tudo: a mensagem que o usuário lê, montada de ponta a
  # ponta pelo Rails. Sem os verbetes ela vinha com a coluna crua no meio.
  it 'a mensagem de erro sai inteira em português' do
    renegociacao = Renegotiation.new
    renegociacao.valid?

    mensagens = renegociacao.errors.full_messages.join(' | ')

    expect(mensagens).not_to match(/[a-z]+_[a-z_]+ /), "sobrou nome de coluna cru: #{mensagens}"
    expect(mensagens).to include('Projeto')
  end
end
