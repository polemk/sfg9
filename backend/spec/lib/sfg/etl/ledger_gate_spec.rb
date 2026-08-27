# frozen_string_literal: true

require 'rails_helper'

# S14 / tarefa **10.7** — o portão do razão.
#
# Os exemplos usam um razão **de mentira, escrito aqui**, e não o de verdade: um
# teste que afirmasse "o razão real passa" reprovaria toda vez que uma fatia
# marcasse um ID, e portão que reprova sem motivo é portão desligado na semana
# seguinte. O que se trava aqui é o **leitor**, não o conteúdo.
RSpec.describe Sfg::Etl::LedgerGate do
  def razao(*linhas)
    arquivo = Tempfile.new(['razao', '.md'])
    arquivo.write(<<~MD)
      | ID | Feature | State | ai9 target | Test | Note |
      | -- | ------- | ----- | ---------- | ---- | ---- |
      #{linhas.join("\n")}
    MD
    arquivo.flush
    described_class.new(arquivo.path)
  end

  it 'lê a nota da última coluna — e não a quebra de linha' do
    # ⚠ **O defeito que este exemplo existe para travar, e que aconteceu:**
    # `line.split('|')` deixa `"\n"` como último pedaço. Ele não é vazio, então
    # sobrevive ao descarte de vazios finais, e depois do `strip` vira nota em
    # branco. O portão passou a acusar **213 `dropped` sem evidência** que têm
    # evidência escrita. Um portão que grita errado é pior que portão nenhum:
    # ensina o time a ignorá-lo.
    gate = razao('| FE-640 | Landing | dropped | — | — | Decisão do usuário no Phase 0 |')

    expect(gate.rows.first.note).to eq('Decisão do usuário no Phase 0')
    expect(gate.dropped_sem_evidencia).to eq([])
  end

  it 'reprova item aberto SEM dono e aprova o mesmo item COM dono' do
    sem = razao('| BE-399 | Despacho themes | pending |  |  | — |')
    com = razao('| BE-399 | Despacho themes | pending |  |  | Dono: S17, junto do tema |')

    expect(sem.abertos_sem_dono.map(&:id)).to eq(['BE-399'])
    expect(sem.verdict['nenhum item aberto sem dono']).to be(false)
    expect(com.abertos_sem_dono).to eq([])
    expect(com.verdict['nenhum item aberto sem dono']).to be(true)
  end

  it 'reprova `to-remove` e `build?` sem resolução, e aceita `build?` resolvido' do
    # A estratégia mora na Note, não numa coluna própria — ver o cabeçalho do
    # `LedgerGate`. Este exemplo trava justamente isso.
    ruim = razao('| DB-001 | X | pending |  |  | to-remove, sem decisão |',
                 '| BE-002 | Y | migrated |  |  | build? ainda decidindo |')
    bom = razao('| BE-002 | Y | migrated |  |  | build? RESOLVIDO pela DEC-89 |')

    expect(ruim.to_remove.map(&:id)).to eq(['DB-001'])
    expect(ruim.verdict['nenhum `build?` sem resolução escrita']).to be(false)
    expect(bom.verdict['nenhum `build?` sem resolução escrita']).to be(true)
  end

  it 'ignora a tabela de features NOVAS, que tem legenda própria' do
    # `NEW-*` usa o status `new`, fora da legenda do inventário. Contá-la faria
    # o portão reprovar todo dia por "status desconhecido".
    gate = razao('| NEW-001 | Feature nova | new |  |  | — |',
                 '| BE-003 | Coisa | migrated | build | spec | S2 |')

    expect(gate.rows.map(&:id)).to eq(['BE-003'])
    expect(gate.status_desconhecido).to eq([])
  end

  it 'aponta status fora da legenda em vez de somê-lo em silêncio' do
    gate = razao('| BE-004 | Coisa | done | build | spec | S2 |')

    expect(gate.status_desconhecido.map(&:status)).to eq(['done'])
    expect(gate.verdict['nenhum status fora da legenda']).to be(false)
  end

  it 'NÃO marca nada — só lê, conta e reprova' do
    fonte = File.read(Rails.root.join('app/lib/sfg/etl/ledger_gate.rb'))
    expect(fonte).not_to match(/\.write|\.update|File\.open.*['"]w/)
  end
end
