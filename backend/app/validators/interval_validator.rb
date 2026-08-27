# frozen_string_literal: true

# Coerência de faixa mínimo/máximo — `BE-455`.
#
#     validates :min_value, interval: true
#     validates :max_value, interval: true
#     # ou, com outros nomes de coluna:
#     validates :piso, interval: { min: :piso, max: :teto }
#
# **Três defeitos do original (`sfg/app/validators/interval_validator.rb`) que
# não vêm junto — os três fazem o validador não validar:**
#
# 1. `value.to_i.to_s == value` compara `String` com `Integer`. Numa coluna
#    `integer` o valor chega como `Integer`, e `"5" == 5` é `false`: **todo
#    registro com faixa inteira era recusado** com "deve ser um número inteiro".
#    Só passava quando o valor chegava como texto.
# 2. `record.errors[field] << "..."` era a forma do Rails 5. Do Rails 6.1 em
#    diante `errors[field]` devolve um array **novo** a cada chamada — o `<<`
#    escreve num objeto descartado e **nenhum erro é registrado**. O validador
#    ficaria mudo nesta base (Rails 8).
# 3. Comparar com a outra ponta sem checar `nil`: `value <= record.max_value`
#    com `max_value` nulo levanta `ArgumentError` dentro do `valid?` — o
#    formulário devolve 500 em vez de mostrar o campo obrigatório.
#
# O legado **não tem nenhum consumidor** deste validador: nenhum model declara
# `min_value`/`max_value`. Ele é portado porque a faixa mín/máx é regra que
# volta nos limites (S5) e nos tipos de operação, e vale ter uma só — correta.
class IntervalValidator < ActiveModel::EachValidator
  DEFAULT_MIN = :min_value
  DEFAULT_MAX = :max_value

  def validate_each(record, attribute, value)
    return if value.nil? # `presence:` é outra validação; ausência não é faixa inválida.

    inteiro = coerce_integer(value)
    if inteiro.nil?
      record.errors.add(attribute, :not_an_integer, message: 'deve ser um número inteiro')
      return
    end

    min_attr = options.fetch(:min, DEFAULT_MIN)
    max_attr = options.fetch(:max, DEFAULT_MAX)
    return unless [min_attr, max_attr].include?(attribute)

    outro = attribute == min_attr ? coerce_integer(record.public_send(max_attr)) : coerce_integer(record.public_send(min_attr))
    # A outra ponta ainda não foi preenchida (ou é inválida por conta própria):
    # não há faixa para comparar, e inventar um erro aqui esconderia o real.
    return if outro.nil?

    if attribute == min_attr
      record.errors.add(attribute, :greater_than_max, message: 'não pode ser maior que o valor máximo') if inteiro > outro
      record.errors.add(attribute, :equal_to_max, message: 'não pode ser igual ao valor máximo') if inteiro == outro
    else
      record.errors.add(attribute, :less_than_min, message: 'não pode ser menor que o valor mínimo') if inteiro < outro
      record.errors.add(attribute, :equal_to_min, message: 'não pode ser igual ao valor mínimo') if inteiro == outro
    end
  end

  private

  # Aceita `Integer` e texto de inteiro; recusa `Float` com parte fracionária,
  # `"5.5"` e `"abc"`. `Integer("05")` seria interpretado como octal, por isso
  # a base explícita.
  def coerce_integer(value)
    case value
    when Integer then value
    when Float then value % 1 == 0 ? value.to_i : nil
    when BigDecimal then value.frac.zero? ? value.to_i : nil
    when String then Integer(value.strip, 10, exception: false)
    end
  end
end
