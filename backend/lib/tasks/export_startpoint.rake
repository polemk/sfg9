namespace :export do
  desc "Exports local plans, agents, configs AND credentials to production_startpoint.rb safely"
  task startpoint: :environment do
    startpoint_file = Rails.root.join('db', 'seeds', 'production_startpoint.rb')
    FileUtils.mkdir_p(File.dirname(startpoint_file))
    
    # Blocos 5 e 7 do trim: `Integration` (AI9-009) e `Operation` (AI9-014) saíram
    # daqui. `SupportPlan`, `Plan`,
    # `PlanFeature` e `PlanFeatureAssignment` (AI9-002) já não existiam desde o Bloco 4 e
    # ficaram pendurados — o `next unless defined?(model)` abaixo nunca protegeu nada,
    # porque o NameError acontece ao montar este array. Corrigido junto.
    models_to_export = [
      Credential,
      ClientApplication,
      ChatFlow
    ]

    File.open(startpoint_file, 'w') do |f|
      f.puts "# ==========================================================================="
      f.puts "# ARQUIVO GERADO AUTOMATICAMENTE POR: rake export:startpoint"
      f.puts "# DATA: #{Time.current}"
      f.puts "# AVISO: ESTE ARQUIVO CONTÉM CREDENCIAIS REAIS E ESTÁ IGNORADO NO GIT (.gitignore)"
      f.puts "# ==========================================================================="
      f.puts
      f.puts "puts '🚀 Iniciando setup do Startpoint de Producao...'"
      
      models_to_export.each do |model|
        next unless defined?(model)
        
        records = model.all.map do |record|
          # Removendo timestamps
          record.attributes.except('created_at', 'updated_at')
        end
        
        f.puts "records_#{model.table_name} = ["
        records.each do |attr|
          # Using `.inspect` dumps the ruby hashes correctly (dates as strings etc)
          f.puts "  #{attr.inspect},"
        end
        f.puts "]"
        f.puts
      end

      f.puts "puts 'Limpando dados existentes onde possivel (respeitando foreign keys)...'"
      models_to_export.reverse.each do |model|
        f.puts "if defined?(#{model.name}) && #{model.name}.table_exists?"
        f.puts "  begin"
        f.puts "    #{model.name}.delete_all"
        f.puts "  rescue ActiveRecord::InvalidForeignKey, PG::ForeignKeyViolation"
        f.puts "    puts '  -> Pulando exclusao total de #{model.name} pois ha registros dependentes. Fara upsert pontual.'"
        f.puts "  end"
        f.puts "end"
      end
      f.puts

      f.puts "puts 'Inserindo ou atualizando dados do startpoint (UPSERT)...'"
      models_to_export.each do |model|
        f.puts "if defined?(#{model.name}) && #{model.name}.table_exists?"
        f.puts "  puts 'Processando #{model.name}...'"
        f.puts "  if records_#{model.table_name}.any?"
        f.puts "    #{model.name}.upsert_all(records_#{model.table_name})"
        f.puts "  end"
        f.puts "end"
        f.puts
      end
      
      f.puts "puts '✅ Startpoint importado com sucesso! Banco base atualizado.'"
    end
    
    puts "✅ Seed startpoint gerado am #{startpoint_file}"
    puts "⚠️  ATENÇÃO: O arquivo gerado contém credenciais e tokens. Ele foi adicionado ao .gitignore para sua segurança."
    puts "Para transportá-lo para a produção, utilize SCP ou copie e cole o conteúdo pelo servidor."
  end
end
