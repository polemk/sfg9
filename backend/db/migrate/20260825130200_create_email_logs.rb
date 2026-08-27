# frozen_string_literal: true

# S1 / 6.7 — `email_logs`. Fecha DB-514, decisão **DEC-90**.
#
# **Guarda só metadados. Nunca o corpo.**
#
# No legado, `livetat_mailer_contacts` guarda `message` — e a coluna foi promovida de
# `string` para `text` em duas migrations de 19/05/2017 justamente para caber o corpo.
# Cada envio grava o corpo antes de enfileirar
# (`mailer19/lib/livetat/mailer19/grind_mailer.rb:5-13,27,47,67,85`), **inclusive
# e-mails de credenciais** (`mailer_decorator.rb:4`), e não há expurgo nenhum: zero
# ocorrências de purge/cleanup/`destroy_all` em `lib/`, `app/jobs` ou no engine.
#
# No ai9 os 3 e-mails vivos são de identidade, e **o código de acesso É a credencial**.
# Guardar o corpo seria guardar a credencial em texto puro por outro nome, com retenção
# infinita. Por isso esta tabela não tem coluna de corpo — não é convenção, é ausência
# deliberada: sem a coluna, nenhum `deliver` futuro consegue gravar o corpo por engano.
#
# O expurgo de 180 dias já existe e já está agendado: `PurgeEmailLogsJob` (S18) tolerava
# a ausência desta tabela e passa a expurgar sozinho a partir daqui.
class CreateEmailLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :email_logs, id: :uuid, comment: 'DEC-90 — metadados de entrega de e-mail. SEM CORPO. Expurgo de 180 dias por PurgeEmailLogsJob.' do |t|
      t.string :mailer,     null: false, comment: 'Classe e ação do mailer (ex.: AuthMailer#magic_login_code).'
      t.string :from_email, null: false, comment: 'Remetente.'
      t.string :to_email,   null: false, comment: 'Destinatário.'
      t.string :subject,                 comment: 'Assunto. É metadado; nunca carrega o código de acesso.'
      t.string :status,     null: false, default: 'sent', comment: 'sent | failed.'
      t.string :error_message,           comment: 'Mensagem do erro quando `status = failed`.'
      t.uuid   :user_id,                 comment: 'Destinatário como usuário, quando conhecido. FK lógica: o log sobrevive à remoção da conta.'

      t.timestamps
    end

    add_index :email_logs, :created_at, name: 'index_email_logs_on_created_at'
    add_index :email_logs, :to_email,   name: 'index_email_logs_on_to_email'
    add_index :email_logs, :user_id,    name: 'index_email_logs_on_user_id'
  end
end
