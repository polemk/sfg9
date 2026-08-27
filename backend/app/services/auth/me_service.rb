# frozen_string_literal: true

module Auth
  class MeService
    include ApiResponseHandler

    def initialize(user)
      @user = user
    end

    def show
      return unauthorized_response('Não autenticado') unless @user

      success_response(Api::Entities::User.represent(@user), 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def update(params, csrf_token)
      return unauthorized_response('Não autenticado') unless @user

      validator = Auth::CsrfService.new(@user)
      return forbidden_response('CSRF inválido') unless validator.valid?(csrf_token)

      # **O telefone é editável, e isso é deliberado** (DEC-74).
      #
      # No legado, `is_phone_checked = 1` travava o campo de telefone para sempre
      # (`my_account/parts/phone/_container.js.erb:14-16`, `prop('readonly')`). O
      # indicador "Verificação: {nível}" foi replicado; a trava **não**. No ai9 o
      # telefone é canal de login (DEC-14): travá-lo deixaria quem perdeu o número sem
      # acesso e sem caminho de autoatendimento. Replicar a trava seria portar um
      # bloqueio de acesso, o que cai na exceção de segurança do próprio DEC-30.
      #
      # `username`, `user_type_id`, `identifier` e `blocked_at` NÃO entram: são
      # identidade e autorização, não perfil. Deixar `user_type_id` passar aqui seria
      # autopromoção por PATCH.
      #
      # **Sem `.compact`, e é O PONTO.** Havia um aqui, e ele impedia de APAGAR campo.
      #
      # O Grape só põe em `params` o que o cliente mandou — então o `.compact` não estava
      # defendendo de nada; ele descartava exatamente o `nil` **explícito**, que é como o
      # cliente diz "apague isto". Medido em 26/08/2026 contra o servidor de dev, antes da
      # correção: `{"graduation": null}` respondia **422 "Nenhum campo para atualizar"**, e
      # `{"birthday": ""}` também — o Grape converte data vazia para `nil`. Resultado:
      # **campo de data não tinha como ser limpo**, e nada acusava: a tela mandava e a
      # resposta dizia que não havia o que atualizar.
      #
      # O que sobra aqui foi mandado de propósito, `nil` inclusive. Quem recolocar o
      # `.compact` derruba três exemplos do contexto "limpando campos do perfil estendido"
      # em `spec/requests/api/auth/v1/me_spec.rb` — conferido.
      attrs = params.to_h.symbolize_keys.slice(
        :email, :phone, :name, :avatar_url, :cpf_cnpj, :cep, :street, :number, :complement,
        :district, :city, :state, :gender, :birthday, :cnpj,
        :fiscal_document_number, :fiscal_document_issued_at, :graduation
      )
      return validation_error_response('Nenhum campo para atualizar') if attrs.empty?

      if @user.update(attrs)
        success_response(Api::Entities::User.represent(@user.reload), 200)
      else
        validation_error_response('Dados inválidos', details: @user.errors.full_messages)
      end
    rescue StandardError => e
      internal_error_response(e.message)
    end
  end
end
