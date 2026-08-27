# frozen_string_literal: true

# S1 / BE-040, FE-026, FE-027 — mudança de permissão chega por **evento**, nunca por
# recarregar a página.
#
# ## O que este canal carrega, e o que ele NÃO carrega
#
# Ele carrega **um aviso**, não o estado: `{ type: 'permissions_changed' }`. Quem
# recebe invalida a consulta no React Query e refaz a leitura pelo endpoint, que é
# onde a autorização mora. Mandar a lista de permissões pelo socket faria a resposta
# ser montada num lugar que não passa pelo `authorize!` — e um dia alguém confiaria
# nela.
#
# ## A trava de assinatura (flag de upstream U2, fechada aqui)
#
# A versão da base fazia `stream_for("permissions:#{params[:user_id]}")` com o
# `user_id` **que o cliente mandou**: qualquer sessão autenticada assinava o fluxo de
# qualquer pessoa. Num canal de aviso o dano é pequeno, mas o padrão é o mesmo que o
# `ProjectProgressChannel` e o `RenegotiationChannel` já recusaram por escrito.
#
# Aqui o fluxo é **sempre o do usuário da conexão**. O `params[:user_id]` continua
# aceito (o front da base o manda) e é **conferido**, não obedecido: pedir o fluxo de
# outra pessoa é `reject`, não um fluxo silenciosamente trocado — recusar é o que faz
# um cliente errado aparecer no log em vez de funcionar por acaso.
class PermissionsChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_user.blank?

    requested = params[:user_id].presence
    return reject if requested.present? && requested.to_s != current_user.id.to_s

    stream_from self.class.stream_name_for(current_user.id)
  end

  def self.stream_name_for(user_id)
    "permissions:#{user_id}"
  end

  # Ponto único de emissão. Serviço nenhum chama `ActionCable.server.broadcast`
  # solto: o nome do stream vira convenção oral e o dia em que ele mudar,
  # metade dos emissores fica falando sozinha.
  def self.publish_changed(user_id, payload = {})
    ActionCable.server.broadcast(
      stream_name_for(user_id),
      { type: 'permissions_changed' }.merge(payload)
    )
  end

  # Uma permissão de PAPEL mudou: avisa todo mundo que tem aquele papel.
  #
  # **É uma consulta de ids, não de objetos** — a lista pode ter milhares de linhas e
  # nada aqui precisa do registro. E o `find_each` mantém o consumo constante em vez
  # de carregar a base inteira para emitir avisos.
  def self.publish_user_type_changed(user_type_id, payload = {})
    User.where(user_type_id: user_type_id).select(:id).find_each do |user|
      publish_changed(user.id, payload.merge(scope: 'user_type'))
    end
  end
end
