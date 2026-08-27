# frozen_string_literal: true

# Base de todo job do Safegold — OPS-460, OPS-462, contrato **D-C**.
#
# ## A regra que este arquivo existe para declarar
#
# **`rescue` em job só existe para enriquecer o log, e SEMPRE termina em `raise`.**
#
# Isso contraria o exemplo canônico de `ai9-conventions.md` §3.7, que mostra um job
# com `rescue StandardError => e; Rails.logger.error(...)` **sem `raise`** — e está
# escrito aqui, e não só na tarefa, porque é a decisão que alguém "conserta" de volta
# por analogia com o resto do repositório. Está registrada em `upstream-flags.md`
# como divergência consciente, não como refatoração da base.
#
# **Por que:** era assim que o legado perdia trabalho em silêncio. Os 7 jobs de
# `../sfg/lib/*_job.rb` capturam `rescue => e` sem relançar, e em
# `insert_projects_on_default_user_job.rb:11-12` o `rescue` é **literalmente vazio** —
# sem log, sem trilha. A fila marcava sucesso, nada era retentado, e um usuário ficava
# sem projeto sem deixar rastro (**D-79**). Engolir a exceção não evita a falha:
# evita que alguém fique sabendo dela.
#
# ## Retentativa e dead set: o default do Sidekiq, de propósito
#
# Não há `retry_on` genérico aqui. Com o adapter Sidekiq, a exceção que sobe do
# `perform` já é retentada com backoff exponencial e, esgotadas as tentativas, o job
# vai para o **dead set** — onde ele fica **visível e reenfileirável**. Configurar
# retentativa por cima disso no ActiveJob cria dois mecanismos empilhados: o
# ActiveJob retenta N vezes *dentro* de uma execução do Sidekiq, que por sua vez
# retenta o conjunto. O resultado é um job que tenta N×M vezes e demora horas para
# chegar ao dead set. Job que precisa de política própria a declara **nele mesmo**,
# e o comentário diz por quê (ver `DefaultMemberJob`).
#
# A política de retenção do dead set fica em `config/sidekiq.yml` (OPS-624), junto
# das filas — e não aqui, porque é configuração de processo, não de classe.
#
# ## Fila
#
# Toda fila usada precisa estar declarada em `config/sidekiq.yml`, ou o job é
# enfileirado e **nenhum worker o consome**. Está escrito lá, com o histórico do
# defeito ("mesmo defeito ja consertado no brsw e no facil").
class ApplicationJob < ActiveJob::Base
  # `DeserializationError` acontece quando o registro que o job carregava foi
  # apagado entre o enfileiramento e a execução. **Não é descartado em silêncio**:
  # vira log de aviso e o job termina — sem isso, todo `destroy` de registro com job
  # pendente entope o dead set com falhas que não têm conserto possível.
  #
  # Note a diferença para o D-79: aqui a condição é *conhecida, esperada e sem ação
  # corretiva*, e mesmo assim ela é REGISTRADA. O que o legado fazia era esconder
  # erro desconhecido.
  rescue_from ActiveJob::DeserializationError do |error|
    Rails.logger.warn(
      "[#{self.class.name}] registro removido antes da execução, job encerrado: #{error.message}"
    )
  end
end
