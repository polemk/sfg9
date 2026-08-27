## ADDED Requirements

### Requirement: CFG-C1 — Contrato de configuração: origem única, boot fail-fast e padrão seguro

O sistema **MUST** obter toda configuração sensível de variáveis de ambiente, **MUST** falhar
o boot quando faltar qualquer variável obrigatória do ambiente corrente, e **MUST** adotar o
valor seguro como padrão em toda opção de segurança de transporte e de log.

> **Contrato transversal desta fatia, não item de paridade.** Ele **não existe no legado**:
> `config/development_credentials.yml:1` versiona um `secret_key_base` de 128 hex em texto
> puro, `config/credentials.yml.enc` existe sem `master.key`, `config/initializers/ssl_for_win.rb`
> desliga a verificação de certificado TLS e `config/puma.rb` fixa o ambiente como
> `development`. E **não existe na base ai9**: o mecanismo de ENV está certo
> (`dotenv-rails`, `.env*` ignorado, `*.example` versionado), mas nada obriga uma variável a
> existir — e a base repete o defeito de TLS em `config/environments/production.rb:83` e
> `development.rb:58` (`openssl_verify_mode: 'none'`, achado **C-05**).
> Os 29 IDs de paridade desta fatia têm requirements próprios em `openspec/specs/` e são
> referenciados por ID; este requirement é o contrato que os une.

O repositório **MUST NOT** versionar nenhum arquivo com valor de segredo real; o único
arquivo de configuração versionado **MUST** ser um `*.example` sem valores.

A lista de variáveis obrigatórias **MUST** ser definida **por ambiente**, e a mensagem de
falha de boot **MUST** nomear **todas** as variáveis ausentes de uma só vez — não apenas a
primeira.

A verificação de certificado TLS **MUST** estar ativa por padrão, e o desligamento **MUST**
exigir uma variável de ambiente explícita.

O log da aplicação **MUST NOT** conter `cpf`, `cnpj` nem `cpf_cnpj` em texto claro.

A política de segurança de conteúdo (CSP) **MUST** existir, e **MUST** nascer em modo
`report-only`, com a transição para modo bloqueante registrada como tarefa datada.

O ambiente de execução do servidor de aplicação **MUST** vir de variável de ambiente, e
**MUST NOT** ser fixado no arquivo de configuração.

Coerção de valor booleano e de moeda **MUST** ser feita por utilitário explícito, e o sistema
**MUST NOT** reabrir classes da linguagem para isso; o utilitário do servidor e o do cliente
**MUST** ser verificados contra o mesmo conjunto de casos.

#### Scenario: variável obrigatória ausente
- **GIVEN** o ambiente de produção sem `SECRET_KEY_BASE` definido
- **WHEN** a aplicação é iniciada
- **THEN** o processo não sobe, e a mensagem de erro nomeia a variável ausente

#### Scenario: várias variáveis obrigatórias ausentes
- **GIVEN** três variáveis obrigatórias ausentes
- **WHEN** a aplicação é iniciada
- **THEN** a mensagem de erro nomeia as três, e não apenas a primeira

#### Scenario: suíte de testes sem integração externa
- **GIVEN** o ambiente de teste, sem nenhuma variável de integração externa definida
- **WHEN** a suíte é executada
- **THEN** ela roda até o fim, porque a lista de obrigatórias é por ambiente

#### Scenario: TLS verificado por padrão
- **GIVEN** nenhuma variável de escape definida
- **WHEN** a aplicação abre uma conexão TLS de saída
- **THEN** o certificado do par é verificado

#### Scenario: documento com CPF não vaza no log
- **GIVEN** uma requisição cujo corpo contém um CPF
- **WHEN** ela é registrada no log
- **THEN** o valor aparece mascarado

#### Scenario: nenhum segredo versionado
- **GIVEN** a árvore de arquivos versionados
- **WHEN** a varredura de segredos do CI é executada
- **THEN** nenhum valor de segredo real é encontrado, e o único arquivo de configuração presente é o de exemplo

#### Scenario: coerção de moeda concorda entre servidor e cliente
- **GIVEN** o conjunto de casos golden extraído do legado
- **WHEN** o utilitário do servidor e o do cliente convertem cada caso
- **THEN** os dois produzem o mesmo valor, inclusive para vazio, nulo e negativo
