# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `renegotiation_attachments` (legado) -> `RenegotiationAttachment`. **S9 / DB-193.**
      #
      # ⚠ **O REGISTRO migra aqui; o BINÁRIO não.** Os arquivos vivem em
      # `public/system/…` **no disco do servidor legado**, e a cópia é
      # **pré-requisito bloqueante de cutover** (DEC-84) que o usuário ainda não
      # forneceu. O passo do binário é `Sfg::Etl::Attachments`, e ele roda em modo
      # relatório enquanto a cópia não chegar.
      #
      # **Por que isso não é "resolver depois":** anexo de renegociação é documento
      # financeiro. Registro apontando para arquivo inexistente é **pior que
      # ausência declarada** — quem abre a renegociação vê um anexo listado e um
      # download que falha, e conclui que o sistema novo perdeu o documento.
      #
      # Por isso este conversor **existe mas fica desligado por padrão**: carregar
      # os registros antes dos arquivos produz exatamente esse estado. `LOAD_ROWS`
      # é a chave explícita para quem quiser as linhas antes (por exemplo, para
      # medir o acervo). Ver o passo 9.6 do runbook.
      #
      # **As 4 colunas do Paperclip não são recriadas** (`file_file_name`,
      # `file_content_type`, `file_file_size`, `file_updated_at`): o nome original
      # vira o `filename` do blob quando o binário for reanexado, e `title` é o
      # nome exibido — que o usuário edita (DEC-53).
      class RenegotiationAttachments < Base
        LOAD_ROWS_ENV = 'ETL_LOAD_RENEGOTIATION_ATTACHMENT_ROWS'

        def self.source_table = 'renegotiation_attachments'
        def self.target_model = 'RenegotiationAttachment'
        def self.requires = %w[RenegotiationAttachment Renegotiation]
        def self.owner_slice = 'S9'

        def self.references = {
          'renegotiation_id' => 'renegotiations',
          'user_id' => 'livetat_auth_users'
        }

        def self.uniques = []
        def self.sums = []

        def self.load_rows? = ENV[LOAD_ROWS_ENV].to_s == '1'

        def convert(row)
          renegotiation_id = ref('renegotiations', row['renegotiation_id'])

          {
            renegotiation_id: renegotiation_id,
            project_id: renegotiation_id && ::Renegotiation.where(id: renegotiation_id).pick(:project_id),
            user_id: ref('livetat_auth_users', row['user_id']),
            # O legado derivava o título do nome do arquivo quando ele vinha em
            # branco (`default_file_name`). Mesma regra, aplicada na carga.
            title: row['title'].presence || nome_sem_extensao(row['file_file_name']) || 'Anexo',
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # Reconcilia `renegotiations.attachments_count` com os anexos que de fato
        # existem no destino.
        #
        # Depende do conjunto inteiro, e por isso é pós-carga: dentro do lote não
        # se sabe quantos anexos aquela renegociação ainda vai receber.
        #
        # Existe por causa de um defeito real: o conversor de `renegotiations`
        # COPIAVA `attachments_count` da origem e o `counter_cache` do
        # `belongs_to` somava por cima, dobrando o contador em 35 das 169
        # renegociações (88 contra 44 anexos reais). A cópia saiu; isto aqui
        # conserta o que carga anterior já tiver gravado errado — e vale também
        # para renegociação que perdeu anexo por decisão, cujo contador tem de
        # cair junto.
        #
        # `update_all` numa consulta só, e não `reset_counters` em laço: são 169
        # linhas hoje, mas o laço faria uma consulta por renegociação e o método
        # roda em toda execução. Idempotente por construção — reexecutar grava o
        # mesmo número.
        def self.post_load!
          return { corrigidas: 0 } unless model_ready?('Renegotiation') && model_ready?('RenegotiationAttachment')

          corrigidas = ::Renegotiation.connection.update(<<~SQL.squish)
            UPDATE renegotiations r
               SET attachments_count = c.total
              FROM (SELECT r2.id, count(a.id) AS total
                      FROM renegotiations r2
                 LEFT JOIN renegotiation_attachments a ON a.renegotiation_id = r2.id
                  GROUP BY r2.id) c
             WHERE c.id = r.id
               AND r.attachments_count IS DISTINCT FROM c.total
          SQL

          { corrigidas: corrigidas,
            note: if corrigidas.zero?
                    'contador ja batia com os anexos carregados — nada a corrigir'
                  else
                    "#{corrigidas} renegociacao(oes) com `attachments_count` fora dos anexos reais, " \
                      'reconciliado contra o destino'
                  end }
        end

        def anomalies(row)
          achados = ["attachment ##{row['id']}: BINÁRIO NÃO MIGRA nesta etapa (DEC-84) — " \
                     "arquivo de origem `#{row['file_file_name']}`"]
          achados << "attachment ##{row['id']}: sem nome de arquivo na origem" if row['file_file_name'].blank?
          unless self.class.load_rows?
            achados << "attachment ##{row['id']}: linha NÃO carregada — defina " \
                       "#{LOAD_ROWS_ENV}=1 para carregar registro sem binário"
          end
          achados
        end

        private

        def nome_sem_extensao(nome)
          return nil if nome.blank?

          partes = nome.to_s.split('.')
          partes.size > 1 ? partes[0...-1].join('.') : nome.to_s
        end
      end
    end
  end
end
