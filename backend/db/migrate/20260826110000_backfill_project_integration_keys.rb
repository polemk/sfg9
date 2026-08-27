# frozen_string_literal: true

# S4 — **backfill de `projects.integration_key`**.
#
# A migration `AddProjectDomainColumns` acrescentou a coluna, e o model passou a
# exigi-la. As linhas que já existiam (as da S0 e as do seed de demonstração da
# S20) nasceram antes da coluna e ficaram com `NULL` — e qualquer `update` nelas
# passou a falhar com "Integration key não pode ficar em branco".
#
# **É a Regra de fronteira aplicada a dado, não a código.** Acrescentar uma
# validação obrigatória é mudar o contrato de escrita do model: quem já estava
# gravado precisa ser levado ao contrato novo no MESMO passo. Apareceu rodando —
# o seed de verificação da fatia quebrou no primeiro `save` de um projeto
# existente, com `rspec` inteiro verde (a suíte cria projeto do zero e portanto
# nunca vê o caso).
#
# A chave é derivada do nome pela MESMA regra do model (`GlobalCatalog.slugify`),
# com desambiguação por sufixo numérico quando duas colidem — o índice é único.
class BackfillProjectIntegrationKeys < ActiveRecord::Migration[8.0]
  def up
    usadas = select_values('SELECT integration_key FROM projects WHERE integration_key IS NOT NULL').to_set

    select_rows('SELECT id, name FROM projects WHERE integration_key IS NULL OR integration_key = %s' % quote(''))
      .each do |id, name|
      base = I18n.transliterate(name.to_s).downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
      base = "projeto_#{id.to_s.delete('-')[0, 8]}" if base.blank?

      candidata = base
      sufixo = 2
      while usadas.include?(candidata)
        candidata = "#{base}_#{sufixo}"
        sufixo += 1
      end
      usadas << candidata

      execute("UPDATE projects SET integration_key = #{quote(candidata)} WHERE id = #{quote(id)}")
      say "projeto #{name.inspect} -> #{candidata}"
    end
  end

  # Irreversível de propósito: desfazer significaria apagar a chave de
  # integração de projetos em uso, e chave de integração é o que consumidor
  # externo guarda. O `down` volta a coluna a NULL só onde ela foi preenchida
  # por esta migration — o que não é distinguível depois. Não vale o risco.
  def down
    raise ActiveRecord::IrreversibleMigration,
          'Apagar chave de integração de projeto em uso quebra consumidor externo (DEC-85).'
  end
end
