# frozen_string_literal: true

require 'rails_helper'

# **BE-486, BE-487, BE-488, BE-530** — os e-mails do observador e da conversa.
#
# Estes cinco e-mails existiam e conferiam com o legado, mas **nenhuma linha de
# spec no repositório inteiro mencionava `ObserverMailer` ou `MessageMailer`**.
# A conferência de paridade da Phase 4 parou os quatro IDs pelo mesmo motivo, e
# não é formalidade: a razão declarada da migração destes mailers é **o escape**.
#
# No legado o HTML era concatenado em Ruby e marcado `html_safe`
# (`feedback19/lib/.../notification.rb:44-64`): 20 linhas de
# `message << "<div style='…'>#{texto_do_usuario}"`. Quem escrevesse `<script>`
# no formulário público mandava `<script>` para a caixa de entrada do
# administrador. O ERB escapa por padrão, e é isso que fecha o buraco.
#
# **Uma melhoria de segurança sem teste não é melhoria: é uma afirmação.** Um
# `raw` ou `html_safe` que alguém acrescente amanhã num destes templates
# reabriria o buraco sem uma linha vermelha. É esse o caso que o primeiro
# exemplo de cada mailer trava.
RSpec.describe 'E-mails do observador e da conversa' do
  # A carga útil vai no NOME e no CORPO, que são os dois campos que o
  # formulário público aceita livremente e que os templates interpolam.
  PAYLOAD = '<script>alert(1)</script>'

  # Os cinco assuntos interpolam `ENV['APP_NAME']`, que neste ambiente vale
  # `ai9`. Fixar aqui deixa o exemplo determinístico E documenta que o nome é
  # configuração, não literal — quem trocar `APP_NAME` no `.env` do cliente não
  # quebra a suíte, e quem trocar o TEXTO ao redor do nome quebra, que é o
  # comportamento que estes exemplos guardam.
  around do |exemplo|
    anterior = ENV.fetch('APP_NAME', nil)
    ENV['APP_NAME'] = 'Safegold'
    exemplo.run
    ENV['APP_NAME'] = anterior
  end

  # Pela fábrica, e não por `User.create!` com senha: no ai9 a conta não tem
  # senha (entrada por link mágico / código), então `password=` nem existe.
  let(:admin) { create(:user, email: 'admin@example.com', name: 'Ana Paula Souza') }

  let(:observador) do
    o = Observer.new(name: 'Observador', email: 'observador@example.com', user: admin)
    o.contexts = %w[problem]
    o.save!
    o
  end

  let(:mensagem) do
    AdminMessage.create!(sender_name: 'Fulano de Tal', sender_email: 'fulano@example.com',
                         message: 'A tela de borderô não abre', context: 'problem')
  end

  # ⚠ **`body.to_s` num e-mail MULTIPART devolve o container, que e vazio.**
  # Ate a versao texto do FE-530 entrar, estes exemplos liam `body` direto e
  # passavam; com as duas partes, passaram a comparar contra string vazia — e
  # `expect("").not_to include(PAYLOAD)` passaria calado, provando nada. O corpo
  # HTML mora em `html_part`, e e nele que o escape se verifica.
  describe ObserverMailer do
    describe '#message_received' do
      it 'ESCAPA o que o usuário digitou — é a razão de ser da troca de concatenação por ERB' do
        suja = AdminMessage.create!(sender_name: PAYLOAD, sender_email: 'fulano@example.com',
                                    message: PAYLOAD, context: 'problem')

        corpo = described_class.message_received(observador, suja).html_part.body.to_s

        expect(corpo).not_to include(PAYLOAD)
        expect(corpo).to include('&lt;script&gt;')
      end

      it 'vai para o observador, com o assunto do legado' do
        email = described_class.message_received(observador, mensagem)

        expect(email.to).to eq(['observador@example.com'])
        expect(email.subject).to eq('Nova mensagem no Safegold')
      end

      it 'entrega os dados que o administrador precisa para responder' do
        corpo = described_class.message_received(observador, mensagem).html_part.body.to_s

        expect(corpo).to include('Fulano de Tal')
        expect(corpo).to include('fulano@example.com')
        expect(corpo).to include('A tela de borderô não abre')
      end
    end

    describe '#added' do
      it 'usa o PRIMEIRO NOME de quem incluiu' do
        email = described_class.added(observador)

        expect(email.to).to eq(['observador@example.com'])
        expect(email.subject).to eq('Ana te incluiu no Safegold')
      end

      # O `primeiro_nome` tem um fallback, e fallback sem teste é o que quebra
      # quando o dado real chega diferente do dado de desenvolvimento.
      it 'sem nome no cadastro, diz "Um administrador" em vez de deixar o assunto capenga' do
        admin.update_columns(name: '')

        expect(described_class.added(observador.reload).subject)
          .to eq('Um administrador te incluiu no Safegold')
      end
    end

    describe '#removed' do
      it 'credita quem REMOVEU, não quem cadastrou' do
        outro = create(:user, email: 'outro@example.com', name: 'Bruno Lima')
        observador.update!(last_updated_user: outro)

        expect(described_class.removed(observador.reload).subject)
          .to eq('Bruno te removeu no Safegold')
      end

      it 'sem quem removeu, cai em quem cadastrou' do
        expect(described_class.removed(observador).subject)
          .to eq('Ana te removeu no Safegold')
      end
    end
  end

  describe MessageMailer do
    describe '#received' do
      it 'ESCAPA o que o usuário digitou' do
        suja = AdminMessage.create!(sender_name: PAYLOAD, sender_email: 'fulano@example.com',
                                    message: PAYLOAD, context: 'problem')

        corpo = described_class.received(suja).html_part.body.to_s

        expect(corpo).not_to include(PAYLOAD)
        expect(corpo).to include('&lt;script&gt;')
      end

      # **BE-483.** O assunto é o do legado (`grind_mailer_decorator.rb:13`), que
      # é também o que o mapa da migração especifica. Estava como "Recebemos sua
      # mensagem — <app>": mais informativo, e divergente sem registro nenhum.
      # Assunto de e-mail que o cliente recebe é interface — trocá-lo é decisão
      # do usuário, e a DEC-30 manda replicar.
      it 'confirma para QUEM ENVIOU, com o assunto personalizado do legado' do
        email = described_class.received(mensagem)

        expect(email.to).to eq(['fulano@example.com'])
        expect(email.subject).to eq('Obrigado, Fulano :)')
      end

      # O model EXIGE nome (`length: { in: 3..40 }`), então este estado não nasce
      # pelo formulário — nasce da CARGA. O legado não tinha essa validação, e a
      # migração traz mensagem antiga como está. `update_columns` porque é
      # exatamente assim que o registro chega: gravado por fora da validação.
      it 'nome vazio vindo do dado legado não deixa o assunto capenga' do
        anonima = AdminMessage.create!(sender_name: 'Sem Nome', sender_email: 'x@example.com',
                                       message: 'texto', context: 'problem')
        anonima.update_columns(sender_name: '')

        expect(described_class.received(anonima.reload).subject).to eq('Obrigado, e volte sempre :)')
      end
    end

    describe '#note_added' do
      it 'avisa o remetente quando quem escreveu foi o administrador' do
        nota = MessageNote.create!(admin_message: mensagem, user: admin,
                                   author_name: admin.name, author_email: admin.email,
                                   description: 'Já estamos verificando')

        email = described_class.note_added(nota)

        expect(email.to).to eq(['fulano@example.com'])
        expect(email.subject).to eq("Respondemos sua mensagem ##{mensagem.id} — Safegold")
      end

      # A guarda que impede o remetente de receber e-mail da própria fala. Sem
      # este exemplo, remover o `return unless note.from_admin?` passa despercebido
      # e o usuário recebe de volta o que ele mesmo escreveu.
      it 'NÃO envia nada quando quem escreveu foi o próprio remetente' do
        nota = MessageNote.create!(admin_message: mensagem, user: nil,
                                   author_name: 'Fulano de Tal',
                                   author_email: 'fulano@example.com',
                                   description: 'Continua sem abrir')

        expect(described_class.note_added(nota).message).to be_a(ActionMailer::Base::NullMail)
      end
    end
  end

  # **FE-530 — a versão TEXTO de cada e-mail.**
  #
  # O legado tinha `confirm_feedback_to.text.erb`; a migração trouxe só o
  # `.html.erb`. Não é acabamento: cliente de e-mail que recusa HTML — e filtro
  # de spam, que pontua mensagem sem alternativa em texto — recebe um corpo
  # vazio. O `auth_mailer` já tinha o par e um spec exigindo-o
  # (`email_service_spec.rb:39`); o módulo de mensagens tinha ficado de fora.
  describe 'multipart' do
    PARES = {
      'message_mailer' => %w[received note_added],
      'observer_mailer' => %w[message_received added removed],
    }.freeze

    PARES.each do |pasta, modelos|
      modelos.each do |modelo|
        it "`#{pasta}/#{modelo}` tem .html.erb E .text.erb" do
          expect(File).to exist(Rails.root.join("app/views/#{pasta}/#{modelo}.html.erb"))
          expect(File).to exist(Rails.root.join("app/views/#{pasta}/#{modelo}.text.erb"))
        end
      end
    end

    # O par de arquivos não prova entrega multipart: um `.text.erb` com erro de
    # ERB, ou um `mail` que só renderiza um formato, passaria no teste acima.
    it 'o e-mail sai com as DUAS partes, e a de texto não vem vazia' do
      email = ObserverMailer.message_received(observador, mensagem)

      expect(email).to be_multipart
      texto = email.text_part.body.to_s
      expect(texto).to include('Fulano de Tal')
      expect(texto).to include('A tela de borderô não abre')
      expect(texto).not_to include('<')
    end
  end
end
