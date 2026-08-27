# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/seeds/demo/orchestrator').to_s
require Rails.root.join('db/seeds/demo/reset').to_s

# Spec do orquestrador do seed de demonstração (S20 / DEC-64).
#
# Duas garantias, e as duas nasceram de modos de falha concretos:
#
#  - **pular com aviso**, porque a S20 precede S3..S11. Um seed que só funciona
#    quando tudo existe é um seed que nunca roda antes da demonstração;
#  - **idempotência**, porque rodar de novo é o gesto natural quando uma fatia
#    entrega o model que faltava.
RSpec.describe Demo::Orchestrator do
  let(:io) { StringIO.new }
  # **Janela curta e grade de amostra, de propósito.** Este spec grava o seed
  # inteiro uma vez por exemplo, e com os 24 meses do desenho são ~24 mil linhas
  # de cada vez — só a cascata de derivados da disponibilidade são 2.280 folhas
  # × ~10 gravações. Medido: três exemplos em **21 min 58 s** com a série
  # completa.
  #
  # `span: 2` encurta a série e liga o modo amostra da grade (um cliente, uma
  # data — ver `Ledger::Availability.entries`). Os mesmos caminhos são
  # exercitados: todos os escritores, a cascata de ponta a ponta, a máquina de
  # estados da mensagem e o reset. Quem confere volumetria, cobertura e as
  # regras de aceitação é `coverage_spec.rb`, que roda **no razão**, sem banco —
  # 46 exemplos em 5,6 s junto com o `ledger_spec.rb`.
  let(:ledger) { Demo::Ledger.new(base_date: Date.new(2026, 8, 28), span: 2) }

  # Papéis e permissões são pré-requisito de referência, não dado de
  # demonstração. O `scaffolding` os aplica sozinho, mas os exemplos que criam
  # usuário ANTES de rodar o orquestrador precisam deles já no lugar.
  before do
    Seeds::Reference::UserTypes.call!(io: StringIO.new)
    Seeds::Reference::Permissions.call!
  end

  def counts
    {
      users: User.where("email LIKE '%@safegold.test' OR email LIKE '%@livetat.test'").count,
      projects: Project.where(slug: ledger.clients.map(&:slug)).count,
      memberships: Membership.count
    }
  end

  # **A transferência do par estático, provada NO BANCO.**
  #
  # É o único agregado do seed cujo escritor não grava linha nenhuma: ele chama
  # `Risk::TransferService`, e é o serviço que decide o sinal de cada ponta,
  # cruza o `pair_id` e refaz as duas cadeias de saldo. Um exemplo no razão
  # provaria só a intenção; este prova o resultado.
  describe 'a transferência pré → antecipação (BE-275)' do
    it 'nasce como PAR, com sinais opostos e `pair_id` cruzado' do
      described_class.new(ledger: ledger, io: io).run

      saidas = RiskMovement.joins(:movement_type)
                           .where(risk_movement_types: { integration_key: RiskMovementType::TRANSFER_OUT_KEY })

      expect(saidas.count).to eq(ledger.static_transfers.size)
      expect(saidas.count).to be_positive

      saidas.each do |saida|
        entrada = RiskMovement.find_by(id: saida.pair_id)

        expect(entrada).not_to be_nil, 'saída de transferência sem contrapartida'
        expect(entrada.pair_id).to eq(saida.id)
        expect(entrada.movement_type.integration_key).to eq(RiskMovementType::TRANSFER_IN_KEY)
        expect(entrada.movement_value).to eq(saida.movement_value)
        # A saída sai da operação `is_pre`; a entrada, do par dela.
        expect(saida.risk_operation.operation_subtype.is_pre).to be(true)
        expect(entrada.risk_operation_id).to eq(saida.risk_operation.pair_id)
        # Sinais opostos — é o que o `Risk::TransferService` documenta.
        expect(saida.risk_operation.reload.balance).to be < 0
        expect(entrada.risk_operation.reload.balance).to be > 0
      end
    end

    # `TransferService` sempre cria — a guarda é do escritor. Sem ela cada
    # ensaio da apresentação acrescentaria um par novo e o saldo andaria.
    it 'a segunda execução NÃO cria um segundo par' do
      described_class.new(ledger: ledger, io: io).run
      antes = RiskMovement.joins(:movement_type).where(risk_movement_types: { is_transfer: true }).count

      described_class.new(ledger: ledger, io: StringIO.new).run
      depois = RiskMovement.joins(:movement_type).where(risk_movement_types: { is_transfer: true }).count

      expect(depois).to eq(antes)
    end
  end

  describe '#run' do
    # **O exemplo mudou de alvo no dia em que a última fatia dona entregou.**
    #
    # Ele exigia `skipped` NÃO vazio — o que fazia sentido enquanto S3..S11
    # estavam em voo e o pulo com aviso era a garantia em teste. Com S6 e S8
    # entregues, **nenhum escritor pula mais**, e a exigência antiga passou a
    # reprovar exatamente o estado que a fatia perseguia. O que continua tendo
    # de valer é o outro lado: todo escritor termina em `ok` **ou** em pulo
    # explicado — nunca num terceiro estado — e os quatro que nunca dependeram
    # de fatia alheia gravam.
    it 'todo escritor termina em gravação ou em pulo explicado' do
      results = described_class.new(ledger: ledger, io: io).run

      ran = results.select { |r| r.status == :ok }.map(&:writer)
      skipped = results.select { |r| r.status == :skipped }

      expect(ran).to include('scaffolding', 'users', 'projects', 'memberships')
      expect(results.map(&:status).uniq - %i[ok skipped]).to be_empty
      expect(skipped.map(&:message).compact.size).to eq(skipped.size)
    end

    # **O portão do pulo com aviso.** Desde que um escritor que estoura passou a
    # ser reportado (`:failed`) em vez de derrubar o seed inteiro — a defesa
    # certa com cinco fatias entregando model na mesma semana —, "não levantou
    # erro" deixou de significar "gravou". Este exemplo é o que separa os dois:
    # pular porque o model não existe é esperado; falhar gravando é defeito, e
    # tem de aparecer aqui e não na véspera da apresentação.
    it 'nenhum escritor falha: o que não é pulo é gravação de verdade' do
      results = described_class.new(ledger: ledger, io: io).run
      failed = results.select { |r| r.status == :failed }

      expect(failed.map { |r| [r.writer, r.message] }).to be_empty
    end

    # Este exemplo mirava `companies`/S4 e passou a ser **pulado** no dia em que
    # a S4 entregou `Company` — um spec que se desliga sozinho a cada entrega é
    # um spec que some. O mecanismo é o mesmo para todos os escritores, então ele
    # agora mira **quem ainda está pulando**, seja quem for: enquanto sobrar um
    # módulo esperando fatia, a mensagem tem de nomear o model E a fatia. No dia
    # em que S6 e S8 entregarem, este exemplo deixa de ter o que verificar — e aí
    # é a lista `ORDER` que está completa, que é o objetivo.
    it 'nomeia o model ausente e a fatia dona em cada pulo' do
      results = described_class.new(ledger: ledger, io: io).run
      skipped = results.select { |r| r.status == :skipped }

      skip 'nenhum escritor pula mais — todas as fatias donas entregaram' if skipped.empty?

      skipped.each do |result|
        writer = Demo::Orchestrator::ORDER.find { |w| w.writer_name == result.writer }

        expect(result.message).to include(writer.missing_models.first)
        expect(result.message).to include(writer.owner_slice)
      end
      expect(io.string).to include('PULADO')
    end

    it 'é idempotente: a segunda execução não cria nem atualiza nada' do
      described_class.new(ledger: ledger, io: io).run
      before = counts

      second = described_class.new(ledger: ledger, io: StringIO.new).run

      expect(counts).to eq(before)
      expect(second.sum(&:created)).to be_zero
      expect(second.sum(&:updated)).to be_zero
      expect(second.sum(&:unchanged)).to be_positive
    end

    it 'retoma de onde parou quando uma execução anterior foi interrompida no meio' do
      # Só os projetos existem, como se o seed tivesse morrido antes das
      # participações. A execução seguinte não pode duplicar projeto.
      Demo::Writers::Users.new(ledger, io: io).run
      Demo::Writers::Projects.new(ledger, io: io).run
      partial = Project.where(slug: ledger.clients.map(&:slug)).count

      described_class.new(ledger: ledger, io: StringIO.new).run

      expect(Project.where(slug: ledger.clients.map(&:slug)).count).to eq(partial)
      expect(Membership.count).to be_positive
    end
  end

  describe 'o elenco e a matriz de autorização' do
    before { described_class.new(ledger: ledger, io: io).run }

    it 'cria os seis usuários nos papéis da DEC-41' do
      levels = ledger.cast.to_h do |member|
        [member[:email], User.find_by(email: member[:email])&.user_type&.hierarchy_level]
      end

      expect(levels['suporte@livetat.test']).to eq(1)
      expect(levels['helena.moreira@safegold.test']).to eq(2)
      expect(levels['gustavo.lins@safegold.test']).to eq(3)
      expect(levels.values.compact.size).to eq(6)
    end

    it 'concede `user_is_readonly` a exatamente um usuário do elenco' do
      readonly = User.where(email: ledger.cast.map { |m| m[:email] }).select do |user|
        Authorization::PermissionResolver.new(user).granted?('user_is_readonly')
      end

      expect(readonly.map(&:email)).to eq(['tereza.machado@safegold.test'])
    end

    it 'não reescreve uma permissão já revogada a cada execução' do
      # Regressão real: o escritor carimbava `revoked_at = Time.current` em toda
      # rodada, então um `user_is_readonly` revogado por alguém pela tela virava
      # "1 atualizado" a cada `demo:seed` — e uma versão nova no `paper_trail`.
      camila = User.find_by(email: 'camila.duarte@safegold.test')
      permission = Permission.find_by(key: 'user_is_readonly')
      record = UserPermission.create!(user: camila, permission: permission, source: 'manual',
                                      granted_at: 2.days.ago, revoked_at: 1.day.ago)
      revoked_at = record.revoked_at

      results = described_class.new(ledger: ledger, io: StringIO.new).run

      expect(record.reload.revoked_at).to be_within(1.second).of(revoked_at)
      expect(results.sum(&:updated)).to be_zero
    end

    it 'dá aos dois colaboradores carteiras que não se cruzam' do
      camila = User.find_by(email: 'camila.duarte@safegold.test')
      rafael = User.find_by(email: 'rafael.antunes@safegold.test')

      expect(camila.projects.pluck(:slug) & rafael.projects.pluck(:slug)).to be_empty
      expect(camila.projects.count).to be_positive
      expect(rafael.projects.count).to be_positive
    end

    # O OG é o único do elenco sem projeto corrente, e é de propósito: sem ele
    # ninguém vê a tela de "escolha um projeto" (409 `PROJECT_NOT_SELECTED`) na
    # apresentação. Tem de ser ELE porque é o usuário que a demonstração ao
    # cliente não usa — deixar o Admin nesse estado atrasaria a primeira tela.
    it 'deixa o OG — e só ele — sem projeto corrente, para a tela de escolha ter dono' do
      sem_projeto = ledger.cast.reject do |member|
        User.find_by(email: member[:email])&.current_project_id.present?
      end

      expect(sem_projeto.map { |m| m[:key] }).to eq([:og])
    end

    it 'deixa cada usuário com um projeto corrente em que ele participa (contrato C1)' do
      ledger.cast.reject { |m| m[:key] == :og }.each do |member|
        user = User.find_by(email: member[:email])

        expect(user.current_project_id).to be_present
        expect(user.member_of?(user.current_project_id)).to be(true)
      end
    end
  end

  describe 'limpeza dos rastros de conferência da S0 (DEC-64)' do
    it 'remove `alpha`/`beta` e os usuários `s0.*`, sem tocar nos OGs da base' do
      og = User.create!(name: 'OG da base', email: 'og.base@example.com',
                        user_type: UserType.og)
      leftover = User.create!(name: 'S0 Admin', email: 's0.admin@sfg.test',
                              user_type: UserType.admin)
      Project.create!(name: 'Projeto Alpha', slug: 'alpha', owner: leftover)

      described_class.new(ledger: ledger, io: io).run

      expect(Project.exists?(slug: 'alpha')).to be(false)
      expect(User.exists?(email: 's0.admin@sfg.test')).to be(false)
      expect(User.exists?(id: og.id)).to be(true)
    end
  end

  describe 'o reset' do
    it 'apaga só o que o seed criou, preservando usuários que não são do elenco' do
      outsider = User.create!(name: 'Fora do elenco', email: 'fora@example.com',
                              user_type: UserType.colaborador)
      Demo::Orchestrator.new(ledger: ledger, io: io).run

      Demo::Reset.new(ledger: ledger, io: StringIO.new).run

      expect(Project.where(slug: ledger.clients.map(&:slug))).to be_empty
      expect(User.where(email: ledger.cast.map { |m| m[:email] })).to be_empty
      expect(User.exists?(id: outsider.id)).to be(true)
    end
  end
end
