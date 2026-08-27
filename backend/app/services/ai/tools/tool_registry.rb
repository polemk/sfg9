# frozen_string_literal: true

# Central registry for AI tool/function calling definitions.
# Tools are grouped into CAPABILITIES that can be enabled per-agent via
# agent_config (e.g. ['console_help', 'console_data']).
#
# @example
#   Ai::Tools::ToolRegistry.definitions_for('anthropic', ['console_help'])
module Ai
  module Tools
    class ToolRegistry
      # HISTÓRICO — o registro ficou VAZIO entre o trim e esta mudança.
      #
      # - `lead_capture` (`capture_lead` + `redirect_to_dashboard`) saiu no Bloco 6
      #   com o AI9-006: `capture_lead` gravava no `Lead`, e `redirect_to_dashboard`
      #   só existia como passo seguinte dela.
      # - `assets` (`search_operation_assets` + `list_all_operation_assets`) saiu no
      #   Bloco 7 com o AI9-014: as duas liam `OperationAsset` por embedding.
      #
      # O que ficou de propósito foi a máquina de formatação por provider
      # (`format_specs`), o núcleo multi-provider do AI9-007 que o DEC-13.2 manda
      # manter — e este arquivo foi deixado como **o ponto de extensão do
      # assistente interno**. É esse ponto que as duas capabilities abaixo usam.
      #
      # ## Duas capabilities, e a separação não é cosmética
      #
      # `console_help` lê o ACERVO DE AJUDA (FAQ e ajuda de campo): conteúdo que
      # alguém escreveu para ser lido, igual para todo mundo. `console_data` lê o
      # DADO OPERACIONAL do projeto corrente: número que muda de pessoa para
      # pessoa e de projeto para projeto.
      #
      # Estão separadas para que ligar o assistente de ajuda não implique abrir o
      # dado — quem administra o fluxo escolhe uma, a outra ou as duas em
      # `agent_config['capabilities']`, e a escolha é auditável ali.
      #
      # ## Toda ferramenta é de LEITURA
      #
      # Não há, e não deve haver, ferramenta que grave. O uso definido no
      # DEC-13.2 é ajuda ao operador; uma escrita disparada por conversa entraria
      # na trilha de auditoria como ato do usuário sem que ele tenha preenchido o
      # formulário que a tela exige. Quem decide grava na tela.
      CAPABILITY_TOOLS = {
        'console_help' => [
          {
            name: 'search_faq',
            description: 'Busca na central de ajuda (FAQ) do sistema pelo termo informado. ' \
                         'Use SEMPRE antes de explicar como uma tela ou um procedimento funciona, ' \
                         'para responder com o que está escrito no acervo em vez de supor. ' \
                         'Zero resultado é resposta: quer dizer que o acervo não cobre o assunto.',
            parameters: {
              type: 'object',
              properties: {
                term: { type: 'string', description: 'Termo ou expressão a buscar (ex.: "borderô", "deságio", "limite no teto")' },
                limit: { type: 'integer', description: 'Quantos itens devolver (1 a 10, padrão 5)' }
              },
              required: ['term']
            }
          },
          {
            name: 'read_faq_item',
            description: 'Lê o conteúdo completo de UM item da central de ajuda, pelo id devolvido por search_faq. ' \
                         'Use quando o trecho da busca não bastar para responder.',
            parameters: {
              type: 'object',
              properties: {
                id: { type: 'string', description: 'Id do item, vindo de search_faq' }
              },
              required: ['id']
            }
          },
          {
            name: 'field_help',
            description: 'Devolve a ajuda de campo (o texto do tooltip) dos formulários que a possuem. ' \
                         'Sem o parâmetro field, devolve o formulário inteiro — use assim para responder ' \
                         '"o que significa cada campo desta tela".',
            parameters: {
              type: 'object',
              properties: {
                scope: {
                  type: 'string',
                  enum: ::Help::FieldHelp::SCOPES,
                  description: 'Formulário: receivables (borderô), risk_operations ou structured_operations'
                },
                field: { type: 'string', description: 'Nome do campo. Omita para receber todos os campos do formulário.' }
              },
              required: ['scope']
            }
          }
        ].freeze,
        'console_data' => [
          {
            name: 'project_snapshot',
            description: 'Retrato do PROJETO CORRENTE numa data: total operado no período, exposição, ' \
                         'limites no teto, renegociações em atraso, a série mensal do total operado, ' \
                         'os limites por tipo e quais estão perto do teto. ' \
                         'É a mesma fonte do painel — use para qualquer pergunta sobre "como estamos". ' \
                         'Campos com has_value falso significam que NÃO HÁ lançamento, o que é diferente de zero. ' \
                         'O que estiver listado em hidden_by_role foi omitido por falta de permissão do perfil, ' \
                         'não por falta de dado.',
            parameters: {
              type: 'object',
              properties: {
                date: { type: 'string', description: 'Data de apuração em AAAA-MM-DD. Padrão: hoje.' },
                months: { type: 'integer', description: 'Meses da janela do total operado (1 a 36, padrão 12)' }
              },
              required: []
            }
          },
          {
            name: 'overdue_renegotiations',
            description: 'Lista as renegociações do projeto corrente com parcela vencida numa data, ' \
                         'da que tem mais parcelas vencidas para a que tem menos. ' \
                         'O painel mostra só as seis primeiras; use esta ferramenta quando a pergunta for ' \
                         '"quais" e não "quantas". O campo total é o número real, antes do corte.',
            parameters: {
              type: 'object',
              properties: {
                date: { type: 'string', description: 'Data de apuração em AAAA-MM-DD. Padrão: hoje.' },
                limit: { type: 'integer', description: 'Quantas linhas devolver (1 a 30, padrão 30)' }
              },
              required: []
            }
          },
          {
            name: 'volume_by_carrier',
            description: 'Exposição acumulada por PORTADOR no projeto corrente numa data — a pergunta de ' \
                         'concentração ("quem concentra o risco"). Lista vazia quer dizer que não há limite ' \
                         'ativo no projeto, que é diferente de todos os portadores estarem zerados.',
            parameters: {
              type: 'object',
              properties: {
                date: { type: 'string', description: 'Data de apuração em AAAA-MM-DD. Padrão: hoje.' }
              },
              required: []
            }
          }
        ].freeze
      }.freeze

      # Returns tool definitions formatted for the given provider, for the enabled capabilities.
      # @param provider_name [String] 'anthropic', 'openai', or 'google'
      # @param capabilities [Array<String>] enabled capability names
      # @return [Array<Hash>] tool definitions in provider-specific format
      def self.definitions_for(provider_name, capabilities = [])
        specs = Array(capabilities).map(&:to_s).uniq.flat_map { |cap| CAPABILITY_TOOLS[cap] || [] }
        return [] if specs.empty?

        format_specs(provider_name, specs)
      end

      # Formats neutral specs ({name, description, parameters}) for each provider's API.
      def self.format_specs(provider_name, specs)
        case provider_name.to_s
        when 'anthropic'
          specs.map { |s| { name: s[:name], description: s[:description], input_schema: s[:parameters] } }
        when 'openai'
          specs.map { |s| { type: 'function', function: { name: s[:name], description: s[:description], parameters: s[:parameters] } } }
        when 'google'
          [{ functionDeclarations: specs.map { |s| { name: s[:name], description: s[:description], parameters: s[:parameters] } } }]
        else
          []
        end
      end
    end
  end
end
