# frozen_string_literal: true

module Seeds
  module Reference
    # S3 / **OPS-540** — a base de um catálogo de referência.
    #
    # **O que é "dado de referência", e o que NÃO é.** Referência é o dado sem o
    # qual o sistema não funciona no primeiro boot: os papéis, o catálogo de
    # permissões, os tipos de garantia (sem eles o select de garantia do projeto
    # sobe vazio — é literalmente o defeito do legado, DEC-86). **Não** é dado de
    # vitrine: portadores, empresas, borderôs e a série temporal são do **seed de
    # demonstração**, que é a fatia S20 e mora em `db/seeds/demo/`.
    #
    # As duas coisas ficam separadas porque no legado elas estavam misturadas, a
    # ponto de o bloco de empresas estar marcado **no próprio código** como
    # "seed feito somente para vídeo de aprovação" — e aquilo rodava em qualquer
    # ambiente.
    #
    # **A regra de idempotência é uma só, e é esta:** grava por **chave
    # natural** com `find_or_initialize_by`, nunca `create`; e — importante —
    # **não sobrescreve alteração feita pelo usuário**. Um campo que o usuário
    # pode editar na tela (`is_active`, `sort_order`, `description`) só é escrito
    # quando a linha **nasce**. Senão o deploy seguinte desfaria, em silêncio, a
    # arrumação que alguém fez no catálogo.
    #
    # ### Como a sua fatia (S5, S6, S8, S17) pluga o catálogo dela
    #
    # 1. crie `app/services/seeds/reference/<seu_catalogo>.rb` herdando desta
    #    classe e implementando `entries` (a lista) e `natural_key`;
    # 2. acrescente uma linha em {Seeds::Reference::Runner::CATALOGS}, com
    #    `requires` (o model) e a fatia dona.
    #
    # É só isso. Não crie um segundo mecanismo de seed — o motivo de este
    # arcabouço existir é que, sem ele, cada fatia inventaria o seu e o deploy
    # passaria a ter cinco formas de semear.
    class Catalog
      class << self
        # Nome legível, para o relatório.
        def catalog_name
          name.demodulize.underscore.humanize
        end

        # Model destino.
        def model
          raise NotImplementedError, "#{name} precisa declarar `model`"
        end

        # Linhas do catálogo: array de hashes de atributos.
        def entries
          raise NotImplementedError, "#{name} precisa declarar `entries`"
        end

        # Chaves que identificam a linha (a chave NATURAL). É por elas que a
        # segunda execução reencontra o registro em vez de duplicá-lo.
        def natural_key
          %i[title]
        end

        # Atributos que o seed só escreve quando a linha NASCE. Ver o cabeçalho:
        # é o que impede o deploy de desfazer a arrumação do usuário.
        def create_only_attributes
          %i[is_active sort_order description observation is_provisional]
        end

        def call!(io: nil)
          created = updated = unchanged = 0

          ActiveRecord::Base.transaction do
            entries.each do |attributes|
              chave = attributes.slice(*natural_key)
              record = model.find_or_initialize_by(**chave)
              nasceu = record.new_record?

              attributes.each do |field, value|
                next if !nasceu && create_only_attributes.include?(field)

                record.public_send(:"#{field}=", value)
              end

              if nasceu
                record.save!
                created += 1
              elsif record.changed?
                record.save!
                updated += 1
              else
                unchanged += 1
              end
            end
          end

          report = Report.new(catalog: catalog_name, created: created, updated: updated, unchanged: unchanged)
          io&.puts("   #{report}")
          report
        end
      end
    end
  end
end
