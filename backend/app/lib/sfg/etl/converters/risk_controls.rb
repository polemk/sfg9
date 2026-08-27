# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `risk_controls` (legado) -> `RiskControl` (ai9). **Escrito pela S5.**
      #
      # ===========================================================================
      # O QUE A PRODUÇÃO REALMENTE TEM — medido, não suposto
      # ===========================================================================
      #
      # `.migration-ai9/analise-dump-producao.md` §2, consulta 5 (26/08/2026):
      #
      # - `risk_controls` tem **600 linhas**;
      # - a tabela **não tem** `risk_operation_type_id`, `limite`, `taxa`,
      #   `original_balance` nem `original_balance_pre` — a migration
      #   `20220611152145_change_risk_control_fields.rb` **nunca subiu**;
      # - o formato real é o de 2021: **4 pares fixos** `(limite_X, taxa_X)`;
      # - valores não-zero por família: auto-liquidáveis **457**, comissária
      #   **151**, fomento **131**, intercompany **28** (total **767**).
      #
      # Ou seja: a pergunta P-018 ("sobrou alguma linha antiga?") estava invertida.
      # **Não existe nenhuma linha no formato novo.**
      #
      # ===========================================================================
      # A carga é em DOIS PASSOS, e o motivo é `risk_entries`
      # ===========================================================================
      #
      # **Passo 1 (este `convert`) — a linha herdada entra como está, SEM tipo.**
      #
      # Ela precisa existir porque `risk_entries` aponta para ela, e `risk_entries`
      # é a **maior tabela do sistema**: 642.447 linhas, com dado até 31/05/2025
      # (DEC-57 manda preservá-las). E a posição diária **não pertence a uma
      # família**: ela tem colunas próprias para `fomento_*`, `comissaria_*` e
      # `intercompany_*` na mesma linha. O alvo natural dela é justamente o limite
      # **não tipado** — apontá-la para uma das quatro famílias seria escolher uma
      # resposta que o dado não dá.
      #
      # É exatamente aqui que a rotina do legado desistia: `generate_new_controls_on_migration`
      # (`../sfg/app/models/risk_control.rb:207`) faz `rc.risk_entries.destroy_all`
      # antes de apagar o limite antigo. **Apagar 642 mil linhas de histórico não é
      # conversão, é perda** — e contraria a DEC-57.
      #
      # **Passo 2 (`expand_typed_controls!`) — as linhas tipadas nascem dos 4 pares.**
      #
      # **Uma linha por tipo, sempre** — 4 por origem, inclusive zeradas, que é o
      # que a rotina de 2022 faz. As linhas tipadas são as que o painel de
      # exposição enxerga; a herdada fica como âncora do histórico, fora de todo
      # agregado, com o rótulo "Legado" na tela (FE-243).
      #
      # **O que isso significa, com honestidade: nao ha oraculo.** Estes valores foram
      # conferidos contra o **fonte de 2022** — arquivo e linha citados em cada
      # cenario —, e nao contra comportamento observado. O golden trava a LEITURA do
      # codigo de 2022; ele nao prova que o numero esta certo, prova que nao mudamos o
      # que o legado fazia. A DEC-103b manda espelhar, e e isso que esta feito.
      #
      # **A marca serve de ponteiro:** no dia em que um numero sair estranho, ela diz
      # em segundos que a resposta esta no fonte de 2022, e nao numa base de producao
      # que nunca teve estes registros.
      #
      # `change_risk_control_fields` e as outras 23 migrations de 2022 nunca
      # subiram (`analise-dump-producao.md` §1).
      #
      # **DEC-103b:** *"vamos manter elas e seus recursos como um espelho do
      # legado mesmo assim"*. O critério de fidelidade é o **fonte** de 2022.
      #
      #
      #
      # ### O que esta conversão replica de `generate_new_controls_on_migration`
      #
      # (`../sfg/app/models/risk_control.rb:172-210`)
      #
      # 1. **Uma linha por tipo, SEMPRE** (`:174`, `RiskOperationType.all.each`),
      #    inclusive com limite e taxa zerados: 4 linhas por origem, 2.400 no
      #    total, não só as 767 com valor.
      # 2. **`is_active = 0` só para "Auto Liquidável"** (`:194`). É a família com
      #    **mais** registros em produção (457 de 767) — ou seja, a maior parte da
      #    carteira entra desativada e fora do painel. **Não há justificativa no
      #    código, e ela é replicada mesmo assim, por decisão explícita do
      #    usuário.** Quem for conferir o painel depois da carga precisa saber
      #    disto: é o comportamento pedido, não um defeito.
      # 3. O par (limite, taxa) de cada família vai para a linha do tipo
      #    correspondente (`:190-204`); `project_id`, `title` e `is_active` são
      #    copiados da origem (`:181-188`).
      #
      # ### As duas coisas que NÃO são espelhadas, e a DEC que manda em cada uma
      #
      # - **`rc.risk_entries.destroy_all` + `rc.destroy`** (`:207-208`) — a rotina
      #   de 2022 APAGA as posições diárias e a linha de origem. Em produção são
      #   **642.447 linhas** de histórico real, com dado até 31/05/2025, e a
      #   **DEC-57** manda preservá-las. Decisão do usuário vence script.
      # - **`when "Auto Liquidável"`** (`:190-204`), casamento por **título
      #   literal** — a decisão **B-09** já trocou esse mecanismo por
      #   `integration_key` em todo o bloco. O de-para produzido é **idêntico**;
      #   o que muda é não quebrar em silêncio depois de um rename na tela. É
      #   troca de mecanismo, não de comportamento — a mesma classe do OPS-234.
      #
      # ===========================================================================
      # O que NÃO é carregado
      # ===========================================================================
      #
      # - **`has_safegold_management`**: derivada do projeto pela empresa no ai9, sem
      #   coluna (mesma escolha da S4 em `Company`).
      # - **o par estático de `RiskOperation`**: não há operação nenhuma em produção
      #   (`create_risk_operations` também nunca subiu), e o `after_create` não roda
      #   na carga — o motor grava sem callback.
      class RiskControls < Base
        # `família => coluna de limite, coluna de taxa, chave do tipo`.
        # As chaves são as mesmas que `Seeds::Reference::RiskOperationTypes` semeia.
        FAMILIES = [
          { key: 'auto_liquidavel', limite: 'limite_auto_liquidaveis', taxa: 'taxa_auto_liquidaveis' },
          { key: 'comissaria',      limite: 'limite_comissaria',       taxa: 'taxa_comissaria' },
          { key: 'fomento',         limite: 'limite_fomento',          taxa: 'taxa_fomento' },
          { key: 'intercompany',    limite: 'limite_intercompany',     taxa: 'taxa_intercompany' }
        ].freeze

        def self.source_table = 'risk_controls'
        def self.target_model = 'RiskControl'
        def self.requires = %w[RiskControl Company Carrier Project RiskOperationType]
        def self.owner_slice = 'S5'

        def self.references = {
          'user_id' => 'livetat_auth_users',
          'project_id' => 'projects',
          'company_id' => 'companies',
          'carrier_id' => 'carriers'
        }

        def self.booleans = %w[is_active has_safegold_management]
        # Os quatro pares REAIS. É neles que o dinheiro está.
        def self.sums = FAMILIES.map { |f| f[:limite] }
        # `title` é reescrito pelo `before_validation` a partir do portador.
        def self.derived = %w[title]

        # **Passo 1** — a linha herdada, sem tipo, com os 4 pares preservados.
        def convert(row)
          atributos = {
            project_id: ref('projects', row['project_id']),
            # DEC-112 — CARIMBO histórico, vindo da origem. Se o callback o
            # recopiasse do projeto/empresa, o valor de hoje apagaria a foto do
            # momento — ver `SafegoldStamped`.
            has_safegold_management: Values.to_boolean(row['has_safegold_management']).value,
            company_id: ref('companies', row['company_id']),
            carrier_id: ref('carriers', row['carrier_id']),
            user_id: ref('livetat_auth_users', row['user_id']),
            title: row['title'],
            # Sem tipo: é o que a produção tem. A validação do model dispensa a
            # linha que tem `legacy_id` — e só ela.
            risk_operation_type_id: nil,
            # As colunas do formato novo não existem na origem; ficam no default.
            limite: 0,
            taxa: 0,
            original_balance: 0,
            original_balance_pre: 0,
            is_active: Values.to_boolean(row['is_active']).value,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }

          FAMILIES.each do |familia|
            atributos[familia[:limite].to_sym] = Values.to_decimal(row[familia[:limite]])
            atributos[familia[:taxa].to_sym] = Values.to_float(row[familia[:taxa]])
          end

          atributos
        end

        # Uma linha da origem com os 4 pares zerados é limite que não autoriza
        # nada. Ela **carrega** (o registro existe e o histórico aponta para ele),
        # mas a anomalia vai ao relatório: é candidata a expurgo, e a decisão é do
        # usuário, não do ETL.
        def anomalies(row)
          vazia = FAMILIES.all? do |f|
            Values.to_decimal(row[f[:limite]]).to_f.zero? && Values.to_float(row[f[:taxa]]).to_f.zero?
          end
          return [] unless vazia

          ["risk_controls##{row['id']}: os 4 pares (limite, taxa) são zero — o limite não autoriza nada."]
        end

        class << self
          # **Passo 2** — expande as linhas herdadas em linhas TIPADAS.
          #
          # Idempotente: `find_or_initialize_by(company, carrier, tipo)` e o índice
          # único do banco por trás. Rodar de novo não duplica e não desfaz o que o
          # usuário arrumou na tela — só preenche o que falta.
          #
          # **Não apaga nada.** A linha herdada continua lá, ancorando as posições
          # diárias (DEC-57).
          def expand_typed_controls!(io: nil)
            return { created: 0, skipped_no_type: [], sources: 0 } unless model_ready?('RiskControl')

            tipos = FAMILIES.to_h { |f| [f[:key], ::RiskOperationType.find_by(integration_key: f[:key])] }
            faltando = tipos.select { |_k, v| v.nil? }.keys
            if faltando.any?
              io&.puts("   ⚠ tipos de limite ausentes: #{faltando.join(', ')} — rode `rake reference:seed` antes")
              return { created: 0, skipped_no_type: faltando, sources: 0 }
            end

            criados = 0
            origens = 0

            ::RiskControl.where(risk_operation_type_id: nil).where.not(legacy_id: nil).find_each do |herdado|
              origens += 1

              # **Uma linha por tipo, SEMPRE** — inclusive zerada. Espelho de
              # `RiskOperationType.all.each` (`risk_control.rb:174`).
              FAMILIES.each do |familia|
                tipado = ::RiskControl.find_or_initialize_by(
                  company_id: herdado.company_id,
                  carrier_id: herdado.carrier_id,
                  risk_operation_type_id: tipos[familia[:key]].id
                )
                next unless tipado.new_record?

                tipado.project_id = herdado.project_id
                tipado.user_id = herdado.user_id
                tipado.limite = herdado.public_send(familia[:limite]) || 0
                tipado.taxa = herdado.public_send(familia[:taxa]) || 0
                # **DEC-105 — decidido pelo usuario, nao e defeito.** Auto-liquidavel
                # entra DESATIVADA; as outras tres herdam o `is_active` da linha
                # antiga. E o que `risk_control.rb:194` faz, sem justificativa no
                # codigo de 2022.
                #
                # A consequencia foi medida e levada ao usuario antes de virar
                # decisao: sao **457 dos 767** limites nao-zero, ou seja a maior
                # parte da carteira nao aparece no painel no primeiro dia. Ele
                # respondeu "se no legado e assim vai continuar assim".
                #
                # QA: nao abra bug contra esta linha. Se alguem perguntar por que
                # faltam limites no painel depois da carga, a resposta e esta.
                tipado.is_active = familia[:key] == 'auto_liquidavel' ? false : herdado.is_active
                tipado.created_at = herdado.created_at
                tipado.updated_at = herdado.updated_at
                tipado.save!(touch: false)
                criados += 1
              end
            end

            io&.puts("   ✔ limites tipados: #{criados} criados a partir de #{origens} linha(s) herdada(s)")
            { created: criados, skipped_no_type: [], sources: origens }
          end

          # Relatório da carga: quantas linhas de cada formato ficaram no destino.
          # É o número que responde a DEC-43 — e, medido contra o dump, a resposta
          # esperada é 600 herdadas e ~767 tipadas.
          def post_load!
            return { legacy_shape: 0, typed: 0 } unless model_ready?('RiskControl')

            herdadas = ::RiskControl.where(risk_operation_type_id: nil).count
            tipadas = ::RiskControl.where.not(risk_operation_type_id: nil).count

            {
              legacy_shape: herdadas,
              typed: tipadas,
              note: "DEC-43 respondida pelo dump: NENHUMA linha da origem tem tipo. #{herdadas} linha(s) " \
                    "herdada(s) preservada(s) como âncora de `risk_entries` (DEC-57) e #{tipadas} linha(s) " \
                    'tipada(s) derivada(s) dos 4 pares. As herdadas ficam FORA de todos os agregados, ' \
                    'com o rótulo "Legado" na tela (FE-243).'
            }
          end
        end
      end
    end
  end
end
