# frozen_string_literal: true

module Sfg
  # **O único lugar onde CPF e CNPJ são validados** — S4 / BE-066, DB-053.
  #
  # Existe porque o Safegold pede documento em três telas (fornecedor, empresa,
  # conta) e o legado resolvia cada uma de um jeito: o `Provider` chamava a gem
  # `cpf_cnpj`, o cadastro de usuário validava só o formato e a consulta de CNPJ
  # não validava nada — cada CNPJ malformado virava uma **consulta paga
  # desperdiçada** na ReceitaWS.
  #
  # Três decisões:
  #
  # 1. **A gem não é portada.** O algoritmo do dígito verificador é público,
  #    cabe em dez linhas e não muda desde 1990. Uma dependência a mais para
  #    isso é superfície sem contrapartida.
  # 2. **Só dígitos entram no banco.** A máscara é da tela. Guardar
  #    `12.345.678/0001-95` e `12345678000195` na mesma coluna é como o legado
  #    conseguiu ter o mesmo fornecedor duas vezes apesar da unicidade.
  # 3. **Documento com todos os dígitos iguais é inválido.** `111.111.111-11`
  #    passa na conta do dígito verificador e não é documento de ninguém.
  module Document
    CPF = 'CPF'
    CNPJ = 'CNPJ'
    TYPES = [CPF, CNPJ].freeze

    LENGTHS = { CPF => 11, CNPJ => 14 }.freeze

    module_function

    # Só os dígitos. `nil` e string vazia devolvem `nil`, nunca `""` — a coluna
    # é opcional (DC-11) e ausência tem de ser ausência, não string vazia.
    def digits(value)
      value.to_s.gsub(/\D/, '').presence
    end

    def valid?(type, value)
      case type.to_s.upcase
      when CPF then valid_cpf?(value)
      when CNPJ then valid_cnpj?(value)
      else false
      end
    end

    def valid_cpf?(value)
      only = digits(value).to_s
      return false unless only.length == 11
      return false if only.chars.uniq.size == 1

      [9, 10].all? { |position| only[position].to_i == cpf_check_digit(only, position) }
    end

    def valid_cnpj?(value)
      only = digits(value).to_s
      return false unless only.length == 14
      return false if only.chars.uniq.size == 1

      [12, 13].all? { |position| only[position].to_i == cnpj_check_digit(only, position) }
    end

    # Pesos 10..2 (primeiro dígito) e 11..2 (segundo).
    def cpf_check_digit(only, position)
      weights = (2..(position + 1)).to_a.reverse
      sum = only[0, position].chars.each_with_index.sum { |d, i| d.to_i * weights[i] }
      remainder = (sum * 10) % 11
      remainder == 10 ? 0 : remainder
    end

    # Pesos cíclicos 2..9, lidos da direita para a esquerda.
    def cnpj_check_digit(only, position)
      weights = (2..9).cycle.first(position).reverse
      sum = only[0, position].chars.each_with_index.sum { |d, i| d.to_i * weights[i] }
      remainder = sum % 11
      remainder < 2 ? 0 : 11 - remainder
    end

    # Máscara para exibição. **Não** é o que vai para o banco.
    def mask(type, value)
      only = digits(value)
      return nil if only.blank?

      case type.to_s.upcase
      when CPF
        only.length == 11 ? only.gsub(/(\d{3})(\d{3})(\d{3})(\d{2})/, '\1.\2.\3-\4') : only
      when CNPJ
        only.length == 14 ? only.gsub(%r{(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})}, '\1.\2.\3/\4-\5') : only
      else
        only
      end
    end
  end
end
