# frozen_string_literal: true

module Seeds
  module Reference
    # S6 / **OPS-153**, **DB-433**, **DB-563** — os tipos de movimentação.
    # REFERÊNCIA, e o mais importante dos três.
    #
    # **Sem estas linhas nenhuma tarifa pode ser lançada** — e, sem tarifa, o
    # borderô não tem deságio, não tem IOF e o CET sai zero. Não é vitrine: é o
    # sistema não calcular.
    #
    # ## As 18 linhas, e o que cada flag decide
    #
    # Copiadas do dump de produção, uma a uma. São elas que classificam a tarifa
    # nos quatro buckets do `Receivables::Calculator` — errar um `is_desagio`
    # aqui muda a base do IOF e os sete CETs de todo borderô daquele tipo.
    #
    # A tarefa F.7 falava em **17**; produção tem **18**: a décima oitava é
    # **"Regresso"**, criada em 25/03/2022 pelo usuário 81. Divergência
    # registrada no relatório.
    #
    # Confere com o `BE-447`: **nenhuma** das 18 tem mais de um classificador
    # ligado, e o `check_constraint` do banco garante que continue assim.
    #
    # ## `kind` deixa de ser texto pt-BR
    #
    # Em produção a coluna guarda `"Crédito"` e `"Débito"`. Aqui é `credit` /
    # `debit`, com o rótulo na apresentação — mesmo tratamento do `status`
    # (BE-445). O de-para vive em `MovementKind::LEGACY_KIND_LABELS`, um lugar
    # só, e é dele que o conversor de ETL lê.
    #
    # ## `integration_key`: duas linhas de produção fogem do padrão
    #
    # "Regresso" tem chave `Regresso` (com maiúscula, sem transliterar) porque
    # foi criada quando o `before_validation` não disparou — o usuário digitou a
    # chave. E "Despesas com  Prorrogação" tem **dois espaços** no meio, que
    # viram `despesas_com__prorrogacao` (dois sublinhados). As duas são
    # preservadas **como estão**: chave de integração que muda de forma quebra
    # consumidor externo em silêncio (mesma leitura do DEC-85).
    class MovementKinds < Catalog
      # `o` = is_operation · `t` = is_title · `a` = advalorem · `d` = deságio
      # `i` = iof · `l` = liquidação
      ENTRIES = [
        { legacy_id: 1,  title: 'Liquidação',                          key: 'liquidacao',                          kind: 'credit', o: false, t: false, l: true },
        { legacy_id: 2,  title: 'TAC',                                 key: 'tac',                                 kind: 'debit',  o: true,  t: true },
        { legacy_id: 3,  title: 'IOF',                                 key: 'iof',                                 kind: 'debit',  o: true,  t: true,  i: true },
        { legacy_id: 4,  title: 'AdValorem',                           key: 'advalorem',                           kind: 'debit',  o: true,  t: true,  a: true },
        { legacy_id: 5,  title: 'Desagio',                             key: 'desagio',                             kind: 'debit',  o: true,  t: true,  d: true },
        { legacy_id: 6,  title: 'Entrada de Titulos',                  key: 'entrada_de_titulos',                  kind: 'debit',  o: true,  t: false },
        { legacy_id: 7,  title: 'Outras Despesas',                     key: 'outras_despesas',                     kind: 'debit',  o: true,  t: true },
        { legacy_id: 8,  title: 'Liberação de Recursos',               key: 'liberacao_de_recursos',               kind: 'debit',  o: false, t: false },
        { legacy_id: 9,  title: 'Assinatura Digital',                  key: 'assinatura_digital',                  kind: 'debit',  o: true,  t: false },
        { legacy_id: 10, title: 'TED',                                 key: 'ted',                                 kind: 'debit',  o: true,  t: false },
        { legacy_id: 11, title: 'Consulta SERASA',                     key: 'consulta_serasa',                     kind: 'debit',  o: true,  t: true },
        { legacy_id: 12, title: 'Custas de Protesto',                  key: 'custas_de_protesto',                  kind: 'debit',  o: true,  t: true },
        { legacy_id: 13, title: 'Multas sobre Liquidação em Cartório', key: 'multas_sobre_liquidacao_em_cartorio', kind: 'debit',  o: true,  t: true },
        { legacy_id: 14, title: 'Outras despesas Bancárias',           key: 'outras_despesas_bancarias',           kind: 'debit',  o: true,  t: true },
        { legacy_id: 15, title: 'Outras despesas da Operação',         key: 'outras_despesas_da_operacao',         kind: 'debit',  o: true,  t: true },
        { legacy_id: 16, title: 'Despesas de Correio',                 key: 'despesas_de_correio',                 kind: 'debit',  o: true,  t: true },
        { legacy_id: 17, title: 'Despesas com  Prorrogação',           key: 'despesas_com__prorrogacao',           kind: 'debit',  o: true,  t: true },
        { legacy_id: 18, title: 'Regresso',                            key: 'Regresso',                            kind: 'debit',  o: true,  t: false }
      ].freeze

      class << self
        def catalog_name = 'Tipos de movimentação (OPS-153)'
        def model = ::MovementKind
        def natural_key = %i[legacy_id]

        # Os classificadores entram no `create_only` porque mudá-los numa linha
        # existente **reescreveria a base do IOF** de todo borderô futuro
        # daquele tipo — e o seed não pode tomar essa decisão por ninguém.
        def create_only_attributes
          %i[is_active is_operation is_title is_advalorem is_desagio is_iof is_liquidation kind title]
        end

        def entries
          ENTRIES.map do |e|
            {
              legacy_id: e[:legacy_id], title: e[:title], integration_key: e[:key], kind: e[:kind],
              is_active: true, is_operation: e[:o], is_title: e.fetch(:t, false),
              is_advalorem: e.fetch(:a, false), is_desagio: e.fetch(:d, false),
              is_iof: e.fetch(:i, false), is_liquidation: e.fetch(:l, false)
            }
          end
        end
      end
    end
  end
end
