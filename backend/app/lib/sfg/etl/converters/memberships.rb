# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `memberships` (legado) -> `Membership` (ai9).
      #
      # Dois pontos que so este conversor conhece:
      #
      # 1. **`memberable_id`/`memberable_type` (polimorfico) vira `project_id`.** No
      #    legado a associacao e polimorfica e, na pratica, sempre `Project`. Linha com
      #    outro `memberable_type` NAO e convertida em silencio: vira anomalia.
      # 2. **O papel de participacao e texto em pt-BR com acento** ("Responsavel",
      #    "Participante", "Coordenador", "Gestor") e vira chave estavel. Valor fora do
      #    de-para **aborta**, porque o `check constraint` do ai9 recusaria a linha no
      #    meio da carga — e um papel de projeto errado e acesso errado.
      class Memberships < Base
        # ======================================================================
        # ⚠ ESTE DE-PARA NÃO COBRE 59% DA PRODUÇÃO, E ISSO É DE PROPÓSITO
        # ======================================================================
        #
        # Medido no dump de 31/05/2025 (`rake sfg_etl:dry_run SOURCE=dump`):
        #
        #   | valor            | linhas | está aqui? |
        #   | ---------------- | -----: | ---------- |
        #   | `Participante`   |    448 | sim        |
        #   | `Responsável`    |     17 | sim        |
        #   | **`Gerente`**    |  **655** | **NÃO**  |
        #   | **`Colaborador`**|   **14** | **NÃO**  |
        #
        # `Coordenador` e `Gestor` estão no de-para porque o **model do legado** os
        # declara (`../sfg/app/models/membership.rb:18-21`) — e **nenhum dos dois
        # existe em produção**. Os 669 que existem e não estão aqui foram escritos
        # pelo **ETL de 2021**: `../sfg/app/models/legacy/membership.rb:17` grava
        # `role: is_staff ? U.MANAGER : is_superuser ? U.ADMIN : U.COLAB`, ou seja o
        # **papel GLOBAL do usuário no campo de papel do PROJETO**, pela mesma
        # expressão de precedência invertida do Q-16.
        #
        # **RESOLVIDO — DEC-106.** A recusa em inventar mapeamento estava certa, e
        # a medição que faltava mudou o quadro. Três fatos, todos conferidos:
        #
        # 1. **O valor não descreve nada.** Cruzando `memberships.role` com o tipo
        #    REAL do usuário no dump: 441 linhas dizem `Gerente` para gente cujo
        #    tipo é **Colaborador**, e 214 para gente que é **Admin**. Não é cópia
        #    do papel global — é uma constante. O que ele codifica é o `is_staff`
        #    do **Django anterior**, lido pelo ETL de 2021 de uma tabela que nem
        #    existe mais em `livetat_auth_users`.
        # 2. **Ninguém lê.** No legado, `memberships.role` é escrito e nunca lido:
        #    as únicas leituras de `.role` no `app/` são `user.role.abilities`,
        #    que é outra coisa. Não há tela, gate nem consulta.
        # 3. **O ai9 proíbe usá-lo.** O comentário de `app/models/membership.rb:10`
        #    diz, com todas as letras, que autorização não passa por aqui.
        #
        # Logo, mapear para `participante` — o default do PRÓPRIO model do legado
        # (`../sfg/app/models/membership.rb:10`, `self.role ||= ROLE__PARTICIPANT`)
        # — **não perde informação, porque não há informação**. O literal de origem
        # vai no relatório do ETL, então a auditoria continua possível.
        #
        # Fica registrado como `D-127` em `legacy-defects.md`: é defeito de dado do
        # importador de 2021, não regra a espelhar. Se um dia alguém quiser os 669
        # de volta ao literal, é uma linha aqui.
        ROLE_MAP = {
          'Responsável' => 'responsavel',
          'Responsavel' => 'responsavel',
          'Participante' => 'participante',
          'Coordenador' => 'coordenador',
          'Gestor' => 'gestor',
          # Os 669 fósseis do importador de 2021 — ver o bloco acima.
          'Gerente' => 'participante',
          'Colaborador' => 'participante'
        }.freeze

        def self.source_table = 'memberships'
        def self.target_model = 'Membership'
        def self.owner_slice = 'S1'
        def self.references = { 'user_id' => 'livetat_auth_users', 'memberable_id' => 'projects' }
        def self.booleans = %w[is_active]
        def self.enums = { 'role' => ROLE_MAP }
        def self.uniques = [%w[user_id memberable_id memberable_type]]

        def convert(row)
          {
            user_id: ref('livetat_auth_users', row['user_id']),
            project_id: ref('projects', row['memberable_id']),
            role: Values.to_enum_key(row['role'], ROLE_MAP).value,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        def anomalies(row)
          type = row['memberable_type'].to_s
          return [] if type.empty? || type == 'Project'

          [{ key: 'memberships:non_project_memberable',
             title: 'Participacao polimorfica apontando para algo que NAO e Project — o ai9 so tem projeto',
             line: "- pk=#{row['id']} memberable_type=#{type.inspect}" }]
        end
      end
    end
  end
end
