# frozen_string_literal: true

module Sfg
  # **O ÚNICO lugar onde se declara o que entra na trilha de auditoria.**
  #
  # A trilha é o `paper_trail` (DEC-59). A tabela `versions`, o preenchimento do
  # `whodunnit` e o job de expurgo nasceram na S0; esta fatia (S19) fecha o que
  # o DEC-78 tornou obrigatório — e a primeira das quatro condições é esta:
  #
  # > "A lista de models versionados é deliberada e CURTA. `has_paper_trail` em
  # > tudo, com foto completa, duplica a base a cada save."
  #
  # Por que a lista mora aqui, e não espalhada pelos models: metade dos models
  # que ela nomeia **ainda não existe** (nascem em S4..S9). Sem um lugar único,
  # "entra na trilha?" vira uma pergunta que cada fatia responde sozinha — e a
  # resposta some no diff. Com a lista aqui, a fatia dona faz duas coisas
  # explícitas e revisáveis: acrescenta a linha em {VERSIONED} e escreve
  # `include Auditable` no model. O spec `spec/lib/sfg/audit_trail_spec.rb`
  # reprova as duas metades se ficarem fora de sincronia — inclusive um
  # `has_paper_trail` que apareça num model **sem** estar declarado aqui.
  #
  # **O que NÃO entra** está em {EXCLUDED}, com o motivo escrito. A lista de
  # exclusões é parte da decisão: sem ela, a próxima pessoa lê a lista curta
  # como esquecimento e "conserta".
  module AuditTrail
    # Opções que valem para todo model versionado.
    #
    # `updated_at` é ignorado em todos: com payload COMPLETO (DEC-78), um
    # `touch` sozinho gravaria a foto inteira do registro sem nada ter mudado.
    BASE_IGNORE = %i[updated_at].freeze

    # Uma entrada por model. `slice` é a fatia dona; `why` é o motivo de estar
    # aqui — auditoria financeira ou auditoria de acesso, nunca "por garantia".
    #
    # `skip:`  → a coluna **não é copiada** para `object`/`object_changes`.
    # `ignore:`→ a mudança da coluna **não gera versão** (e a coluna também não
    #            aparece no `object_changes`).
    #
    # DEC-78 #3: `skip` é o que protege segredo (`jti`, token). `ignore` é o que
    # protege volume (coluna que muda a cada request).
    VERSIONED = {
      # --- Auditoria de ACESSO (existem desde a S0) --------------------------
      'User' => {
        slice: 'S0',
        why: 'Troca de papel e mudança de identidade são o que se quer reconstruir depois.',
        skip: %i[jti],
        ignore: %i[updated_at last_login_at login_count]
      },
      'UserType' => {
        slice: 'S0',
        why: 'Mudar a definição de um papel é ato de acesso: muda o que um grupo inteiro pode fazer.'
      },
      'Permission' => {
        slice: 'S0',
        why: 'Catálogo, mas curto e quase estático — e mudá-lo muda o que todo mundo pode fazer. ' \
             'É a exceção deliberada ao "catálogo não entra" do DEC-78 #1.'
      },
      'UserPermission' => {
        slice: 'S0',
        why: 'Conceder e revogar permissão a uma pessoa é o ato administrativo que mais importa auditar.'
      },
      'UserTypePermission' => {
        slice: 'S0',
        why: 'Conceder e revogar permissão a um papel — o mesmo ato, com alcance maior.'
      },
      'Membership' => {
        slice: 'S0',
        why: 'Entrar e sair de um projeto é ato de acesso: é o que decide o escopo de tudo (contrato C1).'
      },
      'Project' => {
        slice: 'S0',
        why: 'É o eixo de todo o escopo do sistema; renomear ou transferir projeto move o que cada um vê.'
      },

      # --- Auditoria FINANCEIRA (nascem em S5..S12) --------------------------
      # As linhas abaixo estão declaradas ANTES de os models existirem, de
      # propósito: é o que impede a fatia dona de decidir sozinha e diferente.
      # `include Auditable` no model fecha a linha.
      'RiskControl' => {
        slice: 'S5',
        why: 'Limite de risco. "Como estava este limite no dia em que estourou" é a pergunta que o ' \
             'DEC-78 cita como razão do payload completo.'
      },
      # **A chave era `'Receivable'` e virou `'ReceivableEntry'` (S6).** Não há
      # nem haverá um model `Receivable`: a tabela do legado é
      # `receivable_entries` e a classe é `ReceivableEntry`
      # (`../sfg/app/models/receivable_entry.rb:1`). Com a chave antiga o
      # `include Auditable` do model levantaria na carga da classe — que é
      # exatamente o portão funcionando. A linha, o motivo e a fatia são os
      # mesmos; só o nome ficou correto.
      'ReceivableEntry' => {
        slice: 'S6',
        why: 'Recebível: valor, vencimento e portador mudam depois de lançados, e cada mudança tem efeito financeiro.'
      },
      # S6 — cobrança e recibo. Entram pelo mesmo critério de auditoria
      # financeira: o recibo é a RECEITA faturada sobre uma operação, e a
      # cobrança é o pacote que vai ao cliente. "Quanto foi cobrado, sobre quais
      # operações, e quem fechou o pacote" é pergunta de dinheiro.
      'Charge' => {
        slice: 'S6',
        why: 'Pacote de cobrança: fechar como Faturado é ato irreversível de negócio, e os totais são receita.'
      },
      'Receipt' => {
        slice: 'S6',
        why: 'Recibo: a receita faturada sobre uma operação. Incluir e remover do pacote muda o valor cobrado.'
      },
      'RiskOperation' => {
        slice: 'S7',
        why: 'Operação de risco: o ciclo de vida inteiro é dinheiro (DEC-35), e valores históricos já ' \
             'foram recalculados uma vez (DEC-33).'
      },
      'StructuredOperation' => {
        slice: 'S8',
        why: 'Operação estruturada: mesma família da operação de risco — valor, prazo e garantia. ' \
             'Não está nomeada no DEC-78 #1, entra pelo mesmo critério (auditoria financeira), e ' \
             'a inclusão fica escrita aqui em vez de virar decisão silenciosa da S8.'
      },
      # S8 — a **taxa** que o projeto cobra por tipo de operação. Entra por
      # auditoria financeira, e o critério é o mesmo do `RiskControl`: é uma
      # tabela curta (uma linha por projeto × tipo) cujo VALOR multiplica todo o
      # faturamento seguinte (`Receipt#fetch` → `operation_value × fee/100`).
      #
      # Não é catálogo no sentido do DEC-78 #1 (que exclui catálogo por ser
      # lista de opções sem efeito financeiro): mudar `remunerations.value` de
      # 2,55 para 25,5 muda a receita de todo recibo emitido depois, e o recibo
      # já emitido **congela** a taxa — então a única prova de qual taxa vigorava
      # antes da mudança é esta trilha. Volume de escrita é baixo: dezenas de
      # linhas, editadas por painel lateral.
      'Remuneration' => {
        slice: 'S8',
        why: 'A taxa que multiplica TODO o faturamento do tipo. O recibo congela a taxa no dia da ' \
             'emissão, então esta é a única prova de qual taxa vigorava antes de uma edição.'
      },
      'Renegotiation' => {
        slice: 'S9',
        why: 'Renegociação: reescreve as condições de uma dívida. Sem trilha não há como provar o que foi acordado.'
      },
      'Contract' => {
        slice: 'S12',
        why: 'Contrato: o texto vigente decide o que o usuário aceitou. O aceite em si é do DEC-80 ' \
             '(ver EXCLUDED), o TEXTO é daqui.',
        # **Colisão real, descoberta na S12 gravando o primeiro contrato.**
        # `has_paper_trail` cria `attr_accessor :version` para guardar "a versão
        # de que esta instância foi reificada" (`paper_trail/model_config.rb:229`)
        # — e `contracts` TEM uma coluna `version`, que é o número da versão
        # publicada. O `attr_accessor` sombreia o atributo do banco: o model
        # validava com `version = 1` e o INSERT ia com `NULL`.
        # Renomear a associação do paper_trail resolve sem tocar no nome da
        # coluna, que é o do legado e viaja em URL (DEC-84).
        version_association: :reified_version
      },
      # --- S10 — indicadores ------------------------------------------------
      # **Exceção deliberada ao "catálogo não entra" do DEC-78 #1**, e o motivo é
      # específico deste model, não genérico:
      #
      #  - renomear um indicador **reescreve o histórico**: o `after_save`
      #    propaga `title`/`key`/`value_type` para TODAS as suas entries por
      #    `update_all`, sem tocar `updated_at` (T-D11 / G4). Como
      #    `IndicatorEntry` é excluída por volume, sem esta linha **não existiria
      #    lugar nenhum** que registrasse quem reescreveu 20.000 rótulos de série
      #    histórica;
      #  - excluir um indicador é o maior risco de perda de dado do bloco (D-66).
      #    A exclusão passou a ser lógica (`discarded_at`), e é esta trilha que
      #    diz **quem** a fez.
      #
      # Volume é baixo: são dezenas de linhas, não milhares.
      'Indicator' => {
        slice: 'S10',
        why: 'Renomear reescreve a série histórica inteira e excluir é o D-66. ' \
             'A entry é excluída por volume, então este é o único lugar com a trilha.'
      }
    }.freeze

    # **O que fica de fora, e por quê.** Esta metade é decisão, não omissão.
    EXCLUDED = {
      'LoginAttempt' => 'Alto volume de escrita e retenção própria de 90 dias (DEC-60). ' \
                        'Versionar tentativa de login é duplicar um log que já é log.',
      'LoginCode' => 'Alto volume e vida curta; o expurgo horário é o CleanupLoginCodesJob.',
      'PermissionAuditLog' => 'Não ganha produtor (DEC-59). Versioná-lo criaria a segunda trilha ' \
                              'que a decisão existe para evitar.',
      'PaperTrail::Version' => 'A trilha não se audita: seria recursão infinita a cada gravação.',
      'ContractDeal' => 'O aceite tem prova própria — usuário, versão, data/hora e IP no próprio ' \
                        'registro (DEC-80), explicitamente SEM versionamento imutável.',
      # Atendimento (S2). Chegaram versionados e foram retirados por esta fatia,
      # com o portão deste módulo apontando o caso: os dois critérios de entrada
      # do DEC-78 #1 são auditoria FINANCEIRA e de ACESSO, e ticket de suporte
      # não é nenhum dos dois. Não havia leitor: nada no repositório consulta
      # `versions` desses três. Se um dia "quem fechou este chamado" virar
      # requisito, a resposta já está na própria thread de notas.
      'AdminMessage' => 'Atendimento, não auditoria financeira nem de acesso (DEC-78 #1).',
      'MessageNote' => 'Fala de thread: alto volume de escrita, e a foto completa duplicaria o texto ' \
                       'da mensagem a cada edição.',
      'Observer' => 'Cadastro de quem recebe e-mail de atendimento — atendimento, não acesso.',
      'AgentRun' => 'Telemetria de execução de agente: alto volume de escrita, valor de auditoria zero.',
      'ChatSession' => 'Conversa, não ato administrativo; e cada mensagem gravaria a foto inteira.',
      'FlowExecution' => 'Execução de fluxo é telemetria — mesmo caso do AgentRun.',
      'IndicatorEntry' => 'Grade mensal de indicadores — alto volume de escrita (DEC-78 #1 exclui).',
      # S10. A ponte projeto ↔ indicador é junção pura: conectar e desconectar
      # muda o que a tela MOSTRA e não apaga nada (Q-R31 — reconectar traz o
      # histórico de volta). O ato com efeito duradouro é o do `Indicator`, que
      # está versionado.
      'ProjectIndicatorConnection' => 'Junção pura projeto ↔ indicador. Desconectar não apaga lançamento; ' \
                                      'o ato auditável é o do próprio Indicator.',
      'AvailabilityEntry' => 'Lançamento de disponibilidade — alto volume de escrita.',
      # S7. As duas peças da operação de risco que **já são log**. A `RiskOperation`
      # está versionada (acima) e é lá que a mudança de valor, prazo e estado
      # aparece; estas duas são o detalhe que a produziu.
      'RiskMovement' => 'Movimento da cadeia de saldos: alto volume de escrita e reescrito em lote a ' \
                        'cada recálculo (`upsert_all` de `balance`/`sequence`, OPS-235) — versionar ' \
                        'gravaria uma foto por movimento a cada save da operação. O ato auditável ' \
                        '(saldo e valor resultantes) está na RiskOperation, que é versionada.',
      'RiskOperationExtension' => 'Prorrogação: o registro JÁ É o log imutável (sem update exposto, ' \
                                  'com autor, data original e data nova). Versioná-lo criaria a ' \
                                  'segunda trilha que o DEC-59 existe para evitar; a mudança de ' \
                                  '`due_date` que ela causa aparece na trilha da RiskOperation.',
      'Segment' => 'Catálogo (DEC-78 #1).',
      'SubSegment' => 'Catálogo (DEC-78 #1).',
      # S3 — os outros três catálogos globais da fatia. Entram aqui pelo mesmo
      # critério dos dois acima (DEC-78 #1: catálogo não entra), e a linha é
      # escrita para que a lista curta não seja lida como esquecimento. O
      # portador é o caso que mais tenta: ele participa de dinheiro. Mas o que
      # se audita é o LIMITE e a OPERAÇÃO (`RiskControl`, `RiskOperation`, já
      # declarados), não o cadastro da contraparte.
      'Carrier' => 'Catálogo (DEC-78 #1). O que tem efeito financeiro é o limite e a operação, não o cadastro da contraparte.',
      'CarrierGroup' => 'Catálogo (DEC-78 #1). Agrupador de portadores, sem efeito financeiro nem de acesso.',
      'ProjectGuaranteeType' => 'Catálogo (DEC-78 #1). A garantia do PROJETO é que importa; o tipo é a lista de opções.',
      'MovementKind' => 'Catálogo (DEC-78 #1).',
      'ReceivableKind' => 'Catálogo (DEC-78 #1).',
      'ResourceKind' => 'Catálogo (DEC-78 #1).',
      # S8 — os dois catálogos da unidade de operações estruturadas. A linha
      # existe para que a lista curta não seja lida como esquecimento: o que tem
      # efeito financeiro é a OPERAÇÃO e a REMUNERAÇÃO (as duas versionadas
      # acima), não a lista de tipos nem a de fontes de recurso.
      'StructuredOperationType' => 'Catálogo (DEC-78 #1). Os 4 tipos são semeados e `is_default`; ' \
                                   'o que tem efeito financeiro é a operação e a remuneração do tipo.',
      'ResourceSource' => 'Catálogo (DEC-78 #1). Fonte de recurso é classificatória — não entra em ' \
                          'tarifa, IOF, custo efetivo nem remuneração (Q-R19).'
    }.freeze

    module_function

    # Opções de `has_paper_trail` para um model declarado. Levanta se o model
    # não estiver na lista — é o portão que impede versionar por descuido.
    def options_for(model_name)
      entry = VERSIONED[model_name.to_s]
      unless entry
        raise ArgumentError,
              "#{model_name} não está declarado em Sfg::AuditTrail::VERSIONED. " \
              'A lista de models versionados é deliberada (DEC-78 #1): declare a linha, ' \
              'com o motivo, antes de incluir `Auditable`.'
      end

      opts = {}
      opts[:skip] = Array(entry[:skip]) if entry[:skip].present?
      opts[:ignore] = Array(entry[:ignore]).presence || BASE_IGNORE
      # `version:` renomeia o `attr_accessor` que o paper_trail cria para a
      # versão reificada. Só é declarado quando o model TEM uma coluna com esse
      # nome — ver a nota em `Contract`.
      opts[:version] = entry[:version_association] if entry[:version_association].present?
      opts
    end

    def declared_names
      VERSIONED.keys
    end

    # Models declarados cuja classe já existe neste repositório. O resto ainda
    # vai nascer — e é por isso que a lista pode (e deve) chegar antes deles.
    def existing_models
      declared_names.filter_map do |name|
        name.safe_constantize
      end
    end

    # Declarados que ainda não têm classe. Não é erro: é o trabalho das fatias
    # S5..S12, e esta lista é o que elas conferem.
    def pending_names
      declared_names.reject { |name| name.safe_constantize }
    end

    # --- Leitura ------------------------------------------------------------
    #
    # Fica aqui, e não no endpoint, porque a S19 é dona da trilha GLOBAL mas o
    # **histórico do próprio objeto** é servido por cada fatia dona do objeto
    # (DEC-77). Se cada uma escrever o próprio `where`, a trilha do recebível e
    # a do limite discordam na primeira vez que alguém errar o `item_type` —
    # que é `base_class.name`, não `class.name`, e é o erro que STI produz.

    # Histórico de UM registro, do mais recente para o mais antigo.
    #
    # Uso na fatia dona do objeto (a autorização é a do objeto, não a da trilha
    # global):
    #
    #     get ':id/history' do
    #       recebivel = Receivable.find(params[:id])
    #       authorize_record!(recebivel)
    #       versions = paginate(Sfg::AuditTrail.for_record(recebivel))
    #       Api::Entities::AuditVersion.represent(versions.to_a)
    #     end
    def for_record(record)
      PaperTrail::Version
        .where(item_type: record.class.base_class.name, item_id: record.id.to_s)
        .order(created_at: :desc, id: :desc)
    end

    # Filtros COMBINÁVEIS da trilha global (`BE-432`). Combináveis de verdade:
    # cada um estreita o anterior, e o total do envelope é o total do filtrado —
    # no legado o `where!` mutava a relação e o `@trackings.size > 0` a
    # carregava inteira ANTES do `limit`, então "filtrar" carregava tudo.
    def filter(params)
      p = params.respond_to?(:symbolize_keys) ? params.symbolize_keys : params
      scope = PaperTrail::Version.order(created_at: :desc, id: :desc)

      scope = scope.where(item_type: p[:item_type]) if p[:item_type].present?
      scope = scope.where(item_id: p[:item_id].to_s) if p[:item_id].present?
      scope = scope.where(whodunnit: p[:whodunnit].to_s) if p[:whodunnit].present?
      scope = scope.where(event: p[:event]) if p[:event].present?
      scope = scope.where(created_at: p[:from]..) if p[:from].present?
      scope = scope.where(created_at: ..p[:to]) if p[:to].present?
      scope
    end
  end
end
