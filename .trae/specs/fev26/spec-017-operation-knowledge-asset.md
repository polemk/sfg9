# Tarefa 1.2: OperationKnowledge & OperationAsset Models

**Sprint:** 1 - RAG Foundation, Asset Repository & Intent Detector
**Estimativa:** 1 dia
**Tipo:** Backend

---

## Contexto
Atualmente, as `Operations` (operações) possuem apenas campos básicos (title, description, keywords). Para transformar as Operações em uma base de conhecimento inteligente (RAG), precisamos armazenar dados textuais expandidos (como FAQs, argumentários, roteiros) e mídias (imagens, PDFs, vídeos) associados a elas.

Esta tarefa introduz a fundação estrutural: `OperationKnowledge` para abrigar o texto contínuo e seus embeddings vetoriais, e `OperationAsset` para armazenar links e metadados de mídia. Uma mídia terá um "shortcode" único (ex: `[asset:xyz123]`) para que as IAs possam referenciá-la nas respostas textuais sem inflar o prompt da conversa com URLs diretas.

---

## Onde começa
A extensão `pgvector` foi ativada na base de dados (Tarefa 1.1) e a tabela `operations` já existe, porém sem qualquer infraestrutura de dados para anexos ou textos longos vetorizados.

## Onde termina
Duas novas tabelas e seus respectivos modelos ActiveRecord (`OperationKnowledge` e `OperationAsset`) estarão criados. Ambos suportarão colunas vetorizadas (embeddings). O modelo pai (`Operation`) estará devidamente relacionado a essas novas entidades.

---

## O que precisa ser feito

### No Backend
1. **Model e Migration OperationKnowledge**:
   Criar a estrutura relacionada a `Operation`. A tabela deve possuir campos para o conteúdo textual (`content`) e o vetor de similaridade (`embedding`, do tipo `vector` com limite numérico adequado para os modelos em uso, tipicamente 1536 para OpenAI ADA-002). Adicionar status `active`.

2. **Model e Migration OperationAsset**:
   Criar a estrutura para mídias relacionadas a `Operation`. Deve conter a URL do arquivo (`media_url`), tipo (`mime_type`), título e descrição, bem como o vetor da descrição (`embedding`, para busca semântica de mídia). Adicionar também uma coluna para o identificador curto `shortcode` (string única).

3. **Geração Automática de Shortcode**:
   Implementar lógica no modelo `OperationAsset` usando callbacks (ex: `before_validation`) para garantir que registros recém-criados gerem magicamente o seu próprio shortcode aleatório (ex: `SECURE12`), caso não tenha sido fornecido.

4. **Model Operation**:
   Adicionar os relacionamentos `has_many` para as novas entidades com opção `dependent: :destroy`.

### No Frontend
Não se aplica. Tarefa restrita a estruturação de banco de dados e backend models.

---

## Observações importantes
- Ao defnir os campos `vector` nas migrations, é recomendável adicionar o limite da dimensão (esquema `limit: 1536`) evitando falhas ao fazer pesquisas de indexação por cosseno.
- Caso o projeto mude o fornecedor de embeddings no futuro para um modelo de dimensões diferentes (ex: 768 no BERT), a coluna vetorial pode precisar de ajuste. Aceite o padrão do provedor atual da plataforma.

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. Migrations recém-criadas rodando limpas e podendo ser revertidas (`rails db:migrate:redo`).
2. Demonstrar pelo `rails c` a criação um `OperationAsset` e conferir que o `shortcode` foi efetivamente auto-gerado e salvo.
3. Verificar o schema do postgres (ex: instrução `\d operation_knowledges`) atestando a presença da coluna com tipo `vector(1536)`.
4. Os testes automatizados rodando sem quebras nas chaves estrangeiras.

---

## Dependências
- Tarefa 1.1: Setup pgvector & Database (`spec-016-operations-rag-pgvector.md`)

## Próxima tarefa
Tarefa 1.3: Background Embeddings Generation (`spec-018-background-embeddings.md`)
