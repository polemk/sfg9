# frozen_string_literal: true

require 'rails_helper'

# Havia TRÊS caminhos de rich text com três histórias de sanitização diferentes:
# contrato sanitizava no servidor, instrução de indicador só no cliente (com
# sanitizador escrito à mão), e nota de projeto não sanitizava — o comentário
# dizia que "o ActionText recusa anexo no servidor", o que não é sanitizar.
#
# Três allowlists valem pela mais fraca. Estes testes travam a única.
RSpec.describe Sfg::RichText do
  describe '.sanitize' do
    it 'desarma `<script>`: sobra TEXTO inerte, nunca a tag' do
      limpo = described_class.sanitize('<p>oi</p><script>alert(1)</script>')

      expect(limpo).to include('oi')
      expect(limpo).not_to include('<script')
      # O corpo do script sobrevive como texto visível (`alert(1)`), e isso é
      # seguro: texto não executa. Afirmar que a string `alert` some seria exigir
      # o comportamento errado do sanitizador — o que importa é não haver TAG.
      expect(limpo).to eq('<p>oi</p>alert(1)')
    end

    # Vetores conhecidos, medidos contra este sanitizador.
    #
    # A verificação é **no DOM, não por string**. Casar texto na saída dá falso
    # positivo e falso negativo: o caso do `noscript` produz
    # `<p title="</noscript><img src=x onerror=alert(1)>">`, onde `onerror=`
    # aparece como TEXTO dentro de um atributo entre aspas — inerte na
    # reinterpretação, mas um `include('onerror')` reprova. O que importa é se
    # sobrou ELEMENTO executável ou ATRIBUTO de evento.
    VETORES = {
      'script com tag dentro' => '<script>var x = "</script><img src=x onerror=alert(1)>"</script>',
      'svg com onload' => '<svg onload=alert(1)></svg>',
      'mXSS por style dentro de svg' => '<svg></p><style><a id="</style><img src=1 onerror=alert(1)>"></style></svg>',
      'noscript quebrando atributo' => '<noscript><p title="</noscript><img src=x onerror=alert(1)>">',
      'href javascript:' => '<a href="javascript:alert(1)">x</a>',
      'href javascript: com tabulacao no meio' => %Q{<a href="java\tscript:alert(1)">x</a>},
      'href data: com html embutido' => '<a href="data:text/html,<script>alert(1)</script>">x</a>',
      'form de phishing' => '<form action="//mal"><input name="senha"></form>',
    }.freeze

    VETORES.each do |nome, bruto|
      it "neutraliza: #{nome}" do
        # Reinterpreta a saída como o navegador faria — é onde o mXSS aparece.
        doc = Nokogiri::HTML5.fragment(described_class.sanitize(bruto))

        eventos = doc.css('*').flat_map { |n| n.attribute_nodes.map(&:name) }.grep(/\Aon/i)
        expect(eventos).to be_empty, "sobrou atributo de evento: #{eventos.inspect}"

        expect(doc.css('script, style, iframe, object, embed, form, svg, math')).to be_empty

        perigosos = doc.css('a[href], img[src]').map { |n| n['href'] || n['src'] }
        expect(perigosos.grep(/\A\s*(javascript|data|vbscript):/i)).to be_empty
      end
    end

    it 'remove atributo de evento' do
      limpo = described_class.sanitize('<p onclick="roubar()">texto</p>')
      expect(limpo).to include('texto')
      expect(limpo).not_to include('onclick')
    end

    it 'remove `onerror` em imagem — o vetor mais usado' do
      limpo = described_class.sanitize('<img src="x" onerror="alert(1)">')
      expect(limpo).not_to include('onerror')
    end

    it 'remove `<iframe>`, `<style>`, `<object>` e `<form>`' do
      bruto = '<iframe src="//mal"></iframe><style>*{}</style><object></object><form action="//mal"></form>'
      limpo = described_class.sanitize(bruto)
      %w[iframe style object form].each { |t| expect(limpo).not_to include("<#{t}") }
    end

    it 'preserva a formatação que o editor produz' do
      bruto = '<p><strong>negrito</strong> e <em>itálico</em></p><ul><li>um</li></ul>'
      limpo = described_class.sanitize(bruto)
      expect(limpo).to include('<strong>', '<em>', '<ul>', '<li>')
    end

    it 'preserva tabela — contrato e instrução usam' do
      limpo = described_class.sanitize('<table><tbody><tr><td colspan="2">a</td></tr></tbody></table>')
      expect(limpo).to include('<table>', '<td', 'colspan')
    end

    it 'devolve string vazia para nulo e para branco, nunca nil' do
      expect(described_class.sanitize(nil)).to eq('')
      expect(described_class.sanitize('')).to eq('')
      expect(described_class.sanitize('   ')).to eq('')
    end

    it 'aceita ActionText sem o chamador precisar converter' do
      projeto = Project.new
      projeto.availability_note = '<p>nota</p>'
      expect(described_class.sanitize(projeto.availability_note.body)).to include('nota')
    end
  end

  describe 'a allowlist é UMA' do
    it '`Contracts::Renderer` aponta para esta, não tem a própria cópia' do
      # Duas listas que "por acaso" são iguais divergem no primeiro ajuste, e o
      # ajuste sempre acontece num lugar só.
      expect(Contracts::Renderer::ALLOWED_TAGS).to be(described_class::ALLOWED_TAGS)
      expect(Contracts::Renderer::ALLOWED_ATTRIBUTES).to be(described_class::ALLOWED_ATTRIBUTES)
    end

    it 'não permite as tags que executam código' do
      %w[script style iframe object embed form].each do |t|
        expect(described_class::ALLOWED_TAGS).not_to include(t)
      end
    end

    it 'não permite nenhum atributo `on*`' do
      expect(described_class::ALLOWED_ATTRIBUTES.grep(/\Aon/)).to be_empty
    end
  end
end
