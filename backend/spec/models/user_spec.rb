require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_presence_of(:user_type_id) }
    
    # Custom validations
    it 'validates presence of email or phone' do
      user = build(:user, email: nil, phone: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("não pode ficar em branco")
      expect(user.errors[:phone]).to include("não pode ficar em branco")
    end

    it 'allows valid email' do
      user = build(:user, email: 'test@example.com')
      expect(user).to be_valid
    end

    it 'allows valid phone' do
      user = build(:user, phone: '5511999999999', email: nil)
      expect(user).to be_valid
    end
    
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive.allow_blank }
    it 'validates uniqueness of phone' do
      create(:user, phone: '5511999999999')
      user_dup = build(:user, phone: '5511999999999')
      expect(user_dup).not_to be_valid
      expect(user_dup.errors[:phone]).to include('já está em uso')
    end

    
    it { is_expected.to validate_inclusion_of(:provider).in_array(%w[email whatsapp google facebook]).allow_nil }
    it { is_expected.to validate_uniqueness_of(:provider_uid).scoped_to(:provider).allow_nil }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user_type) }
    it { is_expected.to have_many(:login_codes).dependent(:destroy) }
    it { is_expected.to have_many(:login_attempts).dependent(:destroy) }
    it { is_expected.to have_many(:user_permissions).dependent(:destroy) }
    it { is_expected.to have_rich_text(:biography) }
  end

  describe 'normalizers' do
    it 'normalizes email to lowercase' do
      user = create(:user, email: 'TeSt@ExAmPlE.cOm')
      expect(user.email).to eq('test@example.com')
    end

    it 'normalizes phone' do
      user = create(:user, phone: '(55) 11 99999-9999', email: nil)
      expect(user.phone).to eq('5511999999999')
    end
  end

  describe 'scopes' do
    let!(:user_email) { create(:user, email: 'test@example.com') }
    let!(:user_phone) { create(:user, phone: '5511999999999', email: nil) }
    let!(:inactive_user) { create(:user, last_login_at: nil) }
    let!(:active_user) { create(:user, last_login_at: Time.current) }

    it 'finds by email' do
      expect(User.by_email('TEST@EXAMPLE.COM')).to include(user_email)
    end

    it 'finds by phone' do
      expect(User.by_phone('5511999999999')).to include(user_phone)
    end

    it 'filters active users' do
      expect(User.active).to include(active_user)
      expect(User.active).not_to include(inactive_user)
    end
  end
  
  describe 'class methods' do
    # DEC-41: os papéis são os 4 do Safegold. `UserType.default_type` é o
    # Colaborador, e é ele que `find_or_create_by_*` atribui a quem chega sem
    # papel explícito (DEC-18.8).
    before { UserType.seed_default_types! }


    # **`find_or_create_by_email` e `find_or_create_by_phone` FORAM REMOVIDOS.**
    #
    # Eram duas portas de auto-cadastro que a DEC-49 não fechou porque não estavam em
    # `api/root.rb`: qualquer chamador que passasse um e-mail ganhava um usuário novo.
    # Entrada é só por convite (DEC-18.7). O que sobra é `find_for_identifier`, que
    # **só casa**.
    describe '.find_for_identifier (DEC-45 — três chaves de identidade)' do
      let!(:user) { create(:user, email: 'joao@example.com', phone: '5511988887777', username: 'joao.silva') }

      it 'casa por e-mail' do
        expect(User.find_for_identifier('JOAO@example.com')).to eq(user)
      end

      it 'casa por telefone, com ou sem máscara' do
        expect(User.find_for_identifier('+55 (11) 98888-7777')).to eq(user)
      end

      it 'casa por username, sem diferenciar caixa' do
        expect(User.find_for_identifier('Joao.Silva')).to eq(user)
      end

      it 'não cria ninguém quando não acha' do
        expect { expect(User.find_for_identifier('ninguem@example.com')).to be_nil }
          .not_to change(User, :count)
      end
    end

    # DEC-44 — o login social **casa, nunca cria**. Se criasse, o D-39 voltaria por
    # esta porta enquanto as 4 rotas removidas ficassem fechadas.
    describe '.find_for_oauth' do
      it 'casa por (provider, uid)' do
        user = create(:user, email: 'g@example.com', provider: 'google', provider_uid: 'uid-1')
        expect(User.find_for_oauth('google', 'uid-1', { email: 'outro@example.com' })).to eq(user)
      end

      it 'casa por e-mail e grava o vínculo no primeiro login social' do
        user = create(:user, email: 'g2@example.com')
        expect(User.find_for_oauth('google', 'uid-2', { email: 'G2@example.com' })).to eq(user)
        expect(user.reload.provider_uid).to eq('uid-2')
      end

      it 'NÃO cria conta para e-mail desconhecido' do
        expect {
          expect(User.find_for_oauth('google', 'uid-3', { email: 'novo@example.com', name: 'Novo' })).to be_nil
        }.not_to change(User, :count)
      end

      it 'NÃO casa por nome — homônimo não assume conta alheia' do
        create(:user, email: 'joao.silva.1@example.com', name: 'João Silva')
        expect {
          expect(User.find_for_oauth('google', 'uid-4', { email: nil, name: 'João Silva' })).to be_nil
        }.not_to change(User, :count)
      end
    end
  end

  # DEC-45 — a coluna é nullable, com índice único PARCIAL, e o formato é restrito
  # para não colidir com os outros dois canais na mesma caixa de texto.
  describe 'username' do
    before { UserType.seed_default_types! }

    it 'aceita nulo em qualquer quantidade de usuários' do
      create(:user, email: 'a@example.com', username: nil)
      expect { create(:user, email: 'b@example.com', username: nil) }.not_to raise_error
    end

    it 'recusa duplicata' do
      create(:user, email: 'c@example.com', username: 'repetido')
      dup = build(:user, email: 'd@example.com', username: 'repetido')
      expect(dup).not_to be_valid
    end

    it 'recusa username com @ (seria um e-mail) e só-dígitos (seria um telefone)' do
      expect(build(:user, email: 'e@example.com', username: 'a@b.com')).not_to be_valid
      expect(build(:user, email: 'f@example.com', username: '5511999999999')).not_to be_valid
    end
  end

  # BE-048 / IMP-A21 — o código curto nasce com o registro e é único no BANCO.
  describe 'identifier' do
    before { UserType.seed_default_types! }

    it 'é gerado no before_create, com 6 caracteres A-Z0-9' do
      user = create(:user, email: 'ident@example.com')
      expect(user.identifier).to match(/\A[A-Z0-9]{6}\z/)
    end

    it 'a unicidade é garantida pelo índice do banco, não só pela validação' do
      first = create(:user, email: 'i1@example.com')
      second = create(:user, email: 'i2@example.com')
      expect {
        second.update_column(:identifier, first.identifier)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # DEC-39 — bloquear revoga a sessão na hora.
  describe 'bloqueio de conta' do
    before { UserType.seed_default_types! }

    let(:user) { create(:user, email: 'blk@example.com') }

    it 'grava motivo e rotaciona o jti (o access token aberto deixa de valer)' do
      old_jti = user.jti
      user.block!(reason: 'Desligado em 01/2026')
      expect(user).to be_blocked
      expect(user.blocked_reason).to eq('Desligado em 01/2026')
      expect(user.jti).not_to eq(old_jti)
    end

    it 'desbloquear limpa os dois campos' do
      user.block!(reason: 'x')
      user.unblock!
      expect(user).not_to be_blocked
      expect(user.blocked_reason).to be_nil
    end
  end

  # DEC-74 — o indicador é replicado; a trava de edição do telefone NÃO.
  describe 'confiability_level' do
    before { UserType.seed_default_types! }

    it 'sobe conforme o cadastro se completa' do
      user = create(:user, email: 'cl@example.com', phone: nil, cpf_cnpj: nil)
      expect(user.confiability_level).to eq('baixa')
      user.update!(phone: '5511911112222')
      expect(user.confiability_level).to eq('media')
      user.update!(cpf_cnpj: '39053344705')
      expect(user.confiability_level).to eq('alta')
      user.update!(is_phone_checked: true)
      expect(user.confiability_level).to eq('maxima')
    end

    it 'o telefone continua editável mesmo com is_phone_checked (DEC-74)' do
      user = create(:user, email: 'cl2@example.com', phone: '5511911112222', is_phone_checked: true)
      expect(user.update(phone: '5511933334444')).to be true
    end
  end
  
  describe 'instance methods' do
    before { UserType.seed_default_types! }

    let(:colaborador_type) { UserType.colaborador }
    let(:gerente_type) { UserType.gerente }
    let(:og_type) { UserType.og }

    it 'checks roles correctly' do
      user = create(:user, user_type: colaborador_type)
      expect(user).to be_colaborador
      expect(user).not_to be_gerente
      expect(user).not_to be_og

      user.update(user_type: gerente_type)
      expect(user).to be_gerente
      expect(user).not_to be_colaborador
      
      user.update(user_type: og_type)
      expect(user).to be_og
    end
    
    it 'returns correct display name' do
      user = create(:user, name: 'John Doe', email: 'john@example.com')
      expect(user.display_name).to eq('John Doe')
      
      user.name = nil
      expect(user.display_name).to eq('john')
    end
    it 'can store custom variables' do
      user = create(:user)
      user.update(custom_variables: { 'lead_score' => '100', 'interest' => 'shoes' })
      expect(user.reload.custom_variables).to eq({ 'lead_score' => '100', 'interest' => 'shoes' })
    end
  end
end
