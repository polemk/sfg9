# frozen_string_literal: true

module Sfg
  # A frase em pt-BR de um evento da trilha — o `resume` do legado, **derivado**.
  #
  # No legado (`tracking.rb:12`) o resumo era coluna `string` com
  # `length: { maximum: 300 }`, e os 20 emissores do `TrackingFacade` faziam
  # `t.save` sem olhar o retorno. Resumo maior que 300 → `save` devolve `false`
  # → **o evento não existe**. E o evento que sumia era sempre o do caso
  # complicado, porque era o que tinha muito o que descrever (o de falha, que
  # concatena a mensagem da exceção: `t.resume << " falhou com o erro: #{e}"`).
  #
  # Aqui a frase é **calculada na leitura** a partir de `item_type` + `event`,
  # com o rótulo e o gênero vindos do catálogo `pt-BR`. Não existe coluna para
  # estourar, então o defeito não tem onde acontecer — não é "truncamento
  # explícito", é a classe inteira do defeito removida por construção.
  #
  # A concordância de gênero (`FE-432`, o `gender_prefix`) é o par
  # `artigo`/`genero` do catálogo, não um `if` em Ruby.
  module AuditSummary
    module_function

    # `"A permissão do usuário foi criada"`.
    #
    # Tipo sem verbete no catálogo cai num rótulo neutro em vez de levantar: a
    # trilha é o lugar onde **nunca** se troca informação por exceção. O spec da
    # trilha reprova o verbete faltando; em produção o evento aparece assim
    # mesmo, e ninguém perde o registro por causa de uma chave de tradução.
    def call(item_type:, event:)
      verbete = entry_for(item_type)
      genero = verbete[:genero]

      I18n.t(
        'audit_trail.resumo',
        artigo: I18n.t("audit_trail.artigos.#{genero}", default: 'O'),
        entidade: verbete[:rotulo],
        acao: I18n.t("audit_trail.acoes.#{event}.#{genero}", default: I18n.t("audit_trail.acoes.update.#{genero}"))
      )
    end

    # Rótulo e gênero de um `item_type`. Público porque a listagem também usa o
    # rótulo sozinho (cabeçalho de filtro), e ele não pode divergir da frase.
    def entry_for(item_type)
      dados = I18n.t("audit_trail.entidades.#{item_type}", default: nil)
      return { rotulo: dados[:rotulo], genero: dados[:genero].to_s } if dados.is_a?(Hash)

      { rotulo: item_type.to_s.underscore.humanize.downcase, genero: 'm' }
    end

    def label_for(item_type)
      entry_for(item_type)[:rotulo]
    end

    # Todos os tipos com verbete — alimenta o filtro por tipo da tela, para que
    # ela não precise conhecer a lista de models.
    def known_types
      (I18n.t('audit_trail.entidades', default: {}) || {}).keys.map(&:to_s)
    end
  end
end
