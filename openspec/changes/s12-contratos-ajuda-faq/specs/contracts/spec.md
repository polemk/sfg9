# Contracts — deltas da fatia S12

> Os 40 requirements de inventário desta capability **já existem** em
> `openspec/specs/contracts/spec.md` (BE-330…BE-349, FE-330…FE-342, DB-330, DB-331,
> OPS-330…OPS-334). **Não são recriados aqui.**
>
> O que segue são os requirements **novos**, sem ID de inventário: a propriedade
> append-only do versionamento, e a condição de resposta uniforme do contrato **C1** aplicada
> a um catálogo global (contrato não é escopado por projeto — a checagem é de autorização).

## ADDED Requirements

### Requirement: VER-S12 — Versionamento append-only com numeração atribuída só na criação
O sistema SHALL tratar cada versão publicada de contrato como **imutável**, SHALL resolver a
versão vigente pela **maior `version`** do tipo — nunca pelo maior `id` — e SHALL atribuir o
número de versão **apenas na criação**, com unicidade garantida pelo banco.

Contexto: no legado `before_save :version_guess` (`app/models/contract.rb:2`) rodava em todo
`save`, de modo que **re-salvar incrementava a versão**; e `generate_new_version` usava
`.last` sem `order`, resolvendo a "vigente" pelo maior `id` (BE-331, BE-336).

#### Scenario: Re-salvar não cria versão nova
- **GIVEN** um contrato publicado na versão 3
- **WHEN** o registro é salvo novamente sem intenção de publicar
- **THEN** a versão continua 3 e nenhuma versão nova é criada

#### Scenario: A vigente é a maior versão, não o registro mais recente
- **GIVEN** as versões 1, 2 e 3 de um tipo, e a versão 2 tendo sido gravada por último
- **WHEN** a versão vigente é resolvida
- **THEN** a versão 3 é servida

#### Scenario: Publicações concorrentes recebem números distintos
- **GIVEN** duas publicações simultâneas do mesmo tipo de contrato
- **WHEN** ambas são gravadas
- **THEN** cada uma recebe um número de versão distinto, garantido pelo banco e não pela
  aplicação

#### Scenario: Versão publicada é imutável
- **GIVEN** uma versão já publicada
- **WHEN** alguém tenta alterar seu conteúdo
- **THEN** a alteração é recusada, e a única forma de mudar o texto é publicar uma nova
  versão

### Requirement: C1-S12 — Recurso identificado por parâmetro responde igual para inexistente e inacessível
O sistema SHALL resolver todo identificador recebido por parâmetro dentro do escopo de
autorização do solicitante, e SHALL responder o **mesmo status** para um identificador
inexistente e para um identificador que o solicitante não pode acessar.

Contexto: condição do contrato **C1** (`migration-map.md`). Distinguir 403 de 404 transforma
a API em oráculo de existência de id.

#### Scenario: Escrita sem permissão é recusada pelo servidor
- **GIVEN** um usuário sem papel administrativo
- **WHEN** ele chama diretamente o endpoint de publicação de nova versão
- **THEN** a operação é recusada pelo servidor, independentemente de a interface exibir ou
  não o botão

#### Scenario: Inexistente e inacessível respondem igual
- **GIVEN** um identificador que não existe e um identificador que o solicitante não pode
  acessar
- **WHEN** ambos são usados na mesma rota
- **THEN** as duas respostas têm o mesmo status
