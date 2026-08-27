# frozen_string_literal: true

module Seeds
  module Reference
    # S12 / OPS-330, OPS-332 — **publica a versão 1 de cada tipo de contrato e
    # NÃO gera nenhum aceite**.
    #
    # É o oposto exato do seed do legado. Lá (`db/seeds.rb:141-157`) o seed
    # **re-salvava todos os usuários** — o que, com o `version_guess` rodando em
    # todo `save`, mexia na numeração — e **fabricava um `ContractDeal`
    # retroativo para cada usuário sem aceite**. O resultado é a base que a
    # DEC-66 descreve: não dá para distinguir quem aceitou de quem foi carimbado.
    #
    # Aqui: zero aceites. Quem aceita é a pessoa, pelo botão (DEC-65).
    #
    # **Idempotente**: rodar duas vezes não publica versão 2 dos mesmos textos.
    # A segunda execução só preenche o que faltar — publicar uma versão nova é
    # ato humano, com botão e confirmação (FE-342), nunca efeito de rodar seed.
    module Contracts
      # Os documentos de origem, herdados do legado (`db/seed_assets/contracts/`).
      SOURCES = {
        ::Contract::KIND_TERMS_OF_USE => 'tou.html',
        ::Contract::KIND_PRIVACY_POLICY => 'privacy.html'
      }.freeze

      # OPS-332 — `db/seed_assets/contracts/user.html` existe desde o legado,
      # **nenhum seed o carrega** e o tipo dele não consta do catálogo. Possível
      # "contrato de adesão" planejado e nunca ativado (Q-B35). Fica registrado
      # aqui, na lista de ignorados, em vez de sumir por omissão.
      IGNORED_SOURCES = %w[user.html].freeze

      # OPS-477 — a decisão que a fronteira do `proposal.md` pediu que saísse
      # daqui: **esta fatia SEMEIA a partir de arquivo**, então o leitor com
      # limite de tamanho é desta fatia, e a S13 não o constrói.
      MAX_SOURCE_BYTES = 512 * 1024

      module_function

      def assets_dir
        Rails.root.join('db', 'seed_assets', 'contracts')
      end

      def call!(io: nil, actor: nil)
        autor = actor || default_actor
        criados = 0
        inalterados = 0

        SOURCES.each do |kind, arquivo|
          if ::Contract.of_kind(kind).exists?
            # Idempotência com um significado específico aqui: **não republicar**.
            # Nos outros catálogos a segunda execução atualiza a linha; nesta,
            # atualizar seria publicar a versão 2 dos mesmos Termos e deixar
            # todo mundo com aceite pendente. Publicar é ato humano (FE-342).
            inalterados += 1
            next
          end

          corpo = read_source(arquivo)
          next if corpo.blank?

          contrato = ::Contract.new(kind: kind, title: kind, creator: autor)
          contrato.description = corpo
          contrato.save!
          criados += 1
        end

        log_ignored
        report = Report.new(catalog: 'Contratos (versão 1, ZERO aceites)',
                            created: criados, unchanged: inalterados)
        io&.puts("   #{report}")
        report
      end

      # Quem consta como autor da versão 1. O primeiro OG, se houver — e `nil`
      # se não houver nenhum, porque `creator_id` é anulável de propósito: um
      # banco recém-criado não pode ficar sem os Termos por falta de autor.
      def default_actor
        ::User.joins(:user_type).find_by(user_types: { name: ::UserType::OG })
      end

      # As versões publicadas — para quem chama de dentro do app (o spec, o ETL).
      def published
        SOURCES.keys.filter_map { |kind| ::Contract.of_kind(kind).order(:version).first }
      end

      # OPS-477 — leitor com **limite de tamanho**. Um HTML de origem trocado por
      # engano (ou um arquivo de dump com o mesmo nome) não pode virar um
      # documento de 40 MB dentro de `action_text_rich_texts`.
      def read_source(nome)
        caminho = assets_dir.join(nome)
        unless File.exist?(caminho)
          Rails.logger.warn("[seed:contracts] documento de origem ausente: #{caminho}")
          return nil
        end

        tamanho = File.size(caminho)
        if tamanho > MAX_SOURCE_BYTES
          Rails.logger.error(
            "[seed:contracts] #{nome} tem #{tamanho} bytes (teto #{MAX_SOURCE_BYTES}) — ignorado."
          )
          return nil
        end

        texto = File.read(caminho).to_s.strip
        return nil if texto.blank?

        # O arquivo do legado é texto com quebras de linha, não HTML estruturado.
        # Converter aqui é o que faz a versão 1 abrir legível no editor em vez de
        # virar um parágrafo único de 5 KB.
        texto.include?('<') ? texto : simple_html(texto)
      end

      # Os arquivos do legado são texto puro com quebra de linha por largura de
      # coluna — não por sentido. Trocar TODA quebra por `<br>` produziria um
      # documento com linhas raspadas no meio da frase, que é pior que o texto
      # corrido. Parágrafo é bloco separado por linha em branco; dentro dele, a
      # quebra vira espaço.
      def simple_html(texto)
        texto.split(/\n[[:space:]]*\n/)
             .map { |bloco| bloco.gsub(/\s+/, ' ').strip }
             .reject(&:blank?)
             .map { |bloco| "<p>#{ERB::Util.html_escape(bloco)}</p>" }
             .join
      end

      def log_ignored
        IGNORED_SOURCES.each do |nome|
          caminho = assets_dir.join(nome)
          next unless File.exist?(caminho)

          Rails.logger.info(
            "[seed:contracts] #{nome} IGNORADO (OPS-332): existe desde o legado, nenhum seed o carrega " \
            'e o tipo não consta do catálogo fechado. Registrado, não carregado.'
          )
        end
      end
    end
  end
end
