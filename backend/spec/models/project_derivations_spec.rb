# frozen_string_literal: true

require 'rails_helper'

# **BE-095 / BE-096 — o que o projeto DERIVA sozinho, e o que ele recusa.**
#
# A conferência de paridade da Phase 4 travou os dois: `slug` e
# `integration_key` tinham exemplo, e `color` tinha **zero** (`grep -c color` no
# spec de projetos dava 0). As validações novas de `cep`, `color` e
# `address_state` também não tinham nenhuma.
#
# São três derivações que acontecem **uma vez, na criação**, e depois viram
# história: o `slug` entra em URL, o `integration_key` pode estar em uso por um
# sistema externo, e a cor identifica o projeto na tela. Derivação errada aqui
# não quebra nada na hora — ela aparece semanas depois, num link que não abre.
RSpec.describe 'Project — derivações e validações (BE-095 / BE-096)' do
  # ---------------------------------------------------------------- slug
  describe 'slug' do
    it 'sai do NOME, transliterado e em minúsculas' do
      projeto = create(:project, name: 'Açúcar & Cia. Ltda', slug: nil)

      expect(projeto.slug).to eq('acucar-cia-ltda')
    end

    # **Este exemplo custou duas tentativas, e as duas ensinaram algo.**
    #
    # Escrevi primeiro com dois projetos de MESMO nome: `name` é único, então
    # aquele caminho não existe. Reescrevi com nomes diferentes que
    # transliteram igual (`Açúcar` / `Acucar`) e falhou de novo — desta vez em
    # `integration_key`, que o ai9 validou como **único** e que deriva do nome
    # pelo mesmo caminho.
    #
    # ⚠ Consequência, registrada: **o laço de desambiguação do slug é
    # inalcançável pelo caminho comum.** Ele só roda quando a chave de
    # integração é informada à mão, como aqui. O `integration_key` barra antes,
    # e ele **não tem** laço nenhum — o segundo projeto é recusado com "já está
    # em uso" em vez de ganhar sufixo.
    #
    # O legado valida unicidade só em `formal` (o nome). A unicidade de
    # `integration_key` é acréscimo do ai9, sem decisão registrada.
    it 'desambigua quando nomes DIFERENTES caem no mesmo slug' do
      primeiro = create(:project, name: 'Açúcar', slug: nil, integration_key: 'acucar_um')
      segundo = create(:project, name: 'Acucar', slug: nil, integration_key: 'acucar_dois')

      expect(primeiro.slug).to eq('acucar')
      # Regra do legado, replicada: o sufixo entra no NOME antes de
      # transliterar (`Acucar 2` → `acucar-2`), e não é colado no slug pronto.
      expect(segundo.slug).to eq('acucar-2')
    end

    # A imutabilidade vale no MODEL, não só na ausência do campo no `permit`:
    # um job, um seed ou um `update` distraído também não podem trocar a URL de
    # um projeto em produção.
    it 'é CONGELADO na edição — nem pelo model se troca' do
      projeto = create(:project, name: 'Original', slug: nil)
      original = projeto.slug

      projeto.update!(slug: 'outro-endereco')

      expect(projeto.reload.slug).to eq(original)
    end

    it 'aceita `&` e `.` vindos da carga, que o legado permitia' do
      # DEC-122: os dois projetos de produção tinham esses caracteres. A
      # validação foi alargada para não recusar dado que existe.
      projeto = build(:project, slug: 'acucar-&-cia.ltda')

      expect(projeto).to be_valid
    end
  end

  # ------------------------------------------------------- integration_key
  describe 'integration_key' do
    it 'sai do nome na criação' do
      projeto = create(:project, name: 'Aço Norte Fomento', integration_key: nil)

      expect(projeto.integration_key).to eq(GlobalCatalog.slugify('Aço Norte Fomento'))
      expect(projeto.integration_key).to be_present
    end

    it 'o valor informado VENCE a derivação' do
      projeto = create(:project, name: 'Qualquer', integration_key: 'chave_do_erp')

      expect(projeto.integration_key).to eq('chave_do_erp')
    end
  end

  # --------------------------------------------------------------- color
  describe 'color (BE-095 — não tinha um exemplo)' do
    it 'é sorteada na criação, e sempre da PALETA' do
      projeto = create(:project, color: nil)

      expect(projeto.color).to be_present
      expect(Project::PALETTE).to include(projeto.color)
    end

    # O legado usava `ColorGenerator` (HSL aleatório), que às vezes produzia cor
    # ilegível sobre o fundo claro. A paleta fixa é a correção — e é ela que
    # este exemplo trava.
    it 'a cor informada é respeitada, se for hexadecimal de 6 dígitos' do
      projeto = create(:project, color: '#1A2B3C')

      expect(projeto.color).to eq('#1A2B3C')
    end

    it 'recusa o que não é hexadecimal de 6 dígitos' do
      %w[vermelho #FFF #GGGGGG rgb(1,2,3)].each do |invalida|
        projeto = build(:project, color: invalida)

        expect(projeto).not_to be_valid, "aceitou #{invalida.inspect}"
        expect(projeto.errors[:color]).to be_present
      end
    end
  end

  # --------------------------------------------------- endereço (BE-096)
  describe 'endereço' do
    it 'o CEP é normalizado para `00000-000`, venha como vier' do
      %w[86300000 86300-000 86.300-000].each do |entrada|
        projeto = create(:project, cep: entrada)

        expect(projeto.cep).to eq('86300-000')
      end
    end

    # D-PAR-01 — o legado NÃO validava CEP, e a produção tem 3 projetos com 7
    # dígitos. A carga os traz VAZIOS e listados (DEC-128.1); pela tela, o
    # servidor recusa em vez de gravar um CEP que não existe.
    it 'CEP fora de 8 dígitos é RECUSADO pela tela' do
      projeto = build(:project, cep: '8630000')

      expect(projeto).not_to be_valid
      expect(projeto.errors[:cep].join).to match(/8 d[ií]gitos/)
    end

    it 'CEP vazio é permitido — o endereço não é obrigatório' do
      expect(build(:project, cep: '')).to be_valid
      expect(build(:project, cep: nil)).to be_valid
    end

    it 'a UF é normalizada para MAIÚSCULA' do
      expect(create(:project, address_state: 'pr').address_state).to eq('PR')
    end

    it 'UF vazia vira NULA, e não string vazia' do
      # Uma coluna com `''` e outra com `NULL` significando a mesma coisa é como
      # um relatório passa a ter duas categorias de "sem UF".
      expect(create(:project, address_state: '  ').address_state).to be_nil
    end
  end
end
