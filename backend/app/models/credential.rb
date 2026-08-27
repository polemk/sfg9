class Credential < ApplicationRecord
  # Rails 7+ Active Record Encryption
  encrypts :api_key, deterministic: false

  # Validations
  validates :name, presence: true, uniqueness: true
  # DEC-61: a allowlist deixa de ser só de provedor de IA. As chaves de terceiro do
  # Safegold (ReceitaWS, Google Maps) passam a viver aqui, encriptadas, gerenciáveis
  # por tela e trocáveis sem deploy — o cliente troca a própria chave da ReceitaWS,
  # que é paga por consulta (DEC-46).
  # `dkim` guarda a **chave privada de assinatura de e-mail** (S13 / OPS-485).
  # Ela entra aqui, e não num arquivo `.pem`, porque no legado o arquivo estava
  # versionado no repositório — chave de assinatura versionada é chave
  # comprometida. Aqui ela é encriptada, trocável por tela e nunca aparece no
  # `git log`. Ver `app/lib/sfg/dkim_signer.rb`.
  PROVIDERS = %w[openai anthropic google openai_whisper receitaws google_maps dkim].freeze

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :api_key, presence: true

  # Scopes
  scope :by_provider, ->(provider) { where(provider: provider) }

  # Returns masked version of API key for display
  def masked_api_key
    return nil if api_key.blank?

    key = api_key.to_s
    if key.length > 8
      "#{key[0, 4]}...#{key[-4, 4]}"
    else
      "#{key[0, 2]}...#{key[-2, 2]}"
    end
  end
end
