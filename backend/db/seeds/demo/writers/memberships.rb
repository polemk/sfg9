# frozen_string_literal: true

module Demo
  module Writers
    # As participações. Chave natural: `(user_id, project_id)` — o índice único
    # que a S0 já declarou.
    #
    # A teia é desenhada para **provar o escopo ao vivo**: as carteiras dos dois
    # colaboradores não se cruzam, então entrar como Camila e depois como Rafael
    # mostra dois conjuntos de clientes disjuntos, sem nenhuma configuração no
    # meio. É a demonstração mais curta possível de que o escopo vem de
    # `memberships`, e não de uma flag no usuário.
    #
    # `role` aqui é **rótulo descritivo** e nunca autoriza nada (DEC-18.6).
    class Memberships < Base
      def self.requires = %w[Membership User Project]

      def call
        users = ::User.where(email: ledger.cast.map { |m| m[:email] }).index_by(&:email)
        projects = ::Project.where(slug: ledger.clients.map(&:slug)).index_by(&:slug)
        by_key = ledger.cast.index_by { |m| m[:key] }

        ledger.membership_pairs.each do |pair|
          user = users[by_key.dig(pair[:user_key], :email)]
          project = projects[pair[:client].slug]
          next if user.nil? || project.nil?

          upsert!(::Membership,
                  find_by: { user_id: user.id, project_id: project.id },
                  attributes: { role: pair[:role] })
        end

        adopt_current_projects!(users, projects, by_key)
      end

      private

      # Cada usuário abre o console já dentro de um projeto em que participa —
      # e o projeto é sempre o **primeiro da carteira dele**, não o mesmo para
      # todos, senão a troca de usuário mostraria a mesma tela três vezes.
      #
      # **O OG fica de fora, e isso é a demonstração de um estado.** Ele não tem
      # participação (vê todos os projetos por papel, DEC-99) e não tem projeto
      # corrente, então ao entrar cai no `409 PROJECT_NOT_SELECTED` — a tela que
      # pede para escolher um projeto, e não "projeto não encontrado". É o único
      # usuário do elenco nesse estado, de propósito: é preciso um para mostrar a
      # tela, e ele é justamente o que a demonstração ao cliente não usa.
      def adopt_current_projects!(users, projects, by_key)
        ledger.membership_pairs.group_by { |p| p[:user_key] }.each do |key, pairs|
          user = users[by_key.dig(key, :email)]
          project = projects[pairs.first[:client].slug]
          next if user.nil? || project.nil? || user.current_project_id == project.id

          user.update!(current_project_id: project.id)
          @updated += 1
        end
      end
    end
  end
end
