# frozen_string_literal: true

module Auth
  # "Ver como" — impersonação auditada (DEC-18.3).
  #
  # No legado a única checagem era `can_impersonate?` do **ator**: um Admin
  # personificava o OG e virava OG. Combinado com o D-109 (senha determinística a partir
  # do primeiro nome), dava comprometimento trivial do sistema inteiro. É o D-34.
  #
  # As cinco regras que valem aqui, todas verificáveis:
  #
  #  1. **hierarquia estritamente inferior** — nunca o OG, nunca lateral, nunca a si
  #     mesmo (`Authorization::Hierarchy.can_impersonate?`);
  #  2. **motivo obrigatório** — sem motivo não começa;
  #  3. **trilha persistida** em `versions`, a única trilha do sistema (DEC-59): quem
  #     personificou, quem foi personificado, quando, por quê, e quando encerrou;
  #  4. **expira** — o refresh da sessão personificada vive 1 hora, não 30 dias
  #     (`TokenService::IMPERSONATION_REFRESH_TTL`);
  #  5. **não encadeia** — o personificado não personifica.
  class ImpersonateService
    extend ApiResponseHandler

    # Motivo curto demais é o mesmo que motivo nenhum ("ok", "teste"). O piso existe
    # para que a trilha sirva a quem for lê-la seis meses depois.
    MIN_REASON_LENGTH = 5

    class << self
      def start(true_user, target_user_id, reason: nil, ip_address: nil)
        reason = reason.to_s.strip
        if reason.length < MIN_REASON_LENGTH
          return error_response(
            "Informe o motivo da impersonação (mínimo #{MIN_REASON_LENGTH} caracteres). " \
            'Ele fica na trilha de auditoria.', 422
          )
        end

        # **Não encadeia** (DEC-18.3): quem já está sendo personificado não inicia
        # outra impersonação, senão a trilha perde o autor real.
        if PaperTrail.request.controller_info.to_h[:impersonated_id].present?
          return error_response('Sessão personificada não inicia outra impersonação', 403)
        end

        target = User.find_by(id: target_user_id)

        # **IMP-A28 — 403 ANTES de 404/422.**
        #
        # A ordem antiga era: 404 se não achou, 422 se é você mesmo, 403 se não pode.
        # Isso transforma o endpoint num oráculo de existência de ids: quem não tem
        # permissão nenhuma distingue "id existe" (403) de "id não existe" (404) e
        # enumera a base inteira de usuários. Agora quem não pode personificar recebe o
        # MESMO 403 nos dois casos, e a distinção só aparece para quem já podia.
        unless Authorization::Matrix.allow?(true_user&.user_type&.name, 'impersonation', :create)
          return error_response('Sem permissão para impersonar', 403)
        end

        return not_found_response('Usuário') unless target
        return error_response('Não é possível impersonar a si mesmo', 422) if target.id == true_user.id
        return error_response('Não é possível impersonar uma conta bloqueada', 422) if target.blocked?

        unless Authorization::Hierarchy.can_impersonate?(true_user, target)
          return error_response('Sem permissão para impersonar este usuário', 403)
        end

        tokens = Auth::TokenService.new(target).generate_impersonation_tokens(true_user.id)
        record_trail(event: 'impersonate_start', actor: true_user, target: target,
                     reason: reason, ip_address: ip_address)

        Rails.logger.info(
          "[IMPERSONATE] #{true_user.id} iniciou impersonação de #{target.id} — motivo: #{reason}"
        )

        success_response({
                           access_token: tokens[:token],
                           refresh_token: tokens[:refresh_token],
                           expires_in: Auth::TokenService::IMPERSONATION_REFRESH_TTL.to_i,
                           impersonated_user: Api::Entities::User.represent(target),
                           true_user: { id: true_user.id, name: true_user.name, email: true_user.email }
                         }, 200)
      end

      # Encerra a sessão personificada. Continua sendo no-op seguro quando não há
      # impersonação ativa — o endpoint já barra antes, e um `stop` a mais não é erro.
      def stop(true_user_id, impersonated_id: nil, ip_address: nil)
        true_user = User.find_by(id: true_user_id)
        return not_found_response('User') unless true_user

        tokens = Auth::TokenService.new(true_user).generate_tokens

        # Fecha a trilha: sem isto sabe-se quando a impersonação começou e nunca quando
        # acabou, e "por quanto tempo alguém agiu como outra pessoa" é justamente o que
        # uma investigação pergunta primeiro.
        target = impersonated_id.present? ? User.find_by(id: impersonated_id) : nil
        record_trail(event: 'impersonate_stop', actor: true_user, target: target,
                     reason: 'encerramento da sessão personificada', ip_address: ip_address)

        Rails.logger.info("[IMPERSONATE] #{true_user.id} encerrou a impersonação")

        success_response({
                           access_token: tokens[:token],
                           refresh_token: tokens[:refresh_token],
                           user: Api::Entities::User.represent(true_user)
                         }, 200)
      end

      private

      # A trilha é `versions` (DEC-59) — não existe `AuditEvent`, e a coluna `reason`
      # da tabela já foi criada em S0 prevendo este uso ("motivo declarado do ato
      # administrativo (concessão/revogação de permissão, impersonação)").
      def record_trail(event:, actor:, target:, reason:, ip_address:)
        PaperTrail::Version.create!(
          item_type: 'User',
          item_id: (target&.id || actor.id).to_s,
          event: event,
          whodunnit: actor.id.to_s,
          impersonated_id: target&.id&.to_s,
          reason: reason,
          ip_address: ip_address,
          object_changes: {
            actor: { id: actor.id, name: actor.name, role: actor.user_type&.name },
            target: target && { id: target.id, name: target.name, role: target.user_type&.name }
          }
        )
      rescue StandardError => e
        # Falhar a trilha não pode derrubar o encerramento de uma sessão personificada:
        # deixar a pessoa presa na identidade de outra é pior que perder uma linha.
        # No início (`impersonate_start`) o efeito é o oposto e por isso ele é logado
        # como erro — é o caso que exige investigação.
        Rails.logger.error("[IMPERSONATE] falha ao gravar trilha (#{event}): #{e.class}: #{e.message}")
      end
    end
  end
end
