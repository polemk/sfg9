# frozen_string_literal: true

module Demo
  module Support
    # Vocabulário brasileiro do seed: documento, endereço e razão social.
    #
    # O detalhe que mais rende aqui é o **CNPJ de filial**: no Brasil as empresas de
    # um mesmo grupo compartilham a raiz de 8 dígitos e diferem no número da ordem
    # (`0001`, `0002`…), com o dígito verificador recalculado. Quem trabalha com
    # cadastro reconhece isso de imediato, e é de graça.
    module Br
      # Pesos do módulo 11, na ordem em que o cálculo do CNPJ os aplica.
      DV1_WEIGHTS = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze
      DV2_WEIGHTS = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze

      module_function

      # CNPJ completo (14 dígitos) a partir da raiz de 8 e do número de ordem.
      def cnpj(root, branch = 1)
        base = format('%08d%04d', root.to_i, branch.to_i)
        digits = base.chars.map(&:to_i)
        dv1 = check_digit(digits, DV1_WEIGHTS)
        dv2 = check_digit(digits + [dv1], DV2_WEIGHTS)
        "#{base}#{dv1}#{dv2}"
      end

      def format_cnpj(value)
        d = value.to_s.rjust(14, '0')
        "#{d[0, 2]}.#{d[2, 3]}.#{d[5, 3]}/#{d[8, 4]}-#{d[12, 2]}"
      end

      # Validação pelo mesmo cálculo — usada pela spec de plausibilidade. Um CNPJ
      # que não fecha o DV é o tipo de coisa que a tela de cadastro rejeita na
      # frente do cliente.
      def valid_cnpj?(value)
        d = value.to_s.gsub(/\D/, '')
        return false unless d.length == 14
        return false if d.chars.uniq.length == 1

        digits = d.chars.map(&:to_i)
        check_digit(digits[0, 12], DV1_WEIGHTS) == digits[12] &&
          check_digit(digits[0, 13], DV2_WEIGHTS) == digits[13]
      end

      def check_digit(digits, weights)
        sum = digits.each_with_index.sum { |digit, i| digit * weights[i] }
        rest = sum % 11
        rest < 2 ? 0 : 11 - rest
      end

      # Sufixos de razão social de empresa do grupo. A ordem importa: a primeira
      # empresa de um grupo é a operacional, as seguintes são as periféricas.
      COMPANY_SUFFIXES = [
        'Indústria e Comércio Ltda',
        'Participações S.A.',
        'Logística e Transportes Ltda',
        'Comercial Ltda',
        'Filial Nordeste Ltda',
        'Serviços e Manutenção Ltda'
      ].freeze

      # Nomes de pessoa para responsável de projeto e para o elenco de usuários.
      PEOPLE = [
        'Ricardo Almeida', 'Patrícia Camargo', 'Eduardo Bittencourt', 'Juliana Rezende',
        'Marcelo Tavares', 'Cristina Vasconcelos', 'André Sampaio', 'Renata Queiroz',
        'Fernando Bastos', 'Luciana Prado', 'Otávio Mendonça', 'Beatriz Nogueira'
      ].freeze
    end
  end
end
