# frozen_string_literal: true

# S4 / OPS-055, OPS-089 — as duas correções de dado que o legado fazia **à mão,
# no console de produção**.
#
# `fix_after_global_remove`, `fix__7412` e `fix_company_links` eram métodos
# soltos que alguém rodava colando no `rails c`: sem pré-visualização, sem log,
# sem forma de saber depois o que mudou. Uma delas fazia `update_all` — que não
# passa por validação, não passa por callback e não deixa versão na trilha.
#
# As três regras destas tarefas, e valem para qualquer correção de dado futura:
#
# 1. **`DRY_RUN=1` é o DEFAULT.** Rodar sem argumento **não altera nada**: mostra
#    o que faria. Para aplicar é preciso `APPLY=1`, explicitamente.
# 2. **Passa pelo model.** `save!`, nunca `update_all` — assim a trilha
#    (`paper_trail`) registra, e a validação continua valendo. Uma correção que
#    contorna a validação é como se cria a linha que ninguém consegue editar
#    pela tela depois.
# 3. **Log persistente**, com o antes e o depois de cada linha tocada.
#
# Uso:
#     bin/rails sfg:fix_company_links            # pré-visualização
#     APPLY=1 bin/rails sfg:fix_company_links    # aplica
namespace :sfg do
  # ---------------------------------------------------------------- OPS-055
  desc 'Empresas órfãs e sem "Empresa Padrão" — pré-visualiza; APPLY=1 aplica'
  task fix_company_links: :environment do
    aplicar = ENV['APPLY'] == '1'
    registro = Sfg::FixLog.new('fix_company_links', aplicar)

    # 1. Projeto sem NENHUMA empresa. O legado criava a "Empresa Padrão" no
    #    `after_create` do model; projeto criado por seed, por ETL ou por
    #    console ficava sem — e a tela de recebíveis não tinha o que oferecer.
    Project.left_joins(:companies).where(companies: { id: nil }).find_each do |projeto|
      registro.linha("projeto #{projeto.slug}", 'sem empresa', 'cria "Empresa Padrão"')
      next unless aplicar

      Company.create!(project: projeto, title: 'Empresa Padrão')
    end

    # 2. Empresa com título em branco ou com espaço sobrando. O legado não
    #    normalizava, e "Alfa " e "Alfa" conviviam apesar da unicidade.
    Company.where("title <> btrim(title) OR btrim(title) = ''").find_each do |empresa|
      novo = empresa.title.to_s.strip
      novo = "Empresa #{empresa.id.to_s.delete('-')[0, 8]}" if novo.blank?
      registro.linha("empresa #{empresa.id}", empresa.title.inspect, novo.inspect)
      next unless aplicar

      empresa.update!(title: novo)
    end

    registro.encerrar!
  end

  # ---------------------------------------------------------------- OPS-089
  desc 'Dados do projeto: chave, slug e UF fora de forma — pré-visualiza; APPLY=1 aplica'
  task fix_project_data: :environment do
    aplicar = ENV['APPLY'] == '1'
    registro = Sfg::FixLog.new('fix_project_data', aplicar)

    Project.find_each do |projeto|
      correcoes = {}

      if projeto.integration_key.blank?
        correcoes[:integration_key] = GlobalCatalog.slugify(projeto.name)
      end

      uf = projeto.address_state.to_s.strip.upcase.presence
      correcoes[:address_state] = uf if uf != projeto.address_state

      cep = projeto.cep.to_s.gsub(/\D/, '')
      if cep.length == 8
        formatado = "#{cep[0, 5]}-#{cep[5, 3]}"
        correcoes[:cep] = formatado if formatado != projeto.cep
      end

      next if correcoes.empty?

      correcoes.each { |campo, valor| registro.linha("projeto #{projeto.slug}.#{campo}", projeto.public_send(campo).inspect, valor.inspect) }
      next unless aplicar

      projeto.assign_attributes(correcoes)
      projeto.save!
    end

    registro.encerrar!
  end
end
