# frozen_string_literal: true

# Normaliza números de telefone brasileiros para uma forma canônica única,
# usada em toda comparação de telefone (ex.: autorização do admin via WhatsApp).
#
# Forma canônica: apenas dígitos, com DDI 55 — ex. "5548988051484".
# (Sem '+', sem máscara.) Esse é o formato que tanto o webhook da Evolution
# (`remoteJid`) quanto o `users.phone` já usam, então a comparação bate direto.
#
# Regras (Brasil):
# - Remove sufixo de JID (`@s.whatsapp.net`) e tudo que não for dígito.
# - Já com DDI: começa com "55" e tem 12 (fixo) ou 13 (móvel) dígitos → mantém.
# - Sem DDI: 10 (DDD+fixo) ou 11 (DDD+móvel) dígitos → prefixa "55".
# - Qualquer outro tamanho → nil (não reconhecido).
#
# NÃO infere o 9º dígito (evita falso match): só compara igualdade após normalizar.
module PhoneNormalizer
  module_function

  # @param raw [String, nil] número em qualquer formato
  # @return [String, nil] dígitos com DDI 55, ou nil se inválido
  def normalize(raw)
    return nil if raw.nil?

    digits = raw.to_s.split('@').first.to_s.gsub(/\D/, '')
    return nil if digits.empty?

    if digits.start_with?('55') && [12, 13].include?(digits.length)
      digits
    elsif [10, 11].include?(digits.length)
      "55#{digits}"
    end
  end
end
