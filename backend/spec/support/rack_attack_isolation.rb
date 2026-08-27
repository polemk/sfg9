# frozen_string_literal: true

# Isola os contadores do `rack-attack` entre exemplos.
#
# **Achado ao executar a S1 (25/08/2026), e é um defeito de suíte, não de produto.**
#
# `Rack::Attack.cache.store` é o Redis (`config/initializers/rack_attack.rb`), e Redis
# **não participa da transação do teste**. O contador de `check_rate_limit!`
# (5 pedidos de código / 15 min por destino normalizado) sobrevive ao rollback — e
# sobrevive à execução inteira.
#
# O sintoma é o pior possível: um request spec que pede código para o mesmo endereço
# passa nas primeiras execuções e **começa a falhar a partir da sexta**, sem que
# nenhuma linha tenha mudado. Quem for investigar vai procurar no código do login, que
# está certo, porque a causa está num contador de fora do processo.
#
# Limpar antes de cada exemplo devolve o isolamento. O teto continua sendo exercitado
# de propósito por quem quiser: basta pedir seis vezes dentro do mesmo exemplo.
RSpec.configure do |config|
  config.before do
    Rack::Attack.cache.store.clear
  rescue StandardError => e
    # Redis fora do ar não pode derrubar a suíte inteira: sem contador, o
    # `check_rate_limit!` já falha aberto por decisão (ver `security_helpers.rb`).
    Rails.logger.debug { "[spec] não foi possível limpar o contador do rack-attack: #{e.class}" }
  end
end
