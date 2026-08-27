# frozen_string_literal: true

module Demo
  module Writers
    # As 5 contrapartes e os grupos a que pertencem. Chave natural: `bank_code`.
    #
    # `bank_code` é **string** no ai9 (DC-12), justamente para preservar zeros à
    # esquerda — e os códigos daqui (894/907/912/923/936) são **não atribuídos**,
    # nunca 001/237/341.
    class Carriers < Base
      def self.requires = %w[Carrier]
      def self.owner_slice = 'S3'

      def call
        groups = upsert_groups!

        ledger.carriers.each do |carrier|
          upsert!(::Carrier, find_by: { bank_code: carrier.bank_code }, attributes: {
                    title: carrier.title,
                    financial_agent: carrier.financial_agent,
                    group_id: groups[carrier.group]&.id,
                    net_worth: carrier.net_worth,
                    senior_accounts: carrier.senior_accounts,
                    subordinated_accounts: carrier.subordinated_accounts,
                    # `subordinated_accounts_percent` **não é escrito aqui**: a S3
                    # entregou o cálculo e a coluna passou a ser DERIVADA no servidor
                    # (DC-09), a partir das cotas acima. O razão continua guardando
                    # `subordinated_percent` como referência da história, mas gravá-lo
                    # faria o escritor propor um valor que o model recalcula no
                    # `save` — e o seed reportaria "atualizado" a cada execução,
                    # quebrando a própria prova de idempotência.
                    city: carrier.city,
                    uf: carrier.uf,
                    integration_key: carrier.key.to_s,
                    is_active: true
                  })
        end
      end

      private

      def upsert_groups!
        return {} unless defined?(::CarrierGroup)

        ledger.carriers.map(&:group).uniq.compact.to_h do |title|
          [title, upsert!(::CarrierGroup, find_by: { title: title }, attributes: { is_active: true })]
        end
      end
    end
  end
end
