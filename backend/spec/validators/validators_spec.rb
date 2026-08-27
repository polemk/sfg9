# frozen_string_literal: true

require 'rails_helper'

# BE-455 e BE-456. Os dois validadores rodam contra um model em memória, porque
# nenhum model do repositório os declara ainda — eles nascem para S5 e S13.
RSpec.describe 'Validadores compartilhados' do
  describe IntervalValidator do
    let(:model) do
      Class.new do
        include ActiveModel::Model
        attr_accessor :min_value, :max_value

        validates :min_value, interval: true
        validates :max_value, interval: true

        def self.name = 'Faixa'
      end
    end

    it 'aceita uma faixa coerente' do
      expect(model.new(min_value: 1, max_value: 10)).to be_valid
    end

    # O defeito nº 1 do original: `value.to_i.to_s == value` compara String com
    # Integer, então TODA faixa inteira era recusada.
    it 'aceita Integer — no legado o inteiro era recusado como "não inteiro"' do
      registro = model.new(min_value: 1, max_value: 10)
      registro.valid?
      expect(registro.errors[:min_value]).to be_empty
    end

    it 'aceita texto de inteiro' do
      expect(model.new(min_value: '1', max_value: '10')).to be_valid
    end

    it 'recusa fracionário' do
      registro = model.new(min_value: '1.5', max_value: 10)
      expect(registro).not_to be_valid
      expect(registro.errors[:min_value]).to include('deve ser um número inteiro')
    end

    it 'recusa texto que não é número' do
      registro = model.new(min_value: 'dez', max_value: 10)
      expect(registro).not_to be_valid
    end

    it 'recusa mínimo maior que o máximo' do
      registro = model.new(min_value: 10, max_value: 1)
      expect(registro).not_to be_valid
      expect(registro.errors[:min_value]).to include('não pode ser maior que o valor máximo')
      expect(registro.errors[:max_value]).to include('não pode ser menor que o valor mínimo')
    end

    it 'recusa mínimo igual ao máximo' do
      registro = model.new(min_value: 5, max_value: 5)
      expect(registro).not_to be_valid
      expect(registro.errors[:min_value]).to include('não pode ser igual ao valor máximo')
    end

    # Defeito nº 3 do original: `value <= nil` levanta dentro do `valid?`.
    it 'com a outra ponta vazia NÃO levanta — devolve válido para aquele campo' do
      registro = model.new(min_value: 5, max_value: nil)
      expect { registro.valid? }.not_to raise_error
      expect(registro.errors[:min_value]).to be_empty
    end

    # Defeito nº 2: `errors[field] << "..."` não registra nada no Rails 8.
    it 'os erros são realmente registrados (o legado escrevia num array descartado)' do
      registro = model.new(min_value: 'x', max_value: 1)
      registro.valid?
      expect(registro.errors).not_to be_empty
    end

    it 'aceita nomes de coluna diferentes' do
      outro = Class.new do
        include ActiveModel::Model
        attr_accessor :piso, :teto

        validates :piso, interval: { min: :piso, max: :teto }
        validates :teto, interval: { min: :piso, max: :teto }

        def self.name = 'Outra'
      end

      expect(outro.new(piso: 9, teto: 2)).not_to be_valid
      expect(outro.new(piso: 2, teto: 9)).to be_valid
    end
  end

  describe UriValidator do
    let(:model) do
      Class.new do
        include ActiveModel::Model
        attr_accessor :url

        validates :url, uri: true

        def self.name = 'ComUrl'
      end
    end

    it 'aceita http e https' do
      expect(model.new(url: 'http://exemplo.com.br')).to be_valid
      expect(model.new(url: 'https://exemplo.com.br/caminho?q=1')).to be_valid
    end

    it 'recusa outro esquema' do
      expect(model.new(url: 'ftp://exemplo.com.br')).not_to be_valid
      expect(model.new(url: 'javascript:alert(1)')).not_to be_valid
    end

    it 'recusa texto solto e endereço sem host' do
      expect(model.new(url: 'exemplo.com.br')).not_to be_valid
      expect(model.new(url: 'http://')).not_to be_valid
      expect(model.new(url: 'http://exemplo .com')).not_to be_valid
    end

    # D6 — o ponto da tarefa: validar URL deixa de ser chamada de rede.
    it 'NÃO faz requisição de rede — host inexistente é válido no formato' do
      registro = model.new(url: 'https://host-que-nao-existe-999.invalid/webhook')
      expect(registro).to be_valid
      # `webmock` está ligado em todo o spec_helper: qualquer HTTP real
      # levantaria `WebMock::NetConnectNotAllowedError` aqui.
    end

    it 'a mensagem é pt-BR de verdade (o legado apontava para chave inexistente)' do
      registro = model.new(url: 'nada')
      registro.valid?
      expect(registro.errors[:url].first).to eq('não é uma URL http(s) válida')
      expect(registro.errors[:url].first).not_to include('translation missing')
    end

    it 'respeita `allow_blank`' do
      permissivo = Class.new do
        include ActiveModel::Model
        attr_accessor :url

        validates :url, uri: { allow_blank: true }

        def self.name = 'Opcional'
      end

      expect(permissivo.new(url: nil)).to be_valid
      expect(permissivo.new(url: '')).to be_valid
    end

    it 'aceita restringir o esquema' do
      so_https = Class.new do
        include ActiveModel::Model
        attr_accessor :url

        validates :url, uri: { schemes: %w[https] }

        def self.name = 'SoHttps'
      end

      expect(so_https.new(url: 'http://exemplo.com')).not_to be_valid
      expect(so_https.new(url: 'https://exemplo.com')).to be_valid
    end
  end
end
