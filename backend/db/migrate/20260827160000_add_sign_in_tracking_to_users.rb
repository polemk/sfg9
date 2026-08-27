# frozen_string_literal: true

# **DB-012 / DEC-139 — o rastreio de acesso do legado ganha coluna.**
#
# O legado guarda `sign_in_count` e `last_sign_in_at` (Devise trackable) em
# `livetat_auth_users`. Medido no dump de 31/05/2025: **86 usuários com data de
# último acesso** e **6.134 acessos somados**, o mais recente em 31/05/2025.
#
# O item estava travado — e não "esquecido" — porque não era mapeamento
# faltando: as duas colunas **não existiam** no destino. O conversor não tinha
# onde escrever.
#
# ## ⚠ O contador passa a misturar dois mecanismos, e isso é deliberado
#
# O legado contava login **por senha**. O ai9 não tem senha: entra por link
# mágico e por código (DEC-45). O número herdado é histórico do mecanismo
# ANTIGO; o que crescer daqui para frente é do novo.
#
# Somar os dois e ler como "acessos" seria comparar coisas diferentes. Fica
# escrito aqui e no comentário da coluna para ninguém descobrir isso num
# relatório.
#
# `last_sign_in_at` não sofre desse problema: "quando entrou pela última vez" é
# a mesma pergunta nos dois mecanismos, e é o que a tela de detalhe já mostra
# como «Último acesso» — hoje lendo outra fonte.
class AddSignInTrackingToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :sign_in_count, :integer, null: false, default: 0,
               comment: 'Devise trackable do legado. **Conta login por SENHA**, mecanismo que o ai9 ' \
                        'não tem — o valor herdado é histórico e não soma com a entrada por link ' \
                        'mágico. Medido no dump: 6.134 acessos em 86 contas (DEC-139).'

    add_column :users, :last_sign_in_at, :datetime,
               comment: 'Devise trackable do legado: quando a conta entrou pela última vez. ' \
                        'Diferente do contador, esta pergunta é a mesma nos dois mecanismos (DEC-139).'

    # Sem índice: nenhuma consulta filtra nem ordena por estas duas hoje. Índice
    # que ninguém usa é escrita mais cara em toda gravação de conta — e a de
    # conta é a mais quente da base.
  end
end
