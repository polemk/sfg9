# Guia de Estrutura de Mídias e Identificadores

Este documento detalha como gerenciar o conteúdo das mídias na Landing Page utilizando o campo **Identifier** (Identificador) no Painel Administrativo.

Implementamos um sistema dinâmico onde o local de exibição da mídia é determinado pelo seu identificador.

## Resumo dos Identificadores

| Seção no Site                 | Identificador Obrigatório (Identifier)    | Comportamento                                                                                                                |
| :---------------------------- | :---------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------- |
| **Demo / Hero (Topo)**        | `demo`                                    | Exibe a mídia mais recente com este identificador. Substitui o placeholder padrão.                                           |
| **What is it?**               | `what_is_it`                              | Exibe a mídia mais recente com este identificador na seção explicativa.                                                      |
| **Take a closer look (Grid)** | _(Vazio ou qualquer outro)_               | Exibe **todas** as mídias ativas que **NÃO** possuem os identificadores `demo`, `what_is_it` ou `take_a_closer_look_hidden`. |
| **Seção de Features**         | `feature_section_1` a `feature_section_5` | Mapeia cada vídeo para um bloco de texto específico na nova seção de features. Se não houver vídeo, exibe placeholder.       |
| **Oculto**                    | `take_a_closer_look_hidden`               | Use este identificador se quiser manter uma mídia no banco mas não exibi-la em lugar nenhum (nem no Grid).                   |

---

## Detalhes por Seção

### 1. Seção Demo (Media Showcase)

- **Localização**: Logo abaixo do título principal da Home ("Crie e lance...").
- **Componente**: `MediaShowcase`
- **Lógica**: Busca 1 item com `identifier = 'demo'`.
- **Conteúdo**: Pode ser Imagem ou Vídeo. Se for vídeo, exige thumbnail (opcional, mas recomendado) e tem player interativo.

### 2. Seção "What is it?"

- **Localização**: Bloco explicativo sobre o sistema.
- **Componente**: `WhatIsIt`
- **Lógica**: Busca 1 item com `identifier = 'what_is_it'`.
- **Conteúdo**: Idealmente um vídeo curto ou GIF explicativo do funcionamento básico.

### 3. Seção "Take a closer look" (Grade de detalhes)

- **Localização**: Grid de imagens na parte inferior.
- **Componente**: `TakeCloserLook`
- **Lógica**:
  1. Busca até 100 mídias mais recentes.
  2. Filtragem automática no Frontend:
     - **Exclui**: `demo`
     - **Exclui**: `what_is_it`
     - **Exclui**: `take_a_closer_look_hidden`
  3. Exibe o restante.
- **Layout**: O grid se ajusta automaticamente (bento grid) baseado na proporção da imagem/vídeo.

---

## Como Cadastrar no Admin

1. Acesse o Painel Administrativo.
2. Vá para a aba **Media**.
3. Crie ou Edite uma mídia.
4. Preencha o campo **Identifier** conforme a tabela acima.
   - Para o topo do site, escreva: `demo`
   - Para a explicação, escreva: `what_is_it`
   - Para a galeria geral, deixe em branco ou coloque um nome descritivo qualquer (ex: `app_dashboard`).
5. Certifique-se de que a caixa **Active** está marcada.

## Nota Técnica

- **Cache**: O React Query faz cache dessas requisições. Se alterar no admin e não ver na hora, dê um F5 na página.
- **Formatos**: Vídeos devem ser preferencialmente MP4/WebM otimizados. Imagens em WebP/JPG/PNG.
