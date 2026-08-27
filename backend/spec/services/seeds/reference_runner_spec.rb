# frozen_string_literal: true

require 'rails_helper'

# S3 / **OPS-540**, tarefas F.3, F.4 e F.5 — o arcabouço de seed de referência.
#
# O que este spec protege: a propriedade que torna `rake reference:seed` seguro
# como passo fixo de deploy. Sem ela, "idempotente" é promessa.
RSpec.describe Seeds::Reference::Runner do
  let(:io) { StringIO.new }

  it 'roda os catálogos e a SEGUNDA execução não cria nem atualiza nada (F.5)' do
    primeira = described_class.call!(io: io)
    expect(primeira).to all(be_a(Seeds::Reference::Report))

    antes = [UserType.count, Permission.count, ProjectGuaranteeType.count]

    segunda = described_class.call!(io: io)

    expect([UserType.count, Permission.count, ProjectGuaranteeType.count]).to eq(antes)
    expect(segunda.reject(&:skipped?)).to all(be_idempotent)
  end

  it 'o carregador é UM: a lista de catálogos é dado, não `load` espalhado' do
    entradas = described_class::CATALOGS
    expect(entradas).to all(include(:seeder, :label, :requires, :slice))
    expect(entradas.map { |e| e[:seeder] }.uniq.size).to eq(entradas.size)

    # `db/seeds.rb` passa pelo ponto de entrada único, e por mais nenhum.
    seeds = Rails.root.join('db/seeds.rb').read
    expect(seeds).to include('db/seeds/reference/index.rb')
    expect(seeds).not_to include('db/seeds/reference/user_types.rb')
    expect(seeds).not_to include('db/seeds/reference/permissions.rb')
  end

  it 'catálogo cuja fatia dona ainda não entregou o model é PULADO com aviso, não quebra' do
    entrada = { seeder: 'Seeds::Reference::Inexistente', label: 'Catálogo futuro',
                requires: %w[ModelQueAindaNaoNasceu], slice: 'S17' }
    stub_const("#{described_class}::CATALOGS", [entrada])

    relatorios = described_class.call!(io: io)

    expect(relatorios.first).to be_skipped
    expect(io.string).to include('ModelQueAindaNaoNasceu').and include('S17')
  end

  it 'roda um catálogo isolado pelo nome do semeador' do
    ProjectGuaranteeType.delete_all
    relatorio = described_class.call_one!('Seeds::Reference::GuaranteeTypes', io: io)

    expect(relatorio.created).to eq(Seeds::Reference::GuaranteeTypes::TITLES.size)
    expect(ProjectGuaranteeType.count).to eq(Seeds::Reference::GuaranteeTypes::TITLES.size)
  end

  it 'levanta em catálogo desconhecido — erro de digitação não vira silêncio' do
    expect { described_class.call_one!('Seeds::Reference::NaoExiste') }.to raise_error(ArgumentError)
  end

  # A fronteira que o DEC-64 e a DEC-86 desenham juntas.
  it 'referência e demonstração são coisas separadas, e o código diz isso' do
    referencia = Dir[Rails.root.join('app/services/seeds/reference/*.rb')].map { |f| File.basename(f, '.rb') }
    expect(referencia).to include('guarantee_types')
    # Portador, empresa e borderô são VITRINE: moram na S20, não aqui.
    expect(referencia).not_to include('carriers', 'companies', 'receivable_entries')
    expect(Dir[Rails.root.join('db/seeds/demo/writers/*.rb')].map { |f| File.basename(f, '.rb') })
      .to include('carriers')
  end
end
