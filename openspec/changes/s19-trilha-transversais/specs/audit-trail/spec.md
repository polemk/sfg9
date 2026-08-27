## ADDED Requirements

### Requirement: TRK-C1 — Trilha imutável: o evento nunca se perde e nunca é editado

O sistema **MUST** registrar os eventos de auditoria de forma imutável, **MUST** gravar o
evento mesmo quando o texto de resumo excede o limite da coluna, e **MUST NOT** oferecer
nenhum caminho de edição ou exclusão de evento já registrado.

> **Contrato transversal desta fatia, não item de paridade.** Ele **não existe no legado**:
> lá `resume` é limitado a 300 caracteres, a gravação retorna `false` quando o texto é maior
> e nenhum chamador verifica o retorno — **o evento desaparece**, e é sempre o evento do caso
> complicado. E **não existe na base ai9**:
> `backend/app/models/permission_audit_log.rb` é auditoria ad hoc de um assunto só, e
> `paper_trail` está no Gemfile **sem nenhum uso** (achado **C-12**) — e não serve, porque a
> semântica aqui é evento de negócio, não versionamento de registro.
> Os 27 IDs de paridade desta fatia têm requirements próprios em `openspec/specs/` e são
> referenciados por ID; este requirement é o contrato que os une.

Todo evento **MUST** ter autor; o destinatário **MAY** ser omitido. O evento **MUST** poder
referenciar tanto o objeto (`trackable`) quanto o seu pai (`trackable_parent`), de forma
polimórfica.

Quando o resumo excede o limite, o sistema **MUST** truncá-lo de forma explícita, com marca
de truncamento, e **MUST** preservar o texto integral no payload estruturado.

Além do resumo em texto, o evento **MUST** carregar campos estruturados — evento, entidade e
payload — de modo que a trilha seja consultável por filtros combináveis, e **MUST NOT**
depender de busca textual no resumo para responder a esses filtros.

O sistema **MUST NOT** armazenar cópia integral do registro auditado no payload.

A listagem global da trilha **MUST** exigir papel `og` ou `admin`; o histórico de um objeto
específico **MUST** ser visível a quem já pode ver esse objeto.

Toda gravação de trilha **MUST** passar pelo serviço único de trilha; nenhum outro caminho
de escrita na tabela **MUST** existir.

#### Scenario: resumo maior que o limite
- **GIVEN** um evento cujo resumo excede o limite da coluna
- **WHEN** ele é registrado
- **THEN** um evento é gravado, com o resumo truncado e marcado, e o texto integral fica no payload

#### Scenario: tentativa de editar um evento
- **GIVEN** um evento de trilha já gravado
- **WHEN** uma atualização ou exclusão é tentada
- **THEN** a operação levanta erro, e o evento permanece exatamente como estava

#### Scenario: evento sem autor
- **GIVEN** uma tentativa de registrar evento sem autor
- **WHEN** o serviço de trilha é chamado
- **THEN** a gravação é recusada com mensagem que nomeia o autor ausente

#### Scenario: filtros combinados
- **GIVEN** eventos de vários autores, alvos e períodos
- **WHEN** a listagem é consultada filtrando por autor e por período ao mesmo tempo
- **THEN** apenas os eventos que satisfazem os dois filtros são devolvidos, e o total informado é o total filtrado

#### Scenario: trilha global vista por papel insuficiente
- **GIVEN** um usuário com papel Colaborador
- **WHEN** ele consulta a listagem global da trilha
- **THEN** a resposta é 403; e o histórico de um objeto que ele pode ver continua acessível

#### Scenario: ciclo de vida completo de um job
- **GIVEN** um job que executa até o fim
- **WHEN** seus eventos são registrados
- **THEN** a trilha contém os quatro eventos do quarteto, na ordem de execução
