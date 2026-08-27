## Objetivo
Adicionar "biografia" ao `User` como Rich Text (ActionText), sem coluna nova em `users`, permitindo editar via WYSIWYG e atualizar pela rota de update.

## Backend
- Incluir `has_rich_text :biography` em `User`.
- Instalar tabelas do ActionText e ActiveStorage (não cria coluna em `users`): `active_storage_blobs`, `active_storage_attachments`, `action_text_rich_texts`.
- Permitir `biography` no update (`UsersService.update`) usando `user.biography = params[:biography]` e `save!`.
- Expor `biography` na entity `Api::Entities::User` com dois campos: `biography_html` (HTML sanitizado) e `biography_text` (texto plano).
- Documentar no Swagger que `biography` é string (HTML/Markdown) opcional no update.

## Frontend
- No formulário de usuário, mostrar campo simples e ao focar abrir WYSIWYG (Tiptap/Quill). Enviar `biography` como string para a API.
- Renderizar `biography_html` no detalhe do usuário (com sanitização no cliente).

## Testes
- Request spec para `PUT /api/v1/users/:id` atualizando `biography` e validando persistência.
- Entity spec garantindo presença de `biography_html` e `biography_text` nas respostas.

## Observações
- "Sem migração" refere-se a não adicionar coluna em `users`; porém é necessário instalar as migrations padrão do ActionText/ActiveStorage para funcionarem.
- Revisar o 500 em `/auth/v1/sessions/status`: pode ser impactado por ActionText não instalado; autenticação 401 em `/auth/v1/me` é esperado sem JWT.

Confirma prosseguir com esta implementação?