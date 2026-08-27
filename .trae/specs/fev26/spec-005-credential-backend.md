# Tarefa 005: Backend de Credenciais

**Sprint:** 2 - Gerenciamento de Credenciais
**Estimativa:** 1 dia
**Tipo:** Backend

---

## Contexto
Para que os agentes de IA funcionem, precisamos armazenar chaves de API (OpenAI, Anthropic, etc.) de forma segura. Não podemos salvar essas chaves em texto plano no banco de dados. Precisamos de um sistema centralizado de credenciais que possa ser reutilizado por múltiplos agentes.

**Valor para o usuário:** Segurança e conveniência. O usuário cadastra a chave uma vez e a utiliza em vários agentes sem expor o segredo.

---

## Onde começa
- Não existe tabela para armazenamento de segredos/chaves de API no banco.
- Atualmente, qualquer configuração de chave teria que ser hardcoded (inseguro) ou via ENV (não escala para usuários finais).

## Onde termina
- Tabela `credentials` criada com campos criptografados.
- API `/api/v1/credentials` permitindo CRUD seguro (criação e deleção; listagem retorna mascarado).

---

## O que precisa ser feito

### No Backend

1.  **Migration `CreateCredentials`**:
    -   `name`: string, not null (Identificador amigável, ex: "Minha Chave OpenAI").
    -   `provider`: string/enum (ex: `openai`, `anthropic`, `google`), not null.
    -   `api_key_ciphertext`: text (campo criptografado).
    -   `account_id` (se for multi-tenant) ou associação com `User`.

2.  **Model `Credential`**:
    -   Usar `encrypts :api_key` (Rails 7+ Active Record Encryption).
    -   Validar presença de `name` e `provider`.
    -   Validar unicidade de `name` por escopo (conta/usuário).

3.  **Controller `Api::V1::CredentialsController`**:
    -   `index`: Retorna lista. **IMPORTANTE:** O campo `api_key` NÃO deve ser retornado, ou deve retornar mascarado (`sk-proj...XXXX`).
    -   `create`: Recebe `api_key` em texto plano, salva criptografado.
    -   `destroy`: Remove a credencial.
    -   `update`: Permitir alterar nome ou atualizar a chave (write-only).

4.  **Serializer / Entity**:
    -   Garantir que o JSON de resposta nunca vaze o `api_key` descriptografado.
    -   Retornar `masked_key` (primeiros 4 chars + '...').

---

## Observações importantes
-   **Segurança (Rails Patterns):** Usar `Rails.application.credentials.key_base` como master key (padrão Rails).
-   **API Patterns:** Use status `201 Created` para criação e `204 No Content` para deleção.
-   **Audit:** Idealmente, logar (sem a chave) quem criou/apagou credenciais.

---

## Critérios de aceite

1.  **Segurança:**
    -   [ ] Verificar no console do Rails que `Credential.last.api_key` é texto plano, mas `Credential.last.api_key_ciphertext` no banco é ilegível.
2.  **API:**
    -   [ ] `GET /credentials` retorna lista com keys mascaradas.
    -   [ ] `POST /credentials` cria com sucesso.
    -   [ ] `DELETE /credentials/:id` remove o registro.
3.  **Testes:**
    -   [ ] Teste unitário garante encriptação.
    -   [ ] Teste de request garante que a chave real não vaza no JSON.

---

## Dependências
-   Nenhuma direta, mas bloqueia a Tarefa 007.
