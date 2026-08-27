# frozen_string_literal: true

# S3 / BE-069, BE-070, BE-071, DB-057..DB-062 — **portador**: a contraparte
# financiadora (FIDC, securitizadora, factoring ou o próprio cliente).
#
# **Catálogo GLOBAL** (C1, regra 4): sem `project_id`, sem `ProjectScoped`,
# nenhum endpoint chama `current_project!`. O portador é compartilhado entre
# projetos — é isso que permite ao `risk_control` de um projeto apontar para o
# mesmo portador que o recebível de outro.
#
# Quatro comportamentos que valem leitura antes de mexer:
#
# 1. **Título duplicado é PERMITIDO, e isso não é bug.** O comentário do legado
#    ("Cloud #7036") explica: a carga trouxe contrapartes homônimas com usos
#    distintos em renegociações e projetos diferentes, e a unicidade foi
#    desligada de propósito. Um implementador zeloso acrescentaria
#    `uniqueness: true` sem perguntar — este parágrafo existe para impedir isso.
# 2. **`bank_code` é STRING** (DC-12). `001` continua `001` na criação, na
#    leitura, na edição e na serialização.
# 3. **`subordinated_accounts_percent` é DERIVADO no servidor** (DC-09) e nunca
#    aceito do payload. No legado o número era calculado em JS a cada tecla E
#    persistido como coluna editável — duas fontes de verdade —, e a guarda de
#    divisão por zero existia só no cliente: o servidor gravava `NaN`.
#    **A FÓRMULA é a do legado, replicada (DEC-30)** — subordinadas ÷ SÊNIOR,
#    não ÷ total. Ver `#derive_subordinated_percent`.
# 4. **Excluir BLOQUEIA, nunca cascateia** (D-24). No legado
#    `has_many :risk_controls, dependent: :destroy` apagava os limites de risco
#    do portador junto com ele. É a assimetria mais perigosa do bloco.
class Carrier < ApplicationRecord
  include GlobalCatalog

  # Conjunto FECHADO (DB-059). Valor divergente é reportado no dry-run do ETL,
  # nunca inserido calado.
  FINANCIAL_AGENTS = %w[FIDC Securitizadora Factoring Cliente].freeze

  belongs_to :group, class_name: 'CarrierGroup', foreign_key: :group_id,
                     optional: true, counter_cache: :carriers_count, inverse_of: :carriers
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  # **D-24 — a assimetria mais perigosa do bloco, agora com a associação REAL.**
  #
  # No legado esta linha era `has_many :risk_controls, dependent: :destroy`
  # (`../sfg/app/models/carrier.rb`): excluir um portador **apagava os limites de
  # risco** dele — o teto que autoriza toda operação de crédito do Safegold —
  # sem aviso, sem 422 e sem trilha. É perda silenciosa de dado financeiro.
  #
  # Até a S5 entregar `risk_controls` a regra vivia SÓ no registro por nome de
  # `blocking_dependents` (S3, tarefa 2.1.7), porque `has_many` contra classe
  # inexistente levanta `NameError` no `destroy`. **A tabela existe desde a S5**,
  # então a declaração vira associação de verdade e o bloqueio passa a ter as
  # três camadas: registro por nome (a mensagem pt-BR que NOMEIA o vínculo),
  # `restrict_with_error` do ActiveRecord, e a FK `NO ACTION` do Postgres.
  #
  # A ordem importa e é deliberada: o `before_destroy` de `BlockingDependents`
  # é registrado no `include GlobalCatalog`, lá em cima — ou seja, roda ANTES do
  # callback de `restrict_with_error` e é a mensagem dele que chega ao 422.
  # `restrict_with_error` é a rede de baixo, para quem chamar `destroy` num
  # caminho que não passe pelo serviço.
  #
  # **Nunca `dependent: :destroy` aqui.** O spec de `carriers_spec.rb` reprova
  # qualquer cascata de domínio no portador, e a tarefa 5.7 da S3 exige o
  # cenário ponta a ponta: excluir portador com limite → 422 **e o limite
  # permanece**.
  has_many :risk_controls, dependent: :restrict_with_error, inverse_of: :carrier

  # DEC-47 (o logo do Portador volta) + DEC-91 (anexo DIRETO no model).
  #
  # **Não** pelo antigo `Medium` (removido na DEC-113): a tabela `media` não tinha dono nem escopo, e um logo
  # criado por lá apareceria na galeria `/media` para qualquer autenticado,
  # misturado com imagem de conteúdo. **Não** por Paperclip, que não é portado.
  # É a mesma pilha ActiveStorage de `Project#logo` e `Provider#logo`.
  #
  # O `content_type` é verificado pelo TIPO REAL do arquivo — o legado tinha
  # `MediaTypeSpoofDetector#spoofed? → false`, ou seja, a detecção de spoof
  # estava **desligada**, e um `.exe` renomeado para `.png` entrava (OPS-051).
  # S13 — a declaração passou a ser a do MOTOR ÚNICO de anexos (`Attachable`),
  # com o limite e os derivados vindo de `config/attachments.yml` (CFG-02).
  #
  # Duas coisas que a declaração manual daqui não entregava, e as duas foram
  # medidas, não supostas:
  #
  #  1. **A detecção de spoof continuava desligada.** O comentário acima está
  #     certo sobre a intenção, mas `content_type:` sem `spoofing_protection: true`
  #     compara o `Content-Type` que o CLIENTE declarou — exatamente o que o
  #     legado fazia. Conferido: um arquivo de texto puro enviado como
  #     `image/png` passava na validação.
  #  2. **O limite era 2 MB; o do legado é 1 MB** (`carrier.rb:33`), e a DEC-47
  #     religa o logo preservando o comportamento, não redefinindo-o.
  include Attachable
  sfg_attachment :logo

  validates :financial_agent, inclusion: { in: FINANCIAL_AGENTS, message: 'não é um agente financeiro válido' },
                              allow_blank: true
  validates :uf, format: { with: /\A[A-Z]{2}\z/, message: 'deve ter 2 letras' }, allow_blank: true
  validates :uf, inclusion: { in: ->(_carrier) { Api::V1::BrStates::CODES }, message: 'não é uma UF do Brasil' },
                 allow_blank: true
  validates :senior_accounts, :subordinated_accounts,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :net_worth, numericality: { greater_than_or_equal_to: 0 }

  # **DEC-119 / DEC-127 — os quatro SENTINELAS de "sem código bancário".**
  #
  # Medido no dump de 31/05/2025, nos 328 portadores de produção: `8888` em 181,
  # NULL em 83, `999` em 31, `9999` em 13 e `888` em 4 — **312 das 328 linhas**.
  # Entre os 16 códigos de verdade há **zero** repetidos.
  #
  # Não há 181 portadores no mesmo banco: um índice único cheio em `bank_code`
  # seria uma restrição que o dado real **nunca poderia satisfazer**. O erro
  # estava no índice que NÓS desenhamos a partir da intenção do schema legado,
  # não no dado do cliente.
  #
  # Esta validação é o espelho do índice parcial `index_carriers_on_bank_code_real`
  # (`20260827020000_unicidade_parcial_onde_o_legado_diz_nao_se_aplica`): ela
  # existe para dar mensagem em pt-BR; **a trava é o banco**. Note o par
  # `if:`/`conditions:` — sem o `conditions:` a validação compararia o código
  # novo contra os sentinelas também, e recusaria o 182º "sem código".
  SENTINELAS_SEM_BANCO = %w[888 999 8888 9999].freeze

  validates :bank_code,
            uniqueness: { conditions: -> { where.not(bank_code: SENTINELAS_SEM_BANCO) },
                          message: 'já está em uso por outro portador' },
            if: -> { bank_code.present? && SENTINELAS_SEM_BANCO.exclude?(bank_code) }
  # O título é o ÚNICO obrigatório além da chave derivada (BE-071).

  before_validation :normalize_bank_code
  before_validation :normalize_location
  before_validation :derive_subordinated_percent

  def self.blocking_dependents
    {
      # S4 — a conexão projeto ↔ portador.
      'ProjectToCarrierConnection' => { foreign_key: :carrier_id, label: 'conexão(ões) de projeto' },
      # S5 — o que o legado APAGAVA junto (D-24). A regra já está escrita; ela
      # passa a valer sozinha no dia em que a tabela existir.
      'RiskControl' => { foreign_key: :carrier_id, label: 'limite(s) de risco' },
      # S6 — os recebíveis lançados contra esta contraparte.
      'ReceivableEntry' => { foreign_key: :carrier_id, label: 'recebível(is)' }
    }
  end

  ORDERING = Sfg::Sortable.new(
    allowed: {
      'title' => :title, 'key' => :integration_key, 'bank_code' => :bank_code,
      'financial_agent' => :financial_agent, 'city' => :city, 'uf' => :uf,
      'created_at' => :created_at
    },
    default: { title: :asc }
  ).freeze

  # Cidade formatada com fallback `-` — comportamento preservado do legado
  # (`Carrier#formatted_city`), inclusive nos três casos parciais.
  def formatted_city
    return '-' if city.blank? && uf.blank?
    return city if uf.blank?
    return uf if city.blank?

    "#{city}, #{uf}"
  end

  # URL do logo. O NOME e o contrato do método não mudam (a entity e o front
  # leem `logo_url`); o que muda é quem monta a URL — agora o ponto único do
  # motor, que também é o único lugar onde o prazo da assinatura é decidido.
  #
  # `preview` (250 px) é o derivado do legado para esta posição. O `rescue`
  # dentro do motor devolve `nil` em vez de estourar; logo que não gera variante
  # cai para o arquivo original, que ainda tem que aparecer.
  def logo_url
    return nil unless logo.attached?

    Sfg::Attachments.variant_url(logo, :preview, expires_in: Sfg::Attachments.image_url_expires_in) ||
      Sfg::Attachments.url_for(logo, expires_in: Sfg::Attachments.image_url_expires_in)
  end

  private

  # `001` continua `001` (DC-12). Só os espaços saem; nada de `to_i`.
  def normalize_bank_code
    self.bank_code = bank_code.to_s.strip.presence
  end

  def normalize_location
    self.city = city.to_s.strip.presence
    self.uf = uf.to_s.strip.upcase.presence
  end

  # DC-09 + **DEC-30** — a fórmula mora AQUI, e em lugar nenhum além.
  #
  # **A fórmula é a DO LEGADO, replicada, e não a "certa".** O legado divide as
  # cotas subordinadas pelas **sênior** — não pelo total:
  #
  #     carriers/helper/_body.js.erb:47
  #     var prct = senior_accounts.val() == 0
  #                  ? 0
  #                  : 100.0 * (subordinated_accounts / senior_accounts);
  #
  # Com 250 subordinadas e 750 sênior isso dá **33,33%**, não 25%. Um leitor
  # desavisado (eu, na primeira escrita desta linha) "corrige" para
  # `subordinada / (sênior + subordinada)` porque é a definição usual de
  # proporção de cota subordinada num FIDC — e muda, em silêncio, um número que
  # o cliente lê há anos. **DEC-30 é explícito: o legado é sistema validado, e
  # regra e cálculo se mantêm.** O golden `carriers_percentual_golden_spec.rb`
  # trava os dois lados e reprova quem "consertar" sem passar por uma DEC nova.
  #
  # O que o DC-09 muda é **onde** o número é calculado (servidor, uma fonte de
  # verdade, campo somente leitura), não **qual** é a fórmula.
  #
  # A guarda de divisão por zero é a do próprio legado (`senior == 0 → 0`) e
  # passa a valer no SERVIDOR: no legado ela existia só no JS, e o servidor
  # aceitava e gravava `Infinity`/`NaN` (família D-10).
  #
  # Arredondamento em 2 casas, que é o que o legado persistia: o JS gravava no
  # campo o texto já formatado por `toFixed(2)` e era ele que voltava no submit.
  def derive_subordinated_percent
    senior = senior_accounts.to_i
    self.subordinated_accounts_percent =
      if senior.zero?
        0
      else
        (BigDecimal(subordinated_accounts.to_i.to_s) * 100 / senior).round(2)
      end
  end

end
