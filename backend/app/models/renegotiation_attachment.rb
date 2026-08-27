# frozen_string_literal: true

# S9 / BE-226, DB-193 — **anexo da renegociação**.
#
# Uma linha por arquivo. A linha carrega o que o blob não tem e a regra precisa:
# **`title`** (que o usuário edita — DEC-53 manda consertar o "renomear anexo",
# que no legado levantava `NameError` garantido) e **`user_id`**, o autor, que é
# quem — e só quem — pode excluir (BE-229, checado no servidor; no legado a regra
# de dono era só visual).
#
# O binário é do **motor único** (`Attachable` + `config/attachments.yml`, chave
# `renegotiation_attachment.file`). Isso significa, sem uma linha a mais aqui:
# armazenamento privado, tipo conferido pelos **magic bytes** (Marcel) contra
# allowlist, teto de 5 MB no servidor, e leitura só por quem participa do projeto
# (`policy: project_member`).
#
# O teto de **4 arquivos por renegociação** não cabe no motor porque aqui cada
# linha tem UM arquivo: quem o aplica é `Renegotiations::AttachmentService`,
# contando linhas irmãs e lendo o número do **mesmo** catálogo. A tela lê o mesmo
# número por `GET /api/v1/attachments/limits` — nenhum dos dois tem "4" escrito.
#
# **`Medium` nunca foi reusado** — ele restringia `media_type` a
# `image`/`video`, e anexo de renegociação é majoritariamente PDF) e
# **`AssetsProxyController` não é reusado de forma alguma** (serve
# `public/uploads/**` inline e sem autenticação — é literalmente o D-82).
class RenegotiationAttachment < ApplicationRecord
  include ProjectScoped
  include Attachable

  sfg_attachment :file

  belongs_to :renegotiation, inverse_of: :attachments, counter_cache: :attachments_count
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, presence: true, length: { maximum: 255 }

  before_validation :carimbar_escopo_e_titulo

  scope :ordered, -> { order(created_at: :asc) }

  # Nome original do arquivo, para o `Content-Disposition` do download.
  def filename
    file.attached? ? file.filename.to_s : title
  end

  # Extensão exibida na galeria ("PDF", "PNG"…). Vem do nome real do arquivo, não
  # de um campo digitado.
  def format_label
    nome = filename.to_s
    return '' unless nome.include?('.')

    nome.split('.').last.upcase
  end

  def image?
    file.attached? && file.content_type.to_s.start_with?('image/')
  end

  # **Só o autor exclui** (BE-229). OG e Admin passam porque administram o
  # produto; é a mesma exceção que a política `owner` do motor aplica.
  def deletable_by?(user)
    return false if user.blank?
    return true if user.og? || user.admin?

    user_id.present? && user_id == user.id
  end

  private

  def carimbar_escopo_e_titulo
    self.project_id ||= renegotiation&.project_id
    return if title.present?

    nome = file.attached? ? file.filename.to_s : nil
    self.title = nome.present? ? nome.split('.')[0...-1].join('.').presence || nome : nil
  end
end
