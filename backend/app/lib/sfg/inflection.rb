# frozen_string_literal: true

module Sfg
  # Plural em pt-BR — `FE-438`, o `pluralize_for` do legado.
  #
  # O legado fazia `return string + "s"` (`application_helper.rb:68-71`). Isso
  # acerta em "projeto" e erra em tudo que este produto mais escreve:
  # "permissãos", "renegociaçãos", "recebívels", "papels". O helper **não tinha
  # nenhum consumidor** no legado — foi escrito e nunca usado — então não há
  # comportamento de produção a preservar, só a intenção.
  #
  # Aqui o plural é **dado antes de ser regra**: o que estiver em
  # `pt-BR.audit_trail.plurais` vence; o resto cai nas três regras que cobrem o
  # português regular. Palavra nova irregular entra no catálogo, não em `if`.
  module Inflection
    module_function

    # `pluralize(2, 'permissão')` → `"2 permissões"`.
    # `pluralize(1, 'permissão')` → `"1 permissão"`.
    #
    # `com_numero: false` devolve só a palavra flexionada.
    def pluralize(count, word, com_numero: true)
      flexionada = count.abs == 1 ? word : plural(word)
      com_numero ? "#{count} #{flexionada}" : flexionada
    end

    def plural(word)
      texto = word.to_s
      return texto if texto.empty?

      excecao = I18n.t("audit_trail.plurais.#{texto}", default: nil)
      return excecao if excecao.present?

      regular(texto)
    end

    # As três regras que cobrem o português regular sem exceção declarada.
    # Não pretendem ser completas — o catálogo é que é a fonte da verdade.
    def regular(texto)
      case texto
      # `-ão` é ambíguo em português ("mão"→"mãos", "pão"→"pães",
      # "canção"→"canções"). Sem forma declarada não há como acertar: a mais
      # comum é `-ões`, e a exceção vai para o catálogo.
      when /ão\z/ then texto.sub(/ão\z/, 'ões')
      # `-l` → `-is` ("papel"→"papéis" é irregular e está no catálogo;
      # "hotel"→"hotéis" idem; "funil"→"funis" cai aqui).
      when /il\z/ then texto.sub(/il\z/, 'is')
      when /(a|e|o|u)l\z/ then texto.sub(/l\z/, 'is')
      when /(r|z|s)\z/ then "#{texto}es"
      when /m\z/ then texto.sub(/m\z/, 'ns')
      else "#{texto}s"
      end
    end
  end
end
