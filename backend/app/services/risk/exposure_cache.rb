# frozen_string_literal: true

module Risk
  # S5 — **a memória de UMA apuração de exposição**.
  #
  # Vive uma chamada do agregado e morre com ela. Não é cache de aplicação, não
  # tem TTL e não atravessa requisição: é um bloco de rascunho para não perguntar
  # a mesma coisa ao banco quatro vezes na mesma tela.
  #
  # ## O que ela evita, com número
  #
  # `controls_info_on` chama quatro fórmulas por limite (`utilizado`,
  # `liquidavel`, `pre`, `disponivel`), e cada uma:
  #
  # 1. pergunta **as operações da janela** daquele limite — a mesma pergunta, quatro vezes;
  # 2. pergunta **o saldo** de cada operação, uma por uma.
  #
  # Com 18 limites e 212 operações isso eram **495 consultas**. Com a memória:
  # uma consulta de operações por (limite, data) e **uma** de saldos por conjunto.
  #
  # ## O que ela NÃO muda, e é o ponto (decisão B-07)
  #
  # **A ordem da soma.** `operations_on` devolve o array materializado da MESMA
  # relação de antes — é literalmente `relation.to_a`, na ordem que o banco deu.
  # As fórmulas continuam somando uma operação de cada vez, nessa ordem. Com
  # float na cadeia, é a ordem que decide o centavo.
  #
  # O único ponto onde o caminho mudou é o filtro por subtipo (`is_pre`): antes
  # era um `where` no SQL sobre uma segunda consulta, agora é um `select` em Ruby
  # sobre o array já carregado. **Isso torna a ordem mais estável, não
  # diferente**: as duas consultas do legado não tinham `ORDER BY` nenhum, então
  # nada garantia que a filtrada viesse na mesma ordem relativa da completa —
  # agora vem, porque é a mesma lista.
  #
  # A prova de que nenhum número mudou não é este comentário: é o retrato dos
  # agregados de 40 escopos, comparado byte a byte antes e depois, mais os
  # goldens `L1`..`L4`.
  class ExposureCache
    def initialize
      @operacoes = {}
      @saldos = Hash.new { |h, k| h[k] = {} }
      @limites_por_tipo = {}
    end

    # Os limites ativos de um tipo dentro do escopo, materializados uma vez.
    # `total_limits_on` pede a mesma lista **três vezes por tipo** (pelo
    # percentual, pelo disponível e direto); sem o memo, são três consultas
    # idênticas — e três ordens que nada garante serem iguais entre si.
    def controls_of_type(scope, type)
      @limites_por_tipo[[scope.class.name, scope.id, type.id]] ||= yield
    end

    # As operações vigentes do limite na data, **materializadas na ordem do
    # banco**. Memoizado por (limite, data).
    def operations_on(control, date)
      @operacoes[[control.id, chave(date)]] ||= control.operations.on_date(date).to_a
    end

    # O saldo da operação na data. Se ainda não foi carregado, carrega **só ele**
    # — mas o caminho normal é o agregado ter chamado `prime!` com a lista toda.
    def balance_on(operation, date)
      k = chave(date)
      prime!([operation], date) unless @saldos[k].key?(operation.id)

      @saldos[k].fetch(operation.id, 0)
    end

    # Carrega em UMA consulta o saldo de todas as operações que ainda faltam.
    # Idempotente: chamar duas vezes com o mesmo conjunto não consulta de novo.
    def prime!(operations, date)
      k = chave(date)
      faltando = operations.filter_map(&:id).reject { |id| @saldos[k].key?(id) }
      return if faltando.empty?

      carregados = BalanceReader.last_balances(faltando, date)
      # Operação sem movimento vira 0 **e fica registrada como carregada** —
      # senão ela seria reconsultada a cada chamada de fórmula.
      faltando.each { |id| @saldos[k][id] = carregados.fetch(id, 0) }
    end

    private

    def chave(date)
      date.to_date.to_s
    end
  end
end
