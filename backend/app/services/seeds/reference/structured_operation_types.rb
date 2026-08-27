# frozen_string_literal: true

module Seeds
  module Reference
    # S8 / **DB-292**, **DB-580**, tarefas 2.1 e F.3 — os **quatro tipos de
    # operação estruturada**. Dado de REFERÊNCIA, não de vitrine.
    #
    # ### Por que é referência
    #
    # Sem uma linha aqui, `Remuneration` não tem tipo da classe **EST** para
    # apontar, e `Receipt#fetch` nunca acha taxa para uma operação estruturada:
    # o faturamento do lado EST fica em zero e a tela de cobrança mostra lista
    # vazia — que é falso e leva a fechar o mês com receita a menos. É o mesmo
    # critério dos tipos de limite da S5.
    #
    # ### ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
    #
    # `20220701123654_create_structured_operation_types` é uma das **24
    # migrations que nunca subiram** (`analise-dump-producao.md` §1): a última
    # aplicada em produção é de **25/05/2022** e o sistema rodou em uso até
    # **31/05/2025**. A tabela **não existe** no dump, e o `db/seeds.rb` do
    # legado que a preencheria também nunca rodou lá — as flags
    # `should_seed_*` vinham `false`.
    #
    # Logo: isto **não replica dado validado**, replica a leitura do código de
    # 2022 (`../sfg/db/seeds.rb:334-338`), e a distinção fica escrita porque é
    # ela que decide se um golden tem oráculo ou só tem fonte.
    #
    # ### As quatro linhas, verbatim da fonte
    #
    # ```ruby
    # StructuredOperationType.create(title: "Fomento",         is_default: 1, user_id: 1)
    # StructuredOperationType.create(title: "Comissária",      is_default: 1, user_id: 1)
    # StructuredOperationType.create(title: "Intercompany",    is_default: 1, user_id: 1)
    # StructuredOperationType.create(title: "Auto Liquidável", is_default: 1, user_id: 11)
    # ```
    #
    # O que a chamada não passa cai no default da coluna
    # (`20220701123654_create_structured_operation_types.rb`): `is_active = 1`,
    # `allow_manual_operations = 1`, `allow_receivable_entries = 0`,
    # `has_pre_faturamento = 0`. É de onde saem os booleanos abaixo.
    #
    # **O `user_id: 11` do quarto tipo some** (tarefa 2.1). Os três primeiros
    # dizem `1` e o último `11`, sem nada que explique a diferença — é um id de
    # usuário cravado num seed, e no ai9 o autor de um catálogo global vem da
    # sessão de quem o cria, não de um número escrito em 2022. Semear com autor
    # nulo é o que descreve a verdade: **ninguém** criou estas linhas.
    #
    # ### `is_default` em TODAS as quatro, e a consequência
    #
    # O `before_destroy` do model recusa remover tipo padrão
    # (`../sfg/app/models/structured_operation_type.rb:10-15`). Como as quatro
    # nascem `is_default`, **nenhuma é removível pela tela** — nem no legado,
    # nem aqui. Isso é replicado (BE-299/FE-300), com a mensagem dizendo por
    # quê em vez de o botão sumir sem explicação.
    #
    # ### As quatro `integration_key` são CONTRATO
    #
    # `fomento`, `comissaria`, `intercompany`, `auto_liquidavel`. São elas que
    # uma integração externa casa, e são também a chave natural deste seed.
    # Escrevê-las **explicitamente**, em vez de derivá-las do título, é o que
    # impede uma mudança futura em `GlobalCatalog.slugify` de renomear a chave
    # de uma linha já semeada (mesma leitura do DEC-85 e do DC-22). Conferido
    # título a título: a derivação do ai9 produz hoje exatamente estas quatro,
    # iguais às do legado (`I18n.transliterate(title).downcase.gsub(" ","_")`).
    #
    # ### O irmão que ele NÃO é
    #
    # `Seeds::Reference::RiskOperationTypes` semeia quatro tipos com os **mesmos
    # nomes**, e ali as flags variam por família (Comissária e Auto Liquidável
    # com `has_pre_faturamento`). Aqui **não**: o seed do legado não passa flag
    # nenhuma, e `has_pre_faturamento` em operação estruturada não gera subtipo
    # nem muda bucket — não existe subtipo de operação estruturada (Q-R15). Os
    # dois catálogos são homônimos e independentes; copiar as flags de lá para
    # cá seria inventar comportamento.
    class StructuredOperationTypes < Catalog
      ENTRIES = [
        { key: 'fomento', title: 'Fomento' },
        { key: 'comissaria', title: 'Comissária' },
        { key: 'intercompany', title: 'Intercompany' },
        { key: 'auto_liquidavel', title: 'Auto Liquidável' }
      ].freeze

      class << self
        def catalog_name = 'Tipos de operação estruturada (DB-292)'
        def model = ::StructuredOperationType

        # Pela CHAVE, não pelo título: o título é editável na tela e a chave é
        # congelada. Reencontrar por título faria o seed duplicar a linha no
        # primeiro rename — que é exatamente o caso que a idempotência precisa
        # sobreviver.
        def natural_key = %i[integration_key]

        # Tudo aqui é `create_only`: as três flags e o `is_active` são
        # editáveis na tela, e o deploy seguinte não pode desfazer a arrumação
        # de quem editou. `title` entra na lista pelo mesmo motivo — renomear
        # "Comissária" para "Comissária (SP)" é decisão do usuário, e o seed
        # reencontra a linha pela chave de qualquer jeito.
        def create_only_attributes
          %i[title is_active is_default allow_manual_operations allow_receivable_entries has_pre_faturamento]
        end

        def entries
          ENTRIES.map do |entry|
            {
              integration_key: entry[:key],
              title: entry[:title],
              is_active: true,
              is_default: true,
              # Os três abaixo saem dos DEFAULTS da migration de 2022, porque a
              # chamada do seed legado não os passa. Nenhum tem consumidor no
              # repositório inteiro (Q-R15) — são migrados como coluna e não
              # ganham leitor.
              allow_manual_operations: true,
              allow_receivable_entries: false,
              has_pre_faturamento: false
            }
          end
        end
      end
    end
  end
end
