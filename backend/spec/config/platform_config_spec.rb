# frozen_string_literal: true

require 'rails_helper'

# Contrato de plataforma — OPS-611, OPS-626, OPS-627, OPS-628, OPS-605.
#
# Cada exemplo aqui cobre uma decisão que muda o COMPORTAMENTO de quem já roda o
# ambiente. Sem teste, "o boot falha quando falta segredo" vira uma linha de commit
# que alguém remove no primeiro deploy incômodo.
RSpec.describe 'contrato de configuração da plataforma' do
  describe 'boot fail-fast por segredo ausente (OPS-611)' do
    it 'não exige nada em test — a suíte roda sem variável de integração externa' do
      expect(RequiredEnv.required_for('test')).to be_empty
      expect(RequiredEnv.missing('test', {})).to be_empty
    end

    it 'exige os quatro segredos base em development' do
      expect(RequiredEnv.required_for('development'))
        .to contain_exactly('SECRET_KEY_BASE', 'DEVISE_JWT_SECRET_KEY', 'REDIS_URL', 'APP_NAME')
    end

    it 'exige em production as chaves de encriptação, que vinham commitadas na base' do
      expect(RequiredEnv.required_for('production')).to include(
        'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY',
        'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY',
        'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT'
      )
    end

    # A armadilha: nomear só a primeira ausente faz descobrir a lista um deploy por vez.
    it 'nomeia TODAS as ausentes de uma vez, não a primeira' do
      env = { 'REDIS_URL' => 'redis://x', 'APP_NAME' => 'Safegold' }

      expect { RequiredEnv.verify!('development', env) }
        .to raise_error(RuntimeError, /SECRET_KEY_BASE.*DEVISE_JWT_SECRET_KEY/m)
    end

    it 'trata string em branco como ausente' do
      env = { 'SECRET_KEY_BASE' => '   ', 'DEVISE_JWT_SECRET_KEY' => 'x', 'REDIS_URL' => 'x', 'APP_NAME' => 'x' }

      expect(RequiredEnv.missing('development', env)).to eq(['SECRET_KEY_BASE'])
    end
  end

  describe 'TLS verificado por padrão (OPS-626 / C-05)' do
    # O legado desligava VERIFY_PEER globalmente no Windows e a própria base ai9
    # repetia `openssl_verify_mode: 'none'` nos dois ambientes.
    %w[development production].each do |env_name|
      it "não deixa `openssl_verify_mode: 'none'` em #{env_name}.rb" do
        # Só linhas de código: o comentário que documenta a correção cita o valor
        # antigo de propósito, e um grep ingênuo casaria com ele.
        codigo = Rails.root.join('config', 'environments', "#{env_name}.rb")
                     .readlines.reject { |l| l.strip.start_with?('#') }.join

        expect(codigo).not_to match(/openssl_verify_mode:\s*'none'/)
        expect(codigo).to include("ENV.fetch('SMTP_OPENSSL_VERIFY_MODE', 'peer')")
      end
    end
  end

  describe 'máscara de log (OPS-627)' do
    it 'não deixa cpf, cnpj nem cpf_cnpj chegarem ao log' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtrado = filter.filter(
        'cpf' => '123.456.789-00', 'cnpj' => '12.345.678/0001-99', 'cpf_cnpj' => '123', 'name' => 'Maria'
      )

      expect(filtrado.values_at('cpf', 'cnpj', 'cpf_cnpj')).to all(eq('[FILTERED]'))
      expect(filtrado['name']).to eq('Maria')
    end
  end

  describe 'cabeçalhos de segurança (OPS-628 / DEC-48)' do
    it 'aplica CSP fechado às respostas de API e uma exceção escrita para /docs' do
      expect(SfgSecurityHeaders::API_POLICY).to include("default-src 'none'")
      expect(SfgSecurityHeaders::DOCS_POLICY).to include('https://unpkg.com')
    end

    it 'entrega nosniff, DENY e Permissions-Policy' do
      expect(SfgSecurityHeaders::STATIC_HEADERS).to include(
        'X-Content-Type-Options' => 'nosniff',
        'X-Frame-Options' => 'DENY'
      )
    end
  end

  describe 'login social do Facebook desligado (OPS-605)' do
    it 'não registra a estratégia no OmniAuth com o default' do
      expect(ENV.fetch('OAUTH_FACEBOOK_ENABLED', 'false')).to eq('false')
      expect(Devise.omniauth_providers).not_to include(:facebook)
    end
  end

  describe 'contrato do .env.example' do
    let(:example) { Rails.root.join('.env.example').read }

    it 'documenta toda variável obrigatória de todo ambiente' do
      todas = RequiredEnv::BY_ENVIRONMENT.values.flatten.uniq

      ausentes = todas.reject { |name| example.include?(name) }
      expect(ausentes).to be_empty, "faltam no .env.example: #{ausentes.join(', ')}"
    end

    it 'não versiona valor real de segredo' do
      # Um `SECRET=` seguido de coisa que não seja vazio, placeholder ou comentário.
      suspeitas = example.lines.grep(/^(SECRET_KEY_BASE|DEVISE_JWT_SECRET_KEY|.*_API_KEY|.*PASSWORD|CSRF_SECRET|ACTIVE_RECORD_ENCRYPTION_\w+)=(.+)$/)
                         .reject { |l| l.split('=', 2).last.strip.match?(/\A(\*+|)\z/) }

      expect(suspeitas).to be_empty, "possível segredo real versionado: #{suspeitas.join}"
    end
  end
end
