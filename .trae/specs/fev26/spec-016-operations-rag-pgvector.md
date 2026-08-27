# Tarefa 1.1: Setup pgvector & Database

**Sprint:** 1 - RAG Foundation, Asset Repository & Intent Detector
**Estimativa:** 0.5 dia
**Tipo:** Backend

---

## Contexto
Para que possamos implementar busca semântica, Detecção de Intenção (Intent Detection) e RAG (Retrieval-Augmented Generation) para as Operações do sistema, precisamos de um armazenamento físico para dados vetoriais. 
Como o PostgreSQL já é utilizado como o banco de dados principal do monorepo e suporta a extensão oficial `pgvector`, usá-lo permite armazenar e consultar embeddings de texto de forma eficiente sem a necessidade de introduzir uma infraestrutura de dados separada (como Pinecone ou Qdrant). A adoção do `pgvector` aproveita a stack atual, diminui custos e melhora a manutenibilidade.

---

## Onde começa
O projeto Rails 8 (API-only) atual roda sobre um banco de dados PostgreSQL 14+, configurado no `database.yml`, sem a extensão vetorial instalada e sem as gems de integração correspondentes.

## Onde termina
A extensão `vector` (pgvector) deve estar ativada de forma idempotente no PostgreSQL (ambiente de Dev, Test e Prod), e a biblioteca de integração com ActiveRecord devidamente instalada na aplicação Rails, permitindo que as próximas tarefas criem tabelas com colunas do tipo vector.

---

## O que precisa ser feito

### No Backend
1. **Adicionar a dependência**: Incluir a gem `pgvector` (ou `neighbor`, caso prefira a sintaxe abstraída para escopos) no `Gemfile` e rodar `bundle install`.
2. **Ativar a extensão**: 
   Criar uma migration específica (`rails g migration EnablePgvectorExtension`) que ative com segurança a extensão:
   ```ruby
   def up
     enable_extension 'vector' unless extension_enabled?('vector')
   end

   def down
     disable_extension 'vector' if extension_enabled?('vector')
   end
   ```
3. **Ajuste de Testes/CI**: Se o projeto usa Docker Compose ou GitHub Actions para rodar testes que exigem container de banco, garantir que a imagem do Postgres referenciada suporte a extensão (ex: trocar `postgres:14` por `pgvector/pgvector:pg14` ou usar script de build).

### No Frontend
Não se aplica. Tarefa exclusiva de infraestrutura de banco de dados.

---

## Observações importantes
- Ao executar a migration pela primeira vez na inicialização ou num novo deploy, garanta que o usuário do banco (role) tenha privilégios para criar extensões (superuser, ou grant explícito no ambiente). Em ambientes gerenciados (RDS, DigitalOcean), ela costuma estar disponível e pode ser ativada sem problemas.

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. A migration de ativação da extensão rolar e reverter corretamente (verificado via `rails db:migrate:redo`).
2. Abrir o `rails c` e conseguir executar com sucesso `ActiveRecord::Base.connection.execute("SELECT extversion FROM pg_extension WHERE extname = 'vector';")` retornando a versão da extensão.
3. Pipeline de testes rodar sem falhar na inicialização do banco.

---

## Dependências
- Nenhuma dependência direta além das configurações de ambiente já prontas.

## Próxima tarefa
Tarefa 1.2: OperationKnowledge & OperationAsset Models (`spec-017-operation-knowledge-asset.md`)
