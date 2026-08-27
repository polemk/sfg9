# Ops & Config Specification

## Purpose
Define a configuração, os segredos, os initializers, o ambiente de execução e o pipeline de build do
ai9 para o domínio migrado do legado `sfg`. O legado configura por **cópia manual de variantes por
plataforma** (`config/application.{arch,centos,osx,win}.yml`, `config/database.{arch,centos,linux,osx,win}.yml`,
três `Gemfile`), com segredos versionados e o efetivo no `.gitignore`. No ai9 tudo vira **ENV/credentials
por ambiente**, com exemplo versionado e valor real fora do repositório
(`.migration-ai9/ai9-conventions.md` §3.11). Timezone passa a UTC e as constantes de negócio de
`SFG::Metadata` viram configuração.

## Requirements

### Requirement: OPS-600 — Boot da aplicação
O ai9 **MUST** carregar o framework completo do Rails 8 com autoloading Zeitwerk e
`belongs_to_required_by_default` **habilitado**, substituindo o boot do legado, que carrega railties a
dedo (`rails/all` comentado), fixa `load_defaults 6.0` sob Rails 6.1.4, usa
`config.autoloader = :classic` e desabilita a obrigatoriedade de `belongs_to`. Fonte legada:
`config/application.rb:1-30`.

- Consequência do legado: **todas** as associações `belongs_to` são opcionais, e `ActionCable`,
  `ActiveStorage::Engine` (parcial) e `sprockets` não são carregados.

#### Scenario: associação obrigatória por padrão
- **GIVEN** um model do ai9 com `belongs_to :project`
- **WHEN** um registro é salvo sem projeto
- **THEN** a validação falha, em vez de gravar referência nula como no legado

#### Scenario: framework completo disponível
- **GIVEN** a aplicação iniciada
- **WHEN** Action Cable é usado
- **THEN** ele está carregado, sem depender de inclusão manual de railtie

### Requirement: OPS-601 — Locale, fuso e formatação de data
O ai9 **MUST** operar com `default_locale = "pt-BR"`, armazenamento de timestamps em **UTC** e
apresentação em `America/Sao_Paulo`, substituindo o legado, que grava em horário local
(`active_record.default_timezone = :local`, `time_zone = 'Brasilia'`). Fonte legada:
`config/application.rb:26-29`.

- O legado também inclui `Rails.root/my/locales/**` no `i18n.load_path`, e **o diretório `my/` não
  existe** — configuração morta que **MUST NOT** ser portada.

#### Scenario: gravação em UTC
- **GIVEN** um registro criado às 10:00 em Brasília
- **WHEN** o timestamp é persistido
- **THEN** o banco guarda o instante em UTC e a interface o exibe como 10:00 no fuso de Brasília

#### Scenario: formatos de data em pt-BR
- **GIVEN** uma data exibida na interface
- **WHEN** ela é formatada
- **THEN** o formato padrão é `%d/%m/%Y`, como no legado

#### Scenario: caminho de locale inexistente descartado
- **GIVEN** a configuração de i18n do ai9
- **WHEN** ela é inspecionada
- **THEN** não há caminho de carga apontando para diretório inexistente

> Nota: corrige D-102 (legado: `default_timezone = :local` com offset não constante por causa do horário de verão até 2019)

### Requirement: OPS-602 — Carregamento de código
O ai9 **MUST** usar autoloading padrão (Zeitwerk) e **MUST** falhar de forma visível quando um arquivo
não carrega, substituindo o esquema do legado, que adiciona caminhos manuais (`db/factories`, `lib`,
`app/models/decorators`, `app/constants`, `app/definitions`, `app/generators`, `app/adapters`) e faz
`require`/`load` explícito de todo `app/decorators/**/*_decorator*.rb` e todo `lib/*.rb` num
`to_prepare`. Fonte legada: `config/application.rb:31-55`.

- No legado, erros de carga são **engolidos e impressos** (`puts "Não conseguiu definir…"`, linhas 44 e
  52): um decorator quebrado passa despercebido; e em desenvolvimento o `to_prepare` recarrega tudo a
  cada requisição.

#### Scenario: arquivo com erro de sintaxe
- **GIVEN** um arquivo da aplicação com erro de carga
- **WHEN** a aplicação inicia
- **THEN** o boot falha com a exceção original, em vez de imprimir uma mensagem e seguir com a funcionalidade ausente

#### Scenario: nenhum decorator monkey-patching por convenção
- **GIVEN** o código do ai9
- **WHEN** ele é inspecionado
- **THEN** o comportamento vive em classes e services próprios, sem `load` explícito de decorators no boot

### Requirement: OPS-603 — Definições de marca carregadas por caminho explícito
O ai9 **MUST** expor as definições de marca (cores, logos, metadados) como configuração carregada pelo
autoloading normal, substituindo o `require` direto e **case-sensitive** de
`app/definitions/SFG/theme.rb` e `metadata.rb` no legado — o mesmo caminho maiúsculo que fez esses
arquivos ficarem de fora do grafo do graphify. Fonte legada: `config/application.rb:57-59` (com o
comentário `#FIXME: executar pré-definições automaticamente`).

#### Scenario: caminho independente de caixa
- **GIVEN** um sistema de arquivos sensível a maiúsculas e minúsculas
- **WHEN** as definições de marca são carregadas
- **THEN** o carregamento funciona sem depender da grafia exata de um diretório em maiúsculas

#### Scenario: definições visíveis para ferramentas
- **GIVEN** uma ferramenta que varre o código do ai9
- **WHEN** ela indexa os arquivos
- **THEN** as definições de marca aparecem no índice, porque são carregadas pelo mecanismo padrão

### Requirement: OPS-604 — Configuração do domínio de autenticação
O ai9 **MUST** portar as opções de domínio hoje configuradas na engine de autenticação como
**configuração explícita por ambiente**, e **MUST** dar a todo usuário novo um papel definido. Fonte
legada: `config/application.rb:64-73`.

- Valores do legado: `default_role_type = ""` (**vazio** — usuário novo nasce sem papel); apelidos de
  domínio: entidades privadas = "Projetos", públicas = "Módulos"; **tetos de 1000** para projetos
  privados, módulos públicos, usuários e convites; `secret_key` vindo de
  `credentials.env.secret_key_base`.

#### Scenario: usuário novo tem papel
- **GIVEN** um usuário criado sem papel informado
- **WHEN** o registro é persistido
- **THEN** ele recebe o papel padrão definido em configuração, em vez de ficar sem papel

#### Scenario: tetos configuráveis
- **GIVEN** o teto de 1000 projetos herdado do legado
- **WHEN** a configuração é ajustada
- **THEN** o novo teto passa a valer sem alteração de código

### Requirement: OPS-605 — Login social desativado por configuração
O ai9 **MUST** manter o login social desativado por configuração explícita, e não por valores
sentinela. Fonte legada: `config/application.rb:75-80`; `SFG::Metadata::FACEBOOK_APP_ID/SECRET` = `0`;
`facebook_callback_url = "#{ENV['alias']}/users/auth/facebook/callback"`;
`facebook_default_role_type_for_sign_up = ""`.

#### Scenario: flag de configuração e não valor mágico
- **GIVEN** a configuração de login social
- **WHEN** ela é lida
- **THEN** existe uma chave booleana explícita de habilitação, em vez de depender de app id igual a `0`

#### Scenario: desativado por padrão
- **GIVEN** um ambiente ai9 recém-provisionado
- **WHEN** a tela de login é aberta
- **THEN** o login social não é oferecido

### Requirement: OPS-606 — Configuração da experiência de autenticação
O ai9 **MUST** portar as opções de experiência de login/cadastro como configuração, corrigindo o ano
fixo do rodapé e resolvendo a divergência de cores de marca. Fonte legada: `config/application.rb:82-90`.

- Valores do legado: redirecionamento pós-cadastro para `/console`;
  `minimal_type_to_sign_up_through_web = "Admin"`; rodapé
  `"© Copyright 2021 · safegold.com.br · livetat.com · Todos os direitos reservados"` (**ano fixo
  2021**); logo do login `brand/app_text_400.png`; `sign_up_accent_color = "#F43735"` (vermelho) contra
  `SFG::Theme.COLOR__ACCENT = #FFC107` (âmbar); fundo do sign-up
  `radial-gradient(circle, #fdfdff, #fff)` contra `COLOR__LOGIN_BKG = #FBFBFB`.

#### Scenario: ano do rodapé
- **GIVEN** a aplicação em execução em qualquer ano
- **WHEN** o rodapé é renderizado
- **THEN** o ano exibido é o corrente, e não 2021 fixo

#### Scenario: cor de destaque única
- **GIVEN** as telas de login e de cadastro
- **WHEN** elas são renderizadas
- **THEN** usam o mesmo token de destaque da marca, sem uma terceira cor divergente definida em configuração

### Requirement: OPS-607 — Configuração de e-mail
O ai9 **MUST** ler toda a configuração de e-mail de ENV/credentials, **incluindo a porta SMTP**, e
**MUST** usar os tokens de marca do tema nos e-mails. Fonte legada: `config/application.rb:92-109`;
chaves em `config/application.*.yml`.

- Valores do legado: cor primária de e-mail `#1f2428` e destaque `#F43735` (ambos divergindo do tema),
  logo branco `app/frontend/images/brand/app_logo_250.png`, `app_name = "Safegold"`, slogan e mensagem
  vazios; SMTP inteiramente por ENV (8 chaves).
- **`smtp_settings.port` nunca é atribuída** em `config/application.rb`, embora o engine a leia
  (`engines/mailer19/lib/livetat/mailer19/engine.rb:45`) e a chave `smtp_settings_port: "587"` exista
  em `config/application.*.yml:4`.

#### Scenario: porta chega ao cliente SMTP
- **GIVEN** a porta configurada no ambiente
- **WHEN** a aplicação inicializa o e-mail
- **THEN** a porta configurada é usada, e não o default 25 por valor nulo

#### Scenario: cores do e-mail vêm da marca
- **GIVEN** o tema da aplicação
- **WHEN** um e-mail é montado
- **THEN** as cores usadas são as do tema, sem uma paleta paralela definida na configuração de e-mail

> Nota: corrige D-112 (legado: `smtp_settings_port` existe no yml e é lida pelo engine, mas nunca é atribuída, deixando o SMTP sem porta)

### Requirement: OPS-608 — Assinatura DKIM configurada por secret
O ai9 **MUST** configurar a assinatura DKIM (domínio e seletor) por ENV/credentials, com a chave
privada fornecida como secret, e **MUST** liberar o descritor de arquivo após a leitura. Fonte legada:
`config/application.rb:110-114`; chave em `lib/dkim_private_key.pem`, lida com `open(...)` sem fechar,
dentro do `before_initialize`.

#### Scenario: chave lida sem vazar descritor
- **GIVEN** a inicialização da aplicação
- **WHEN** a chave DKIM é carregada
- **THEN** o arquivo (ou o segredo) é lido e liberado, sem descritor pendurado no processo

#### Scenario: domínio e seletor configuráveis
- **GIVEN** a necessidade de trocar o seletor DKIM após a rotação da chave
- **WHEN** a configuração é ajustada
- **THEN** a nova assinatura passa a valer sem alteração de código

> Nota: corrige D-85 (legado: chave privada DKIM commitada no repositório — comprometida, precisa ser rotacionada e virar secret)

### Requirement: OPS-609 — Credenciais por ambiente
O ai9 **MUST** resolver credenciais por ambiente usando o mecanismo padrão do Rails 8 + `dotenv`,
substituindo o `CredentialsByEnvironment` do legado, que carrega
`config/#{Rails.env}_credentials.yml`, **define um método por chave dinamicamente** e delega o resto por
`method_missing` para `Rails.application.credentials`. Fonte legada:
`config/credentials_by_environment.rb:1-30`; instalado em `config/application.rb:62`.

- O legado usa `File.exists?`, removido no Ruby 3.x — potencial `NoMethodError` no boot em runtime mais
  novo.

#### Scenario: chave ausente falha cedo
- **GIVEN** uma credencial obrigatória não definida no ambiente
- **WHEN** a aplicação inicia
- **THEN** o boot falha nomeando a chave, em vez de devolver nulo por `method_missing` e quebrar mais tarde

#### Scenario: sem definição dinâmica de métodos
- **GIVEN** o acesso a uma credencial no código do ai9
- **WHEN** ele é lido
- **THEN** o acesso é explícito e rastreável, sem métodos criados em tempo de execução por chave

### Requirement: OPS-610 — Nenhum segredo de assinatura versionado
O ai9 **MUST NOT** versionar `secret_key_base` de nenhum ambiente. No legado,
`config/development_credentials.yml:1` traz uma chave de 128 hex em texto puro no git; como ela assina
os cookies de sessão, qualquer ambiente não-produção que a use tem **sessões forjáveis**.

#### Scenario: repositório sem chave de assinatura
- **GIVEN** o repositório do ai9
- **WHEN** ele é varrido por segredos
- **THEN** nenhum `secret_key_base` literal é encontrado, nem para desenvolvimento

#### Scenario: ambiente sem chave não sobe
- **GIVEN** um ambiente sem `SECRET_KEY_BASE` definido
- **WHEN** a aplicação inicia
- **THEN** o boot falha explicitamente

> Nota: corrige D-85 (legado: segredos commitados — mesma família da chave DKIM, da senha SMTP e do token da ReceitaWS)

### Requirement: OPS-611 — Falha no boot quando o segredo obrigatório falta
O ai9 **MUST** exigir os segredos obrigatórios **no boot**, corrigindo o legado, em que
`config.require_master_key` está **comentado** (`config/environments/production.rb:17`) e uma produção
sem `RAILS_MASTER_KEY` (ou `config/master.key`, nenhum dos dois versionado) **sobe e falha depois**.
Fonte legada: `config/credentials.yml.enc`; `.gitignore:175`.

#### Scenario: produção sem chave mestra
- **GIVEN** um ambiente de produção sem o segredo de descriptografia das credenciais
- **WHEN** a aplicação inicia
- **THEN** o boot falha imediatamente com mensagem clara, em vez de subir e quebrar na primeira funcionalidade que precisa de credencial

#### Scenario: inventário de segredos obrigatórios
- **GIVEN** a lista de segredos obrigatórios do ai9
- **WHEN** o ambiente é provisionado
- **THEN** a ausência de qualquer um deles é detectada na inicialização

### Requirement: OPS-612 — Configuração por ambiente, não por plataforma
O ai9 **MUST** ter **um** mecanismo de configuração por ambiente (ENV/dotenv com exemplo versionado),
substituindo as quatro variantes de plataforma do legado
(`config/application.{arch,centos,osx,win}.yml`, 12 linhas cada), que cada desenvolvedor copia para o
`config/application.yml` efetivo — este, sim, no `.gitignore:174`. Fonte legada: os 4 arquivos.

- Divergências reais entre as variantes: `arch`/`osx` apontam para `http://localhost:8192`, `centos`
  para o staging real `https://stg02-sfgv1.livetat.com`, e `win` difere apenas no caminho do
  ImageMagick (`C:\Program Files\ImageMagick-7.0.1-Q16`).
- O **token da ReceitaWS está commitado em texto puro nos 4 arquivos** (`:12`);
  `smtp_settings_password` aparece mascarado como `xxx`.
- A chave `paperclip_path` **MUST** ser descartada: o grep confirma zero leituras no código.

#### Scenario: um arquivo de exemplo, valores fora do repositório
- **GIVEN** um desenvolvedor novo configurando o ambiente
- **WHEN** ele segue o exemplo versionado
- **THEN** ele preenche valores locais em arquivo ignorado pelo git, sem copiar variante de plataforma

#### Scenario: chave morta descartada
- **GIVEN** a lista de chaves de configuração do ai9
- **WHEN** ela é revisada
- **THEN** `paperclip_path` não está presente

#### Scenario: nenhum token versionado
- **GIVEN** os arquivos de configuração versionados do ai9
- **WHEN** eles são inspecionados
- **THEN** contêm apenas placeholders, nunca credenciais reais

> Nota: corrige D-85 (legado: token da ReceitaWS commitado nos 4 yml) e D-119 (legado: `paperclip_path` sem nenhuma leitura)

### Requirement: OPS-613 — Configuração de banco por ambiente
O ai9 **MUST** configurar o banco por `DATABASE_URL`/arquivo ignorado pelo git com exemplo versionado,
e **MUST** ter **uma única** conexão, sem a conexão secundária `sfg_legacy`. Fonte legada: as 5
variantes `config/database.{arch,centos,linux,osx,win}.yml`; o efetivo `config/database.yml` está no
`.gitignore:173`.

- Divergências reais do legado: `linux` define `development_psql` (nome não-padrão, nunca usado pelo
  Rails) e uma produção **MySQL2 via socket**, enquanto `centos` (o staging real) define produção
  **PostgreSQL** — as duas se contradizem; `win` traz um `development_msql` órfão. **Todas** as
  variantes trazem o bloco `sfg_legacy`. Pool 10 (20 no MySQL).
- **Senha em texto puro** `livetat&sfg251` em `config/database.linux.yml:8,25` (nas demais, mascarada).
- Conforme DEC-05, o banco é **PostgreSQL**; conforme a convenção do ai9, a branch de migração usa
  banco próprio (`sfg9_dev`/`sfg9_test`).

#### Scenario: banco próprio da branch de migração
- **GIVEN** o ambiente de desenvolvimento da branch `sfg9`
- **WHEN** a aplicação conecta
- **THEN** ela usa `sfg9_dev`, sem misturar dado do produto base com dado do cliente migrado

#### Scenario: nenhuma conexão secundária ao legado
- **GIVEN** a configuração de banco do ai9
- **WHEN** ela é inspecionada
- **THEN** não existe bloco `sfg_legacy` nem segunda conexão

#### Scenario: nenhuma senha versionada
- **GIVEN** os arquivos de configuração de banco versionados
- **WHEN** eles são inspecionados
- **THEN** contêm apenas placeholders

> Nota: corrige D-85 (legado: senha de banco em texto puro em `config/database.linux.yml:8,25`) e DEC-12 (legado: bloco `sfg_legacy` presente em todas as variantes)

### Requirement: OPS-614 — Dependências reprodutíveis
O ai9 **MUST** ter **um** `Gemfile` com `Gemfile.lock` versionado e versões vindas de rubygems,
substituindo os três Gemfiles do legado (`Gemfile.linux`, `Gemfile.osx`, `Gemfile.prod`), com o
`Gemfile` e o `Gemfile.lock` efetivos no `.gitignore:171-172`. Fonte legada: `Gemfile.linux:1-55`,
`Gemfile.osx`, `Gemfile.prod`.

- Diferenças do legado: `Gemfile.prod` fixa **Ruby 2.6.1 + Rails 6.0.3.2**, enquanto `Gemfile.linux` usa
  Ruby 3.0.2 + Rails 6.1.4 e `Gemfile.osx`, Ruby 3.0.1 + Rails 6.1.3.1. Produção usa forks próprios de
  `delayed_job`/`delayed_job_active_record` (`github.com/livetat/…`, branch `rails-6-compatibility`),
  `wkhtmltopdf-binary-edge`, `mini_racer`, Puma 3.12 e `deep_cloneable ~> 2.4`; o Rails vem de **git
  tag**, não do rubygems.

> AMBIGUIDADE — DEC-11 confirmou Ruby 2.6.1 / Rails 6.0.3.2 como ambiente de produção, mas
> `Gemfile.prod` foi tocado pela última vez em maio/2021 (`3deef40`) enquanto as migrations vão até
> agosto/2022 e `SFG::Metadata::DESCRIPTION` anuncia a versão 1.11.1 de 06/04/2023. Se o deploy real
> não usa `Gemfile.prod`, o ambiente de referência de paridade muda. Confirmar no servidor com
> `ruby -v` e `bundle exec rails -v`.

#### Scenario: build reprodutível
- **GIVEN** duas máquinas instalando as dependências do ai9
- **WHEN** o bundle é instalado
- **THEN** ambas obtêm exatamente as mesmas versões, porque o lock está versionado

#### Scenario: ambiente de referência de paridade
- **GIVEN** a necessidade de extrair valores golden do legado para comparação financeira
- **WHEN** o ambiente legado é reconstruído
- **THEN** ele usa Ruby 2.6.1 / Rails 6.0.3.2 e o fork do `delayed_job`, conforme DEC-11

### Requirement: OPS-615 — Ambiente de desenvolvimento
O ai9 **MUST** ter ambiente de desenvolvimento com recarga eficiente de código e sem derrubar a página
por chave de tradução ausente. Fonte legada: `config/environments/development.rb:1-34`.

- No legado: cache ligado apenas se existir `tmp/caching-dev.txt`; `active_storage.service = :local`;
  **`raise_on_missing_translations = true`** (`:29`); `reload_classes_only_on_change = false`
  (recarrega tudo a cada requisição, necessário por causa do `to_prepare` de OPS-602);
  `verbose_query_logs` ligado.

#### Scenario: tradução ausente
- **GIVEN** uma chave de i18n não definida
- **WHEN** a página é renderizada em desenvolvimento
- **THEN** um aviso é registrado e a página continua utilizável

#### Scenario: recarga só do que mudou
- **GIVEN** uma requisição em desenvolvimento sem alteração de código
- **WHEN** ela é processada
- **THEN** nenhuma recarga completa de classes acontece

### Requirement: OPS-616 — Ambiente de produção
O ai9 **MUST** ter produção com `cache_store` compartilhado, estáticos servidos por camada dedicada,
armazenamento de anexos que sobrevive a redeploy e HTTPS forçado. Fonte legada:
`config/environments/production.rb:1-42`.

- No legado: `perform_caching` ligado **sem `cache_store` definido** (cache de memória por processo,
  não compartilhado entre os 2 workers do Puma); `public_file_server.enabled = true` **forçado**
  (`:19`, com o check de `RAILS_SERVE_STATIC_FILES` comentado), sem CDN nem nginx à frente;
  `active_storage.service = :local` (uploads não sobrevivem a redeploy em container); log `:info` com
  `request_id` e `autoflush_log = false`; **sem `force_ssl`**, sem `asset_host`,
  `dump_schema_after_migration = false`.

#### Scenario: cache compartilhado entre workers
- **GIVEN** dois processos da aplicação em produção
- **WHEN** um deles grava no cache
- **THEN** o outro enxerga o mesmo valor

#### Scenario: conexão sem TLS
- **GIVEN** uma requisição HTTP simples em produção
- **WHEN** ela chega
- **THEN** é redirecionada para HTTPS

#### Scenario: chave morta de estáticos descartada
- **GIVEN** a lista de chaves de configuração do ai9
- **WHEN** ela é revisada
- **THEN** `RAILS_SERVE_STATIC_FILES` não está presente, porque o serviço de estáticos é decidido pela camada de infraestrutura

> Nota: corrige D-119 (legado: `RAILS_SERVE_STATIC_FILES` comentada e valor forçado — chave que engana quem lê)

### Requirement: OPS-617 — Suíte de testes
O ai9 **MUST** ter suíte de testes automatizados (RSpec no backend, Vitest no frontend, conforme
`ai9-conventions.md` §6), incluindo **testes de caracterização** que travam os números financeiros do
legado. O legado **não tem nenhum teste**: não existem `test/` nem `spec/`, e nenhum Gemfile traz gem
de teste — só o `config/environments/test.rb:1-47` padrão e intocado.

#### Scenario: paridade financeira travada por teste
- **GIVEN** valores golden extraídos do legado
- **WHEN** a suíte roda
- **THEN** qualquer divergência de cálculo financeiro falha a build

#### Scenario: CI executa a suíte
- **GIVEN** um pull request
- **WHEN** o CI roda
- **THEN** a suíte de backend e de frontend é executada e o resultado bloqueia o merge em caso de falha

### Requirement: OPS-618 — Sentinelas de data do domínio
O ai9 **MUST** portar as sentinelas de data usadas pelos filtros (`dinosaurs` = hoje − 2000 anos e
`mars` = hoje + 2000 anos, como limites "infinitos"; `today_start` = meia-noite) e **MUST** corrigir o
fim do dia. Fonte legada: `config/initializers/date_overload.rb:1-17`.

- No legado, `today_end` é **23:59** — registros criados no último minuto do dia ficam de fora de
  qualquer filtro que o use.

#### Scenario: registro criado às 23:59:30
- **GIVEN** um registro criado às 23:59:30
- **WHEN** um filtro "hoje" é aplicado
- **THEN** o registro é incluído, porque o fim do dia é o último instante e não 23:59

#### Scenario: limites abertos de intervalo
- **GIVEN** um filtro sem data inicial nem final informada
- **WHEN** a consulta é montada
- **THEN** as sentinelas são usadas como limites e o resultado equivale a "sem restrição de data"

> Nota: corrige D-119 (legado: `today_end = 23:59` excluía silenciosamente o último minuto do dia)

### Requirement: OPS-619 — Coerção booleana e formatação de moeda
O ai9 **MUST** portar as regras de coerção e de formatação hoje implementadas como monkey-patch de
classes core, como **helpers explícitos**. Fonte legada: `config/initializers/type_casting.rb:1-91`.

- `String#to_bool` aceita como verdadeiro `true, t, yes, y, s, sim, 1` e como falso
  `false, f, no, n, não, 0` **ou string vazia**, sem distinção de caixa e com os termos em português;
  qualquer outro valor levanta `ArgumentError`. `Integer#to_bool`: 1 → true, 0 → false, outro levanta.
  `TrueClass`/`FalseClass#to_i` → 1/0; `NilClass#to_bool` → false. É o que sustenta o padrão "booleano
  como inteiro 0/1" de todo o schema legado.
- O módulo `Currency` define **BRL** (delimitador `.`, separador `,`, unidade `R$`, precisão 2, símbolo
  antes do número) e USD, com `DEFAULT = BRL`, injetando `to_currency`/`with_delimiter`/`with_precision`
  em `Integer`, `Float` e `BigDecimal`, e `to_number`/`numeric?` em `String`.

#### Scenario: valor em português coagido
- **GIVEN** o valor `"sim"` vindo de um formulário
- **WHEN** ele é convertido para booleano
- **THEN** o resultado é verdadeiro, preservando o vocabulário aceito pelo legado

#### Scenario: valor inesperado
- **GIVEN** o valor `"talvez"`
- **WHEN** a conversão é tentada
- **THEN** um erro é levantado, sem interpretação silenciosa

#### Scenario: formatação monetária única
- **GIVEN** um valor monetário exibido na interface
- **WHEN** ele é formatado
- **THEN** o formato é `R$ 1.234,56` e vem de um único helper, sem uma segunda implementação de moeda no frontend

### Requirement: OPS-620 — Busca sem dialeto condicional e sem redefinição de DNS
O ai9 **MUST** implementar a busca case-insensitive diretamente em PostgreSQL (DEC-05), dispensando a
abstração `Dev.ilike` do legado, que devolve `"ILIKE LOWER(?)"` no PostgreSQL e
`"COLLATE utf8_general_ci LIKE LOWER(?)"` no MySQL, e **MUST NOT** portar `Dev.replace_dns`. Fonte
legada: `config/initializers/dev.rb:1-39`.

- `Dev.replace_dns` **redefine o resolver de DNS do Ruby** para o Google (8.8.8.8/8.8.4.4) com
  `search: ['mydns.com']`; não é chamado em lugar nenhum, mas a redefinição de
  `Resolv::DefaultResolver` (`:32-39`) está sempre carregada.

#### Scenario: busca com acento
- **GIVEN** um registro com acento no título
- **WHEN** o usuário busca sem acento
- **THEN** o registro é encontrado, com a comparação normalizada nos dois lados

#### Scenario: resolver de DNS intacto
- **GIVEN** a aplicação em execução
- **WHEN** um nome de host é resolvido
- **THEN** a resolução usa o resolver do sistema, sem redefinição global embutida no código

### Requirement: OPS-621 — Timeout de geocoding
O ai9 **MUST** configurar o timeout do geocoding em **segundos**, com valor compatível com uma chamada
externa (poucos segundos), substituindo o `timeout: 12000` do legado, que equivale a ~3h20 — ou seja,
sem timeout na prática. Fonte legada: `config/initializers/geocoding.rb:1-6`; provedor `:google`
passado na chamada (`app/models/geolocation.rb:138`); demais opções `units: :km`,
`distances: :spherical`, `language: :pt_br`.

#### Scenario: serviço externo pendurado não consome a capacidade do servidor
- **GIVEN** o provedor de geocoding sem responder
- **WHEN** a chamada é feita
- **THEN** ela é abortada dentro do timeout configurado, sem prender uma thread da aplicação

#### Scenario: capacidade do servidor preservada
- **GIVEN** várias chamadas de geocoding simultâneas com o provedor lento
- **WHEN** os timeouts disparam
- **THEN** a aplicação continua atendendo requisições normalmente

> Nota: corrige D-83 (legado: `timeout: 12000` em segundos travava threads do Puma — que tem apenas 2 workers × 4 threads, ver OPS-631)

### Requirement: OPS-622 — Configuração da consulta de CNPJ
O ai9 **MUST** manter a consulta de CNPJ configurável (token, janela de cache e timeout), lendo o token
de ENV/credentials. Fonte legada: `config/initializers/receitaws.rb:1-15`: token de
`ENV['rws_api_token']`, cache de **365 dias**, timeout **10 s**.

#### Scenario: janela de cache ajustável
- **GIVEN** a necessidade de reduzir a janela de aceitação de dado cacheado
- **WHEN** a configuração é ajustada
- **THEN** o novo valor passa a valer sem alteração de código

#### Scenario: token ausente
- **GIVEN** o token não configurado
- **WHEN** a consulta de CNPJ é tentada
- **THEN** a resposta indica que a integração está indisponível, sem expor detalhe interno

### Requirement: OPS-623 — Detecção de spoof de media-type ativa
O ai9 **MUST** manter ativa a verificação de que o conteúdo do arquivo corresponde à extensão e ao
content-type declarados. No legado, `config/initializers/paperclip.rb:1-14` sobrescreve
`Paperclip::MediaTypeSpoofDetector#spoofed?` para **sempre retornar `false`**, desligando a checagem em
todo o sistema; o segundo patch do arquivo apenas conserta a junção de caminhos no Windows.

#### Scenario: arquivo com content-type forjado
- **GIVEN** um arquivo cujo conteúdo não corresponde ao content-type declarado
- **WHEN** o upload é enviado
- **THEN** o servidor recusa o arquivo

#### Scenario: nenhum patch em biblioteca de terceiros
- **GIVEN** os initializers do ai9
- **WHEN** eles são inspecionados
- **THEN** nenhum deles redefine método de biblioteca de anexo para desligar verificação

> Nota: corrige D-82 (legado: spoof detector monkey-patchado para `false`, permitindo upload de arquivo com tipo forjado)

### Requirement: OPS-624 — Política da fila configurada
O ai9 **MUST** configurar tempo máximo de execução, política de retentativa e retenção de jobs falhos
em valores compatíveis com operação, substituindo os do legado. Fonte legada:
`config/initializers/delayed_job_config.rb:1-2`: **`max_run_time = 7 dias`** (o default da gem é 4 h) e
**`destroy_failed_jobs = false`** (jobs falhos permanecem na tabela, exigindo expurgo manual).

#### Scenario: job travado é reciclado rapidamente
- **GIVEN** um job que trava
- **WHEN** o tempo máximo de execução é atingido
- **THEN** o worker é liberado em minutos, e não depois de uma semana

#### Scenario: histórico de falhas com expurgo
- **GIVEN** jobs falhos acumulados
- **WHEN** a política de retenção é aplicada
- **THEN** o histórico é mantido pelo prazo configurado e expurgado automaticamente depois

### Requirement: OPS-625 — Sem sobrescrita declarativa de views de engine
O ai9 **MUST NOT** usar mecanismo de override declarativo de views (`deface`), que o legado mantém
ligado. Fonte legada: `config/initializers/new_framework_defaults_6_0.rb:1-2`
(`config.deface.enabled = true`, e a repetição de `belongs_to_required_by_default = false`).

#### Scenario: interface própria, sem engine a customizar
- **GIVEN** o frontend do ai9 em React
- **WHEN** uma tela precisa ser alterada
- **THEN** o componente correspondente é editado diretamente, sem override declarativo sobre view de terceiro

#### Scenario: obrigatoriedade de belongs_to não é desligada de novo
- **GIVEN** os initializers do ai9
- **WHEN** eles são inspecionados
- **THEN** nenhum deles redefine `belongs_to_required_by_default` para falso

### Requirement: OPS-626 — Verificação de TLS sempre ativa
O ai9 **MUST** manter a verificação de certificado TLS ativa em **todos** os sistemas operacionais,
eliminando o `config/initializers/ssl_for_win.rb:1` do legado
(`OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE if Gem.win_platform?`), que em máquinas Windows
expõe **toda** conexão TLS de saída (Google Maps, ReceitaWS, SMTP) a man-in-the-middle.

#### Scenario: desenvolvimento em Windows
- **GIVEN** um desenvolvedor rodando o ai9 em Windows
- **WHEN** a aplicação faz uma chamada HTTPS
- **THEN** o certificado do servidor é verificado normalmente

#### Scenario: nenhuma constante de OpenSSL redefinida
- **GIVEN** o código do ai9
- **WHEN** ele é varrido por `VERIFY_NONE`
- **THEN** nenhuma ocorrência é encontrada

> Nota: corrige D-85 (legado: `VERIFY_NONE` forçado em Windows e também no SMTP)

### Requirement: OPS-627 — Mascaramento de dado sensível em log
O ai9 **MUST** filtrar dos logs a lista ampla de parâmetros sensíveis
(`passw secret token _key crypt salt certificate otp ssn code login_code magic_code`, conforme
`ai9-conventions.md` §3.10), substituindo o legado, que filtra **somente `:password`**
(`config/initializers/filter_parameter_logging.rb:4`) e deixa em texto puro `token`, `secret`,
`legacy_password`, CPF/CNPJ, `_key` e dados de e-mail.

#### Scenario: token não aparece no log
- **GIVEN** uma requisição carregando um token
- **WHEN** ela é logada
- **THEN** o valor do token aparece filtrado

#### Scenario: documento pessoal não aparece no log
- **GIVEN** um cadastro enviando CPF e CNPJ
- **WHEN** a requisição é logada
- **THEN** os documentos aparecem filtrados

> Nota: corrige D-85 (legado: filtro de log cobria apenas `:password`, deixando token, segredo e documentos em texto puro)

### Requirement: OPS-628 — Política de segurança de conteúdo e defaults de framework
O ai9 **MUST** definir uma **Content Security Policy** efetiva, corrigindo o legado, em que o bloco de
CSP existe porém está **inteiramente comentado** (`config/initializers/content_security_policy.rb:7-19`)
— ou seja, não há CSP alguma. Fonte legada: também
`config/initializers/{cookies_serializer,wrap_parameters,inflections,mime_types,backtrace_silencers,application_controller_renderer}.rb`.

- Defaults relevantes do legado: `cookies_serializer = :json`; `wrap_parameters format: [:json]`;
  `inflections`, `mime_types`, `backtrace_silencers` e `application_controller_renderer` vazios ou
  comentados — sem inflexões pt-BR customizadas.

#### Scenario: CSP presente nas respostas
- **GIVEN** uma resposta da aplicação
- **WHEN** os cabeçalhos são inspecionados
- **THEN** existe um cabeçalho de Content-Security-Policy restringindo origens de script e de conexão

#### Scenario: dado do servidor não é injetado como script
- **GIVEN** um valor vindo do servidor exibido na interface
- **WHEN** a página é renderizada
- **THEN** o valor é passado como dado e não como trecho de script embutido, como fazia o padrão de injetar `@target` em JS no legado

### Requirement: OPS-629 — Idioma da interface
O ai9 **MUST** nascer em **pt-BR fixo**, como o legado (DEC-09), preservando o dicionário de domínio de
`config/locales/pt-BR.yml` (337 linhas) usado nas mensagens de erro — nomes de model e de atributo
(Portador, Recebíveis, Carteira, Subsegmento, …) e as mensagens de `restrict_dependent_destroy` por
model (ex.: "A cobrança possui relações e não pode ser removida"). Fonte legada:
`config/locales/{pt-BR.yml, en.yml, devise.pt-BR.yml, devise.en.yml, validates_timeliness.pt-BR.yml, validates_timeliness.en.yml}`.

- Varredura confirmada: **0 de 717** arquivos em `app/views/` usam `t()`/`I18n.t` — todo o texto é
  hardcoded. `en.yml` contém apenas `hello: "Hello world"`: o inglês não existe de fato.
- O typo em produção `"em alguns minutis"` (`devise.pt-BR.yml:5`) **MUST** ser corrigido.

#### Scenario: mensagem de bloqueio por relação
- **GIVEN** uma tentativa de excluir uma entidade com dependências
- **WHEN** a exclusão é recusada
- **THEN** a mensagem exibida é a do dicionário de domínio, em pt-BR, nomeando a entidade corretamente

#### Scenario: nenhum idioma adicional prometido
- **GIVEN** a interface do ai9
- **WHEN** ela é usada
- **THEN** só existe pt-BR, sem arquivo de tradução vazio sugerindo suporte a outro idioma

### Requirement: OPS-630 — Arquivo de configuração órfão descartado
O ai9 **MUST NOT** portar `config/resources.yml`: o arquivo define `operating_hours` com dia da semana,
horário de início/fim e um campo `sex: "Masculino"/"Feminino"`, **não é lido por nenhum código** (grep
confirma zero referências) e não tem relação com o domínio Safegold. Fonte legada:
`config/resources.yml:1-25`.

#### Scenario: nenhuma configuração sem consumidor
- **GIVEN** os arquivos de configuração do ai9
- **WHEN** eles são revisados
- **THEN** cada um tem consumidor identificado no código

#### Scenario: descarte com evidência
- **GIVEN** a decisão de descartar o arquivo
- **WHEN** o registro da migração é consultado
- **THEN** consta a evidência de zero referências no legado

### Requirement: OPS-631 — Servidor de aplicação
O ai9 **MUST** definir o ambiente do servidor de aplicação **a partir da variável de ambiente**, com
concorrência e timeouts dimensionados, corrigindo o `config/puma.rb:1-7` do legado, que traz
**`environment "development"` fixo no arquivo** (`:4`) — se a produção subir por ele sem sobrescrever
`RAILS_ENV`, roda em modo de desenvolvimento, com backtraces expostos, sem eager load e sem cache.

- Valores do legado: `host 0.0.0.0`, porta **8192**, `threads 1,4`, `workers 2`, `preload_app!`,
  `worker_timeout 6000` (100 min) — capacidade total de 8 threads, com chamadas externas sem timeout
  efetivo (OPS-621).

#### Scenario: produção sobe como produção
- **GIVEN** o ambiente definido como produção na variável de ambiente
- **WHEN** o servidor inicia
- **THEN** ele roda em modo de produção, sem backtrace exposto

#### Scenario: capacidade dimensionada
- **GIVEN** a configuração de concorrência do ai9
- **WHEN** ela é revisada
- **THEN** o número de workers e threads vem de variável de ambiente, e não de valores fixos no arquivo

### Requirement: OPS-632 — Processos, tarefas e scripts do projeto
O ai9 **MUST** declarar os processos de execução para desenvolvimento e produção e **MUST** ter tarefas
administrativas versionadas (incluindo as do ETL), corrigindo o legado, cujo `Procfile:1-2` sobe apenas
`server: bin/rails s -p 8192` e `assets: bin/webpack-dev-server` — um Procfile de desenvolvimento, sem
worker e sem servidor de produção — e cujo `Rakefile:1-3` carrega tarefas de um diretório
`lib/tasks/` que **não existe**: o legado tem **zero rake tasks customizadas**. Fonte legada:
`Procfile`, `config.ru:1-2`, `Rakefile:1-3`, `bin/{rails,rake,bundle,setup,update,webpack,webpack-dev-server,yarn}`
(com `bin/yarn` comentado em `bin/setup` e `bin/update`).

#### Scenario: setup de máquina nova
- **GIVEN** um desenvolvedor clonando o repositório
- **WHEN** ele roda o script de setup
- **THEN** as dependências de backend e de frontend são instaladas, sem passo manual não documentado

#### Scenario: tarefas do ETL versionadas
- **GIVEN** a necessidade de executar a introspecção ou o dry-run da migração
- **WHEN** o operador procura o comando
- **THEN** existe uma tarefa versionada no repositório para cada etapa

### Requirement: OPS-633 — Worker declarado no ambiente
O ai9 **MUST** declarar o worker da fila junto com os demais processos da aplicação, corrigindo o
legado, em que `bin/delayed_job:1-5` daemoniza o worker carregando o ambiente completo e **não está no
`Procfile`** — precisa ser iniciado separadamente em produção ou **nenhum job roda**. Fonte legada:
`bin/delayed_job`; gems `daemons`, `delayed_job`, `delayed_job_active_record`, `progress_job`.

#### Scenario: ambiente completo sobe com a fila
- **GIVEN** o ambiente iniciado pelos processos declarados
- **WHEN** um job é enfileirado
- **THEN** ele é processado sem nenhum comando adicional

#### Scenario: nenhum daemon manual
- **GIVEN** a documentação operacional do ai9
- **WHEN** ela é lida
- **THEN** não há passo manual de iniciar daemon de worker por número de índice

### Requirement: OPS-634 — Páginas de erro
O ai9 **MUST** ter páginas de erro 404, 422 e 500 com a identidade visual da marca e **sem recurso
externo carregado por HTTP**. Fonte legada: `public/404.html` (72 l.), `public/422.html` (72 l.),
`public/500.html` (84 l.): título **"Vish!"**, fundo `#1f2428` (a cor primária do e-mail, e não a
`COLOR__PRIMARY` #2D2D2A do tema), texto `#eee` e a fonte **Quicksand carregada do Google Fonts via
`http://`** — bloqueada como conteúdo misto num site HTTPS, então em produção a fonte não carrega.

#### Scenario: fonte carrega em site HTTPS
- **GIVEN** a página de erro servida por HTTPS
- **WHEN** ela é renderizada
- **THEN** a tipografia aparece como projetada, sem bloqueio por conteúdo misto

#### Scenario: cor da marca
- **GIVEN** as páginas de erro do ai9
- **WHEN** elas são renderizadas
- **THEN** usam o token de cor primária da marca, e não uma terceira cor divergente

### Requirement: OPS-635 — Indexação e ícones
O ai9 **MUST** publicar um `robots.txt` que **desautoriza indexação**, coerente com uma aplicação
privada de gestão financeira, e **MUST** servir os ícones da marca. No legado, `public/robots.txt` tem
**0 bytes** — o que permite indexação total — e os ícones (`favicon.ico`, `apple-touch-icon.png`,
`apple-touch-icon-precomposed.png`) são servidos da raiz, enquanto o favicon/OG da marca vive em
`app/frontend/images/brand/`.

#### Scenario: crawler não indexa a aplicação
- **GIVEN** um crawler acessando `robots.txt`
- **WHEN** ele lê o arquivo
- **THEN** encontra a diretiva que desautoriza a indexação

#### Scenario: ícone da marca consistente
- **GIVEN** a aplicação aberta no navegador
- **WHEN** a aba é exibida
- **THEN** o ícone é o da marca Safegold, servido de um único lugar

### Requirement: OPS-636 — Nenhum arquivo de teste em diretório público
O ai9 **MUST NOT** publicar arquivos de teste ou rascunho em diretório servido publicamente, e **MUST
NOT** portar `public/mailtest.html` — um HTML de e-mail de 706 linhas, com o título "Criação de
empressa" (sic) e **tags ERB não processadas** (`<%= image_url('favicon.ico') %>`, `:5`), servido como
estático e acessível sem autenticação.

#### Scenario: diretório público auditado
- **GIVEN** o diretório de arquivos públicos do ai9
- **WHEN** ele é listado
- **THEN** contém apenas os ativos que devem mesmo ser públicos

#### Scenario: template de e-mail fora do público
- **GIVEN** um template de e-mail do ai9
- **WHEN** ele é armazenado
- **THEN** vive junto do código do mailer e não é acessível por URL

### Requirement: OPS-637 — Build de assets
O ai9 **MUST** usar o build de frontend próprio (Vite, conforme `ai9-conventions.md`), substituindo o
Webpacker 5 do legado. Fonte legada: `config/webpacker.yml:1-76`.

- Configuração legada, para referência: fonte em **`app/frontend`** (não `app/javascript`), entradas em
  `app/frontend/packs`, saída em `public/assets/packs`; resolve `.erb` **antes** de `.js` (`:27`);
  dev server em `localhost:3035` com HMR, `disable_host_check: true` e
  `Access-Control-Allow-Origin: '*'`; em produção `compile: false` (precompilação obrigatória no
  deploy), `extract_css: true`, `cache_manifest: true`; em desenvolvimento `extract_css: false`.

#### Scenario: dev server não aceita qualquer origem
- **GIVEN** o servidor de desenvolvimento do frontend do ai9
- **WHEN** uma requisição de outra origem chega
- **THEN** ela é tratada conforme a política de origem configurada, sem liberar tudo

#### Scenario: build de produção determinístico
- **GIVEN** o pipeline de deploy
- **WHEN** os assets são compilados
- **THEN** o build é executado na etapa de deploy e a aplicação não compila assets em tempo de requisição

### Requirement: OPS-638 — Sem dependência de Ruby no build de frontend
O ai9 **MUST** ter um build de frontend independente do backend, eliminando o `rails-erb-loader` do
legado, que pré-processa `.erb` dentro do bundle rodando `bin/rails runner` — o que faz o build de
assets **exigir um ambiente Rails funcional**. Fonte legada:
`config/webpack/{environment.js,development.js,production.js,configs/alias.js,loaders/{erb,jquery-expose,file,css-chunks}.js}`.

- Outras características do legado: `expose-loader` publica jQuery como `$` e `jQuery` globais (todo o
  JS assume jQuery global); alias `image_path` → `app/frontend/images`; produção explode o vendor em um
  arquivo por pacote npm (`production.js:14-22`, `minSize: 0`, `maxInitialRequests: Infinity`),
  gerando centenas de requisições; `HashedModuleIdsPlugin` para hashes estáveis; os loaders `file.js`
  e `css-chunks.js` estão escritos mas **desabilitados** (`environment.js:4,10` comentados).

#### Scenario: frontend compila sem backend
- **GIVEN** apenas o diretório do frontend e as dependências npm instaladas
- **WHEN** o build roda
- **THEN** ele conclui sem precisar de Ruby, Rails ou banco de dados

#### Scenario: chunks razoáveis
- **GIVEN** o bundle de produção do ai9
- **WHEN** a página inicial carrega
- **THEN** o número de requisições é da ordem de dezenas, e não de centenas de arquivos por pacote npm

### Requirement: OPS-639 — Biblioteca de componentes do frontend
O ai9 **MUST** substituir a biblioteca de UI do legado pelos equivalentes já usados na base ai9
(React 18 + TypeScript + Tailwind), **MUST** substituir os dois pacotes proprietários por componentes do
ai9 (DEC-10) e **MUST** ter `package-lock`/`yarn.lock` versionado. Fonte legada: `babel.config.js:1-84`,
`postcss.config.js:1-15`, `package.json:1-58`.

- Componentes do legado a reproduzir funcionalmente: `foundation-sites` 6.6 (grid/CSS),
  `animejs` 3.2 (animações), `air-datepicker` (calendário), `jquery-mask-plugin` (máscaras de
  CPF/CNPJ/moeda), `jquery-toast-plugin` (notificações), `tippy.js` (tooltips), `croppie` (recorte de
  avatar), `photoswipe` + `iv-viewer` (visualizador de imagem), `dragula` (drag-and-drop),
  `masonry-layout` (grade), `trix` + `@rails/actiontext` (rich text), `vanilla-picker` (seletor de cor
  dos temas), `node-vibrant` (extração de paleta), `romanjs` (numeração romana), `jquery.rateit`
  (avaliação por estrelas), `normalize.css`, sobre a base `jquery` 3.6 + `jquery-ujs`/`@rails/ujs`.
- **Proprietários**: `./vendor/dialog` (modal) e `./vendor/doughnut` (gráfico de rosca — o **único**
  gráfico do produto), ambos sem equivalente npm.
- No legado, `yarn.lock` está no `.gitignore:184` (build de frontend não reprodutível) e `npm`/`yarn`
  aparecem como **dependências de runtime** (erro de empacotamento).

#### Scenario: gráfico do produto substituído
- **GIVEN** o gráfico de rosca proprietário do legado
- **WHEN** a tela correspondente é implementada no ai9
- **THEN** ela usa a biblioteca de gráficos do ai9, com o resultado visual apresentado antes do fechamento do slice

#### Scenario: build de frontend reprodutível
- **GIVEN** duas máquinas instalando as dependências do frontend
- **WHEN** a instalação roda
- **THEN** ambas obtêm as mesmas versões, porque o lockfile está versionado

#### Scenario: nenhum gerenciador de pacotes como dependência de runtime
- **GIVEN** o manifesto de dependências do ai9
- **WHEN** ele é inspecionado
- **THEN** `npm` e `yarn` não aparecem como dependências da aplicação

### Requirement: CFG-01 — Chaves de configuração que viram ENV no ai9
O ai9 **MUST** expor cada chave abaixo como variável de ambiente/credential, com exemplo versionado e
valor real fora do repositório, e **MUST** falhar no boot quando uma chave obrigatória faltar. Fonte
legada: `config/application.rb`, `config/application.*.yml`, `config/environments/production.rb`,
`config/cable.yml`, `app/definitions/SFG/metadata.rb`.

| Chave legada | Papel | Obrigatória |
| ------------ | ----- | ----------- |
| `alias` | host público, base de todo link absoluto gerado fora de request (e-mail, notificação, OpenGraph) — 19 pontos de leitura | **Sim** |
| `smtp_settings_address` | servidor SMTP (`smtp.office365.com`) | **Sim** |
| `smtp_settings_port` | porta SMTP (`587`) — hoje nunca atribuída (D-112) | **Sim** |
| `smtp_settings_sender` | remetente (`noreply@safegold.com.br`) | **Sim** |
| `smtp_settings_domain` | domínio HELO (`safegold.com.br`) | **Sim** |
| `smtp_settings_user_name` | usuário SMTP | **Sim** |
| `smtp_settings_password` | senha SMTP (**secret**) | **Sim** |
| `smtp_settings_auth_type` | tipo de autenticação (`login`) | Sim |
| `smtp_settings_tls_enabled` | TLS (no legado, a **string** `"true"`) | Sim |
| `smtp_settings_delivering` | modo de entrega (`async`) | Sim |
| `rws_api_token` | token da ReceitaWS (**secret**, hoje commitado — rotacionar) | Sim, se a consulta de CNPJ for portada |
| `GOOGLE_MAPS_API_KEY` | mapas e geocodificação (**secret**, hoje hardcoded — rotacionar) | **Sim** |
| Chave privada DKIM | assinatura de e-mail (**secret**, hoje commitada — rotacionar) | **Sim**, se DKIM for mantido |
| `SECRET_KEY_BASE` | assinatura de sessão/cookies (**secret**) | **Sim** |
| `RAILS_MASTER_KEY` | descriptografia das credentials (**secret**) | **Sim em produção** |
| Credenciais de banco | conexão principal (**secret**) — sem o bloco `sfg_legacy` | **Sim** |
| `REDIS_URL` | fila Sidekiq e Action Cable (no legado era chave morta) | **Sim no ai9** |
| `RAILS_ENV` / `NODE_ENV` | ambiente de runtime e de build | **Sim** |
| `paperclip_path` | caminho do ImageMagick — **zero leituras** no legado | **Descartada** |
| `RAILS_SERVE_STATIC_FILES` | serviço de estáticos — comentada e forçada no legado | **Descartada** |
| `BUNDLE_GEMFILE` | escolha entre os 3 Gemfiles do legado | **Descartada** |

#### Scenario: chave obrigatória ausente
- **GIVEN** um ambiente sem `SECRET_KEY_BASE`
- **WHEN** a aplicação inicia
- **THEN** o boot falha nomeando a chave faltante

#### Scenario: chave opcional ausente
- **GIVEN** um ambiente sem o token da ReceitaWS
- **WHEN** a aplicação inicia
- **THEN** ela sobe, e apenas a consulta de CNPJ responde como indisponível

#### Scenario: chaves mortas não são recriadas
- **GIVEN** o arquivo de exemplo de variáveis do ai9
- **WHEN** ele é lido
- **THEN** `paperclip_path`, `RAILS_SERVE_STATIC_FILES` e `BUNDLE_GEMFILE` não aparecem

#### Scenario: segredos rotacionados antes do cutover
- **GIVEN** os três segredos que estiveram versionados (chave DKIM, senha SMTP, token ReceitaWS) e a chave do Google Maps
- **WHEN** o ai9 entra em produção
- **THEN** todos já foram rotacionados na origem e os valores antigos não funcionam mais

> Nota: corrige D-85 (legado: chave privada DKIM, senha SMTP e token da ReceitaWS commitados, além de `VERIFY_NONE`) e D-119 (legado: `paperclip_path`, `REDIS_URL` e `RAILS_SERVE_STATIC_FILES` como chaves mortas)

### Requirement: CFG-02 — Constantes de negócio viram configuração
O ai9 **MUST** expor as constantes de negócio de `SFG::Metadata` como **configuração por ambiente**, e
não como constante de código, para que possam ser ajustadas sem deploy. Fonte legada:
`app/definitions/SFG/metadata.rb`; consumo em `app/helpers/application_helper.rb:192-194`,
`app/models/renegotiation_attachment.rb` e nas views de anexo e de endereço.

| Constante legada | Valor no legado | Onde importa |
| ---------------- | --------------- | ------------ |
| `MAX_FILES_PER_RENEGOTIATION` | 4 | limite de anexos por renegociação (validação de servidor, OPS-495) |
| `MAX_FILE_SIZE` | 5 MB | tamanho máximo por anexo (validação de servidor, OPS-495) |
| `PUBLIC_CREATE_USER` | 1 (ligado) | habilita o auto-cadastro público de usuário |
| `GOOGLE_MAPS_DEFAULT_PLACE` | lat -27.1740121 / lng -51.5053261 | centro padrão do mapa |
| `AUTOCOMPLETE_BIAS_LAT` / `_LNG` / `_RADIUS` | -27.1748947 / -51.5500562 / 10 km | viés do autocomplete de endereço (OPS-482) |
| `GOOGLE_ANA_APP_ID` | G-7E78XXZX5X | identificador de analytics (OPS-486) |

#### Scenario: limite de anexos ajustado sem deploy
- **GIVEN** a decisão de permitir 6 anexos por renegociação
- **WHEN** a configuração é alterada
- **THEN** o novo limite passa a valer na validação de servidor, sem alteração de código

#### Scenario: auto-cadastro público controlado por configuração
- **GIVEN** o auto-cadastro público desabilitado na configuração
- **WHEN** alguém acessa a rota de cadastro diretamente
- **THEN** a rota recusa a criação, e não apenas esconde o botão como no legado

#### Scenario: viés de geolocalização configurável
- **GIVEN** um cliente atendido em outra região
- **WHEN** as coordenadas de viés e o raio são ajustados na configuração
- **THEN** o autocomplete passa a priorizar a nova região

> Nota: corrige D-85 (legado: identificadores e chave de mapas fixados em código) e o comportamento de `PUBLIC_CREATE_USER`, que no legado escondia o botão sem fechar a rota
