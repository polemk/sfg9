# frozen_string_literal: true

require 'rails_helper'

# S13 / tarefas 5.2 e F.9 — **OPS-485, OPS-608: DKIM que degrada, não derruba.**
#
# Os dois defeitos do legado que este arquivo tranca:
#
#  - a chave privada vinha de um `.pem` **versionado no repositório**, lido com
#    `open()` dentro do `config/application.rb`. Arquivo ausente = a aplicação
#    inteira não sobe;
#  - domínio e seletor estavam assados no código.
RSpec.describe Sfg::DkimSigner do
  # Carregar `ApplicationMailer` é o que registra o interceptor (e o que traz a
  # constante `Mail` junto). Em produção e em desenvolvimento o eager load faz
  # isso no boot; num spec isolado, ninguém referenciou o mailer ainda.
  before { ApplicationMailer }

  # Chave de 1024 bits, gerada no próprio exemplo: nada de chave de assinatura
  # em arquivo do repositório — é o defeito que esta tarefa fecha.
  let(:chave) { OpenSSL::PKey::RSA.new(1024).to_pem }

  let(:mensagem) do
    Mail.new do
      from    'no-reply@safegold.com.br'
      to      'alguem@example.com'
      subject 'Seu código de acesso'
      body    'Use o código 123456.'
    end
  end

  def com_env(**pares)
    originais = pares.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    pares.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    described_class.reset_warning!
    yield
  ensure
    originais.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    described_class.reset_warning!
  end

  describe 'desligado — o estado normal de desenvolvimento e de teste' do
    it 'sem DKIM_DOMAIN não assina nada e não reclama' do
      com_env('DKIM_DOMAIN' => nil, 'DKIM_PRIVATE_KEY' => nil) do
        expect(Rails.logger).not_to receive(:warn)
        expect(described_class.status).to eq(:disabled)
        expect(described_class.sign!(mensagem)).to be(false)
        expect(mensagem['DKIM-Signature']).to be_nil
      end
    end
  end

  describe 'degradado — quer assinar e não tem chave' do
    it 'o e-mail SAI, sem assinatura, e o boot não é afetado' do
      com_env('DKIM_DOMAIN' => 'safegold.com.br', 'DKIM_PRIVATE_KEY' => nil) do
        expect(described_class.status).to eq(:degraded)
        expect(described_class).to be_degraded

        expect { described_class.sign!(mensagem) }.not_to raise_error
        expect(mensagem['DKIM-Signature']).to be_nil
      end
    end

    it 'avisa UMA vez por processo — alerta repetido a cada envio deixa de ser lido' do
      com_env('DKIM_DOMAIN' => 'safegold.com.br', 'DKIM_PRIVATE_KEY' => nil) do
        avisos = []
        allow(Rails.logger).to receive(:warn) { |m| avisos << m }

        3.times { described_class.sign!(Mail.new(from: 'a@b.c', to: 'd@e.f', subject: 'x', body: 'y')) }

        degradacao = avisos.grep(/ENVIO DEGRADADO/)
        expect(degradacao.size).to eq(1)
        expect(degradacao.first).to include('sem chave privada')
      end
    end
  end

  describe 'ativo' do
    it 'assina, e o cabeçalho traz o domínio e o seletor do ambiente' do
      com_env('DKIM_DOMAIN' => 'safegold.com.br', 'DKIM_SELECTOR' => 'dk2',
              'DKIM_PRIVATE_KEY' => chave) do
        expect(described_class.status).to eq(:active)
        expect(described_class.sign!(mensagem)).to be(true)

        assinatura = mensagem['DKIM-Signature'].to_s
        expect(assinatura).to include('d=safegold.com.br')
        expect(assinatura).to include('s=dk2')
        expect(assinatura).to include('v=1')
        expect(assinatura).to match(/b=[^;]+/)
      end
    end

    it 'não empilha assinatura: assinar duas vezes deixa UMA' do
      com_env('DKIM_DOMAIN' => 'safegold.com.br', 'DKIM_PRIVATE_KEY' => chave) do
        described_class.sign!(mensagem)
        described_class.sign!(mensagem)

        expect(mensagem.header.fields.count { |f| f.name.casecmp('DKIM-Signature').zero? }).to eq(1)
      end
    end

    it 'a chave vem do Credential quando não há ENV (DEC-61)' do
      Credential.create!(name: 'DKIM Safegold', provider: 'dkim', api_key: chave)

      com_env('DKIM_DOMAIN' => 'safegold.com.br', 'DKIM_PRIVATE_KEY' => nil) do
        expect(described_class.status).to eq(:active)
        expect(described_class.sign!(mensagem)).to be(true)
        expect(mensagem['DKIM-Signature'].to_s).to include('d=safegold.com.br')
      end
    end

    it 'chave inválida DEGRADA — o e-mail sai; interceptor que levanta cancela a entrega' do
      com_env('DKIM_DOMAIN' => 'safegold.com.br', 'DKIM_PRIVATE_KEY' => 'isto não é um PEM') do
        erros = []
        allow(Rails.logger).to receive(:error) { |m| erros << m }

        expect(described_class.sign!(mensagem)).to be(false)
        expect(mensagem['DKIM-Signature']).to be_nil
        expect(erros.join).to include('Sfg::DkimSigner').and include('SEM assinatura')
      end
    end
  end

  describe 'o interceptor está registrado no ApplicationMailer' do
    it 'e é registrado UMA vez, mesmo com o autoload recarregando a classe' do
      registrados = Mail.class_variable_get(:@@delivery_interceptors)
      expect(registrados.count { |i| i == Sfg::DkimInterceptor }).to eq(1)
    end

    it 'passa por ele todo e-mail do produto — sem chave, o envio acontece' do
      com_env('DKIM_DOMAIN' => 'safegold.com.br', 'DKIM_PRIVATE_KEY' => nil) do
        expect { Sfg::DkimInterceptor.delivering_email(mensagem) }.not_to raise_error
        expect(mensagem['DKIM-Signature']).to be_nil
      end
    end

    it 'com chave, o e-mail entregue sai assinado' do
      com_env('DKIM_DOMAIN' => 'safegold.com.br', 'DKIM_PRIVATE_KEY' => chave) do
        Sfg::DkimInterceptor.delivering_email(mensagem)
        expect(mensagem['DKIM-Signature'].to_s).to include('d=safegold.com.br')
      end
    end

    # 26/08/2026 — em desenvolvimento o job do código de acesso morreu com
    # `NameError: uninitialized constant Sfg::DkimInterceptor::DkimSigner`. A causa
    # era de bancada (autoload sob concorrência num worker de horas), mas expôs que
    # a garantia "nunca levanta" dependia de a chamada CHEGAR ao signer: todo o
    # `rescue` morava lá dentro. Este exemplo prova a borda, não o miolo.
    it 'não cancela a entrega nem quando quebra ANTES de chegar ao signer' do
      allow(Sfg::DkimSigner).to receive(:sign!).and_raise(NameError, 'uninitialized constant')

      expect { Sfg::DkimInterceptor.delivering_email(mensagem) }.not_to raise_error
      expect(Sfg::DkimInterceptor.delivering_email(mensagem)).to eq(mensagem)
      expect(mensagem['DKIM-Signature']).to be_nil
    end
  end

  describe 'nada de chave em arquivo do repositório' do
    it 'não existe `.pem` versionado no backend — foi o pior dos três defeitos' do
      pems = Dir[Rails.root.join('**/*.pem')].reject { |p| p.include?('/tmp/') || p.include?('/node_modules/') }
      expect(pems).to be_empty, "PEM versionado encontrado: #{pems.join(', ')}"
    end
  end
end
