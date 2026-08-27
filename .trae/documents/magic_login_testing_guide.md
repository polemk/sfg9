# Magic Login - Guia de Testes e Validação

## 1. Visão Geral dos Testes

Este documento descreve os testes necessários para garantir a qualidade e segurança do sistema Magic Login, cobrindo fluxos de autenticação via WhatsApp, email e OAuth.

## 2. Estrutura de Testes

### 2.1 Testes de Backend (RSpec)
```
spec/
├── requests/
│   ├── api/
│   │   ├── auth/
│   │   │   ├── v1/
│   │   │   │   ├── magic_login_spec.rb
│   │   │   │   ├── oauth_spec.rb
│   │   │   │   └── sessions_spec.rb
├── services/
│   ├── auth/
│   │   ├── magic_login_service_spec.rb
│   │   ├── code_validation_service_spec.rb
│   │   ├── email_service_spec.rb
│   │   └── oauth_service_spec.rb
├── models/
│   ├── user_spec.rb
│   ├── login_code_spec.rb
│   └── user_type_spec.rb
└── channels/
    └── notifications_channel_spec.rb
```

### 2.2 Testes de Frontend (Jest/React Testing Library)
```
src/
├── components/
│   ├── auth/
│   │   ├── __tests__/
│   │   │   ├── AuthContainer.test.tsx
│   │   │   ├── MagicLoginForm.test.tsx
│   │   │   ├── CodeInput.test.tsx
│   │   │   └── SocialLoginButtons.test.tsx
├── hooks/
│   ├── __tests__/
│   │   ├── useAuth.test.ts
│   │   └── useCountdown.test.ts
├── services/
│   ├── __tests__/
│   │   └── authService.test.ts
└── utils/
    ├── __tests__/
    │   └── validators.test.ts
```

## 3. Testes de Backend

### 3.1 Testes de Requisição - Magic Login
```ruby
# spec/requests/api/auth/v1/magic_login_spec.rb
require 'rails_helper'

RSpec.describe 'Magic Login API', type: :request do
  describe 'POST /api/auth/v1/magic_login/request_code' do
    context 'com email válido' do
      it 'retorna sucesso e envia código' do
        post '/api/auth/v1/magic_login/request_code', params: {
          identifier: 'test@example.com',
          method: 'email'
        }
        
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(json_response['message']).to include('Código enviado')
        
        # Verificar que código foi criado
        expect(LoginCode.count).to eq(1)
        expect(LoginCode.last.identifier).to eq('test@example.com')
      end
    end

    context 'com telefone válido' do
      it 'retorna sucesso e envia código via WhatsApp' do
        allow_any_instance_of(Auth::EmailService).to receive(:send_magic_login_code).and_return(true)
        
        post '/api/auth/v1/magic_login/request_code', params: {
          identifier: '+5511999999999',
          method: 'whatsapp'
        }
        
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
      end
    end

    context 'com identificador inválido' do
      it 'retorna erro de validação' do
        post '/api/auth/v1/magic_login/request_code', params: {
          identifier: 'email-invalido',
          method: 'email'
        }
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['error']).to include('Identificador inválido')
      end
    end

    context 'com rate limiting' do
      it 'limita requisições por IP' do
        # Simular múltiplas requisições
        6.times do
          post '/api/auth/v1/magic_login/request_code', params: {
            identifier: 'test@example.com',
            method: 'email'
          }
        end
        
        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end

  describe 'POST /api/auth/v1/magic_login/validate_code' do
    let!(:user) { create(:user, email: 'test@example.com') }
    let!(:login_code) { create(:login_code, identifier: 'test@example.com', code: '123456') }

    context 'com código válido' do
      it 'autentica usuário e retorna tokens' do
        post '/api/auth/v1/magic_login/validate_code', params: {
          identifier: 'test@example.com',
          code: '123456',
          method: 'email'
        }
        
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(json_response['token']).to be_present
        expect(json_response['user']['email']).to eq('test@example.com')
      end
    end

    context 'com código inválido' do
      it 'retorna erro de validação' do
        post '/api/auth/v1/magic_login/validate_code', params: {
          identifier: 'test@example.com',
          code: '000000',
          method: 'email'
        }
        
        expect(response).to have_http_status(:unauthorized)
        expect(json_response['error']).to include('Código inválido')
      end
    end

    context 'com código expirado' do
      it 'retorna erro de código expirado' do
        login_code.update(created_at: 6.minutes.ago)
        
        post '/api/auth/v1/magic_login/validate_code', params: {
          identifier: 'test@example.com',
          code: '123456',
          method: 'email'
        }
        
        expect(response).to have_http_status(:unauthorized)
        expect(json_response['error']).to include('expirado')
      end
    end
  end
end
```

### 3.2 Testes de Serviço
```ruby
# spec/services/auth/magic_login_service_spec.rb
require 'rails_helper'

RSpec.describe Auth::MagicLoginService do
  let(:service) { described_class.new }
  let(:user) { create(:user, email: 'test@example.com') }

  describe '#generate_code' do
    it 'gera código de 6 dígitos' do
      code = service.send(:generate_code)
      expect(code).to match(/^\d{6}$/)
    end

    it 'não gera códigos repetidos consecutivos' do
      codes = 10.times.map { service.send(:generate_code) }
      expect(codes.uniq.length).to be > 8
    end
  end

  describe '#create_login_code' do
    it 'cria registro de código com expiração' do
      login_code = service.send(:create_login_code, 'test@example.com', 'email')
      
      expect(login_code).to be_persisted
      expect(login_code.code).to match(/^\d{6}$/)
      expect(login_code.expires_at).to be > Time.current
      expect(login_code.expires_at).to be <= Time.current + 5.minutes
    end
  end

  describe '#send_magic_code' do
    context 'via email' do
      it 'envia código por email' do
        allow_any_instance_of(Auth::EmailService).to receive(:send_magic_login_code).and_return(true)
        
        result = service.send_magic_code('test@example.com', 'email')
        
        expect(result[:success]).to be true
        expect(LoginCode.count).to eq(1)
      end
    end

    context 'via WhatsApp' do
      it 'envia código por WhatsApp' do
        allow_any_instance_of(Auth::WhatsMessageService).to receive(:send_message).and_return(true)
        
        result = service.send_magic_code('+5511999999999', 'whatsapp')
        
        expect(result[:success]).to be true
        expect(LoginCode.count).to eq(1)
      end
    end
  end
end
```

### 3.3 Testes de Modelo
```ruby
# spec/models/login_code_spec.rb
require 'rails_helper'

RSpec.describe LoginCode, type: :model do
  describe 'validações' do
    it 'é válido com atributos padrão' do
      login_code = build(:login_code)
      expect(login_code).to be_valid
    end

    it 'requer identifier' do
      login_code = build(:login_code, identifier: nil)
      expect(login_code).not_to be_valid
    end

    it 'requer code' do
      login_code = build(:login_code, code: nil)
      expect(login_code).not_to be_valid
    end

    it 'requer method válido' do
      login_code = build(:login_code, method: 'invalid_method')
      expect(login_code).not_to be_valid
    end
  end

  describe '#expired?' do
    it 'retorna true se código expirou' do
      login_code = create(:login_code, created_at: 6.minutes.ago)
      expect(login_code.expired?).to be true
    end

    it 'retorna false se código não expirou' do
      login_code = create(:login_code, created_at: 2.minutes.ago)
      expect(login_code.expired?).to be false
    end
  end

  describe '#validate_code' do
    let!(:login_code) { create(:login_code, code: '123456') }

    it 'valida código correto' do
      expect(login_code.validate_code('123456')).to be true
    end

    it 'rejeita código incorreto' do
      expect(login_code.validate_code('000000')).to be false
    end

    it 'rejeita código expirado' do
      login_code.update(created_at: 6.minutes.ago)
      expect(login_code.validate_code('123456')).to be false
    end
  end

  describe 'tentativas de validação' do
    let!(:login_code) { create(:login_code, code: '123456', validation_attempts: 0) }

    it 'incrementa tentativas em falha' do
      login_code.validate_code('000000')
      expect(login_code.validation_attempts).to eq(1)
    end

    it 'bloqueia após 3 tentativas' do
      3.times { login_code.validate_code('000000') }
      expect(login_code.validate_code('123456')).to be false
    end
  end
end
```

## 4. Testes de Frontend

### 4.1 Testes de Componente
```typescript
// src/components/auth/__tests__/CodeInput.test.tsx
import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CodeInput } from '../CodeInput';

const mockOnSubmit = jest.fn();
const mockOnBack = jest.fn();

describe('CodeInput', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renderiza 6 inputs de código' do {
    render(
      <CodeInput
        identifier="test@example.com"
        method="email"
        onSubmit={mockOnSubmit}
        onBack={mockOnBack}
        isLoading={false}
      />
    );

    const inputs = screen.getAllByRole('textbox');
    expect(inputs).toHaveLength(6);
  });

  it('permite digitar código completo' do {
    render(
      <CodeInput
        identifier="test@example.com"
        method="email"
        onSubmit={mockOnSubmit}
        onBack={mockOnBack}
        isLoading={false}
      />
    );

    const inputs = screen.getAllByRole('textbox');
    
    // Digitar código
    inputs.forEach((input, index) => {
      fireEvent.change(input, { target: { value: (index + 1).toString() } });
    });

    // Verificar que callback foi chamado
    expect(mockOnSubmit).toHaveBeenCalledWith('123456');
  });

  it('auto-focus próximo input ao digitar' => {
    render(
      <CodeInput
        identifier="test@example.com"
        method="email"
        onSubmit={mockOnSubmit}
        onBack={mockOnBack}
        isLoading={false}
      />
    );

    const inputs = screen.getAllByRole('textbox');
    
    // Digitar no primeiro input
    fireEvent.change(inputs[0], { target: { value: '1' } });
    
    // Segundo input deve ter focus
    expect(inputs[1]).toHaveFocus();
  });

  it('mostra contador regressivo' => {
    jest.useFakeTimers();
    
    render(
      <CodeInput
        identifier="test@example.com"
        method="email"
        onSubmit={mockOnSubmit}
        onBack={mockOnBack}
        isLoading={false}
      />
    );

    // Verificar tempo inicial (5 minutos)
    expect(screen.getByText(/5:00/)).toBeInTheDocument();
    
    // Avançar tempo
    act(() => {
      jest.advanceTimersByTime(1000);
    });
    
    // Verificar que contador decrementou
    expect(screen.getByText(/4:59/)).toBeInTheDocument();
    
    jest.useRealTimers();
  });

  it('mostra mensagem de expirado quando tempo acaba' => {
    jest.useFakeTimers();
    
    render(
      <CodeInput
        identifier="test@example.com"
        method="email"
        onSubmit={mockOnSubmit}
        onBack={mockOnBack}
        isLoading={false}
      />
    );

    // Avançar 5 minutos
    act(() => {
      jest.advanceTimersByTime(5 * 60 * 1000);
    });
    
    expect(screen.getByText('Código expirado')).toBeInTheDocument();
    expect(screen.getByText('Solicitar novo código')).toBeInTheDocument();
    
    jest.useRealTimers();
  });
});
```

### 4.2 Testes de Hook
```typescript
// src/hooks/__tests__/useAuth.test.ts
import { renderHook, act } from '@testing-library/react-hooks';
import { useAuth } from '../useAuth';
import { authService } from '../../services/authService';

jest.mock('../../services/authService');

describe('useAuth', () => {
  beforeEach(() => {
    localStorage.clear();
    jest.clearAllMocks();
  });

  it('inicia com estado não autenticado' => {
    const { result } = renderHook(() => useAuth());
    
    expect(result.current.user).toBeNull();
    expect(result.current.token).toBeNull();
    expect(result.current.isLoading).toBe(false);
  });

  it('faz login com código com sucesso' => {
    const mockResponse = {
      success: true,
      user: { id: '1', email: 'test@example.com' },
      token: 'mock-token',
      refresh_token: 'mock-refresh'
    };
    
    (authService.requestMagicCode as jest.Mock).mockResolvedValue({ success: true });
    (authService.validateCode as jest.Mock).mockResolvedValue(mockResponse);
    
    const { result } = renderHook(() => useAuth());
    
    act(async () => {
      await result.current.loginWithCode('test@example.com', 'email');
    });
    
    expect(result.current.isLoading).toBe(false);
  });

  it('trata erro de login com código' => {
    const mockError = new Error('Código inválido');
    (authService.validateCode as jest.Mock).mockRejectedValue(mockError);
    
    const { result } = renderHook(() => useAuth());
    
    act(async () => {
      try {
        await result.current.loginWithCode('test@example.com', 'email', '123456');
      } catch (error) {
        expect(error).toEqual(mockError);
      }
    });
    
    expect(result.current.error).toBe('Código inválido');
  });

  it('faz logout corretamente' => {
    localStorage.setItem('token', 'mock-token');
    localStorage.setItem('refreshToken', 'mock-refresh');
    
    const { result } = renderHook(() => useAuth());
    
    act(async () => {
      await result.current.logout();
    });
    
    expect(localStorage.getItem('token')).toBeNull();
    expect(localStorage.getItem('refreshToken')).toBeNull();
  });
});
```

## 5. Testes de Segurança

### 5.1 Testes de Rate Limiting
```ruby
# spec/requests/api/auth/v1/security_spec.rb
require 'rails_helper'

RSpec.describe 'Security Tests', type: :request do
  describe 'Rate limiting' do
    it 'limita tentativas de código por IP' do
      identifier = 'test@example.com'
      
      # Criar código válido
      login_code = create(:login_code, identifier: identifier)
      
      # Fazer 6 tentativas com código errado
      6.times do
        post '/api/auth/v1/magic_login/validate_code', params: {
          identifier: identifier,
          code: '000000',
          method: 'email'
        }
      end
      
      expect(response).to have_http_status(:too_many_requests)
      expect(json_response['error']).to include('Muitas tentativas')
    end

    it 'limita requisições de código por IP' do
      # Fazer 6 requisições de código
      6.times do
        post '/api/auth/v1/magic_login/request_code', params: {
          identifier: 'test@example.com',
          method: 'email'
        }
      end
      
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'Brute force protection' do
    it 'bloqueia após 3 tentativas de código errado' do
      login_code = create(:login_code, code: '123456')
      
      # 3 tentativas erradas
      3.times do
        post '/api/auth/v1/magic_login/validate_code', params: {
          identifier: login_code.identifier,
          code: '000000',
          method: 'email'
        }
      end
      
      # 4ª tentativa com código correto deve falhar
      post '/api/auth/v1/magic_login/validate_code', params: {
        identifier: login_code.identifier,
        code: '123456',
        method: 'email'
      }
      
      expect(response).to have_http_status(:unauthorized)
      expect(json_response['error']).to include('Muitas tentativas')
    end
  end
end
```

### 5.2 Testes de Validação
```ruby
# spec/validators/email_validator_spec.rb
require 'rails_helper'

RSpec.describe EmailValidator do
  subject { Class.new { include ActiveModel::Validations; attr_accessor :email; validates :email, email: true }.new }

  valid_emails = [
    'user@example.com',
    'user.name@example.com',
    'user+tag@example.co.uk',
    'user@subdomain.example.com'
  ]

  invalid_emails = [
    'invalid-email',
    'user@',
    '@example.com',
    'user@.com',
    'user@example',
    ''
  ]

  valid_emails.each do |email|
    it 