# Magic Login - Configuração Frontend React

## 1. Estrutura de Componentes

### 1.1 Árvore de Componentes

```
src/
├── components/
│   ├── auth/
│   │   ├── MagicLoginForm.tsx
│   │   ├── CodeInput.tsx
│   │   ├── SocialLoginButtons.tsx
│   │   ├── AuthContainer.tsx
│   │   └── AuthContext.tsx
│   ├── ui/
│   │   ├── Button.tsx
│   │   ├── Input.tsx
│   │   ├── Card.tsx
│   │   └── Toast.tsx
├── services/
│   └── authService.ts
├── hooks/
│   ├── useAuth.ts
│   └── useCountdown.ts
├── types/
│   └── auth.types.ts
└── utils/
    └── validators.ts
```

### 1.2 Componente Principal - AuthContainer.tsx

```typescript
import React, { useState } from 'react';
import { MagicLoginForm } from './MagicLoginForm';
import { CodeInput } from './CodeInput';
import { SocialLoginButtons } from './SocialLoginButtons';
import { useAuth } from '../../hooks/useAuth';
import { AuthMethod, LoginStep } from '../../types/auth.types';

export const AuthContainer: React.FC = () => {
  const [currentStep, setCurrentStep] = useState<LoginStep>('method-selection');
  const [selectedMethod, setSelectedMethod] = useState<AuthMethod | null>(null);
  const [identifier, setIdentifier] = useState<string>('');
  const [isLoading, setIsLoading] = useState(false);
  const { loginWithCode, loginWithSocial } = useAuth();

  const handleMethodSelect = (method: AuthMethod) => {
    setSelectedMethod(method);
    if (method === 'google' || method === 'facebook') {
      handleSocialLogin(method);
    } else {
      setCurrentStep('identifier-input');
    }
  };

  const handleIdentifierSubmit = async (identifier: string) => {
    if (!selectedMethod) return;
    
    setIdentifier(identifier);
    setIsLoading(true);
    
    try {
      await loginWithCode(identifier, selectedMethod);
      setCurrentStep('code-input');
    } catch (error) {
      console.error('Erro ao solicitar código:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleCodeSubmit = async (code: string) => {
    if (!selectedMethod || !identifier) return;
    
    setIsLoading(true);
    
    try {
      await loginWithCode(identifier, selectedMethod, code);
      // Redirecionar para dashboard
    } catch (error) {
      console.error('Erro ao validar código:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSocialLogin = async (provider: 'google' | 'facebook') => {
    setIsLoading(true);
    
    try {
      await loginWithSocial(provider);
      // Redirecionar para dashboard
    } catch (error) {
      console.error('Erro no login social:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleBack = () => {
    if (currentStep === 'code-input') {
      setCurrentStep('identifier-input');
    } else if (currentStep === 'identifier-input') {
      setCurrentStep('method-selection');
      setSelectedMethod(null);
      setIdentifier('');
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8">
        {currentStep === 'method-selection' && (
          <MagicLoginForm onMethodSelect={handleMethodSelect} isLoading={isLoading} />
        )}
        
        {currentStep === 'identifier-input' && selectedMethod && (
          <IdentifierInput
            method={selectedMethod}
            onSubmit={handleIdentifierSubmit}
            onBack={handleBack}
            isLoading={isLoading}
          />
        )}
        
        {currentStep === 'code-input' && (
          <CodeInput
            identifier={identifier}
            method={selectedMethod!}
            onSubmit={handleCodeSubmit}
            onBack={handleBack}
            isLoading={isLoading}
          />
        )}
        
        {currentStep === 'method-selection' && (
          <SocialLoginButtons onSocialLogin={handleSocialLogin} isLoading={isLoading} />
        )}
      </div>
    </div>
  );
};
```

### 1.3 Formulário de Método - MagicLoginForm.tsx

```typescript
import React from 'react';
import { Card } from '../ui/Card';
import { Button } from '../ui/Button';
import { Mail, MessageCircle } from 'lucide-react';
import { AuthMethod } from '../../types/auth.types';

interface MagicLoginFormProps {
  onMethodSelect: (method: AuthMethod) => void;
  isLoading: boolean;
}

export const MagicLoginForm: React.FC<MagicLoginFormProps> = ({ 
  onMethodSelect, 
  isLoading 
}) => {
  const methods = [
    {
      id: 'email' as AuthMethod,
      name: 'Email',
      description: 'Receber código por email',
      icon: Mail,
      color: 'blue'
    },
    {
      id: 'whatsapp' as AuthMethod,
      name: 'WhatsApp',
      description: 'Receber código por WhatsApp',
      icon: MessageCircle,
      color: 'green'
    }
  ];

  return (
    <Card className="p-6">
      <div className="text-center mb-6">
        <h2 className="text-3xl font-bold text-gray-900">Acesse sua conta</h2>
        <p className="mt-2 text-gray-600">
          Escolha como deseja receber seu código de acesso
        </p>
      </div>

      <div className="space-y-4">
        {methods.map((method) => {
          const Icon = method.icon;
          return (
            <Button
              key={method.id}
              onClick={() => onMethodSelect(method.id)}
              disabled={isLoading}
              variant="outline"
              className={`w-full justify-start border-${method.color}-200 hover:border-${method.color}-300`}
            >
              <Icon className={`mr-3 h-5 w-5 text-${method.color}-500`} />
              <div className="text-left">
                <div className="font-medium">{method.name}</div>
                <div className="text-sm text-gray-500">{method.description}</div>
              </div>
            </Button>
          );
        })}
      </div>
    </Card>
  );
};
```

### 1.4 Input de Identificador - IdentifierInput.tsx

```typescript
import React, { useState } from 'react';
import { Card } from '../ui/Card';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';
import { ArrowLeft, Mail, Phone } from 'lucide-react';
import { AuthMethod } from '../../types/auth.types';
import { validateEmail, validatePhone } from '../../utils/validators';

interface IdentifierInputProps {
  method: AuthMethod;
  onSubmit: (identifier: string) => void;
  onBack: () => void;
  isLoading: boolean;
}

export const IdentifierInput: React.FC<IdentifierInputProps> = ({
  method,
  onSubmit,
  onBack,
  isLoading
}) => {
  const [identifier, setIdentifier] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!identifier.trim()) {
      setError('Por favor, insira seu ' + (method === 'email' ? 'email' : 'telefone'));
      return;
    }

    if (method === 'email' && !validateEmail(identifier)) {
      setError('Por favor, insira um email válido');
      return;
    }

    if (method === 'whatsapp' && !validatePhone(identifier)) {
      setError('Por favor, insira um telefone válido');
      return;
    }

    onSubmit(identifier);
  };

  const getPlaceholder = () => {
    return method === 'email' ? 'seu@email.com' : '+55 11 99999-9999';
  };

  const getLabel = () => {
    return method === 'email' ? 'Email' : 'Telefone';
  };

  const getIcon = () => {
    return method === 'email' ? Mail : Phone;
  };

  const Icon = getIcon();

  return (
    <Card className="p-6">
      <div className="mb-4">
        <Button
          onClick={onBack}
          variant="ghost"
          size="sm"
          className="mb-4"
        >
          <ArrowLeft className="mr-2 h-4 w-4" />
          Voltar
        </Button>
        
        <div className="text-center">
          <h2 className="text-2xl font-bold text-gray-900">Insira seu {getLabel()}</h2>
          <p className="mt-2 text-gray-600">
            Enviaremos um código de acesso para você
          </p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <Input
            type={method === 'email' ? 'email' : 'tel'}
            placeholder={getPlaceholder()}
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            icon={Icon}
            error={error}
            disabled={isLoading}
            autoFocus
          />
        </div>

        <Button
          type="submit"
          className="w-full"
          disabled={isLoading}
          loading={isLoading}
        >
          Enviar código
        </Button>
      </form>
    </Card>
  );
};
```

### 1.5 Input de Código - CodeInput.tsx

```typescript
import React, { useState, useRef, useEffect } from 'react';
import { Card } from '../ui/Card';
import { Button } from '../ui/Button';
import { ArrowLeft } from 'lucide-react';
import { AuthMethod } from '../../types/auth.types';
import { useCountdown } from '../../hooks/useCountdown';

interface CodeInputProps {
  identifier: string;
  method: AuthMethod;
  onSubmit: (code: string) => void;
  onBack: () => void;
  isLoading: boolean;
}

export const CodeInput: React.FC<CodeInputProps> = ({
  identifier,
  method,
  onSubmit,
  onBack,
  isLoading
}) => {
  const [code, setCode] = useState(['', '', '', '', '', '']);
  const inputsRef = useRef<(HTMLInputElement | null)[]>([]);
  const { countdown, isActive, start } = useCountdown(300); // 5 minutos

  useEffect(() => {
    start();
    inputsRef.current[0]?.focus();
  }, []);

  const handleCodeChange = (index: number, value: string) => {
    if (value.length > 1) return;
    
    const newCode = [...code];
    newCode[index] = value;
    setCode(newCode);

    // Auto-focus próximo input
    if (value && index < 5) {
      inputsRef.current[index + 1]?.focus();
    }

    // Verificar se código está completo
    const fullCode = newCode.join('');
    if (fullCode.length === 6) {
      onSubmit(fullCode);
    }
  };

  const handleKeyDown = (index: number, e: React.KeyboardEvent) => {
    if (e.key === 'Backspace' && !code[index] && index > 0) {
      inputsRef.current[index - 1]?.focus();
    }
  };

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const maskIdentifier = () => {
    if (method === 'email') {
      const [local, domain] = identifier.split('@');
      return `${local.slice(0, 2)}***@${domain}`;
    } else {
      return identifier.slice(0, 3) + '***' + identifier.slice(-3);
    }
  };

  return (
    <Card className="p-6">
      <div className="mb-4">
        <Button
          onClick={onBack}
          variant="ghost"
          size="sm"
          className="mb-4"
        >
          <ArrowLeft className="mr-2 h-4 w-4" />
          Voltar
        </Button>
        
        <div className="text-center">
          <h2 className="text-2xl font-bold text-gray-900">Digite o código</h2>
          <p className="mt-2 text-gray-600">
            Enviamos um código para {maskIdentifier()}
          </p>
        </div>
      </div>

      <div className="space-y-6">
        <div className="flex justify-center space-x-2">
          {code.map((digit, index) => (
            <input
              key={index}
              ref={(el) => (inputsRef.current[index] = el)}
              type="text"
              inputMode="numeric"
              pattern="[0-9]*"
              maxLength={1}
              value={digit}
              onChange={(e) => handleCodeChange(index, e.target.value)}
              onKeyDown={(e) => handleKeyDown(index, e)}
              className="w-12 h-12 text-center text-2xl font-bold border-2 border-gray-300 rounded-lg focus:border-blue-500 focus:outline-none"
              disabled={isLoading || !isActive}
            />
          ))}
        </div>

        <div className="text-center">
          {isActive ? (
            <p className="text-sm text-gray-600">
              Código expira em: <span className="font-bold text-red-500">{formatTime(countdown)}</span>
            </p>
          ) : (
            <div>
              <p className="text-sm text-red-500 mb-2">Código expirado</p>
              <Button
                onClick={onBack}
                variant="outline"
                size="sm"
              >
                Solicitar novo código
              </Button>
            </div>
          )}
        </div>
      </div>
    </Card>
  );
};
```

## 2. Serviços e Hooks

### 2.1 Serviço de Autenticação - authService.ts

```typescript
import api from '../lib/api/client';
import { AuthResponse, CodeRequest, CodeValidation } from '../types/auth.types';

export const authService = {
  async requestMagicCode(identifier: string, method: 'email' | 'whatsapp') {
    const response = await api.post('/auth/v1/magic_login/request_code', {
      identifier,
      method
    });
    return response.data;
  },

  async validateCode(identifier: string, code: string, method: string) {
    const response = await api.post('/auth/v1/magic_login/validate_code', {
      identifier,
      code,
      method
    });
    return response.data as AuthResponse;
  },

  async getOAuthUrl(provider: 'google' | 'facebook', redirectUri: string) {
    const response = await api.get(`/auth/v1/oauth/${provider}_url`, {
      params: { redirect_uri: redirectUri }
    });
    return response.data;
  },

  async handleOAuthCallback(provider: string, code: string, state?: string) {
    const response = await api.post('/auth/v1/oauth/callback', {
      provider,
      code,
      state
    });
    return response.data as AuthResponse;
  },

  async refreshToken(refreshToken: string) {
    const response = await api.post('/auth/v1/sessions/refresh', {
      refresh_token: refreshToken
    });
    return response.data;
  },

  async logout() {
    const response = await api.delete('/auth/v1/sessions/logout');
    return response.data;
  },

  async checkSessionStatus() {
    const response = await api.get('/auth/v1/sessions/status');
    return response.data;
  }
};
```

### 2.2 Hook de Autenticação - useAuth.ts

```typescript
import { useState, useCallback, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { authService } from '../services/authService';
import { User, AuthResponse } from '../types/auth.types';

export const useAuth = () => {
  const [user, setUser] = useState<User | null>(null);
  const [token, setToken] = useState<string | null>(localStorage.getItem('token'));
  const [refreshToken, setRefreshToken] = useState<string | null>(localStorage.getItem('refreshToken'));
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  // Verificar sessão ao carregar
  useEffect(() => {
    if (token) {
      checkSession();
    }
  }, [token]);

  const checkSession = async () => {
    try {
      const response = await authService.checkSessionStatus();
      if (response.authenticated) {
        setUser(response.user);
      } else {
        // Token inválido, tentar refresh
        await refreshAccessToken();
      }
    } catch (error) {
      console.error('Erro ao verificar sessão:', error);
      logout();
    }
  };

  const loginWithCode = useCallback(async (identifier: string, method: 'email' | 'whatsapp', code?: string) => {
    setIsLoading(true);
    setError(null);

    try {
      if (!code) {
        // Solicitar código
        const response = await authService.requestMagicCode(identifier, method);
        
        // Em desenvolvimento, mostrar código no toast
        if (response.code && process.env.NODE_ENV === 'development') {
          console.log('Código de acesso:', response.code);
          // Mostrar toast com código
        }
        
        return response;
      } else {
        // Validar código e fazer login
        const response = await authService.validateCode(identifier, code, method);
        handleSuccessfulLogin(response);
        return response;
      }
    } catch (error: any) {
      setError(error.response?.data?.message || 'Erro ao processar login');
      throw error;
    } finally {
      setIsLoading(false);
    }
  }, []);

  const loginWithSocial = useCallback(async (provider: 'google' | 'facebook') => {
    setIsLoading(true);
    setError(null);

    try {
      // Obter URL de autorização
      const { url } = await authService.getOAuthUrl(provider, window.location.origin + '/auth/callback');
      
      // Redirecionar para OAuth
      window.location.href = url;
    } catch (error: any) {
      setError(error.response?.data?.message || 'Erro ao iniciar login social');
      throw error;
    } finally {
      setIsLoading(false);
    }
  }, []);

  const handleOAuthCallback = useCallback(async (provider: string, code: string, state?: string) => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await authService.handleOAuthCallback(provider, code, state);
      handleSuccessfulLogin(response);
    } catch (error: any) {
      setError(error.response?.data?.message || 'Erro ao processar callback OAuth');
      throw error;
    } finally {
      setIsLoading(false);
    }
  }, []);

  const handleSuccessfulLogin = (response: AuthResponse) => {
    setUser(response.user);
    setToken(response.token);
    setRefreshToken(response.refresh_token);
    
    // Salvar no localStorage
    localStorage.setItem('token', response.token);
    localStorage.setItem('refreshToken', response.refresh_token);
    
    // Redirecionar para dashboard
    navigate('/dashboard');
  };

  const refreshAccessToken = async () => {
    if (!refreshToken) return;

    try {
      const response = await authService.refreshToken(refreshToken);
      setToken(response.token);
      setRefreshToken(response.refresh_token);
      
      localStorage.setItem('token', response.token);
      localStorage.setItem('refreshToken', response.refresh_token);
    } catch (error) {
      // Refresh falhou, fazer logout
      logout();
    }
  };

  const logout = useCallback(async () => {
    try {
      await authService.logout();
    } catch (error) {
      console.error('Erro ao fazer logout:', error);
    } finally {
      setUser(null);
      setToken(null);
      setRefreshToken(null);
      localStorage.removeItem('token');
      localStorage.removeItem('refreshToken');
      navigate('/login');
    }
  }, []);

  return {
    user,
    token,
    isLoading,
    error,
    loginWithCode,
    loginWithSocial,
    handleOAuthCallback,
    logout,
    refreshAccessToken
  };
};
```

### 2.3 Hook de Contador - useCountdown.ts

```typescript
import { useState, useEffect, useCallback } from 'react';

export const useCountdown = (initialSeconds: number) => {
  const [countdown, setCountdown] = useState(initialSeconds);
  const [isActive, setIsActive] = useState(true);

  const start = useCallback(() => {
    setCountdown(initialSeconds);
    setIsActive(true);
  }, [initialSeconds]);

  const stop = useCallback(() => {
    setIsActive(false);
  }, []);

  const reset = useCallback(() => {
    setCountdown(initialSeconds);
    setIsActive(true);
  }, [initialSeconds]);

  useEffect(() => {
    let interval: NodeJS.Timeout | null = null;

    if (isActive && countdown > 0) {
      interval = setInterval(() => {
        setCountdown(countdown => countdown - 1);
      }, 1000);
    } else if (countdown === 0) {
      setIsActive(false);
    }

    return () => {
      if (interval) clearInterval(interval);
    };
  }, [isActive, countdown]);

  return {
    countdown,
    isActive,
    start,
    stop,
    reset
  };
};
```

## 3. Tipos e Interfaces

### 3.1 Tipos de Autenticação - auth.types.ts

```typescript
export type AuthMethod = 'email' | 'whatsapp' | 'google' | 'facebook';
export type LoginStep = 'method-selection' | 'identifier-input' | 'code-input';

export interface User {
  id: string;
  email: string;
  phone: string;
  name: string;
  avatar_url: string | null;
  user_type: string;
  last_login_at: string;
  login_count: number;
}

export interface AuthResponse {
  success: boolean;
  message: string;
  user: User;
  token: string;
  refresh_token: string;
  is_new_user?: boolean;
}

export interface CodeRequest {
  identifier: string;
  method: 'email' | 'whatsapp';
}

export interface CodeValidation extends CodeRequest {
  code: string;
}

export interface OAuthResponse {
  url: string;
  provider: 'google' | 'facebook';
}
```

## 4. Estilos e Tema

### 4.1 Configuração Tailwind - tailwind.config.js

```javascript
module.exports = {
  content: [
    "./src/**/*.{js,jsx,ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          100: '#dbeafe',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
        },
        success: {
          50: '#f0fdf4',
          100: '#dcfce7',
          500: '#22c55e',
          600: '#16a34a',
        }
      },
      animation: {
        'fade-in': 'fadeIn 0.5s ease-in-out',
        'slide-up': 'slideUp 0.3s ease-out',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { transform: 'translateY(10px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        }
      }
    },
  },
  plugins: [],
}
```

### 4.2 Estilos Globais - index.css

```css
@import 'tailwindcss/base';
@import 'tailwindcss/components';
@import 'tailwindcss/utilities';

@layer base {
  body {
    @apply antialiased;
  }
}

@layer components {
  .btn-primary {
    @apply bg-primary-600 hover:bg-primary-700 text-white font-medium py-2 px-4 rounded-lg transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2;
  }
  
  .btn-secondary {
    @apply bg-gray-200 hover:bg-gray-300 text-gray-900 font-medium py-2 px-4 rounded-lg transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2;
  }
  
  .input-base {
    @apply block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-primary-500 focus:border-primary-500;
  }
}

/* Animações de loading */
@keyframes pulse {
  0%, 100% {
    opacity: 1;
  }
  50% {
    opacity: .5;
  }
}

.animate-pulse {
  animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}
```

## 5. Integração com Backend

### 5.1 Configuração API Client

```typescript
// src/lib/api/client.ts
import axios, { AxiosInstance, AxiosRequestConfig } from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:3000/api';

class ApiClient {
  private client: AxiosInstance;

  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      (config) => {
        const token = localStorage.getItem('token');
        if (token) {
          config.headers.Authorization = `Bearer ${token}`;
        }
        return config;
      },
      (error) => {
        return Promise.reject(error);
      }
    );

    // Response interceptor
    this.client.interceptors.response.use(
      (response) => {
        return response;
      },
      async (error) => {
        const originalRequest = error.config;

        if (error.response?.status === 401 && !originalRequest._retry) {
          originalRequest._retry = true;
          
          try {
            const refreshToken = localStorage.getItem('refreshToken');
            if (refreshToken) {
              // Implementar refresh token
              return this.client(originalRequest);
            }
          } catch (refreshError) {
            // Refresh falhou, fazer logout
            localStorage.removeItem('token');
            localStorage.removeItem('refreshToken');
            window.location.href = '/login';
          }
        }

        return Promise.reject(error);
      }
    );
  }

  async get<T>(url: string, config?: AxiosRequestConfig) {
    const response = await this.client.get<T>(url, config);
    return response;
  }

  async post<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const response = await this.client.post<T>(url, data, config);
    return response;
  }

  async put<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const response = await this.client.put<T>(url, data, config);
    return response;
  }

  async delete<T>(url: string, config?: AxiosRequestConfig) {
    const response = await this.client.delete<T>(url, config);
    return response;
  }
}

export default new ApiClient();
```

## 6. Testes

### 6.1 Teste do Componente AuthContainer

```typescript
// src/components/auth/__tests__/AuthContainer.test.tsx
import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AuthContainer } from '../AuthContainer';
import { useAuth } from '../../../hooks/useAuth';

jest.mock('../../../hooks/useAuth');

describe('AuthContainer', () => {
  const mockLoginWithCode = jest.fn();
  const mockLoginWithSocial = jest.fn();

  beforeEach(() => {
    (useAuth as jest.Mock).mockReturnValue({
      loginWithCode: mockLoginWithCode,
      loginWithSocial: mockLoginWithSocial,
      isLoading: false,
      error: null
    });
  });

  it('deve renderizar opções de login inicialmente', () => {
    render(<AuthContainer />);
    
    expect(screen.getByText('Acesse sua conta')).toBeInTheDocument();
    expect(screen.getByText('Email')).toBeInTheDocument();
    expect(screen.getByText('WhatsApp')).toBeInTheDocument();
  });

  it('deve mostrar formulário de email ao clicar em Email', () => {
    render(<AuthContainer />);
    
    fireEvent.click(screen.getByText('Email'));
    
    expect(screen.getByPlaceholderText('seu@email.com')).toBeInTheDocument();
  });

  it('deve chamar loginWithCode ao submeter identificador', async () => {
    mockLoginWithCode.mockResolvedValue({ success: true });
    
    render(<AuthContainer />);
    
    fireEvent.click(screen.getByText('Email'));
    
    const input = screen.getByPlaceholderText('seu@email.com');
    fireEvent.change(input, { target: { value: 'test@example.com' } });
    
    fireEvent.click(screen.getByText('Enviar código'));
    
    await waitFor(() => {
      expect(mockLoginWithCode).toHaveBeenCalledWith('test@example.com', 'email');
    });
  });
});
```

## 7. Performance e UX

### 7.1 Otimizações

* **Lazy loading** de componentes pesados

* **Memoização** de componentes estáveis

* **Debouncing** em inputs de formulário

* **Prefetch** de dados críticos

### 7.2 Acessibilidade

* **ARIA labels** em todos os elementos interativos

* **Navegação por teclado** completa

* **Anúncios de erros** para leitores de tela

* **Alto contraste** para visibilidade

### 7.3
