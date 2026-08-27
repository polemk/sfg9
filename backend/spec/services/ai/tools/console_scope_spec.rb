# frozen_string_literal: true

require 'rails_helper'

# O PORTÃO das ferramentas do assistente (DEC-13.2).
#
# Três riscos, e os três são de vazamento — por isso o spec existe antes dos
# handlers:
#
#  1. **sessão sem dono** — a ferramenta roda depois do controller, sem
#     `current_user`. Se ela lesse a partir da sessão sozinha, voltaria o IDOR
#     que o Bloco 8 fechou no `/chat/*`;
#  2. **projeto não revalidado** — usar o id guardado responderia com o número de
#     um projeto do qual a pessoa já foi removida (contrato C1);
#  3. **a porta lateral** — o que a tela esconde do papel, a conversa também tem
#     de esconder, e administração fica fora até para o OG.
RSpec.describe Ai::Tools::ConsoleScope do
  before { UserType.seed_default_types! }

  let(:gerente)  { create(:user, user_type: UserType.gerente) }
  let(:estranho) { create(:user, user_type: UserType.gerente) }
  let!(:projeto) { create_project_with_owner(gerente) }
  let(:flow)     { create(:chat_flow) }

  def escopo_de(user)
    described_class.new(create(:chat_session, chat_flow: flow, user: user))
  end

  describe 'o dono da conversa' do
    it 'sem dono não lê dado nem ajuda' do
      escopo = described_class.new(create(:chat_session, chat_flow: flow))

      expect(escopo.block_for_data('dash')).to include(success: false, message: described_class::SEM_DONO)
      expect(escopo.block_for_help('faq')).to include(success: false, message: described_class::SEM_DONO)
    end
  end

  describe 'o projeto corrente' do
    it 'resolve o projeto gravado quando a participação existe' do
      gerente.update!(current_project_id: projeto.id)

      escopo = escopo_de(gerente)
      expect(escopo.project).to eq(projeto)
      expect(escopo.block_for_data('dash')).to be_nil
    end

    # O fallback do `resolve_current_project`, copiado aqui de propósito: quem
    # participa de um projeto só e nunca tocou no seletor vê os números na tela.
    # O assistente roda dentro dessa tela — discordar dela é pior que calar.
    it 'sem preferência gravada, participação única já é o projeto' do
      expect(escopo_de(gerente).project).to eq(projeto)
    end

    it 'sem preferência e com vários projetos, pede a escolha em vez de adivinhar' do
      create_project_with_owner(gerente)

      expect(escopo_de(gerente).block_for_data('dash'))
        .to include(success: false, message: described_class::SEM_PROJETO)
    end

    # O caso que a revalidação existe para pegar: o id continua gravado na
    # coluna, a linha de `memberships` não existe mais.
    it 'participação revogada derruba o projeto, mesmo com o id ainda gravado' do
      gerente.update!(current_project_id: projeto.id)
      Membership.where(project: projeto, user: gerente).destroy_all

      escopo = escopo_de(gerente)
      expect(escopo.project).to be_nil
      expect(escopo.block_for_data('dash')).to include(message: described_class::SEM_PROJETO)
    end

    it 'projeto de outra pessoa gravado na coluna não vira projeto corrente' do
      alheio = create_project_with_owner(estranho)
      gerente.update!(current_project_id: alheio.id)

      expect(escopo_de(gerente).project).to be_nil
    end
  end

  describe 'a matriz DEC-18' do
    it 'segue a matriz para os recursos que o assistente lê' do
      escopo = escopo_de(gerente)

      expect(escopo.allow?('dash')).to be true
      expect(escopo.allow?('faq')).to be true
      expect(escopo.allow?('renegotiations')).to be true
    end

    # A lista de proibidos é MAIS restritiva que a matriz de propósito: o uso
    # definido é ajuda ao operador, não administração por conversa.
    it 'nega administração e dado sensível inclusive para o OG' do
      og = create(:user, user_type: UserType.og)
      escopo = escopo_de(og)

      described_class::FORBIDDEN_RESOURCES.each do |recurso|
        expect(escopo.allow?(recurso)).to be(false), "#{recurso} deveria estar fora do alcance do assistente"
      end
    end

    it 'recusa a leitura quando o papel não alcança o recurso' do
      escopo = escopo_de(gerente)
      allow(Authorization::Matrix).to receive(:allow?).and_return(false)

      expect(escopo.block_for_help('faq')).to include(success: false, message: described_class::SEM_ACESSO)
    end
  end
end
