# frozen_string_literal: true

module Ai
  module Tools
    module Handlers
      # As ferramentas de AJUDA do assistente (capability `console_help`).
      #
      # ## Por que ler o acervo em vez de descrever as telas no prompt
      #
      # O prompt do seed já mandava "não invente tela, botão nem caminho que você
      # não tem certeza que existe" — e não dava ao agente **nenhuma** fonte para
      # ter certeza. Uma instrução de não inventar sem material para consultar é
      # uma instrução que o modelo não tem como cumprir.
      #
      # A fonte é a que o produto já mantém: o **FAQ** (S12) e a **ajuda de
      # campo** (OPS-545/DEC-88). As duas são editadas por quem administra o
      # sistema, sem deploy — então a qualidade da resposta do assistente sobe
      # junto com o acervo, e não depende de alguém lembrar de reescrever um
      # prompt.
      #
      # ## O corpo vai em TEXTO PURO
      #
      # `description_text`, nunca `description_html`. O item é ActionText: mandar
      # a marcação para o modelo gasta contexto com `<div>` e ensina o agente a
      # devolver HTML numa bolha de chat que renderiza markdown.
      module ConsoleHelp
        # Quantos resultados a busca devolve. Cinco cabe numa resposta de chat
        # sem virar lista de links — o agente lê os cinco e responde com o que
        # serve, em vez de despejar o acervo.
        DEFAULT_LIMIT = 5
        MAX_LIMIT     = 10

        # Corte do corpo de UM item. Item de ajuda longo existe (procedimento de
        # fechamento, por exemplo); mandar 20 mil caracteres para o modelo custa
        # contexto e não melhora a resposta.
        MAX_BODY = 4_000

        module_function

        # Busca no acervo inteiro do FAQ.
        def search_faq(args, scope)
          bloqueio = scope.block_for_help('faq')
          return bloqueio if bloqueio

          termo = args['term'].to_s.strip
          return scope.failure('Preciso de um termo para buscar na ajuda.') if termo.blank?

          limite = [[args['limit'].to_i, 1].max, MAX_LIMIT].min
          limite = DEFAULT_LIMIT if args['limit'].blank?

          itens = ::Help::Search.all(term: termo).includes(category: :group).limit(limite)

          {
            success: true,
            message: {
              term: termo,
              # Zero resultado é RESPOSTA, não erro: diz que o acervo não cobre o
              # assunto, e é isso que o agente precisa dizer em vez de inventar.
              count: itens.size,
              items: itens.map do |item|
                {
                  id: item.id,
                  title: item.title,
                  group: item.category&.group&.title,
                  category: item.category&.title,
                  excerpt: ::Help::Search.excerpt(item, term: termo)
                }
              end
            }.to_json
          }
        end

        # O corpo completo de um item, para quando o trecho não bastou.
        def read_faq_item(args, scope)
          bloqueio = scope.block_for_help('faq')
          return bloqueio if bloqueio

          item = ::HelpItem.find_by(id: args['id'])
          return scope.failure('Esse item de ajuda não existe.') if item.nil?

          texto = item.description_text.to_s

          {
            success: true,
            message: {
              id: item.id,
              title: item.title,
              group: item.category&.group&.title,
              category: item.category&.title,
              body: texto.first(MAX_BODY),
              truncated: texto.length > MAX_BODY
            }.to_json
          }
        end

        # A ajuda de campo dos três formulários (DEC-88). Sem `field`, devolve o
        # formulário inteiro — é assim que o agente responde "o que é cada campo
        # desta tela" sem precisar adivinhar os nomes das chaves.
        def field_help(args, scope)
          bloqueio = scope.block_for_help('help')
          return bloqueio if bloqueio

          escopo = args['scope'].to_s.strip
          unless ::Help::FieldHelp::SCOPES.include?(escopo)
            disponiveis = ::Help::FieldHelp::SCOPES.join(', ')
            return scope.failure("Formulário desconhecido. Os que têm ajuda de campo são: #{disponiveis}.")
          end

          campo = args['field'].to_s.strip

          if campo.present?
            texto = ::Help::FieldHelp.text_for(escopo, campo)
            # Chave ausente não quebra nada (regra 1 do `FieldHelp`) e não vira
            # invenção: o agente recebe "não há texto" e diz isso.
            corpo = { scope: escopo, field: campo, text: texto, found: texto.present? }
            return { success: true, message: corpo.to_json }
          end

          textos = ::Help::FieldHelp.for_scope(escopo)
          { success: true, message: { scope: escopo, fields: textos }.to_json }
        end
      end
    end
  end
end
