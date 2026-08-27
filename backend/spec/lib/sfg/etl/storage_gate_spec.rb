# frozen_string_literal: true

require 'rails_helper'

# S14 / tarefa **9.7** — **Q-07 / F-13: `Disk` não serve para o cutover.**
#
# A decisão já existia escrita em três lugares (o cabeçalho de
# `config/storage.yml`, o pré-requisito 1.4 do `docs/runbook-cutover.md` e o
# `platform-runbook.md`). O que **não** existia era alguém conferindo: nada
# impedia `rake sfg_etl:relink_attachments RELINK=1` de gravar os **44 anexos de
# renegociação** (37,6 MB de documento financeiro, DEC-84) num serviço `Disk`
# dentro do release.
#
# O modo de falha é o pior possível num sistema financeiro: **silencioso e
# diferido**. A carga passa, o portão de reconciliação fecha, alguém assina — e
# o acervo some no primeiro redeploy que troque o diretório, meses depois, com o
# registro no banco ainda apontando para um blob inexistente. "Anexo listado com
# download que falha é pior que ausência declarada" é literalmente o argumento
# do DEC-84.
#
# **Este arquivo não escolhe provedor** — isso é do usuário (DEC-76). Ele prova
# que a escolha é cobrada no único momento em que ela ainda pode ser feita.
RSpec.describe Sfg::Etl::Attachments, 'portão de storage (Q-07 / F-13)' do
  def rodar(env:, dry_run:, override: nil)
    ambiente = ActiveSupport::StringInquirer.new(env)
    allow(Rails).to receive(:env).and_return(ambiente)
    anterior = ENV.fetch('ALLOW_DISK_STORAGE', nil)
    ENV['ALLOW_DISK_STORAGE'] = override
    described_class.new(source: Sfg::Etl::Source::Fixture.new,
                        report: Sfg::Etl::Report.new('teste_storage', io: StringIO.new),
                        io: StringIO.new).migrate!(dry_run: dry_run)
  ensure
    ENV['ALLOW_DISK_STORAGE'] = anterior
  end

  def secao(report)
    report.sections.find { |s| s.title.start_with?('Storage de destino') }
  end

  # O ambiente de teste usa `Disk` (`config/storage.yml`, alvo `test`), então o
  # portão está sempre diante do caso que ele existe para pegar.
  it 'o ambiente deste teste é mesmo Disk — senão o resto não prova nada' do
    expect(ActiveStorage::Blob.service).to be_a(ActiveStorage::Service::DiskService)
  end

  it 'ABORTA quando é para gravar, em produção, com Disk' do
    report = rodar(env: 'production', dry_run: false)

    expect(secao(report).severity).to eq(:abort)
    expect(report.aborted?).to be(true)
    expect(secao(report).lines.join("\n"))
      .to include('BLOQUEADO').and include('F-13').and include('documento financeiro')
  end

  it 'NÃO aborta no ensaio, mesmo em produção — ensaio não grava' do
    report = rodar(env: 'production', dry_run: true)

    expect(secao(report).severity).to eq(:warn)
    expect(report.aborted?).to be(false)
  end

  it 'NÃO aborta fora de produção — o ensaio precisa rodar, e o dev é Disk por definição' do
    report = rodar(env: 'development', dry_run: false)

    expect(secao(report).severity).to eq(:warn)
    expect(report.aborted?).to be(false)
  end

  # Desvio consciente existe, e **deixa rastro assinado**. Um portão sem escape
  # vira portão desligado no primeiro aperto de janela; um escape sem registro
  # vira decisão que ninguém tomou.
  it 'com `ALLOW_DISK_STORAGE=1` grava, e a autorização fica ESCRITA no relatório' do
    report = rodar(env: 'production', dry_run: false, override: '1')

    expect(report.aborted?).to be(false)
    expect(secao(report).lines.join("\n"))
      .to include('DESVIO AUTORIZADO').and include('Quem assinar este relatório')
  end

  it 'o serviço em uso vai para o CABEÇALHO de todo relatório, bloqueando ou não' do
    report = rodar(env: 'development', dry_run: true)

    expect(report.render).to include('**storage de destino**:').and include('DiskService')
  end

  # ==========================================================================
  # DEC-129.1 — `Disk` FICA, e o portão passa a cobrar AFIRMAÇÃO, não silêncio.
  # ==========================================================================
  #
  # O usuário decidiu manter `Disk`, com o deploy garantindo um volume que
  # sobrevive a redeploy. A DEC é explícita sobre a **forma**: o ETL não deve
  # simplesmente parar de recusar — isso trocaria uma trava por silêncio, e o
  # modo de falha continuaria sendo o mesmo (anexo que some semanas depois).
  #
  # Então o portão aceita `Disk` quando alguém **afirma que o volume é
  # persistente**, e **assina** a afirmação. Estes testes provam as duas metades:
  # que a afirmação destrava, e que a afirmação anônima **não** destrava.
  describe 'DEC-129.1 — afirmação explícita do volume, com autor' do
    def rodar_com_volume(env:, dry_run:, afirmado: nil, autor: nil)
      ambiente = ActiveSupport::StringInquirer.new(env)
      allow(Rails).to receive(:env).and_return(ambiente)
      anteriores = ENV.to_h.slice('ACTIVE_STORAGE_DISK_VOLUME_IS_PERSISTENT',
                                  'ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY', 'ALLOW_DISK_STORAGE')
      ENV['ACTIVE_STORAGE_DISK_VOLUME_IS_PERSISTENT'] = afirmado
      ENV['ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY'] = autor
      ENV['ALLOW_DISK_STORAGE'] = nil
      described_class.new(source: Sfg::Etl::Source::Fixture.new,
                          report: Sfg::Etl::Report.new('teste_storage', io: StringIO.new),
                          io: StringIO.new).migrate!(dry_run: dry_run)
    ensure
      %w[ACTIVE_STORAGE_DISK_VOLUME_IS_PERSISTENT ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY
         ALLOW_DISK_STORAGE].each { |k| ENV[k] = anteriores[k] }
    end

    it 'sem afirmação nenhuma continua ABORTANDO — o padrão não afrouxou' do
      report = rodar_com_volume(env: 'production', dry_run: false)

      expect(report).to be_aborted
      expect(secao(report).lines.join("\n")).to include('ACTIVE_STORAGE_DISK_VOLUME_IS_PERSISTENT')
    end

    it 'com a afirmação E o autor, GRAVA — e o relatório diz QUEM afirmou' do
      report = rodar_com_volume(env: 'production', dry_run: false,
                                afirmado: '1', autor: 'Vinícius Nascimento')

      expect(report).not_to be_aborted
      expect(secao(report).lines.join("\n"))
        .to include('VOLUME AFIRMADO PERSISTENTE')
        .and include('Vinícius Nascimento')
        .and include('DEC-129.1')
    end

    # A metade que faz a afirmação valer alguma coisa. Aceitar `=1` anônimo
    # seria reintroduzir o `if` que ninguém lê — a confirmação precisa ter autor
    # para responder "quem disse que isso estava certo?" seis meses depois.
    it 'afirmação SEM autor NÃO destrava, e a mensagem diz por quê' do
      report = rodar_com_volume(env: 'production', dry_run: false, afirmado: '1')

      expect(report).to be_aborted
      expect(secao(report).lines.join("\n"))
        .to include('SEM AUTOR').and include('ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY')
    end

    it 'autor sem a afirmação também não destrava — assinar não é afirmar' do
      report = rodar_com_volume(env: 'production', dry_run: false, autor: 'Alguém')

      expect(report).to be_aborted
    end

    it 'autor em branco conta como anônimo' do
      report = rodar_com_volume(env: 'production', dry_run: false, afirmado: '1', autor: '   ')

      expect(report).to be_aborted
      expect(secao(report).lines.join("\n")).to include('SEM AUTOR')
    end

    it 'o runbook traz o pré-requisito de conferir o volume ANTES da carga' do
      runbook = Rails.root.join('../docs/runbook-cutover.md').read

      expect(runbook).to include('ACTIVE_STORAGE_DISK_VOLUME_IS_PERSISTENT')
      expect(runbook).to include('ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY')
      expect(runbook).to include('sobrevive a um redeploy').or include('SOBREVIVE a um redeploy')
    end
  end
end
