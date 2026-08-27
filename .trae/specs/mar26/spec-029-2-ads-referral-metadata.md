# Tarefa 029.2: Metadados de Anúncios CTWA/CTIA no Comentário

**Sprint:** 2 - Aquisição de Leads via Comentários no Instagram
**Estimativa:** 0.5 dia
**Tipo:** Backend

---

## Contexto
Quando um comentário de Instagram é originado de um Anúncio Pago (Click-to-Instagram), a Meta embute dentro do objeto JSON um bloco adicional de referência chamado `referral`.
Esses metadados (como `ad_id` da campanha e o identificador do clique `ctwa_clid`) são importantíssimos para Atribuição de Tráfego: permite ao negócio cruzar a inteligência de negócios do Ai9 com as campanhas que realmente geram leads e receita. Ignorar esse bloco resultaria em uma visão míope de ROAS (Retorno sobre Investimentos de Anúncio).

---

## Onde começa
- Handler do Webhook do Meta configurado na Tarefa 029.1 que já sabe separar a diferença entre `field: "messages"` e `field: "comments"`.
- A API de criação/cadastro de Leads que deve suportar receber UTMs/tags adicionais.

## Onde termina
- Tratamento explícito quando a chave `referral` vier no JSON do comentário do Hub Meta.
- O novo Lead cadastrado ganha colunas de metadados abastecidas com os valores Ads.

---

## O que precisa ser feito

### No Backend

1. **Leitura Extensiva no Normalizer:**
   - Após normalizar as raízes do Payload de comentário, implementar um `Safe Navigation Array/Hash Validator` para ver se existe a árvore: `changes[0].value.referral`.
   
2. **Extração Opcional:**
   - Se `referral` estiver presente, recolher se disponível:
     - `ref`: O parâmetro customizado criado no ato do anúncio (muitas lojas usam para cupons ou tags visuais).
     - `ad_id`: ID do anúncio Meta.
     - `ctwa_clid`: Meta Click ID do clique.
     - `ads_context_data.ad_title`: Nome da campanha.

3. **Injeção de Metadata:**
   - No envio asseptizado que repassa a Mensagem / Lead para o Storage, incluir como array ou Hash no bloco de `metadata` e/ou Atributos UTMs da tabela Lead.
   - Atualizar a API receptora, se necessário, para salvar as chaves `ad_id`, `ctwa_clid` e `ad_title` dentro da hash `custom_data` ou base oficial de campanha.

---

## Observações importantes
- Essa tarefa é propensa a exceções NoMethodError e Nil class, dado que 90% dos comentários (os orgânicos) virão SEM o bloco `referral`. O código precisa usar `.dig(:referral, :ref)` e afins no Ruby para extração defensiva e não derrubar o processamento do lado do Job Assíncrono.

---

## Critérios de aceite
O dev deve demonstrar que:
1. Jogando um mock JSON "comentário_com_referral.json" via spec/post, um Lead e sua Mensagem são atualizados possuindo o metadado CTWA inseridos.
2. Fazendo o teste orgânico "comentário_sem_referral.json", o processamento decorre com segurança retornando Sucesso até o final da pipeline.

---

## Dependências
- Tarefa 029.1

## Próxima tarefa
- **Tarefa 029.3:** Executar um Private Reply no Instagram usando o Comentário Capturado.
