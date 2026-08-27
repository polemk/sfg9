# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `livetat_auth_users` (+ `livetat_auth_roles`, `livetat_auth_role_types`,
      # `livetat_auth_user_infos`) -> `User` (ai9).
      #
      # **É o conversor de maior risco da migração inteira**, por três razões, e as três
      # estão tratadas explicitamente abaixo:
      #
      # 1. **O papel (contrato C3).** No legado o papel NÃO é coluna de `users`: é o par
      #    `livetat_auth_roles(user_id, role_type_id)` -> `livetat_auth_role_types(name,
      #    hierarchy)`. E a escala é **invertida** — maior = mais poder (OG 1111 >
      #    Admin 998 > Gerente 888 > Colaborador 799) — contra a do ai9, onde **menor =
      #    mais poder**. O de-para é `Legacy::RoleMap`, **tabela explícita**: fórmula
      #    sobreviveria a um valor inesperado e produziria nível plausível e errado, e
      #    inverter o sinal aqui **dá poder de OG a um Colaborador**.
      #
      # 2. **`is_active = 0` nasce BLOQUEADO** (DEC-39): `blocked_at` preenchido e o
      #    usuário sai numa lista de exceções para revisão humana antes do cutover.
      #    Replicar seria não bloquear ninguém — a coluna foi criada em 2021 e **não tem
      #    um único leitor** no legado. Bloquear e revisar é reversível; liberar por
      #    engano não é. **`legacy_password` NÃO é migrada** (hash Django, senha
      #    adivinhável a partir do primeiro nome + `#6230` — D-106/D-109), num produto
      #    que não tem senha (DEC-14).
      #
      # 3. **`username` é identificador** (DEC-45), mas **não é canal**: quem tem
      #    `username` e nem e-mail nem telefone **não consegue entrar no dia 1**. Essa
      #    lista é obrigatória no dry-run e é possível bloqueador de cutover.
      class Users < Base
        def self.source_table = 'livetat_auth_users'
        def self.target_model = 'User'
        def self.requires = %w[User UserType]
        def self.owner_slice = 'S1'

        # O papel e o perfil não são colunas de `livetat_auth_users`: um usuário do
        # legado é a junção de QUATRO tabelas. Elas não entram na ordem de carga
        # porque não viram linha própria no ai9 — viram colunas de `users`.
        def self.also_reads = %w[livetat_auth_roles livetat_auth_role_types livetat_auth_user_infos]

        def self.references = { 'manager_id' => 'livetat_auth_users',
                                'default_project_id' => 'projects' }

        # `default_project_id` fecha o ciclo users -> projects -> segments -> users:
        # resolvido no SEGUNDO PASSO, depois de `projects` existir.
        def self.deferred = { 'default_project_id' => %w[projects default_project_id] }
        def self.booleans = %w[is_active is_default_member deactivated]
        def self.uniques = [%w[email], %w[username]]
        # `phone` e normalizado pelo model do ai9 (o `+` some). O valor migrado e o da
        # origem; a comparacao literal e que nao se aplica.
        def self.derived = %w[phone]

        # ======================================================================
        # QUEM ESTÁ DESLIGADO NO LEGADO — medido no dump de 31/05/2025
        # ======================================================================
        #
        # **`is_active` NÃO é o flag de bloqueio do legado. `deactivated` é.**
        #
        # `deactivated` é o **único** `boolean` do schema inteiro do legado, e é o que
        # o produto de fato lê: `sessions_decorator.rb:12` recusa o login,
        # `pub_application_controller.rb:45` derruba a sessão a cada request,
        # `users_controller.rb:149,154` é quem liga e desliga, e
        # `users/list/_widget.html.erb:20,62` é o que a tela mostra. **`is_active` não
        # tem um único leitor** — foi exatamente essa a observação que originou a
        # DEC-39.
        #
        # O cruzamento das duas colunas em produção:
        #
        #   | `is_active` | `deactivated` | usuários |
        #   | ----------- | ------------- | -------: |
        #   | 1           | f             |   **50** |  ← os únicos ativos de verdade
        #   | 1           | t             |   **72** |
        #   | 0           | t             |   **13** |
        #
        # `is_active = 0` é **subconjunto** de `deactivated = true`: bloquear só por
        # ele deixaria **72 contas hoje impedidas de entrar no legado entrarem no
        # ai9**, e nenhuma conta ativa seria bloqueada por engano. É a direção de erro
        # que a própria DEC-39 escolheu evitar — "bloquear e revisar é reversível;
        # liberar por engano não é".
        #
        # Por isso o bloqueio é a **união** das duas: 85 contas nascem com
        # `blocked_at`, e o relatório separa as três populações para a revisão humana.
        # É a REGRA da DEC-39 aplicada à coluna certa, e cai na exceção de
        # segurança/autorização do DEC-30 — não é regra nova.
        def self.blocked?(row)
          Sfg::Coercion.to_bool(row['deactivated']) || !Sfg::Coercion.to_bool(row['is_active'])
        end

        def convert(row)
          user_type, = role_for(row)
          info = user_info_for(row)
          active = !self.class.blocked?(row)

          {
            email: row['email'],
            name: row['formal'],
            username: row['username'].presence,
            identifier: valid_identifier(row['identifier']),
            user_type_id: user_type&.id,
            phone: compose_phone(info),
            # DEC-74: o indicador é REPLICADO como está. A **trava de edição do
            # telefone NÃO é** — no ai9 o telefone é canal de login, e replicar a
            # trava portaria um bloqueio de acesso sem autoatendimento.
            is_phone_checked: Values.to_boolean(info['is_phone_checked']).value,
            birthday: info['birthday'],
            # **DB-004.** `livetat_auth_user_infos.cpf` estava sendo LIDO e nao
            # mapeado: o conversor pegava `phone`, `birthday` e `is_phone_checked`
            # da mesma linha e deixava o documento para tras. Medido no dump de
            # 31/05/2025: **12 CPFs reais** na origem, `users.cpf_cnpj` zerado no
            # destino.
            #
            # Passava despercebido porque a coluna do destino aceita nulo — nao ha
            # erro, nao ha linha recusada, o documento so nao chega. Foi a
            # conferencia de paridade que achou, comparando origem x destino.
            #
            # O `before_validation :normalize_cpf_cnpj` do `User` tira a pontuacao;
            # os 12 tem 11 digitos, entao passam na validacao `\d{11}|\d{14}`.
            #
            # Nao ha `cnpj` a mapear: a coluna nao existe em `user_infos`.
            cpf_cnpj: info['cpf'].presence,
            manager_id: ref('livetat_auth_users', row['manager_id']),
            is_default_member: Values.to_boolean(row['is_default_member']).value,
            kind: row['kind'],
            color: row['color'],
            # DEC-39 — a conta inativa nasce BLOQUEADA, não "inativa e liberada".
            blocked_at: active ? nil : Values.to_utc(row['updated_at']).value,
            blocked_reason: active ? nil : blocked_reason_for(row),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
            # `legacy_password` NÃO consta desta lista, e é de propósito (BE-453).
          }
        end

        def natural_key(row) = { email: row['email'] }

        # O motivo diz QUAL das duas colunas desligou a conta. Sem isso a revisão
        # humana não distingue "desligado pelo produto" de "marcado por uma coluna que
        # ninguém lê".
        def blocked_reason_for(row)
          desligado = Sfg::Coercion.to_bool(row['deactivated'])
          inativo = !Sfg::Coercion.to_bool(row['is_active'])
          motivos = []
          motivos << '`deactivated = true` (o flag que o legado de fato lê no login)' if desligado
          motivos << '`is_active = 0` (coluna sem leitor no legado)' if inativo
          "Conta desligada no legado (DEC-39): #{motivos.join(' e ')}. Pendente de revisão humana antes do cutover."
        end

        # ------------------------------------------------------------ anomalias
        def anomalies(row)
          out = []
          out.concat(role_anomalies(row))
          out.concat(access_anomalies(row))
          out.concat(identifier_anomalies(row))
          out
        end

        # Achado ao EXECUTAR a carga contra a fixture, e ele e real: no legado
        # `identifier` e `string` livre; no ai9 e `/\A[A-Z0-9]{6}\z/` com unicidade
        # (`user.rb:122-125`). Identificador que nao casa **nao e adivinhado nem
        # normalizado**: entra `nil` e a linha vai para o relatorio. Inventar um
        # identificador de seis caracteres a partir de outro seria fabricar dado.
        AI9_IDENTIFIER = /\A[A-Z0-9]{6}\z/

        # ACHADO PELA INTROSPECCAO, e ele era um bloqueador de acesso silencioso:
        # **`livetat_auth_user_infos.phone` NAO EXISTE**. A migration
        # `20171201171448_add_phone_columns_to_user_info.rb` a REMOVEU em 2017 e a
        # partiu em tres — `phone_country_code`, `phone_area_code`, `phone_number`
        # (e `20171213170127` trocou o default de `+55` para `55`).
        #
        # Ler `info['phone']` traria `nil` para TODO MUNDO. E no ai9 o telefone e
        # **canal de login** (DEC-14): a base inteira chegaria sem canal de telefone,
        # e o dry-run do DEC-45 nao teria como contar quem fica sem entrar.
        def compose_phone(info)
          parts = [info['phone_country_code'], info['phone_area_code'], info['phone_number']]
          digits = parts.map { |part| part.to_s.gsub(/\D/, '') }
          return nil if digits[1].empty? && digits[2].empty?

          digits.join.presence
        end

        def valid_identifier(value)
          raw = value.to_s.strip
          raw.match?(AI9_IDENTIFIER) ? raw : nil
        end

        def identifier_anomalies(row)
          raw = row['identifier'].to_s.strip
          return [] if raw.empty? || raw.match?(AI9_IDENTIFIER)

          [{ key: 'users:identifier_format',
             title: 'Identificador da origem fora do formato do ai9 (/\A[A-Z0-9]{6}\z/) — carregado como NULO e listado',
             line: "- pk=#{row['id']} `#{row['email']}` identifier=#{raw.inspect}" }]
        end

        private

        # C3 — o de-para. `Legacy::RoleMap.resolve` LEVANTA em valor desconhecido; aqui
        # o levantar é deixado subir de propósito na carga (aborta o lote) e é
        # capturado no scan, para virar linha de relatório em vez de nível inventado.
        def role_for(row)
          type = role_type_row(row)
          Legacy::RoleMap.user_type_for(hierarchy: type&.dig('hierarchy'), name: type&.dig('name'))
        rescue Legacy::RoleMap::UnknownLegacyRole
          [nil, true]
        end

        def role_type_row(row)
          role = roles_by_user[row['id'].to_i]
          return nil if role.nil?

          role_types[role['role_type_id'].to_i]
        end

        def roles_by_user
          @roles_by_user ||= begin
            rows = run.source.table?('livetat_auth_roles') ? run.source.ordered_rows('livetat_auth_roles') : []
            rows.index_by { |r| r['user_id'].to_i }
          end
        end

        def role_types
          @role_types ||= begin
            rows = run.source.table?('livetat_auth_role_types') ? run.source.ordered_rows('livetat_auth_role_types') : []
            rows.index_by { |r| r['id'].to_i }
          end
        end

        def user_infos
          @user_infos ||= begin
            rows = run.source.table?('livetat_auth_user_infos') ? run.source.ordered_rows('livetat_auth_user_infos') : []
            rows.index_by { |r| r['user_id'].to_i }
          end
        end

        def user_info_for(row) = user_infos.fetch(row['id'].to_i, {})

        def role_anomalies(row)
          type = role_type_row(row)
          out = []

          # D-36 / DEC-18.8 — papel vazio. Entra como Colaborador **e** vai para revisão.
          if type.nil? || (type['hierarchy'].to_s.strip.empty? && type['name'].to_s.strip.empty?)
            out << { key: 'roles:empty_role',
                     title: 'Papel vazio na origem (D-36) — entram como Colaborador e vão para REVISÃO HUMANA',
                     line: "- pk=#{row['id']} `#{row['email']}` sem papel na origem" }
          else
            begin
              Legacy::RoleMap.resolve(hierarchy: type['hierarchy'], name: type['name'])
            rescue Legacy::RoleMap::UnknownLegacyRole => e
              out << { key: 'roles:unknown',
                       title: 'PAPEL DESCONHECIDO NA ORIGEM — o de-para é tabela e NÃO adivinha',
                       line: "- pk=#{row['id']} `#{row['email']}` — #{e.message}" }
            end
          end

          out.concat(staff_precedence_anomalies(row))
          out
        end

        # **Q-16 / tarefa 5.5.** O adaptador de 2021 fazia
        # `is_staff ? MANAGER : is_superuser ? ADMIN : COLAB`
        # (`../sfg/app/models/legacy/u.rb:33`) — **equipe tem precedência sobre
        # superusuário**. Quem era `is_staff` E `is_superuser` virou **Gerente**, não
        # Admin. Há usuários ativos com papel errado desde 2021.
        #
        # **DEC-16: NÃO reprocessar.** O dry-run LISTA, com o par `(is_staff,
        # is_superuser)` da origem, e a revisão é humana.
        def staff_precedence_anomalies(row)
          django = django_users[row['email'].to_s.downcase]
          return [] if django.nil?

          staff = truthy?(django['is_staff'])
          superuser = truthy?(django['is_superuser'])
          return [] unless staff && superuser

          [{ key: 'roles:staff_precedence',
             title: 'Q-16 — papel definido em 2021 por precedência INVERTIDA (equipe venceu superusuário). REVISÃO HUMANA, sem reprocessar',
             line: "- pk=#{row['id']} `#{row['email']}` — origem Django: is_staff=#{staff}, is_superuser=#{superuser} " \
                   '-> o adaptador gravou **Gerente**; se a intenção era superusuário, o papel correto seria **Admin**' }]
        end

        # A tabela Django só existe quando a origem é o dump pré-2021. Ausente, a seção
        # sai vazia — e isso é dito, não silenciado.
        def django_users
          @django_users ||= begin
            rows = run.source.table?('authentication_user') ? run.source.ordered_rows('authentication_user') : []
            rows.index_by { |r| r['email'].to_s.downcase }
          end
        end

        def truthy?(value) = [true, 't', 'true', 1, '1'].include?(value)

        # DEC-45 + DEC-39 + DEC-74 — as três contagens que o usuário precisa ver ANTES
        # do cutover, porque duas delas são bloqueador de acesso.
        def access_anomalies(row)
          out = []
          has_email = row['email'].to_s.strip.present?
          # **`user_info['phone']` NÃO EXISTE** — a migration de 2017 a partiu em três.
          # Ler a coluna morta aqui fazia `has_phone` ser `false` para todo mundo, e a
          # contagem do DEC-45 media outra coisa. Usa-se o MESMO compositor da carga.
          has_phone = compose_phone(user_info_for(row)).present?

          if row['username'].to_s.strip.present? && !has_email && !has_phone
            out << { key: 'users:username_without_channel',
                     title: 'DEC-45 — tem `username` e NENHUM canal (nem e-mail nem telefone): NÃO CONSEGUE ENTRAR no dia 1',
                     line: "- pk=#{row['id']} username=`#{row['username']}` — possível BLOQUEADOR DE CUTOVER" }
          end

          if self.class.blocked?(row)
            out << { key: 'users:inactive_blocked',
                     title: 'DEC-39 — conta DESLIGADA no legado: nasce com `blocked_at` e vai para revisão humana. ' \
                            'O flag que vale é `deactivated` (o único que o legado lê), não `is_active`',
                     line: "- pk=#{row['id']} `#{row['email']}` — deactivated=#{row['deactivated'].inspect}, " \
                           "is_active=#{row['is_active'].inspect}" }
          end

          if Values.to_boolean(user_info_for(row)['is_phone_checked']).value
            out << { key: 'users:phone_checked',
                     title: 'DEC-74 — chega com `is_phone_checked = 1` (a trava de edição NÃO é replicada)',
                     line: "- pk=#{row['id']} `#{row['email']}`" }
          end

          out
        end
      end
    end
  end
end
