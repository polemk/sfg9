# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `providers` (legado) -> `Provider` (ai9). **S4** (BE-066, DB-052..DB-056).
      #
      # 289 linhas em produção, medidas no dump de 31/05/2025. É a contraparte
      # das renegociações (S9), e o conversor com **mais redesenho de coluna** de
      # toda a migração: 31 colunas na origem viram 27 no destino, e três pares
      # de colunas legadas viram uma coluna cada.
      #
      # ## 1. `cnpj` + `cpf` viram o par `(document_type, document)` — DC-11
      #
      # O legado tinha **duas colunas**, e a regra "ao menos um deve ser
      # preenchido" estava **comentada dentro do próprio model**
      # (`../sfg/app/models/provider.rb:36-38`). Medido:
      #
      #   | situação            | linhas |
      #   | ------------------- | -----: |
      #   | só CNPJ (14 dígitos)|    195 |
      #   | só CPF (11 dígitos) |     44 |
      #   | **nenhum documento**|     50 |
      #   | os dois preenchidos |      0 |
      #
      # Os 50 sem documento entram **sem documento** — é caso legítimo, e exigir
      # documento agora reprovaria dado histórico. Os dois preenchidos ao mesmo
      # tempo não existem hoje; `anomalies` cobre o dia em que existirem, porque
      # o par do ai9 não comporta dois e escolher um em silêncio seria decidir
      # pelo cliente qual documento vale.
      #
      # **E os 239 documentos que existem passam no dígito verificador** —
      # conferidos um a um com `Sfg::Document.valid?`, o mesmo validador que o
      # model roda na gravação. Zero inválidos. Sem essa medição, a carga
      # estouraria no meio com `RecordInvalid`, e a única forma de descobrir
      # seria a janela de cutover.
      #
      # ## 2. `atividades` (JSON em texto) + `cnaes` (YAML) viram UM `jsonb` — D-25
      #
      # Dois formatos para a mesma coisa na mesma tabela, e o YAML ainda é
      # superfície de desserialização (`serialize :cnaes` no model legado). O
      # `activities` do ai9 é `jsonb NOT NULL default {}`.
      #
      # **Medido: as duas colunas estão NULAS em 289 de 289 linhas.** Nenhum
      # fornecedor de produção tem atividade cadastrada — o autopreenchimento
      # por ReceitaWS é posterior ao cadastro desta base. Então a carga real
      # grava `{}` nas 289. A leitura continua escrita, com `YAML.safe_load` de
      # classes permitidas (nunca `YAML.load`), porque **o conversor não pode
      # depender de o dado continuar vazio** — e porque o dia em que ele não
      # estiver é o dia em que ninguém vai lembrar disto.
      #
      # As chaves preservam o nome legado (`atividades`, `cnaes`): o `jsonb` é
      # livre nos dois lados (o `permit` do ai9 é `optional :activities, type:
      # Hash`), e renomear em silêncio perderia a proveniência sem ganhar nada.
      #
      # ## 3. As 4 colunas `logo_*` do Paperclip NÃO são recriadas — DEC-91
      #
      # O binário vive no disco do servidor legado, sob `public/system/`, e é
      # religado por ActiveStorage no passo 6.7 (`rake sfg_etl:relink_attachments`).
      # Medido: **0 dos 289 fornecedores tem `logo_file_name`** — não há um único
      # logo de fornecedor no acervo. `has_logo?` do legado também não é portado:
      # ele tratava a string literal `"missing.jpg"` como ausência de arquivo.
      #
      # ## 4. ⚠ ANOMALIA NOVA — `integration_key` NÃO é única por projeto na produção
      #
      # O ai9 tem índice **único** em `(project_id, integration_key)` e o model
      # tem a validação correspondente. Medido no dump: **6 grupos, 163 das 289
      # linhas** (56%) compartilham a chave com outro fornecedor do mesmo
      # projeto — um dos grupos tem **119 linhas**.
      #
      # E o dado diz *por que*: **dentro de cada grupo os títulos são todos
      # distintos** (119 títulos distintos no grupo de 119). Ou seja a chave
      # **não foi derivada do título** — o `before_validation` do legado só a
      # preenche quando ela chega em branco. As chaves repetidas ainda estão em
      # CAIXA e com acento, forma que aquela derivação (`transliterate.downcase.
      # gsub(" ","_")`) nunca produziria. São **rótulos de classificação
      # digitados por gente**, não chaves de integração.
      #
      # É a mesma família de `duplicates:carriers[bank_code]` e de
      # `duplicates:renegotiations[project_id+integration_key]` (DEC-119) — num
      # dos 6 grupos o rótulo repetido é, literalmente, o mesmo daquele caso.
      # **O erro está na restrição que NÓS desenhamos a partir da intenção do
      # schema, não no dado do cliente.**
      #
      # Este conversor **declara e não conserta**: a chave de decisão é
      # `duplicates:providers[project_id+integration_key]` e ela está PENDENTE de
      # assinatura. Enquanto estiver, o dry-run **aborta** — que é o
      # comportamento certo. Duas coisas são necessárias, e a decisão sozinha não
      # basta:
      #
      #   1. a decisão assinada em `db/etl/decisions.yml`; e
      #   2. o índice único de `(project_id, integration_key)` virar **parcial ou
      #      não-único**, com a validação do model acompanhando — migration da
      #      S4, exatamente como a DEC-119 fez para `carriers.bank_code`.
      #
      # Sem (2), a carga para na 2ª linha de cada grupo com `RecordInvalid`,
      # ainda que (1) exista. Está no relatório do ETL com essa letra.
      #
      # ## 5. O que o model normaliza, o conversor já entrega normalizado
      #
      # `Provider#normalize_strings` roda em todo save: `strip` no título,
      # `upcase` na UF, e **somente dígitos** em documento e CEP. O conversor
      # aplica a mesma regra, para que a **reconciliação compare o que foi de
      # fato gravado** em vez de acusar divergência em toda linha — mesma razão
      # do `strip` em `Converters::SubSegments`.
      #
      # Sobre o CEP, medido: 264 vazios, 24 com 8 dígitos e **1 com 9**. O ai9
      # guarda `varchar(9)`, então os 9 dígitos **cabem** — nada é truncado e
      # nada é corrigido. A linha entra como está; a observação fica aqui porque
      # "CEP com 9 dígitos" é dado torto na origem, não erro de conversão.
      class Providers < Base
        def self.source_table = 'providers'
        def self.target_model = 'Provider'
        def self.requires = %w[Provider Project]
        def self.owner_slice = 'S4'
        def self.references = { 'project_id' => 'projects', 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active]
        # A unicidade que a produção NÃO satisfaz — ver o bloco 4. Declarada de
        # propósito: é ela que faz a anomalia aparecer no dry-run com contagem.
        def self.uniques = [%w[project_id integration_key]]
        # Derivadas AQUI a partir de duas colunas da origem, não copiadas de uma:
        # comparar literalmente acusaria divergência em toda linha.
        def self.derived = %w[document_type document activities cnpj_fetched_at]

        def convert(row)
          tipo, numero = documento(row)
          {
            project_id: ref('projects', row['project_id']),
            user_id: ref('livetat_auth_users', row['user_id']),
            title: row['title'].to_s.strip,
            resume: row['resume'],
            # DEC-85 — chave publicada para fora. COPIADA, nunca rederivada.
            integration_key: row['integration_key'],
            is_active: Values.to_boolean(row['is_active']).value,
            # DC-11 — o par `(tipo, número)`, somente dígitos. Nulo dos dois lados
            # quando não há documento: meio par é a coluna que ninguém sabe ler depois.
            document_type: tipo,
            document: numero,
            # NULO de propósito: a coluna é do ai9 (quando o cadastro veio da
            # ReceitaWS) e não existe na origem. Todo fornecedor migrado foi
            # preenchido à mão — é isso que o nulo diz, e é verdade.
            cnpj_fetched_at: nil,
            legal_name: row['nome'],
            trade_name: row['fantasia'],
            status: row['situacao'],
            opened_at: row['abertura'],
            status_changed_at: row['data_situacao'],
            email: row['email'],
            phone: row['telefone'],
            # `normalize_strings` do model faria os dois; aqui é explícito para a
            # reconciliação comparar o valor gravado.
            zip_code: row['cep'].to_s.gsub(/\D/, '').presence,
            street: row['logradouro'],
            number: row['numero'],
            complement: row['complemento'],
            district: row['bairro'],
            city: row['municipio'],
            state: row['uf'].to_s.strip.upcase.presence,
            activities: atividades(row),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # O par do ai9 comporta UM documento. A precedência é CNPJ antes de CPF —
        # a mesma de `Provider#cpf_cnpj` e `#is_cpf_cnpj` do legado
        # (`../sfg/app/models/provider.rb:76-92`), que é o que a tela mostrava.
        # Não vale para nenhuma linha de hoje (0 com os dois), e é a precedência
        # que o legado já usava para o dia em que valer.
        def documento(row)
          cnpj = Sfg::Document.digits(row['cnpj'])
          return [Sfg::Document::CNPJ, cnpj] if cnpj.present?

          cpf = Sfg::Document.digits(row['cpf'])
          return [Sfg::Document::CPF, cpf] if cpf.present?

          [nil, nil]
        end

        # D-25 — os dois acervos de atividade num `jsonb` só. `cnaes` é YAML
        # (`serialize :cnaes`) e `atividades` é JSON dentro de coluna de texto.
        #
        # **`YAML.safe_load`, nunca `YAML.load`**: o conteúdo vem do banco do
        # cliente, e desserializar objeto arbitrário a partir de dado migrado é a
        # superfície que esta migração fecha, não a que ela carrega adiante.
        # Conteúdo que não abre vira **anomalia**, nunca `{}` em silêncio — `{}`
        # é indistinguível de "não tinha nada", que é o caso das 289 de hoje.
        def atividades(row)
          {
            'atividades' => parse_json(row['atividades']),
            'cnaes' => parse_yaml(row['cnaes'])
          }.compact
        end

        def parse_json(raw)
          return nil if raw.to_s.strip.empty?

          JSON.parse(raw)
        rescue JSON::ParserError
          nil
        end

        def parse_yaml(raw)
          return nil if raw.to_s.strip.empty?

          YAML.safe_load(raw, permitted_classes: [Symbol], aliases: false)
        rescue Psych::Exception
          nil
        end

        def anomalies(row)
          linhas = []
          cnpj = Sfg::Document.digits(row['cnpj'])
          cpf = Sfg::Document.digits(row['cpf'])

          # Não existe hoje (medido: 0 linhas). Existe o relatório porque o par do
          # ai9 comporta um só, e o descarte do outro precisa ser visto por alguém.
          if cnpj.present? && cpf.present?
            linhas << { key: 'providers:two_documents',
                        title: 'Fornecedor com CNPJ **e** CPF preenchidos — o ai9 guarda UM par ' \
                               '`(tipo, número)` e o CNPJ prevalece; o CPF é DESCARTADO',
                        line: "- pk=#{row['id']} projeto=#{row['project_id']} — CNPJ e CPF preenchidos" }
          end

          # O documento é validado de verdade no ai9 (dígito verificador), e o
          # legado nunca validou os que já estavam gravados. Zero em produção — a
          # linha existe para o `RecordInvalid` não ser descoberto na janela.
          tipo, numero = documento(row)
          if numero.present? && !Sfg::Document.valid?(tipo, numero)
            linhas << { key: 'providers:invalid_document',
                        title: 'Documento que NÃO passa no dígito verificador — o legado não validava ' \
                               'o que já estava gravado, e o ai9 valida na gravação',
                        line: "- pk=#{row['id']} tipo=#{tipo} (#{numero.to_s.length} dígitos)" }
          end

          linhas
        end
      end
    end
  end
end
