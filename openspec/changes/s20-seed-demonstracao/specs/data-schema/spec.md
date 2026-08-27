# Delta: data-schema — o seed de demonstração

> **Não recria requisitos do legado.** Não há o que replicar: o seed do legado
> (`sfg/db/seeds.rb:243-268`) é marcado no próprio código como
> `#TODO: seed feito somente para video de aprovacao` e produz taxa de 87% ao mês. Os
> requisitos abaixo nascem da **DEC-64** e do desenho `.migration-ai9/demo-seed-design.md`.

## ADDED Requirements

### Requirement: S20-01 — O seed de demonstração é separado do seed de produção

O sistema SHALL manter o seed de demonstração em `db/seeds/demo/`, acionado **apenas** por
`rake demo:seed`, e SHALL NOT executá-lo como parte de `db:seed`.

> Nota: no cutover real o dado da demonstração não pode entrar. Separar por diretório e por
> tarefa é a única forma que não depende de alguém lembrar de uma variável de ambiente.

#### Scenario: `db:seed` num ambiente limpo
- **GIVEN** um banco sem nenhum dado de demonstração
- **WHEN** `rake db:seed` é executado
- **THEN** nenhum projeto, empresa, borderô ou usuário de demonstração é criado

#### Scenario: `demo:seed` é explícito
- **GIVEN** um banco com os seeds de referência aplicados
- **WHEN** `rake demo:seed` é executado
- **THEN** o dado de demonstração é criado e o seed de referência não é duplicado

### Requirement: S20-02 — O seed é idempotente por chave natural

O sistema SHALL usar `find_or_initialize_by` com chave natural estável em todo registro que
o seed de demonstração cria, e SHALL produzir contagens idênticas quando executado duas
vezes seguidas sobre o mesmo banco.

> Nota: a chave natural de cada agregado coincide com um índice único já planejado pela
> fatia dona. Chave que o schema não tem é duplicata entrando por outra porta.

#### Scenario: Segunda execução consecutiva
- **GIVEN** um banco onde `rake demo:seed` já rodou até o fim
- **WHEN** `rake demo:seed` é executado de novo, sem `reset`
- **THEN** a contagem de registros de cada tabela semeada é exatamente a mesma da primeira
  execução, e nenhum registro é duplicado

#### Scenario: Execução interrompida no meio
- **GIVEN** uma execução anterior que parou depois de gravar os projetos e antes das empresas
- **WHEN** `rake demo:seed` é executado de novo
- **THEN** os projetos existentes são reaproveitados pela chave natural e a execução segue
  do ponto que faltava, sem criar projeto duplicado

### Requirement: S20-03 — Um módulo cujo model ainda não existe pula com aviso explícito

O sistema SHALL organizar o seed em módulos por agregado, em ordem explícita de dependência,
e cada módulo SHALL declarar os models que exige. Quando um model exigido não estiver
definido, o módulo SHALL ser pulado e SHALL emitir aviso identificando o model ausente e a
fatia que o entrega. O seed SHALL prosseguir com os módulos restantes.

> Nota: a S20 roda antes de S3..S11. Um seed que só funciona quando tudo existe é um seed
> que nunca roda antes da demonstração (DEC-64). Um seed que pula em silêncio é pior: ele
> "roda sem erro" na véspera e não semeia nada.

#### Scenario: Model de domínio ainda não entregue
- **GIVEN** um banco em que a tabela `companies` ainda não existe
- **WHEN** `rake demo:seed` é executado
- **THEN** o módulo de empresas é pulado com aviso nomeando `Company` e a fatia S4, os
  módulos que não dependem dele são executados normalmente, e a tarefa termina com sucesso

#### Scenario: Model de domínio entregue depois
- **GIVEN** o mesmo banco depois de a fatia S4 ter criado `companies`
- **WHEN** `rake demo:seed` é executado de novo
- **THEN** o módulo de empresas passa a gravar, sem que nenhum módulo anterior duplique
  registro

### Requirement: S20-04 — A cadeia aritmética fecha entre domínios

O sistema SHALL derivar os valores do seed de um único gerador determinístico, de forma que
`Project → Company → (Carrier, limite, taxa) → borderôs → movimentos → saldo` seja coerente:
o saldo de uma operação SHALL ser o acumulado dos seus movimentos na ordem de `sequence`; o
valor final de um borderô SHALL ser o bruto menos o recusado; a soma das operações vivas de
uma empresa num carrier e modalidade SHALL NOT ultrapassar o limite do `RiskControl`
correspondente; e o indicador de volume operado de um mês SHALL ser a soma dos borderôs
daquele mês.

> Nota: é a razão de a DEC-64 ter feito disto uma fatia própria. Painel que mostra um total
> diferente da soma da lista que o gerou é, numa demonstração comercial, pior que tela vazia.

#### Scenario: Saldo conferido contra os movimentos
- **GIVEN** uma operação de risco semeada com os seus movimentos
- **WHEN** os movimentos são somados na ordem de `sequence`, respeitando a convenção de sinal
  (DEC-01)
- **THEN** o resultado é igual ao saldo persistido da operação

#### Scenario: Limite nunca estourado
- **GIVEN** qualquer trio (empresa, carrier, modalidade) com `RiskControl` semeado
- **WHEN** os saldos das operações vivas daquele trio são somados
- **THEN** o total é menor ou igual ao limite do controle

#### Scenario: Total do painel bate com a lista
- **GIVEN** um mês qualquer da série de 24 meses
- **WHEN** o indicador de volume operado daquele mês é comparado à soma dos
  `vlr_bruto_final` dos borderôs do mesmo mês
- **THEN** os dois números são iguais

### Requirement: S20-05 — O dado é plausível para gestão de crédito brasileira

O sistema SHALL gerar razões sociais, documentos e valores verossímeis: CNPJ com dígito
verificador válido, taxas dentro das faixas praticadas no mercado, valores monetários sem
arredondamento redondo, e datas relativas a uma data-base parametrizável. O sistema SHALL
NOT usar rótulos de teste como "Empresa 1", "Teste" ou "Lorem", e SHALL NOT nomear
instituições financeiras reais nem usar códigos bancários atribuídos.

> Nota: número errado destrói mais credibilidade do que nome feio. O seed do legado sorteia
> limite entre R$ 0 e R$ 100 milhões e taxa entre 0% e 100% ao mês; quem é do mercado
> desqualifica a tela em dois segundos. E carrier com nome de banco real, numa demonstração
> comercial, sugere relação comercial que não existe.

#### Scenario: Documentos das empresas
- **GIVEN** o conjunto de empresas semeadas
- **WHEN** o CNPJ de cada uma é validado pelo cálculo dos dois dígitos verificadores
- **THEN** todos são válidos, e as empresas de um mesmo grupo compartilham a raiz de 8
  dígitos, variando apenas o número da filial

#### Scenario: Faixas de taxa
- **GIVEN** o conjunto de limites e taxas semeados
- **WHEN** as taxas ao mês são examinadas
- **THEN** todas estão dentro das faixas de mercado declaradas por contraparte, e nenhuma
  taxa de operação diverge mais de 0,15 ponto percentual da taxa do controle que a rege

#### Scenario: Data-base
- **GIVEN** o seed executado em dois dias diferentes
- **WHEN** as datas dos registros são comparadas à data de execução
- **THEN** a série continua terminando no mês corrente, sem registro vencido por
  envelhecimento do seed
