# frozen_string_literal: true

module Ai
  # Bloco 8 do trim (AI9-007) — memória de conversa do assistente interno.
  #
  # POR QUE ESTA CLASSE EXISTE
  # Até o Bloco 6 o histórico do agente era `lead.messages` (`LeadMessage`), que
  # é AI9-006 e saiu inteiro com o CRM. O `AgentService` ficou com `history = []`
  # fixo: o assistente não lembrava da mensagem anterior.
  #
  # O DEC-20 decidiu onde ele passa a lembrar: **em memória/Redis, sem tabela
  # nova**. O histórico vive na sessão e expira. Consequências assumidas e
  # registradas no DEC-20 — NÃO são omissões:
  #   - a conversa **não retoma** depois de fechar a aba;
  #   - **não há trilha auditável** do que o assistente respondeu.
  # Se um dia o assistente passar a orientar decisão de crédito, uma
  # `ChatMessage` ligada à `ChatSession` (que continua existindo) é aditiva.
  #
  # ONDE MORA
  # `Rails.cache`, que em dev e produção é `ActiveSupport::Cache::RedisCacheStore`
  # (`config/environments/{development,production}.rb`) — o MESMO Redis que o
  # `Rack::Attack` usa como store (`config/initializers/rack_attack.rb`). Não há
  # dependência nova: se o Redis está de pé para o rate limit, está para isto.
  #
  # A CHAVE INCLUI O USUÁRIO, não só a sessão.
  # `ChatSession#id` é inteiro sequencial e vinha do parâmetro. Chavear só por
  # sessão propagaria para a memória da conversa o mesmo vazamento que o
  # `user_id` em `chat_sessions` fechou. Com o usuário na chave, mesmo que um
  # `session_id` alheio vaze, a memória lida é a de quem está autenticado.
  class ConversationMemory
    # Prefixo próprio: o store é compartilhado com o `Rack::Attack` e com o cache
    # da aplicação. Namespace explícito para o `--scan --pattern` de operação
    # conseguir distinguir (e limpar) só o que é do assistente.
    KEY_PREFIX = 'ai9:chat:history'

    # TTL de 2 horas.
    #
    # POR QUE 2 HORAS, e não 15 minutos nem 30 dias:
    #   - o piso é a duração de uma conversa de ajuda real. O usuário abre o
    #     widget, tenta uma tela, volta e pergunta de novo. Um TTL curto (5, 15
    #     min) faria o assistente esquecer NO MEIO do atendimento, que é
    #     exatamente o defeito que esta classe existe para corrigir;
    #   - o teto é o DEC-20: "o histórico vive na sessão e expira". Um TTL longo
    #     transformaria o Redis em persistência de conversa por vias travessas —
    #     seria a tabela que o DEC-20 recusou, sem o índice e sem o backup;
    #   - 2h cobre com folga um turno de trabalho contínuo no console sem
    #     virar armazenamento.
    #
    # O TTL é deslizante: cada escrita renova (ver `append`). Enquanto a conversa
    # está viva o fio não se perde; 2h depois do último turno, some.
    TTL = 2.hours

    # Teto de mensagens guardadas (turnos completos = MAX_MESSAGES / 2).
    #
    # Corta pelo FIM (mantém as mais recentes). É limite de janela de contexto,
    # não de retenção: sem ele uma conversa longa cresce sem teto e estoura o
    # `max_tokens` do provider — o erro apareceria como resposta truncada, não
    # como erro de memória.
    MAX_MESSAGES = 40

    class << self
      # Histórico do turno, no formato que os 3 providers já consomem
      # (`[{ role: 'user'|'assistant', content: String }]`).
      #
      # @param session [ChatSession]
      # @return [Array<Hash>] vazio quando não há memória (ou o Redis está fora)
      def history_for(session)
        key = key_for(session)
        return [] unless key

        Array(Rails.cache.read(key))
      rescue StandardError => e
        # Fail-soft: memória indisponível degrada para "agente sem memória", que
        # é o comportamento de antes deste bloco. Nunca derruba a resposta.
        Rails.logger.warn("[ConversationMemory] leitura ignorada: #{e.class}: #{e.message}")
        []
      end

      # Acrescenta um turno (mensagem do usuário + resposta do assistente) e
      # renova o TTL.
      #
      # @param session [ChatSession]
      # @param user_content [String] o que o usuário mandou
      # @param assistant_content [String] o que o assistente respondeu
      # @return [Boolean] true se gravou
      def append(session, user_content:, assistant_content:)
        key = key_for(session)
        return false unless key

        messages = Array(Rails.cache.read(key))
        messages << { role: 'user', content: user_content.to_s } if user_content.present?
        messages << { role: 'assistant', content: assistant_content.to_s } if assistant_content.present?
        return false if messages.empty?

        Rails.cache.write(key, messages.last(MAX_MESSAGES), expires_in: TTL)
        true
      rescue StandardError => e
        Rails.logger.warn("[ConversationMemory] escrita ignorada: #{e.class}: #{e.message}")
        false
      end

      # Esquece a conversa (troca de agente, fim de sessão).
      def clear(session)
        key = key_for(session)
        return false unless key

        Rails.cache.delete(key)
        true
      rescue StandardError
        false
      end

      # `ai9:chat:history:u<user_id>:s<session_id>`
      #
      # Sem sessão persistida não há memória — e sem dono também não: uma sessão
      # órfã (anterior ao Bloco 8) não pode compartilhar chave com ninguém.
      # @return [String, nil]
      def key_for(session)
        return nil unless session.respond_to?(:id) && session.id.present?

        owner = session.try(:user_id)
        return nil if owner.blank?

        "#{KEY_PREFIX}:u#{owner}:s#{session.id}"
      end
    end
  end
end
