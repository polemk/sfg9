# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `contract_deals` (legado) -> `ContractDeal` (ai9). **S12** (DB-331, DEC-66, DEC-80).
      #
      # **272 linhas** em produção, medidas no dump de 31/05/2025: 136 por
      # contrato, 0 duplicata em `(user_id, contract_id)`.
      #
      # ## O que a tabela do legado guardava, e por que isso é o D-65
      #
      # `user_id`, `contract_id` e os dois timestamps. **Nada mais.** Era prova de
      # que existiu um aceite, **sem prova do que foi aceito** — e como o texto do
      # contrato continua editável, "fulano aceitou os Termos v1" não diz qual
      # texto fulano leu.
      #
      # O ai9 acrescenta sete colunas de prova (IP, user-agent, hash, texto lido,
      # tipo e versão denormalizados, origem do aceite). **Seis delas a origem
      # não tem como preencher**, e é isso que este conversor registra.
      #
      # ## DEC-66 — todo aceite existente entra `implicit_legacy`, e isso NÃO é opinião
      #
      # O passivo do legado tem **duas origens conhecidas e documentadas**:
      #
      #  * o `after_create` que gravava aceite **sem interação nenhuma**
      #    (`../sfg/app/decorators/user_decorator.rb:234-240`); e
      #  * o seed que **fabricou aceite retroativo para a base inteira**
      #    (`../sfg/db/seeds.rb:141-157`).
      #
      # A base antiga **não distingue quem aceitou de quem foi carimbado** — e
      # nada aqui pode dizer que distingue. Por isso `source = implicit_legacy`,
      # que **não satisfaz a pendência**: o novo aceite explícito é exigido na
      # próxima entrada, e é o banner que o pede. A data original é preservada em
      # `accepted_at` **e** em `legacy_accepted_at`, para que a promoção a
      # explícito não apague o histórico (o índice único `(user_id, contract_id)`
      # só admite uma linha por versão).
      #
      # ## Sem IP, sem user-agent e SEM HASH — e o vazio é informação
      #
      # `ip_address` e `user_agent` são nulos porque **não houve requisição**.
      # `content_hash` e `accepted_body` são nulos porque inventá-los faria um
      # aceite carimbado parecer prova de leitura — e é justamente a diferença
      # que a DEC-80 existe para preservar. `ContractDeal#hash_matches_current?`
      # devolve `false` para hash em branco, que é a resposta certa: **não se
      # sabe** o que essa pessoa leu.
      #
      # ## `contract_kind` e `contract_version` são DENORMALIZADOS de propósito
      #
      # "A prova não pode depender de JOIN" — se o contrato for editado ou
      # removido, o aceite continua dizendo de que tipo e de que número ele era.
      # Os dois valores vêm da **origem**, lidos de `contracts` (2 linhas), e não
      # do destino: no dry-run o destino ainda não tem nada, e um conversor que
      # só funciona depois da carga não é conversor.
      #
      # ## ⚠ ANOMALIA NOVA — 2 aceites de um usuário que NÃO EXISTE MAIS
      #
      # Medido: 2 das 272 linhas apontam para um `user_id` que não está em
      # `livetat_auth_users`. É **um** usuário (os ids vão de 1 a 136 e há 135
      # contas: falta exatamente um do meio), com um aceite de cada contrato. O
      # legado roda com `belongs_to_required_by_default = false` e **sem FK no
      # banco**, então apagar a conta deixou os aceites para trás.
      #
      # No ai9 `contract_deals.user_id` é **`null: false` com FK**. As duas linhas
      # **não têm como entrar**, e nenhuma decisão as faz entrar: não existe a
      # quem apontar. A chave é `orphans:contract_deals.user_id` e ela está
      # PENDENTE — enquanto estiver, o dry-run **aborta**, que é o comportamento
      # certo.
      #
      # Duas observações para quem for assinar:
      #
      #  * diferente de `orphans:livetat_auth_users.default_project_id` (DEC-119),
      #    que se resolveu **nulificando** porque a coluna é anulável, aqui a
      #    coluna é obrigatória. O efeito só pode ser **descartar as 2 linhas** —
      #    e descartar prova de aceite é decisão de gente, não de conversor;
      #  * o motor **não tem passo de "pular linha"**: ele grava toda linha que
      #    lê. Medido, com a chave autorizada num arquivo de ensaio: a carga anda
      #    3 linhas e para em `ActiveRecord::RecordInvalid: User é obrigatório(a)`.
      #    Autorizar o descarte exige, além da assinatura, ou a linha sair da
      #    origem, ou o motor ganhar o passo. **Está declarado, não contornado.**
      class ContractDeals < Base
        def self.source_table = 'contract_deals'
        def self.target_model = 'ContractDeal'
        def self.requires = %w[ContractDeal Contract User]
        def self.owner_slice = 'S12'
        def self.references = { 'user_id' => 'livetat_auth_users', 'contract_id' => 'contracts' }
        # No legado era `validates_uniqueness_of :contract_id, scope: [:user_id]`
        # — validação de aplicação, e "dois cliques gravavam duas linhas". No ai9
        # é índice do banco. Medido: 0 duplicata nas 272.
        def self.uniques = [%w[user_id contract_id]]
        # As seis colunas de prova que a origem não tem, mais as duas
        # denormalizadas: nenhuma se compara literalmente com uma coluna da origem.
        def self.derived = %w[source ip_address user_agent content_hash accepted_body
                              contract_kind contract_version]

        def convert(row)
          data = Values.to_utc(row['created_at']).value
          contrato = contrato_de_origem(row)
          {
            user_id: ref('livetat_auth_users', row['user_id']),
            contract_id: ref('contracts', row['contract_id']),
            # DEC-66 — o ponto inteiro deste conversor.
            source: ContractDeal::SOURCE_IMPLICIT_LEGACY,
            accepted_at: data,
            legacy_accepted_at: data,
            # Denormalizados da ORIGEM: a prova não pode depender de JOIN, e o
            # conversor não pode depender de o destino já estar carregado.
            contract_kind: contrato && Contract.kind_for(contrato['kind']),
            contract_version: contrato && contrato['version'],
            # Nulos porque não houve requisição, e porque inventar o hash faria um
            # carimbo parecer prova de leitura. O vazio é informação.
            ip_address: nil,
            user_agent: nil,
            content_hash: nil,
            accepted_body: nil,
            legacy_id: row['id'],
            created_at: data,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # Índice `id do contrato => linha`, montado UMA vez sobre 2 linhas de
        # origem. Sem ele seriam 272 leituras da mesma tabela.
        def contrato_de_origem(row)
          contratos[row['contract_id'].to_i]
        end

        def contratos
          @contratos ||= begin
            tabela = 'contracts'
            source.table?(tabela) ? source.ordered_rows(tabela).index_by { |r| r['id'].to_i } : {}
          end
        end

        # O órfão de `user_id` já é contado pelo motor (`references`), com a chave
        # `orphans:contract_deals.user_id`. O que ELE não sabe dizer é que a
        # coluna é obrigatória no destino — e essa é a metade que muda a decisão.
        # Ver o bloco da anomalia no cabeçalho.
        def anomalies(row)
          contrato = contrato_de_origem(row)
          return [] if contrato.present?

          [{ key: 'contract_deals:contract_not_in_source',
             title: 'Aceite cujo CONTRATO não está na origem — sem o tipo e o número, o aceite ' \
                    'deixa de ser prova (as duas colunas são `null: false`)',
             line: "- pk=#{row['id']} aponta para `contracts`##{row['contract_id']}" }]
        end
      end
    end
  end
end
