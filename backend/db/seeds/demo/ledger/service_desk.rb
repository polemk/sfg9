# frozen_string_literal: true

require 'active_support/core_ext/digest/uuid'

module Demo
  class Ledger
    # **Atendimento** (S2) — mensagens administrativas e observadores.
    #
    # As duas tabelas estavam **zeradas** no banco de demonstração de
    # 26/08/2026, e as duas telas existem e estão no menu (`/messages`). Uma
    # tela de tickets vazia é pior que uma tela ausente: ela sugere que o
    # recurso não funciona.
    #
    # ## O que a tela sabe pintar, e por isso está aqui
    #
    # `AdminMessage` tem **8 situações** e **4 contextos**, e a lista filtra por
    # ambos. Lista monocromática não demonstra filtro nem pílula: **cada uma das
    # 8 situações e cada um dos 4 contextos tem ao menos um exemplo**, e há um
    # spec que reprova quem quebrar isso.
    #
    # ## Os tokens são DETERMINÍSTICOS, e é por eles que a idempotência funciona
    #
    # `public_token` é único no banco e o model o gera com `SecureRandom` quando
    # chega em branco — o que faria cada execução criar 28 mensagens novas. Aqui
    # o token é um UUID v5 derivado da chave do razão: tem a mesma cara de um
    # token de verdade, e é a **chave natural** do escritor.
    #
    # Não se usa `legacy_id` para isso de propósito: o **DEC-12** reserva essa
    # coluna para proveniência do banco legado, e carimbar nela um número de
    # seed é plantar uma origem que não existe.
    module ServiceDesk
      NAMESPACE = 'e5a1c0de-5f20-4f20-9f20-5f6764656d6f'

      # Remetentes externos — clientes da gestora escrevendo pelo formulário
      # público. Nomes brasileiros plausíveis, e-mail no domínio do próprio
      # cliente fictício.
      SENDERS = [
        ['Marina Toledo', 'marina.toledo@aliancametalurgica.test'],
        ['Douglas Ferraz', 'douglas.ferraz@nordestealimentos.test'],
        ['Simone Batista', 'simone.batista@serraazul.test'],
        ['Wagner Peixoto', 'wagner.peixoto@valedorio.test'],
        ['Elaine Cordeiro', 'elaine.cordeiro@campolargo.test'],
        ['Rogério Sanches', 'rogerio.sanches@quimicapaulista.test'],
        ['Tatiane Furtado', 'tatiane.furtado@portobelo.test'],
        ['Nelson Braga', 'nelson.braga@agroinsumoscerrado.test'],
        ['Vanessa Klein', 'vanessa.klein@moveisbento.test'],
        ['Ivo Marcondes', 'ivo.marcondes@litoralnorte.test'],
        ['Sônia Rabelo', 'sonia.rabelo@fundicaotresrios.test'],
        ['Caio Villaça', 'caio.villaca@tecnologiaribeirao.test']
      ].freeze

      # As 28 mensagens. `days` é a idade em dias contada da data-base — nenhuma
      # data literal (§10 do desenho).
      #
      # A distribuição não é estética: as **8 situações** de
      # `AdminMessage::STATES` e os **4 contextos** de `CONTEXTS` aparecem todos,
      # e as mais recentes concentram `unread`/`read`, que é como uma caixa de
      # atendimento de verdade se parece.
      MESSAGES = [
        { days: 0, sender: 0, context: 'problem', state: 'unread', internal: false,
          text: 'O borderô 004312 aparece com o líquido diferente do extrato do banco em R$ 1.284,17. ' \
                'Conseguem conferir a tarifa de deságio desse lote?' },
        { days: 0, sender: 4, context: 'contact', state: 'unread', internal: false,
          text: 'Boa tarde. Gostaria de agendar uma conversa sobre a renovação do limite com o ' \
                'FIDC Solaris antes do fechamento do mês.' },
        { days: 1, sender: 2, context: 'suggestion', state: 'unread', internal: false, favorite: true,
          text: 'Seria possível exportar a lista de borderôs filtrada em planilha? Hoje copiamos ' \
                'a tela para montar o relatório da diretoria.' },
        # **`answered`, e não `read`.** A thread desta mensagem tem uma resposta do
        # administrador, e `MessageNote#advance_message_state` move "Lido" para
        # "Respondido" na primeira fala de quem atende. Declarar `read` aqui faria
        # o seed gravar um estado que o próprio model corrige um instante depois —
        # e a execução seguinte tentaria gravá-lo de novo, para sempre.
        { days: 1, sender: 7, context: 'problem', state: 'answered', internal: false,
          text: 'Não consigo abrir o painel de disponibilidade pelo celular: a grade fica cortada ' \
                'e o botão de salvar não aparece.' },
        { days: 2, sender: 1, context: 'other', state: 'read', internal: false,
          text: 'Quem é o responsável pelo nosso grupo agora? O contato antigo não responde mais.' },
        { days: 3, sender: 5, context: 'problem', state: 'open', internal: false,
          text: 'A tela de limites mostra o Banco Meridiano com limite disponível negativo, mas ' \
                'não fizemos nenhuma operação nova nesta semana.' },
        { days: 4, sender: 10, context: 'contact', state: 'open', internal: false, favorite: true,
          text: 'Precisamos discutir a renegociação com a Fundição Morro Alto. O fornecedor pediu ' \
                'antecipação de duas parcelas.' },
        { days: 5, sender: 3, context: 'suggestion', state: 'evaluated', internal: false,
          text: 'Sugestão: colocar o número do contrato na lista de operações de risco. Hoje só ' \
                'aparece o portador e a gente precisa entrar em cada linha.' },
        # **`open`**: aqui o remetente respondeu DEPOIS do administrador, e a
        # segunda transição automática reabre a conversa. Mesmo motivo da de
        # cima — o razão declara o estado que a máquina produz.
        { days: 6, sender: 8, context: 'problem', state: 'open', internal: false,
          text: 'O indicador de volume operado de julho está zerado no gráfico, mas os borderôs ' \
                'do mês estão todos lançados.' },
        { days: 7, sender: 6, context: 'other', state: 'answered', internal: false,
          text: 'Recebemos dois e-mails com o mesmo código de acesso. Isso é esperado?' },
        { days: 9, sender: 11, context: 'contact', state: 'done', internal: false,
          text: 'Obrigado pelo atendimento de ontem. O acesso da nossa controladoria já está ' \
                'funcionando.' },
        { days: 11, sender: 9, context: 'problem', state: 'done', internal: false,
          text: 'A garantia de fiança bancária do Vértice estava com o valor antigo. Já corrigimos ' \
                'com a equipe de vocês pelo telefone.' },
        { days: 13, sender: 0, context: 'suggestion', state: 'closed', internal: false,
          text: 'Poderiam permitir filtrar renegociações por fornecedor? Temos treze abertas e a ' \
                'busca por texto não ajuda.' },
        { days: 15, sender: 2, context: 'other', state: 'closed', internal: false,
          text: 'Atualizamos o endereço da matriz. Segue para o cadastro: Rua Doutor Amadeu da ' \
                'Luz, 210, Blumenau, SC.' },
        { days: 17, sender: 4, context: 'problem', state: 'rejected', internal: false,
          text: 'Quero acesso ao painel de outro cliente do grupo do meu sócio para comparar as ' \
                'taxas praticadas.' },
        { days: 19, sender: 7, context: 'contact', state: 'read', internal: false,
          text: 'Quais documentos vocês precisam para incluir a nova filial no cadastro de ' \
                'empresas do projeto?' },
        { days: 21, sender: 1, context: 'suggestion', state: 'evaluated', internal: false,
          text: 'A tela de cobranças poderia somar o total do período no rodapé. Hoje somamos à ' \
                'mão as páginas.' },
        { days: 23, sender: 5, context: 'problem', state: 'open', internal: false,
          text: 'Ao salvar um lançamento de disponibilidade duas vezes seguidas o valor muda ' \
                'sozinho. É esperado?' },
        { days: 26, sender: 3, context: 'other', state: 'done', internal: false,
          text: 'Confirmando o recebimento do relatório mensal. Está tudo certo com os números.' },
        { days: 28, sender: 8, context: 'contact', state: 'closed', internal: false,
          text: 'Vamos trocar o e-mail de faturamento. O novo é financeiro@agroinsumoscerrado.test.' },
        { days: 31, sender: 10, context: 'problem', state: 'answered', internal: false,
          text: 'O prazo médio ponderado do banco está saindo maior que o da empresa em todos os ' \
                'borderôs de agosto. Faz sentido?' },
        { days: 34, sender: 6, context: 'suggestion', state: 'done', internal: false,
          text: 'Um alerta por e-mail quando o limite passar de 90% ajudaria muito a tesouraria.' },
        { days: 38, sender: 9, context: 'other', state: 'closed', internal: false,
          text: 'Só um retorno: a apresentação de resultados que vocês montaram foi bem recebida ' \
                'pelo conselho.' },
        { days: 42, sender: 11, context: 'problem', state: 'rejected', internal: false,
          text: 'Peço que apaguem os borderôs de junho do sistema. Preferimos que não fiquem ' \
                'registrados.' },
        # As quatro internas: escritas por quem opera o sistema, e é isso que
        # `is_internal` decide — observador externo NÃO as recebe.
        { days: 2, sender: :admin, context: 'problem', state: 'open', internal: true, favorite: true,
          text: 'Interno: conferir com a TI do Meridiano por que o retorno de recusa vem sem o ' \
                'número do título desde a virada do mês.' },
        { days: 8, sender: :gerente, context: 'other', state: 'read', internal: true,
          text: 'Interno: revisar a carteira do Litoral Norte antes da reunião de quinta. O ' \
                'volume caiu dois meses seguidos.' },
        { days: 16, sender: :admin, context: 'suggestion', state: 'evaluated', internal: true,
          text: 'Interno: padronizar o texto de cobrança enviado aos clientes em atraso. Hoje ' \
                'cada analista escreve o seu.' },
        { days: 30, sender: :gerente, context: 'contact', state: 'done', internal: true,
          text: 'Interno: contato com a Cooperativa Ipiranga fechado. Eles aceitam subir o limite ' \
                'da Móveis Bento Gonçalves em 20%.' }
      ].freeze

      # As respostas da thread. `admin: true` é fala de quem atende
      # (`user_id` presente); `false` é o remetente respondendo. É essa diferença
      # que a tela usa para desenhar os dois lados da conversa — thread de um
      # lado só não demonstra nada.
      REPLIES = {
        3 => [[false, 'Consigo reproduzir num iPhone 12 e num Android também.', 1],
              [true, 'Obrigada pelo detalhe. Reproduzimos aqui e já está na fila de correção.', 0]],
        5 => [[true, 'Verificamos: o limite foi renegociado para baixo na semana passada e as ' \
                     'operações vivas ficaram acima do novo teto. Vamos remarcar com o portador.', 2]],
        8 => [[true, 'O indicador de julho estava sem lançamento. Reprocessamos e o gráfico já ' \
                     'mostra o mês.', 5],
              [false, 'Confirmado, apareceu aqui. Obrigado.', 4]],
        9 => [[true, 'É esperado quando o código é pedido duas vezes em menos de um minuto: o ' \
                     'segundo invalida o primeiro.', 6]],
        10 => [[true, 'Que bom. Qualquer coisa é só chamar por aqui.', 8]],
        14 => [[true, 'Não é possível: cada projeto só é visível para quem participa dele. ' \
                      'Podemos incluir você formalmente no outro projeto, se o responsável autorizar.', 16]],
        20 => [[true, 'Faz: o prazo do banco inclui o float acordado. A diferença aparece na ' \
                      'coluna de float calculado.', 30]],
        24 => [[true, 'Registrado. Vou levantar com o portador e volto até sexta.', 1]],
        26 => [[true, 'Modelo escrito e em revisão. Entra na próxima versão da central de ajuda.', 15]]
      }.freeze

      # Quem recebe e-mail de cada contexto. **Nem todo observador é interno** —
      # o não interno é o que prova a regra de `Observer.for_message`: mensagem
      # marcada como interna não sai para ele.
      OBSERVERS = [
        { name: 'Central de Atendimento Safegold', email: 'atendimento@safegold.test',
          is_internal: true, contexts: %w[other problem contact suggestion] },
        { name: 'Helena Prado Moreira', email: 'helena.moreira@safegold.test',
          is_internal: true, contexts: %w[problem contact] },
        { name: 'Gustavo Lins', email: 'gustavo.lins@safegold.test',
          is_internal: true, contexts: %w[suggestion other] },
        { name: 'Mesa de Crédito', email: 'mesa.credito@safegold.test',
          is_internal: true, contexts: %w[contact] },
        { name: 'Auditoria Externa Vieira & Prado', email: 'auditoria@vieiraprado.test',
          is_internal: false, contexts: %w[problem] },
        { name: 'Ouvidoria Terceirizada Atlas', email: 'ouvidoria@atlasouvidoria.test',
          is_internal: false, contexts: %w[other suggestion] }
      ].freeze

      module_function

      def token(kind, index)
        Digest::UUID.uuid_v5(NAMESPACE, "sfg-demo/admin_message/#{index}/#{kind}")
      end

      def messages(base_date, cast)
        MESSAGES.each_with_index.map do |row, index|
          name, email = sender_for(row[:sender], cast)
          created_at = timestamp(base_date, row[:days], index)

          record = Records::AdminMessage.new(
            key: "msg-#{format('%02d', index)}",
            public_token: token('public', index),
            private_token: token('private', index),
            sender_name: name, sender_email: email,
            message: row[:text],
            state: row[:state], context: row[:context],
            is_read: row[:state] != 'unread',
            is_favorite: row.fetch(:favorite, false),
            is_internal: row[:internal],
            # Só quem já saiu de "Não lido" tem administrador dono — é a
            # transição que `mark_opened_by` faz na tela.
            handled_by: row[:state] == 'unread' ? nil : :admin,
            created_at: created_at,
            read_at: row[:state] == 'unread' ? nil : created_at + (3 * 3600),
            notes: []
          )
          record.notes = notes_for(record, row, index, base_date)
          record
        end
      end

      # A primeira nota é **a própria mensagem**, e ela existe porque o
      # `after_create_commit` do model a criaria de qualquer jeito: escrevê-la
      # aqui é o que permite acrescentar as respostas na mesma transação, na
      # ordem certa.
      def notes_for(message, row, index, base_date)
        first = Records::MessageNote.new(
          message: message, description: row[:text],
          author_name: message.sender_name, author_email: message.sender_email,
          from_admin: false, unread: row[:state] == 'unread',
          created_at: message.created_at
        )

        replies = REPLIES.fetch(index, []).each_with_index.map do |(from_admin, text, days), position|
          Records::MessageNote.new(
            message: message, description: text,
            author_name: from_admin ? 'Helena Prado Moreira' : message.sender_name,
            author_email: from_admin ? 'helena.moreira@safegold.test' : message.sender_email,
            from_admin: from_admin,
            unread: false,
            created_at: timestamp(base_date, days, index) + (position * 900)
          )
        end

        [first] + replies
      end

      def observers
        OBSERVERS.map { |row| Records::Observer.new(**row) }
      end

      # Hora do dia derivada do índice: mensagens todas às 00:00 é o tipo de
      # detalhe que entrega o seed numa lista ordenada por data.
      def timestamp(base_date, days, index)
        base_date.to_time + (((-days * 24) + 9 + (index % 8)) * 3600) + ((index % 5) * 660)
      end

      def sender_for(sender, cast)
        return SENDERS[sender] if sender.is_a?(Integer)

        member = cast.find { |m| m[:key] == sender }
        [member[:name], member[:email]]
      end
    end
  end
end
