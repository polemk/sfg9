# frozen_string_literal: true

module Legacy
  # S0 / DB-006 (parte ETL), F.2 — o de-para de papel do legado `sfg` para o ai9.
  #
  # **É TABELA, NUNCA FÓRMULA.** Não existe aritmética convertendo 1111/998/888/799
  # em 1/2/3/4 em lugar nenhum deste repositório, e não deve passar a existir: uma
  # fórmula sobrevive a um valor inesperado e produz um nível **plausível e
  # errado**. A tabela **falha alto** — que é o comportamento desejado.
  #
  #   | legado (`hierarchy`) | papel        | ai9 (`hierarchy_level`) |
  #   |                 1111 | OG           | 1                       |
  #   |                  998 | Admin        | 2                       |
  #   |                  888 | Gerente      | 3                       |
  #   |                  799 | Colaborador  | 4                       |
  #   |     `""` / nil (D-36)| —            | 4 + LISTA DE EXCEÇÕES   |
  #
  # O papel vazio é o **D-36**: `config/application.rb:65` do legado define
  # `default_role_type = ""`, então há usuários cujo papel não casa com
  # og?/admin?/manager?/colab?. DEC-18.8: entram como Colaborador **e saem numa
  # lista de exceções para revisão humana antes do cutover** — nem promovidos nem
  # bloqueados em silêncio.
  #
  # Consumidor: o ETL da fatia S14.
  module RoleMap
    class UnknownLegacyRole < StandardError; end

    # Chave: `hierarchy` do `Livetat::Auth::RoleType` do legado.
    BY_HIERARCHY = {
      1111 => UserType::OG,
      998 => UserType::ADMIN,
      888 => UserType::GERENTE,
      799 => UserType::COLABORADOR
    }.freeze

    # Chave: `name` literal do RoleType (`user_decorator.rb:24-30` do legado).
    BY_NAME = {
      'OG' => UserType::OG,
      'Admin' => UserType::ADMIN,
      'Gerente' => UserType::GERENTE,
      'Colaborador' => UserType::COLABORADOR
    }.freeze

    # Papel vazio/nulo do D-36. Vai para Colaborador **e** para a lista de exceções.
    EMPTY_ROLE_FALLBACK = UserType::COLABORADOR

    module_function

    # Devolve `[nome_do_papel_ai9, excecao?]`.
    #
    # `excecao?` verdadeiro significa "carregue, mas ponha na lista de revisão
    # humana". Um `hierarchy` DESCONHECIDO não é exceção: é erro, e levanta.
    def resolve(hierarchy: nil, name: nil)
      return [EMPTY_ROLE_FALLBACK, true] if blank_role?(hierarchy, name)

      mapped = BY_HIERARCHY[normalize_hierarchy(hierarchy)] || BY_NAME[name.to_s.strip]
      return [mapped, false] if mapped

      raise UnknownLegacyRole,
            "papel do legado desconhecido (hierarchy=#{hierarchy.inspect}, name=#{name.inspect}). " \
            'O de-para é tabela explícita: acrescente a linha em Legacy::RoleMap em vez de inferir o nível.'
    end

    # Conveniência para o ETL: já devolve o `UserType` do ai9.
    def user_type_for(hierarchy: nil, name: nil)
      role, exception = resolve(hierarchy: hierarchy, name: name)
      [UserType.find_by!(name: role), exception]
    end

    # O D-36 chega das duas formas: coluna nula e string vazia.
    def blank_role?(hierarchy, name)
      hierarchy.to_s.strip.empty? && name.to_s.strip.empty?
    end

    def normalize_hierarchy(hierarchy)
      return nil if hierarchy.nil?
      return nil unless hierarchy.to_s.strip.match?(/\A-?\d+\z/)

      hierarchy.to_i
    end
  end
end
