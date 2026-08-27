# frozen_string_literal: true

module Seeds
  module Reference
    # S5 / **OPS-230, DB-574** — os quatro tipos de limite. Dado de REFERÊNCIA.
    #
    # **Por que é referência e não demonstração:** sem nenhuma linha aqui,
    # `RiskControl` não pode ser criado (o tipo é obrigatório), o motor de
    # pré-faturamento não tem tipo com `has_pre_faturamento` e o console de risco
    # sobe sem um único cabeçalho. Não é falta de vitrine — é o sistema não
    # funcionar no primeiro boot.
    #
    # ### As flags saem do seed de produção do legado, verbatim
    #
    # `../sfg/db/seeds.rb:316-319`:
    #
    # ```ruby
    # RiskOperationType.create(title: "Fomento",        is_default: 1, allow_receivable_entries: 0)
    # RiskOperationType.create(title: "Comissária",     is_default: 1, allow_manual_operations: 0, has_pre_faturamento: 1)
    # RiskOperationType.create(title: "Intercompany",   is_default: 1, allow_manual_operations: 0)
    # RiskOperationType.create(title: "Auto Liquidável",is_default: 1, allow_manual_operations: 0, has_pre_faturamento: 1)
    # ```
    #
    # O que não aparece na chamada fica no default da coluna (`1` → `true`).
    #
    # ### ⚠ O que é validado aqui, e o que é rascunho de 2022
    #
    # Medido no dump (`.migration-ai9/analise-dump-producao.md` §1 e §2): a
    # tabela `risk_operation_types` **não existe em produção** — a migration que
    # a cria nunca subiu. Logo este seed **não replica dado validado**; ele
    # implementa o `db/seeds.rb` de 2022, que também nunca rodou lá.
    #
    # O que **é** dado de produção, e por isso não se discute:
    #
    # - **as quatro famílias existem e têm valor**. Elas são as colunas de
    #   `risk_controls`, que rodou três anos com 600 registros. Distribuição dos
    #   valores não-zero: auto-liquidáveis **457**, comissária **151**, fomento
    #   **131**, intercompany **28**.
    #
    # O que é **leitura do código de 2022**, e está declarado como tal:
    #
    # - as flags `allow_manual_operations`, `allow_receivable_entries` e
    #   `has_pre_faturamento` de cada família. Nenhum usuário jamais operou com
    #   elas, e não há registro real que as confirme.
    #
    # ### As quatro chaves de integração são CONTRATO
    #
    # `fomento`, `comissaria`, `intercompany` e `auto_liquidavel`. São elas que o
    # ETL (S14) usa para casar as linhas do legado, e a derivação do ai9
    # (`GlobalCatalog.slugify`) produz exatamente as mesmas quatro que a do
    # legado (`I18n.transliterate(title).downcase.gsub(" ","_")`) — conferido
    # título a título. Escrevê-las explicitamente aqui, em vez de derivá-las,
    # é o que impede uma mudança futura na função de slug de renomear a chave
    # de um registro migrado.
    #
    # ### DEC-67 — o subtipo padrão
    #
    # Os subtipos nascem do `after_create` do próprio tipo, e é lá que
    # `is_default_for_type` é marcado — reproduzindo o que o `.first` sem `order`
    # do legado escolhia (o "pré", que é criado primeiro). Este seed não precisa
    # tocar em subtipo nenhum; ele só não pode duplicar tipo, senão duplicaria os
    # subtipos junto. É o que a chave natural garante.
    class RiskOperationTypes < Catalog
      ENTRIES = [
        { key: 'fomento', title: 'Fomento',
          allow_manual_operations: true,  allow_receivable_entries: false, has_pre_faturamento: false },
        { key: 'comissaria', title: 'Comissária',
          allow_manual_operations: false, allow_receivable_entries: true,  has_pre_faturamento: true },
        { key: 'intercompany', title: 'Intercompany',
          allow_manual_operations: false, allow_receivable_entries: true,  has_pre_faturamento: false },
        { key: 'auto_liquidavel', title: 'Auto Liquidável',
          allow_manual_operations: false, allow_receivable_entries: true,  has_pre_faturamento: true }
      ].freeze

      class << self
        def catalog_name = 'Tipos de limite de risco (OPS-230)'
        def model = ::RiskOperationType

        # Pela CHAVE, não pelo título: o título é editável na tela e a chave é
        # congelada (DC-22). Reencontrar por título faria o seed duplicar a linha
        # no primeiro rename.
        def natural_key = %i[integration_key]

        # `has_pre_faturamento` entra aqui porque é **imutável depois do create**
        # e porque mudá-la numa linha existente trocaria o bucket de limite de
        # toda operação daquele tipo. As demais são editáveis na tela e o seed
        # não desfaz a arrumação do usuário.
        def create_only_attributes
          %i[is_active is_default has_pre_faturamento allow_manual_operations allow_receivable_entries title]
        end

        def entries
          ENTRIES.map do |entry|
            {
              integration_key: entry[:key],
              title: entry[:title],
              is_active: true,
              is_default: true,
              allow_manual_operations: entry[:allow_manual_operations],
              allow_receivable_entries: entry[:allow_receivable_entries],
              has_pre_faturamento: entry[:has_pre_faturamento]
            }
          end
        end
      end
    end
  end
end
