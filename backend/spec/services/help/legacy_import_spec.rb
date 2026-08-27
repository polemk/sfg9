# frozen_string_literal: true

require 'rails_helper'

# S12 / tarefa 6.1 — a carga em DOIS PASSOS do item de ajuda (DB-369 / D-58).
RSpec.describe Help::LegacyImport do
  let(:grupo) { create(:help_group, legacy_id: 1) }
  let(:categoria) { create(:help_category, group: grupo, legacy_id: 10) }

  def linha(legacy_id:, rich: nil, coluna: nil, titulo: 'Item')
    { legacy_id: legacy_id, title: titulo, category_legacy_id: 10, user_legacy_id: nil,
      rich_text_body: rich, column_description: coluna }
  end

  it 'o dry-run diz quantos vieram de CADA origem, e não grava nada' do
    linhas = [
      linha(legacy_id: 1, rich: '<p>de 2024</p>'),
      linha(legacy_id: 2, coluna: 'de 2018'),
      linha(legacy_id: 3)
    ]

    relatorio = described_class.call(linhas, dry_run: true)

    expect(relatorio.from_rich_text).to eq(1)
    expect(relatorio.from_column).to eq(1)
    expect(relatorio.without_body).to eq(1)
    expect(HelpItem.count).to eq(0)
  end

  it 'o ActionText vence a coluna quando o item tem os DOIS acervos' do
    # Inverter a ordem faria o conteúdo de 2018 sobrescrever o de 2024.
    corpo, origem = described_class.resolve_body(
      linha(legacy_id: 1, rich: '<p>novo</p>', coluna: 'antigo')
    )
    expect(origem).to eq(:rich_text)
    expect(corpo).to include('novo')
  end

  it 'os dois acervos acabam no MESMO campo e a busca acha os dois (D-58)' do
    categoria
    described_class.call(
      [linha(legacy_id: 1, rich: '<p>prorrogação em 2024</p>', titulo: 'Novo'),
       linha(legacy_id: 2, coluna: 'prorrogação em 2018', titulo: 'Antigo')],
      dry_run: false
    )

    expect(HelpItem.count).to eq(2)
    expect(Help::Search.all(term: 'prorrogacao').count).to eq(2)
  end

  it 'conta os corpos com anexo embutido — o risco alto do DB-482 (fatia S-08)' do
    relatorio = described_class.call(
      [linha(legacy_id: 1, rich: '<p><action-text-attachment sgid="x"></action-text-attachment></p>')],
      dry_run: true
    )
    expect(relatorio.with_attachments).to eq(1)
  end

  it 'categoria ausente é registrada, não silenciada' do
    relatorio = described_class.call([linha(legacy_id: 9)], dry_run: false)
    expect(relatorio.skipped).to eq(1)
    expect(relatorio.errors.first).to include('categoria')
  end
end
