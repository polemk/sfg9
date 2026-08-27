# frozen_string_literal: true

require_relative 'ledger'
require_relative 'writers/base'
require_relative 'writers/scaffolding'

module Demo
  # Apaga **só o que o seed de demonstração cria**, identificado pelas mesmas
  # chaves naturais que o gravaram.
  #
  # Poder resetar entre ensaios importa: é a diferença entre repetir a
  # apresentação com o banco no estado exato do ensaio anterior e improvisar em
  # cima de dado sujo.
  #
  # **O que ele NÃO apaga, e por quê:**
  #
  #  - os OGs da base ai9 (`vinaoxd@gmail.com` e companhia) — são contas de quem
  #    desenvolve, não dado de demonstração;
  #  - os catálogos globais (papéis, permissões, tipos de operação e de
  #    movimento) — são de referência, idempotentes, e o deploy os aplica. Apagar
  #    catálogo num reset de ensaio é a forma mais rápida de derrubar o sistema
  #    inteiro cinco minutos antes da demo.
  #
  # Nunca usa `delete_all` de tabela: sempre o escopo da chave natural.
  class Reset
    # **A lista de tabelas é DESCOBERTA, não escrita à mão.**
    #
    # A lista fixa que morava aqui tinha os quinze agregados que o seed escreve —
    # e o reset morreu no meio na primeira vez que rodou contra o banco de
    # desenvolvimento, porque `availability_entries` (de outra fatia) referencia
    # `companies` e não estava nela. O estado que sobrou foi o pior possível:
    # metade apagada, metade não.
    #
    # A regra correta não é "as minhas tabelas": é **tudo o que é escopado pelo
    # projeto que está sendo removido**, porque apagar um projeto sem apagar os
    # filhos dele é deixar órfão ou bater na FK. Toda tabela com `project_id`
    # entra, na ordem em que as FKs permitem — e a fatia que nascer amanhã com
    # uma tabela nova entra sozinha, sem ninguém lembrar de editar este arquivo.
    #
    # **Continua não sendo `TRUNCATE ... CASCADE`**, e a diferença é o que
    # protege as contas de login: o `CASCADE` segue a FK para FORA do escopo
    # (`users.current_project_id` aponta para `projects`, e foi assim que a base
    # inteira de usuários foi apagada uma vez). Aqui cada `DELETE` é filtrado por
    # `project_id IN (...)`, e `users` não tem `project_id` — não há caminho.

    def initialize(ledger: nil, io: $stdout)
      @ledger = ledger || Ledger.new
      @io = io
    end

    attr_reader :ledger, :io

    def run
      io.puts
      io.puts 'Reset do seed de demonstração (S20 / DEC-64)'
      io.puts '-' * 78

      project_ids = demo_project_ids
      drop_project_scoped(project_ids)
      drop_projects(project_ids)
      drop_users
      drop_carriers
      drop_demo_indicators
      drop_service_desk
      drop_global_availability_templates
      drop_orphan_versions
      io.puts '-' * 78
    end

    private

    def slugs
      @slugs ||= ledger.clients.map(&:slug) + Writers::Scaffolding::LEFTOVER_PROJECT_SLUGS
    end

    def emails
      @emails ||= ledger.cast.map { |m| m[:email] } +
                  Writers::Scaffolding::LEFTOVER_USER_EMAILS
    end

    def demo_project_ids
      return [] unless defined?(::Project)

      ::Project.where(slug: slugs).pluck(:id)
    end

    def drop_project_scoped(project_ids)
      return if project_ids.empty?

      ordered_scoped_tables.each do |table|
        count = connection.delete(
          ActiveRecord::Base.sanitize_sql_array(
            ["DELETE FROM #{connection.quote_table_name(table)} WHERE project_id IN (?)", project_ids]
          )
        )
        io.puts format('  · %-28<m>s %<c>d removidos', m: table, c: count) if count.positive?
      end
    end

    # Toda tabela com `project_id`, **filhos primeiro**: em cada passada saem as
    # que nenhuma das restantes referencia. Determinístico (ordem alfabética
    # dentro da passada) e à prova de ciclo — se um aparecer, o laço escolhe uma
    # tabela e segue, em vez de rodar para sempre.
    def ordered_scoped_tables
      remaining = connection.tables.select do |table|
        table != 'projects' && connection.columns(table).any? { |c| c.name == 'project_id' }
      end
      references = remaining.to_h { |t| [t, referenced_tables(t)] }
      ordered = []

      until remaining.empty?
        free = remaining.select { |t| remaining.none? { |o| o != t && references[o].include?(t) } }
        free = [remaining.min] if free.empty?
        ordered.concat(free.sort)
        remaining -= free
      end

      ordered
    end

    def referenced_tables(table)
      connection.foreign_keys(table).map(&:to_table).uniq
    rescue StandardError
      []
    end

    def connection
      ::ActiveRecord::Base.connection
    end

    def drop_projects(project_ids)
      return if project_ids.empty?

      count = ::Project.where(id: project_ids).delete_all
      io.puts format('  · %-28<m>s %<c>d removidos', m: 'Project', c: count)
    end

    def drop_users
      users = ::User.where(email: emails)
      count = users.count
      return if count.zero?

      users.destroy_all
      io.puts format('  · %-28<m>s %<c>d removidos', m: 'User', c: count)
    end

    # As 5 contrapartes fictícias são dado de demonstração, não catálogo: nenhuma
    # existe fora deste seed.
    #
    # **`delete_all` NÃO decrementa `counter_cache` — é por isso que a
    # recontagem abaixo existe.** `Carrier belongs_to :group, counter_cache:
    # :carriers_count` (`app/models/carrier.rb:36-37`) só mexe na coluna por
    # callback de `create`/`destroy`, e `DELETE` cru não passa por callback. Como
    # este reset roda entre ensaios da apresentação, cada `demo:reseed` somava
    # mais um por portador sem nunca subtrair: medido em 26/08, sete execuções
    # deixaram a tela de grupos mostrando **7 / 7 / 7 / 14** onde o real é
    # **1 / 1 / 1 / 2** — 35 portadores declarados para os 5 que existem.
    #
    # Não é número cosmético. `carriers_count` é o critério do botão de excluir
    # (`CarrierGroupsPage.tsx:53` → `usageCount` do `CatalogScreen`): grupo com o
    # contador inflado **nunca mais parece vazio** e o usuário perde a ação de
    # remover, embora o servidor — que conta de verdade — fosse aceitar.
    #
    # `reset_counters` **reconta a partir da tabela**, então é idempotente e
    # conserta também a defasagem que as execuções anteriores já deixaram no
    # banco de demonstração — que é o estado em que ele está. Reconta todos os
    # grupos (é catálogo global, são poucas linhas) em vez de só os afetados:
    # depender de ter capturado os `group_id` antes do `DELETE` seria mais uma
    # coisa para alguém esquecer ao mexer aqui.
    #
    # **Trocar por `destroy_all` foi descartado de propósito.** `Carrier` tem
    # `BlockingDependents` + `restrict_with_error`, então um vínculo remanescente
    # faria o reset **falhar no meio** — metade apagada, metade não, que é o
    # estado que o cabeçalho desta classe descreve como o pior possível.
    def drop_carriers
      return unless available?('Carrier')

      count = ::Carrier.where(bank_code: ledger.carriers.map(&:bank_code)).delete_all
      io.puts format('  · %-28<m>s %<c>d removidos', m: 'Carrier', c: count) if count.positive?
      resync_carrier_group_counters
    end

    def resync_carrier_group_counters
      return unless available?('CarrierGroup')

      ajustados = ::CarrierGroup.pluck(:id).count do |id|
        antes = ::CarrierGroup.where(id: id).pick(:carriers_count)
        ::CarrierGroup.reset_counters(id, :carriers)
        antes != ::CarrierGroup.where(id: id).pick(:carriers_count)
      end
      return if ajustados.zero?

      io.puts format('  · %-28<m>s %<c>d recontados', m: 'CarrierGroup#carriers_count', c: ajustados)
    end

    # Os indicadores do seed são **globais** (`project_id IS NULL`), então não
    # caem junto com os projetos. São dado de vitrine — nenhum deles existe fora
    # daqui —, e por isso saem no reset, pela chave e **só** quando já não
    # sobrou lançamento apontando para eles (`dependent: :restrict_with_error`,
    # D-66: apagar indicador nunca leva a série histórica junto).
    def drop_demo_indicators
      return unless available?('Indicator')

      keys = ::Demo::Ledger::Ancillary::INDICATORS.map { |i| i[:key] }
      scope = ::Indicator.where(project_id: nil, key: keys).where.missing(:entries)
      count = scope.count
      return if count.zero?

      scope.find_each(&:destroy!)
      io.puts format('  · %-28<m>s %<c>d removidos', m: 'Indicator', c: count)
    end

    # Mensagens administrativas e observadores **não são escopados por projeto**
    # — são uma caixa de atendimento só, para o sistema inteiro —, então não caem
    # com os projetos. Saem pela mesma chave natural que os gravou: o
    # `public_token` determinístico do razão e o e-mail do observador.
    #
    # `destroy_all` e não `delete_all`: `message_notes` e `observer_contexts`
    # dependem por `dependent: :destroy`, e um `DELETE` cru deixaria as duas
    # tabelas cheias de órfão apontando para id inexistente.
    def drop_service_desk
      if available?('AdminMessage')
        scope = ::AdminMessage.where(public_token: ledger.admin_messages.map(&:public_token))
        count = scope.count
        if count.positive?
          scope.destroy_all
          io.puts format('  · %-28<m>s %<c>d removidos', m: 'AdminMessage', c: count)
        end
      end

      return unless available?('Observer')

      scope = ::Observer.where(email: ledger.observers.map(&:email))
      count = scope.count
      return if count.zero?

      scope.destroy_all
      io.puts format('  · %-28<m>s %<c>d removidos', m: 'Observer', c: count)
    end

    # O catálogo global de padrões de disponibilidade (`project_id IS NULL`) não
    # cai com os projetos, e nenhuma das dezesseis linhas existe fora deste seed
    # — mesma leitura das cinco contrapartes fictícias.
    #
    # **Dos mais fundos para os mais rasos**: `child_templates` é
    # `restrict_with_error`, então apagar a raiz antes do filho falha. E só sai o
    # que não tem derivado de projeto vivo apontando para ele — se sobrou algum,
    # é de projeto que não é deste seed, e não é nosso para apagar.
    def drop_global_availability_templates
      return unless available?('GlobalAvailabilityTemplate')

      titles = ledger.availability_templates.map { |t| Writers::Base.normalized_title(t.title) }
      scope = ::GlobalAvailabilityTemplate.order(sort_key: :desc).to_a.select do |template|
        titles.include?(Writers::Base.normalized_title(template.title))
      end
      return if scope.empty?

      removed = 0
      scope.each do |template|
        next if ::ProjectAvailabilityTemplate.exists?(global_availability_template_id: template.id)
        next if ::AvailabilityTemplate.exists?(parent_template_id: template.id)

        template.destroy
        removed += 1 if template.destroyed?
      end
      return if removed.zero?

      io.puts format('  · %-28<m>s %<c>d removidos', m: 'GlobalAvailabilityTemplate', c: removed)
    end

    # **A trilha de auditoria não é escopada por projeto, e sem isto ela cresce
    # a cada ensaio.**
    #
    # `versions` (paper_trail, DEC-59) não tem `project_id`, então nenhuma das
    # varreduras acima a alcança. Medido depois de três `demo:reseed` no banco de
    # desenvolvimento: **14.993 linhas**, das quais 8.130 de `ReceivableEntry`
    # para 2.706 borderôs — três gerações de registro apagado. Repetir a
    # apresentação cinco vezes encheria a tela de Trilha de auditoria de eventos
    # de criação de registros que não existem mais, e as páginas iniciais
    # deixariam de mostrar o que está no banco agora.
    #
    # **Só sai o que está ÓRFÃO**: a consulta confere, tipo a tipo, que o
    # registro apontado não existe mais. Nenhuma versão de registro vivo é
    # tocada, e o `NOT EXISTS` é a garantia — não a lista de tipos.
    #
    # Isto **não** apaga rastro de exclusão de negócio: o reset usa `DELETE`
    # cru, que não passa por callback e portanto nunca gerou versão de `destroy`.
    # O que sobra é a versão de `create` de um registro que o próprio seed
    # inventou e o próprio seed removeu.
    def drop_orphan_versions
      return unless connection.table_exists?('versions')

      total = 0
      connection.select_values('SELECT DISTINCT item_type FROM versions').each do |item_type|
        model = safe_constant(item_type)
        next if model.nil? || !model.respond_to?(:table_name)

        table = connection.quote_table_name(model.table_name)
        sql = <<~SQL.squish
          DELETE FROM versions v
           WHERE v.item_type = #{connection.quote(item_type)}
             AND NOT EXISTS (SELECT 1 FROM #{table} t WHERE t.id::text = v.item_id::text)
        SQL
        total += connection.delete(sql)
      end

      io.puts format('  · %-28<m>s %<c>d órfãs removidas', m: 'PaperTrail::Version', c: total) if total.positive?
    end

    def safe_constant(name)
      Object.const_get(name) if Object.const_defined?(name)
    rescue StandardError
      nil
    end

    def available?(model_name)
      Object.const_defined?(model_name) &&
        Object.const_get(model_name).respond_to?(:table_exists?) &&
        Object.const_get(model_name).table_exists?
    rescue StandardError
      false
    end
  end
end
