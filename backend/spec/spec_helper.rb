# frozen_string_literal: true

require 'simplecov'
SimpleCov.start 'rails' do
  # Excluir integrações externas do cálculo de cobertura
  add_filter '/app/services/evolution_connection.rb'
  add_filter '/app/services/polemk_chat_service.rb'
  add_filter '/app/services/polemk_group_service.rb'
  add_filter '/app/services/polemk_webhook_service.rb'
  add_filter '/app/services/n8n/'
  add_filter '/app/services/fake_data/'
  add_filter '/app/mailers/'
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
