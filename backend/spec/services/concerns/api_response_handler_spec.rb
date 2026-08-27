# frozen_string_literal: true

require 'rails_helper'

# **Concordância de gênero na frase de "não encontrado".**
#
# O helper compunha `"#{recurso} não encontrado"` com o adjetivo fixo, e sete
# chamadas passam substantivo feminino: a tela dizia **"Instância não
# encontrado"**, "Permissão não encontrado", "Conexão não encontrado" e
# "Participação não encontrado".
#
# Achado **renderizando** `/platform/whatsapp` num banco sem instância
# cadastrada — `tsc`, `rspec` e `rubocop` não têm como pegar concordância, e
# essa frase é lida pelo cliente.
RSpec.describe ApiResponseHandler do
  let(:objeto) { Class.new { include ApiResponseHandler }.new }

  it 'concorda no masculino por padrão — a maioria das chamadas' do
    expect(objeto.not_found_response('Usuário')[:error]).to eq('Usuário não encontrado')
    expect(objeto.not_found_response[:error]).to eq('Registro não encontrado')
  end

  it 'concorda no feminino quando pedido' do
    expect(objeto.not_found_response('Instância', genero: :feminino)[:error])
      .to eq('Instância não encontrada')
  end

  it 'responde 404 nos dois casos' do
    expect(objeto.not_found_response('Projeto')[:status]).to eq(404)
    expect(objeto.not_found_response('Permissão', genero: :feminino)[:status]).to eq(404)
  end

  # ------------------------------------------------------------------
  # O outro caminho de 404: os serviços com `resource_label`
  # ------------------------------------------------------------------
  # `ProjectScopedService` e `CatalogService` compunham a frase com o remendo
  # `(a)` — "Renegociação não encontrado(a).", "vinculados a este(a) empresa".
  # Achado renderizando `/renegotiations/:id` de um projeto que não é o
  # corrente (o 404 de escopo, que é comportamento CORRETO).
  describe 'os serviços com `resource_label`' do
    it 'nenhum deles usa o remendo `(a)`' do
      remendos = []

      Dir[Rails.root.join('app/services/**/*.rb')].each do |arquivo|
        # **Sem os comentários.** Quase toda menção que sobra ao remendo está em
        # comentário, explicando o que saiu — e essa documentação é desejável.
        # O que não pode é o remendo chegar ao texto que o cliente lê. Um
        # scanner que não separa os dois vira ruído e acaba desligado — mesma
        # razão do varredor de marca do front.
        conteudo = File.read(arquivo).gsub(/^\s*#.*$/, '')
        %w[encontrado(a) este(a)].each do |remendo|
          remendos << "#{arquivo.sub(Rails.root.to_s, '')}: #{remendo}" if conteudo.include?(remendo)
        end
      end

      expect(remendos).to be_empty
    end

    # A lista de rótulos femininos é conferida contra o próprio código: um
    # serviço novo com rótulo feminino e sem `resource_genero` reprova aqui, que
    # é como o remendo voltaria.
    it 'todo rótulo feminino declara `resource_genero`' do
      femininos = %w[Carteira Cobrança Empresa Garantia Parcela Remuneração Renegociação]
      faltando = []

      Dir[Rails.root.join('app/services/**/*.rb')].each do |arquivo|
        conteudo = File.read(arquivo)
        conteudo.scan(/def resource_label = '([^']+)'/) do |(rotulo)|
          next unless femininos.any? { |palavra| rotulo.start_with?(palavra) }
          next if conteudo.include?('resource_genero = :feminino')

          faltando << "#{arquivo.sub(Rails.root.to_s, '')}: #{rotulo}"
        end
      end

      expect(faltando).to be_empty
    end

    it 'o 404 do serviço concorda — "Renegociação não encontrada."' do
      resposta = RenegotiationService.send(:not_found)

      expect(resposta[:error]).to eq('Renegociação não encontrada.')
    end

    it 'e o masculino continua masculino' do
      resposta = SegmentService.send(:not_found)

      expect(resposta[:error]).to eq('Segmento não encontrado.')
    end
  end

  # A prova de que os sete pontos foram trocados, e não só o helper: uma varredura
  # do código, porque acrescentar uma chamada feminina nova é o jeito de o defeito
  # voltar sem ninguém ver.
  it 'nenhuma chamada com substantivo feminino ficou sem `genero:`' do
    femininos = %w[Instância Permissão Conexão Participação]
    faltando = []

    Dir[Rails.root.join('app/**/*.rb')].each do |arquivo|
      File.read(arquivo).scan(/not_found_response\((.*?)\)/) do |(argumentos)|
        next unless femininos.any? { |palavra| argumentos.include?(palavra) }
        next if argumentos.include?('genero: :feminino')

        faltando << "#{arquivo.sub(Rails.root.to_s, '')}: #{argumentos}"
      end
    end

    expect(faltando).to be_empty
  end
end
