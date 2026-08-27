# frozen_string_literal: true

module Demo
  module Writers
    # Os 12 clientes da gestora (`projects`). Chave natural: `slug`.
    #
    # Hoje o `Project` da S0 é **esquema e regra mínima** — nome, slug, dono e
    # `is_active`. As colunas de cadastro (`formal`, `closing_date`, `segment_id`,
    # `integration_key`, `color`, `responsible_id`) nascem na **S4**. Este escritor
    # já as manda: `Base#assign` grava as que existem e registra as que não
    # existem. Quando a S4 entregar, **o mesmo `rake demo:seed` passa a preenchê-las
    # sozinho**, sem uma linha de mudança aqui.
    #
    # Doze projetos com Kaminari em 10 por página dão **duas páginas** — que é o
    # ponto de §6: paginador vazio parece protótipo.
    class Projects < Base
      def self.requires = %w[Project User]

      # Paleta estável por índice, para o cliente #3 ter sempre a mesma cor entre
      # ensaios. Cor sorteada muda a cada rodada e confunde quem já viu a demo.
      COLORS = %w[#1F6FEB #B45309 #047857 #7C3AED #BE123C #0E7490
                  #4D7C0F #9333EA #C2410C #0F766E #DC2626 #2563EB].freeze

      def call
        owner = ::User.find_by(email: admin_email)
        if owner.nil?
          io.puts '   ⚠ usuário Admin do elenco ausente — projetos não foram criados'
          return
        end

        ledger.clients.each do |client|
          upsert!(::Project, find_by: { slug: client.slug }, attributes: {
                    name: client.name,
                    formal: client.formal,
                    user_id: owner.id,
                    is_active: true,
                    color: COLORS[(client.index - 1) % COLORS.length],
                    closing_date: client.closing_date,
                    integration_key: client.slug.tr('-', '_'),
                    has_safegold_management: true
                  })
        end

        write_availability_notes!
        adopt_current_project!(owner)
      end

      private

      # A **nota de disponibilidade** (ActionText, DB-313). Três projetos com
      # texto e nove sem, de propósito.
      #
      # Campo de texto rico que o seed deixa sempre vazio é exatamente onde mora
      # o defeito que ninguém vê: o detalhe de projeto já caiu inteiro com
      # `Cannot read properties of null (reading 'trim')` porque a entity
      # devolvia `nil` para nota vazia enquanto o irmão `_html` devolvia `""` —
      # e o `tsc` estava verde. Semear **os dois caminhos** é o que faz a
      # apresentação passar por ambos.
      NOTES = {
        0 => 'Fechamento do grupo consolidado toda sexta-feira, com prévia na quarta. ' \
             'Antecipações de intercompany exigem aprovação do controller.',
        2 => 'Cliente opera com dois FIDCs desde a entrada do Aurora. Prazo médio ' \
             'combinado de 42 dias; recusa acima de 8% dispara revisão do lastro.',
        10 => 'Em recuperação. Renegociações com fornecedores em andamento e limite ' \
              'do Vértice reduzido — a exposição está acima do teto vigente.'
      }.freeze

      def write_availability_notes!
        NOTES.each do |index, texto|
          client = ledger.clients[index]
          project = client && ::Project.find_by(slug: client.slug)
          next if project.nil? || !project.respond_to?(:availability_note)
          # **Só quando vazia.** A nota é conteúdo editável na tela; reescrevê-la
          # a cada execução desfaria o que o usuário escreveu — e faria o
          # ActionText gravar uma linha nova por rodada.
          next if project.availability_note.body.present?

          project.availability_note = texto
          project.save!
          @updated += 1
        end
      end

      def admin_email
        ledger.cast.find { |m| m[:key] == :admin }[:email]
      end

      # `users.current_project_id` é **preferência**, não autorização (contrato
      # C1) — mas sem ela o Admin abre o console sem projeto corrente e a primeira
      # tela da demo pede uma escolha antes de mostrar qualquer coisa.
      def adopt_current_project!(owner)
        first = ::Project.find_by(slug: ledger.clients.first.slug)
        return if first.nil? || owner.current_project_id == first.id

        owner.update!(current_project_id: first.id)
        @updated += 1
      end
    end
  end
end
