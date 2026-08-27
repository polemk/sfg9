# Integrations Specification

## Purpose
Define as integrações externas e os canais de saída do ai9 para o domínio migrado do legado `sfg`:
consulta de CNPJ (ReceitaWS), geocodificação e mapas (Google), catálogo de estados e cidades, SMTP e
DKIM, Google Analytics, Redis, Action Cable, uploads/anexos e o catálogo completo de e-mails
transacionais. Todos os segredos que hoje estão commitados passam a ENV/credentials; anexos saem de
`public/` para storage privado com URL assinada; e o polling do legado é substituído por Action Cable.

> DEC-09 — **geração de PDF fica fora do escopo**: `wicked_pdf` e `wkhtmltopdf-binary` estão declarados
> no Gemfile do legado, mas a varredura exaustiva (`grep -ri pdf` em `app/`, `engines/`, `config/`,
> `lib/`) confirma **zero PDFs gerados** (D-84). Não há paridade a preservar e a feature não é
> inventada aqui.

## Requirements

### Requirement: OPS-480 — ReceitaWS (consulta de CNPJ)
O ai9 **MUST** portar a consulta de CNPJ na ReceitaWS usada no cadastro de fornecedor, e **MUST**
tratar erro, aplicar cache local e ler o token de ENV/credentials. Fonte legada:
`config/initializers/receitaws.rb:1-16`; wrapper `app/helpers/cnpj_api.rb:1-5`; chamada em
`app/controllers/pub/providers_controller.rb:124` (`get_api_info`).

- Configuração legada: `config.token = ENV['rws_api_token']`, `config.days = 365` (aceita dado de até
  1 ano do cache da própria ReceitaWS), `config.timeout = 10s`.
- Resposta legada: payload cru com `status: :ok`, ou `[]` com **404** quando `info.blank?`.
- O preenchimento automático de `cnaes`/`atividades` no `create` está **comentado**
  (`providers_controller.rb:67-77`): hoje o retorno só alimenta a tela e não é persistido — o ai9
  preserva esse comportamento (DEC-09).

#### Scenario: limite de requisições da API
- **GIVEN** a ReceitaWS respondendo HTTP 429 (o plano gratuito limita a 3 requisições por minuto)
- **WHEN** o usuário consulta um CNPJ
- **THEN** o endpoint devolve erro tratado e legível ao usuário, em vez de 500 por exceção não capturada

#### Scenario: consulta repetida do mesmo CNPJ
- **GIVEN** um CNPJ já consultado dentro da janela de cache
- **WHEN** a consulta é repetida
- **THEN** a resposta vem do cache local e nenhuma chamada externa é feita

#### Scenario: token fora do código
- **GIVEN** a aplicação em execução
- **WHEN** a integração é inicializada
- **THEN** o token vem de ENV/credentials e nenhum token literal existe em arquivo versionado

> Nota: corrige D-85 (legado: token da ReceitaWS commitado em texto puro nos 4 `config/application.*.yml:12`) e a ausência de `rescue` e de cache local

### Requirement: OPS-481 — Geocodificação reversa
O ai9 **MUST** executar geocodificação reversa (lat/lng → endereço) de forma **assíncrona**, com
**timeout em segundos** e **cache**, nunca dentro de um `before_save`. Fonte legada:
`config/initializers/geocoding.rb:1-6`; uso em `app/models/geolocation.rb:138-159,166-171`.

- Campos preenchidos a partir de `address_components`: `address`, `full_address`, `city`, `state`,
  `cep`, `country`, `street_number`, `neighborhood`; distância por
  `Geocoder::Calculations.distance_between` em km.
- Configuração legada: `timeout: 12000` (interpretado em segundos pelo Geocoder ≈ 3h20), `units: :km`,
  `distances: :spherical`, `language: :pt_br`, sem cache e sem `rescue`.

#### Scenario: serviço externo pendurado
- **GIVEN** a API de geocoding sem responder
- **WHEN** um registro com coordenadas é salvo
- **THEN** o salvamento conclui normalmente e o enriquecimento fica pendente em processamento assíncrono, sem travar a requisição

#### Scenario: timeout em segundos
- **GIVEN** a chamada de geocoding
- **WHEN** o tempo limite configurado é atingido
- **THEN** a chamada é abortada em poucos segundos e o job é retentado, em vez de esperar horas

#### Scenario: coordenada já consultada
- **GIVEN** um par lat/lng já geocodificado
- **WHEN** o mesmo par é consultado de novo
- **THEN** o resultado vem do cache, sem nova chamada externa

> Nota: corrige D-83 (legado: Geocoder síncrono no `before_save`, `timeout: 12000` ≈ 3h20 e sem cache — um save podia travar a request por horas e um erro da API abortava o save da entidade dona)

### Requirement: OPS-482 — Google Maps JavaScript API (mapa e autocomplete de endereço)
O ai9 **MUST** portar o autocomplete de endereço da aba "Endereço" de Minha Conta, carregando a API do
Google Maps com chave vinda de configuração e **MUST** aplicar de fato o viés de localidade, hoje
declarado e não usado. Fonte legada: `app/definitions/SFG/metadata.rb:8-10,25-27`; carregamento em
`app/views/pub/console/parts/my_account/parts/address/_container.js.erb:4-14,54-78`.

- No legado o script é carregado com `libraries=geometry,places`, o código espera **200 ms** com
  `setTimeout` e então instancia `google.maps.places.Autocomplete` no campo `#query`.
- Ao escolher um lugar, o formulário é preenchido a partir de `place.address_components`; sem
  `place.geometry`, mostra o toast "Endereço inválido — Escolha uma das opções oferecidas durante a
  busca".
- As constantes de viés (`AUTOCOMPLETE_BIAS_LAT/LNG/RADIUS`, `GOOGLE_MAPS_DEFAULT_PLACE`) existem em
  `metadata.rb` mas **não são aplicadas** — no ai9 elas viram configuração e são efetivamente usadas.

#### Scenario: carga do script mais lenta que a espera fixa
- **GIVEN** a API do Google Maps demorando mais de 200 ms para carregar
- **WHEN** o autocomplete é inicializado
- **THEN** a inicialização aguarda o carregamento real do script, sem quebrar com `google is not defined`

#### Scenario: chave inválida ou quota estourada
- **GIVEN** o script de mapas indisponível
- **WHEN** o usuário digita um endereço
- **THEN** uma mensagem explica que a busca de endereço está indisponível, em vez de o campo simplesmente não reagir

#### Scenario: viés de localidade aplicado
- **GIVEN** o viés configurado (latitude, longitude e raio)
- **WHEN** o usuário digita um termo ambíguo
- **THEN** as sugestões priorizam a região configurada

> Nota: corrige D-85 (legado: `GOOGLE_MAPS_API_KEY` hardcoded em `app/definitions/SFG/metadata.rb`, commitada no repositório — deve virar ENV e ser rotacionada)

### Requirement: OPS-483 — Catálogo de estados e cidades do Brasil
O ai9 **MUST** portar o comportamento dos selects encadeados País → Estado → Cidade e a conversão de
nome de estado para sigla, hoje fornecidos pela gem `city-state`. Fonte legada: `Gemfile.linux:17`;
`app/controllers/pub/console_controller.rb:259-270`;
`app/views/pub/console/parts/my_account/parts/address/_container.html.erb:33,41`;
`app/models/geolocation.rb:67-76`; AJAX em `_container.js.erb:18-52`.

- Operações usadas: listar estados por país, listar cidades por UF e casar o valor recebido por
  transliteração; `abbreviated_state` converte nome do estado em sigla.

#### Scenario: nome de estado que não casa exatamente
- **GIVEN** um nome de estado com acentuação ou grafia divergente
- **WHEN** a sigla é resolvida
- **THEN** a comparação é transliterada nos dois lados e a sigla correta é devolvida, em vez de `nil`

#### Scenario: dados disponíveis sem depender de rede
- **GIVEN** o ambiente sem acesso à internet
- **WHEN** os selects de estado e cidade são carregados
- **THEN** as listas são preenchidas a partir de dados empacotados na aplicação

### Requirement: OPS-484 — SMTP
O ai9 **MUST** enviar e-mail por SMTP com **todas** as credenciais em ENV/credentials, **verificação de
certificado TLS habilitada** e **erro de entrega observável**. Fonte legada: `config/application.rb:92-115`;
`engines/mailer19/lib/livetat/mailer19/engine.rb:33-52`;
`engines/mailer19/lib/livetat/mailer19/smtp_settings.rb:7-17`; valores em
`config/application.centos.yml:3-11`.

- Configuração legada: `address: smtp.office365.com`, `port: 587`, `domain`/`user`/`sender:
  noreply@safegold.com.br`, `authentication: login`, `enable_starttls_auto: true`,
  **`openssl_verify_mode: VERIFY_NONE`** (`engine.rb:43`) e
  `raise_delivery_errors = false` (`engine.rb:39`).
- A porta **MUST** ser efetivamente atribuída a partir da configuração — no legado
  `smtp_settings_port: "587"` existe no yml, o engine a lê (`engine.rb:45`), mas
  `config/application.rb` **nunca a atribui**, e o `Net::SMTP` acaba no default 25.

#### Scenario: falha de SMTP não é silenciosa
- **GIVEN** o servidor SMTP recusando a conexão
- **WHEN** um e-mail é enviado
- **THEN** o erro é registrado, o job é retentado e a falha final fica visível, em vez de o envio falhar sem exceção, sem log e sem retentativa

#### Scenario: porta correta usada
- **GIVEN** a porta 587 configurada
- **WHEN** a conexão SMTP é aberta
- **THEN** a porta usada é 587, e não o default 25

#### Scenario: certificado do servidor verificado
- **GIVEN** um certificado TLS inválido apresentado pelo servidor
- **WHEN** a conexão é negociada
- **THEN** a conexão é recusada, em vez de aceita como no legado com `VERIFY_NONE`

#### Scenario: senha fora do repositório
- **GIVEN** o código-fonte do ai9
- **WHEN** ele é inspecionado
- **THEN** não existe nenhuma senha SMTP literal, e a credencial vem de ENV/credentials

> Nota: corrige D-112 (legado: `smtp_settings_port` nunca atribuída, SMTP caindo na porta 25), D-85 (legado: senha `lvt&ticket251` hardcoded em `smtp_settings.rb:13` e `VERIFY_NONE`) e D-78 (legado: `raise_delivery_errors = false` tornava a falha de entrega invisível)

### Requirement: OPS-485 — Assinatura DKIM
O ai9 **MUST** assinar os e-mails com DKIM lendo a chave privada de secret/ENV, e **MUST** falhar de
forma diagnosticável — não travar o boot — quando a chave estiver ausente. Fonte legada:
`config/application.rb:110-114`; chave em `lib/dkim_private_key.pem`; interceptor global
`ActionMailer::Base.register_interceptor(Dkim::Interceptor)`, `domain = 'safegold.com.br'`,
`selector = 'dk'`.

- A chave privada do legado está **commitada no repositório** e, portanto, comprometida: **MUST** ser
  rotacionada e o registro DNS `dk._domainkey.safegold.com.br` atualizado.

#### Scenario: chave ausente na inicialização
- **GIVEN** a aplicação iniciando sem a chave DKIM configurada
- **WHEN** o boot ocorre
- **THEN** a aplicação sobe com o envio de e-mail marcado como degradado e um erro explícito no log, em vez de não subir por causa de um `open(...)` no `before_initialize`

#### Scenario: chave fora do repositório
- **GIVEN** o repositório do ai9
- **WHEN** ele é varrido por material criptográfico
- **THEN** nenhum arquivo `.pem` de chave privada está versionado

#### Scenario: assinatura aplicada a todo e-mail
- **GIVEN** o DKIM configurado
- **WHEN** qualquer e-mail transacional é enviado
- **THEN** a mensagem sai assinada com o domínio e o seletor configurados

> Nota: corrige D-85 (legado: chave privada DKIM commitada em `lib/dkim_private_key.pem`, com `open(...)` no boot que derruba a aplicação se o arquivo sumir)

### Requirement: OPS-486 — Google Analytics
O ai9 **MUST** portar a instrumentação de analytics com o identificador vindo de **configuração** e o
snippet **compatível com o identificador**. Fonte legada: `app/definitions/SFG/metadata.rb:7`
(`GOOGLE_ANA_APP_ID = G-7E78XXZX5X`); partial `app/views/livetat/analytics/_google.js.erb:1-4`;
incluída em `pub/start/_index.js.erb:1`, `pub/console/_index.js.erb:1`, `pub/contracts/_index.js.erb:2`
e `pub/users/sessions/_new.js.erb:1`.

- No legado o ID é formato **GA4** (`G-…`) mas o snippet carregado é o de **Universal Analytics**
  (`analytics.js`, descontinuado desde jul/2023) — na prática provavelmente não coleta nada hoje.
- A partial é carregada uma vez por página (`unless @ga_has_been_loaded`), exceto em `contracts`, que
  carrega sempre.

#### Scenario: identificador e snippet compatíveis
- **GIVEN** um identificador de medição GA4 configurado
- **WHEN** a página carrega a instrumentação
- **THEN** o snippet usado é o correspondente ao GA4, e a coleta funciona

#### Scenario: script bloqueado
- **GIVEN** um bloqueador impedindo o carregamento do script
- **WHEN** o usuário navega
- **THEN** nenhuma funcionalidade da aplicação quebra

#### Scenario: carregamento único por página
- **GIVEN** uma página que renderiza vários parciais
- **WHEN** a página é montada
- **THEN** a instrumentação é injetada uma única vez

### Requirement: OPS-487 — Redis
O ai9 **MUST** usar Redis para **fila (Sidekiq)** e para o **adapter do Action Cable**, ampliando o uso
do legado, onde o Redis existia **apenas** como adapter do Action Cable em produção
(`url: ENV['REDIS_URL']`, fallback `redis://localhost:6379/1`, `channel_prefix: sfg_production`) e não
era usado para cache, sessão nem fila. Fonte legada: `Gemfile.linux:42`; `config/cable.yml:7-10`.

#### Scenario: Redis indisponível
- **GIVEN** o Redis fora do ar
- **WHEN** a aplicação tenta enfileirar um job ou abrir um WebSocket
- **THEN** a falha é explícita e monitorável, e a interface degrada de forma controlada

#### Scenario: prefixo de canal por ambiente
- **GIVEN** dois ambientes compartilhando a mesma instância Redis
- **WHEN** mensagens são publicadas
- **THEN** o prefixo de canal separa os ambientes e nenhuma mensagem cruza

> Nota: corrige D-119 (legado: `REDIS_URL` era chave morta, porque `action_cable/engine` nem sequer era carregado)

### Requirement: OPS-488 — Action Cable substitui todo polling
O ai9 **MUST** implementar Action Cable de verdade — engine carregada, canais em
`backend/app/channels/`, autorização no `subscribed` com `reject`, e o cliente conectando com token de
handshake — e **MUST** substituir por ele os três pontos de polling do legado. Fonte legada:
`config/cable.yml:1-10`; `config/application.rb:4-12`; `app/frontend/.../polling_helper.js:47`
(`PollingManager`, 5 s); `_widget.js.erb:7-16` (monitor de usuário de 1 s, já desativado);
`live_progress_percent` (progresso de job).

- No legado **nada é realtime**: `action_cable/engine` não é requerido, não existe nenhum
  `*_channel.rb`, não há `app/channels`, nem `createConsumer` no frontend, nem
  `mount ActionCable.server` nas rotas.

#### Scenario: progresso de job em tempo real
- **GIVEN** um job de template em execução
- **WHEN** o progresso avança
- **THEN** a interface é atualizada por evento no canal, sem nenhum `setInterval` consultando a API

#### Scenario: bloqueio de conta reflete na sessão aberta
- **GIVEN** um usuário com sessão aberta que é desativado por um administrador
- **WHEN** a desativação ocorre
- **THEN** a sessão é encerrada por evento em tempo real, sem o monitor de 1 segundo do legado

#### Scenario: assinatura sem permissão é recusada
- **GIVEN** um cliente tentando assinar um canal de um projeto do qual não é membro
- **WHEN** a assinatura é solicitada
- **THEN** o canal recusa a inscrição no `subscribed`

#### Scenario: nenhum polling remanescente
- **GIVEN** o código do frontend do ai9
- **WHEN** ele é varrido por consulta periódica de dados
- **THEN** não existe `PollingManager` nem intervalo consultando a API por atualização de dado

> Nota: corrige D-86 (legado: `PollingManager` a cada 5 s, monitor de usuário de 1 s e progresso de job por `live_progress_percent` — polling é proibido no ai9)

### Requirement: OPS-489 — Login social (Facebook) permanece desativado
O ai9 **MUST** manter o login com Facebook **desativado**, como está no legado, onde
`facebook_app_id` e `facebook_app_secret` valem `0` e nenhum fluxo OAuth completa. Fonte legada:
`config/application.rb:75-80`; `app/definitions/SFG/metadata.rb:4-5`; callback
`#{ENV['alias']}/users/auth/facebook/callback`.

#### Scenario: botão de login social não é oferecido
- **GIVEN** a tela de login do ai9
- **WHEN** ela é renderizada
- **THEN** nenhuma opção de login com Facebook é apresentada

#### Scenario: rota de callback inerte
- **GIVEN** uma requisição ao endpoint de callback OAuth
- **WHEN** ela chega
- **THEN** a resposta é erro controlado, sem tentativa de autenticação

### Requirement: OPS-490 — Geração de PDF não é portada
O ai9 **MUST NOT** portar `wicked_pdf` nem `wkhtmltopdf-binary`: a busca exaustiva no legado
(`grep -ri pdf` em `app/`, `engines/`, `config/`, `lib/` e `find -iname '*pdf*'`) retorna **zero**
ocorrências fora do Gemfile — nenhum `WickedPdf`, nenhum `format.pdf`, nenhum template `.pdf.erb`,
nenhuma rota `.pdf`. Fonte legada: `Gemfile.linux:34,36`.

#### Scenario: nenhuma dependência de PDF no bundle
- **GIVEN** o `Gemfile` do ai9
- **WHEN** ele é inspecionado
- **THEN** não há gem de geração de PDF, porque não há feature de PDF a suportar

#### Scenario: evidência do descarte registrada
- **GIVEN** a decisão DEC-09 de não construir feature nova
- **WHEN** o registro da migração é consultado
- **THEN** consta que o legado declarava a gem e não gerava nenhum PDF (D-84)

### Requirement: OPS-491 — Motor de anexos e armazenamento privado
O ai9 **MUST** armazenar anexos em **storage privado**, servindo-os apenas por **URL assinada** de vida
curta, com **validação real de tipo no servidor**. Fonte legada: `Gemfile.linux:38,47`;
`config/initializers/paperclip.rb:1-14`; `config/application.centos.yml:2`;
`config/environments/production.rb:19`.

- No legado o armazenamento é em disco local sob
  `:rails_root/public/system/:attachment/:id/:basename_:style.:extension`, servido **como estático**
  (`public_file_server.enabled = true`), e o initializer **monkey-patcha**
  `Paperclip::MediaTypeSpoofDetector#spoofed?` para retornar sempre `false`
  (`paperclip.rb:2-8`), desligando a proteção contra extensão/MIME falsificados em todo o sistema.
- As conversões de imagem do legado (`-set colorspace sRGB -strip -alpha remove -background white
  -flatten +matte`) são preservadas nos derivados.

#### Scenario: arquivo não é acessível por URL adivinhada
- **GIVEN** um anexo armazenado no ai9
- **WHEN** alguém tenta acessá-lo diretamente sem autorização
- **THEN** o acesso é negado, porque o arquivo não é servido como estático público

#### Scenario: conteúdo não corresponde à extensão
- **GIVEN** um arquivo executável renomeado com extensão de imagem e content-type forjado
- **WHEN** o upload é enviado
- **THEN** o servidor detecta a divergência entre conteúdo e tipo declarado e recusa o arquivo

#### Scenario: URL assinada expira
- **GIVEN** uma URL assinada emitida para um anexo
- **WHEN** o prazo de validade passa
- **THEN** a URL deixa de funcionar

> Nota: corrige D-82 (legado: spoof detector monkey-patchado para `false`, arquivos servidos de `public/` sem autenticação) e D-85 (legado: `VERIFY_NONE` e segredos no repositório na mesma família de achados)

### Requirement: OPS-492 — Um único sistema de anexos
O ai9 **MUST** ter **um único** mecanismo de anexo, eliminando a convivência entre Paperclip (anexos de
negócio) e ActiveStorage (imagens embutidas no rich text de projeto) do legado, e **MUST** usar
armazenamento que sobreviva a redeploy. Fonte legada: `config/storage.yml:1-34`;
`config/environments/production.rb:22` (`active_storage.service = :local`);
`app/models/project.rb:60` (`has_rich_text :availability_description`).

- No legado todos os serviços de nuvem em `storage.yml` estão comentados e o disco é
  `Rails.root/storage` — em container, os uploads não sobrevivem a um redeploy.

#### Scenario: redeploy não apaga anexo
- **GIVEN** um anexo enviado antes de um redeploy
- **WHEN** a aplicação sobe de novo
- **THEN** o anexo continua acessível

#### Scenario: rich text e anexo de negócio no mesmo mecanismo
- **GIVEN** uma imagem embutida na descrição de disponibilidade e um anexo de renegociação
- **WHEN** ambos são armazenados
- **THEN** os dois passam pelo mesmo mecanismo de anexo e pelas mesmas regras de acesso

### Requirement: OPS-493 — Upload de avatar de usuário
O ai9 **MUST** portar o upload de avatar de usuário, com os derivados efetivamente usados pelo produto
e **MUST** tolerar a ausência de avatar em qualquer consumidor. Fonte legada:
`engines/auth19/app/models/livetat/auth/user.rb:4-14,60-61`; redefinição em
`app/decorators/models/user_decorator.rb:11-22`.

- Derivados efetivos (decorator do app): `thumb 80`, `preview 250`, `original 1500`; tipo aceito
  `image/*`; **limite 3 MB**.
- A engine declara outros derivados (`medium 500`, `large 1200`, `retina 1500`), divergência que causa
  referência a estilo inexistente em consumidores que pedem o caminho sem estilo.

#### Scenario: usuário sem avatar consumido por e-mail
- **GIVEN** um administrador sem avatar carregado
- **WHEN** um e-mail que exibe o avatar do remetente é montado
- **THEN** um avatar padrão é usado e o e-mail é enviado, em vez de o envio estourar por arquivo inexistente

#### Scenario: limite de tamanho aplicado no servidor
- **GIVEN** um arquivo de 4 MB
- **WHEN** o upload de avatar é enviado
- **THEN** o servidor recusa por exceder o limite configurado

> Nota: corrige D-82 (legado: validações e limites frágeis, arquivos públicos) e a divergência de estilos entre engine e decorator que quebrava `Mailing#account_invitation` (`engines/mailer19/app/mailers/livetat/mailer19/mailing.rb:31`)

### Requirement: OPS-494 — Upload de avatar de projeto
O ai9 **MUST** portar o upload de avatar de projeto com os mesmos derivados e limites do legado. Fonte
legada: `app/models/project.rb:48-58,126-127`.

- Derivados: `thumb 80` (jpg q100), `preview 250` (jpg q70), `original 1500` (jpg q70);
  `content_type image/*`; **limite 5 MB**.

#### Scenario: arquivo não-imagem recusado
- **GIVEN** um PDF enviado como avatar de projeto
- **WHEN** o upload é processado
- **THEN** o servidor recusa, verificando o conteúdo real do arquivo e não apenas o content-type declarado

#### Scenario: derivados gerados
- **GIVEN** uma imagem válida de 3 MB
- **WHEN** o upload conclui
- **THEN** os derivados `thumb`, `preview` e `original` existem com as dimensões e qualidades definidas

> Nota: corrige D-82 (legado: com o spoof detector desligado, a validação de `image/*` era contornável)

### Requirement: OPS-495 — Anexos de renegociação
O ai9 **MUST** validar **no servidor** os limites dos anexos de renegociação — no máximo **4 arquivos**
por renegociação e **5 MB** por arquivo, ambos vindos de configuração — e **MUST** validar o tipo do
arquivo e servi-lo apenas por URL assinada. Fonte legada:
`app/models/renegotiation_attachment.rb:4-13,38-40`; limites de interface em
`app/views/pub/console/parts/renegotiations/detail/tabs/_tab_geral.html.erb:200` e
`_tab_geral.js.erb:90-102`.

- No legado o model usa **`do_not_validate_attachment_file_type :file`** (aceita qualquer tipo), não
  tem `validates_attachment_size` nem contagem, e os dois limites existem **apenas em JavaScript**,
  com as mensagens "O máximo de arquivos permitido para envio é de 4 arquivos" e "O tamanho máximo de
  cada arquivo permitido para envio é de 5 MB"; o formulário fica `data-locked` ao chegar a 4 anexos.
- Combinado com o spoof detector desligado e o armazenamento em `public/`, o legado permite **upload
  arbitrário de arquivo publicamente acessível** — inclusive de documento financeiro de cliente.

#### Scenario: POST direto ignorando a interface
- **GIVEN** uma renegociação com 4 anexos
- **WHEN** um POST direto envia o quinto arquivo, de 50 MB e tipo arbitrário
- **THEN** o servidor recusa por quantidade, por tamanho e por tipo, sem depender de qualquer verificação no cliente

#### Scenario: documento financeiro não é público
- **GIVEN** um anexo de renegociação armazenado
- **WHEN** a URL do arquivo é acessada sem autorização
- **THEN** o acesso é negado

#### Scenario: limites vêm de configuração
- **GIVEN** a necessidade de alterar o máximo de anexos ou o tamanho por arquivo
- **WHEN** a configuração é ajustada
- **THEN** o novo limite passa a valer sem alteração de código

> Nota: corrige D-82 (legado: `do_not_validate_attachment_file_type`, limites apenas client-side, spoof detector desligado e arquivos servidos de `public/` sem autenticação)

### Requirement: OPS-496 — Imagens genéricas (galeria polimórfica)
O ai9 **MUST** tratar o upload de imagem genérica polimórfica (`Picture#image`) como **não portado**,
coerente com DB-593: nenhum model do legado declara `has_many :pictures` e o `counter_cache` aponta
para uma coluna inexistente, o que faria qualquer criação levantar exceção. Fonte legada:
`app/models/picture.rb:6-22,25-36`.

- Comportamento declarado no legado (para registro): derivados `thumb 80` (jpg q100),
  `preview 250` (jpg q70), `original 1500` (jpg q50); `content_type image/*`; presença obrigatória;
  limites dinâmicos via `imageable.max_image_count` e `imageable.max_image_size`, com fallback de 5 MB.

#### Scenario: descarte confirmado
- **GIVEN** a análise de que a galeria genérica nunca foi usada
- **WHEN** o ai9 é implementado
- **THEN** não existe upload polimórfico genérico, e a decisão fica registrada com a evidência

#### Scenario: limite dinâmico não é reintroduzido de forma frágil
- **GIVEN** o padrão legado `defined?(self.imageable.max_image_count)`, que avalia a chamada e devolve `nil` se o método não existir
- **WHEN** algum recurso do ai9 precisar de limite por entidade
- **THEN** o limite é lido de configuração explícita, sem depender de introspecção de método

### Requirement: OPS-497 — Upload de logo de fornecedor
O ai9 **MUST** portar o upload de logo de fornecedor com os derivados e o limite do legado. Fonte
legada: `app/models/provider.rb:12-24,28-29`.

- Derivados: `thumb 80`, `preview 250`, `medium 500`, `large 1200`, `retina 1500` (todos png q100);
  `content_type image/*`; **limite 1 MB** — bem mais apertado que os demais uploads.

#### Scenario: limite de 1 MB preservado
- **GIVEN** um logo de 2 MB
- **WHEN** o upload é enviado
- **THEN** o servidor recusa, mantendo a paridade com o limite do legado

#### Scenario: cinco derivados em png
- **GIVEN** um logo válido
- **WHEN** o upload conclui
- **THEN** os cinco derivados existem em png

### Requirement: OPS-498 — Upload de logo de cedente
O ai9 **MUST** portar o upload de logo de cedente/banco com os mesmos derivados e limite do fornecedor.
Fonte legada: `app/models/carrier.rb:16-28,32-33`.

- Derivados: `thumb 80`, `preview 250`, `medium 500`, `large 1200`, `retina 1500` (png q100);
  `content_type image/*`; **limite 1 MB**.

#### Scenario: limite de 1 MB preservado
- **GIVEN** um logo de 2 MB
- **WHEN** o upload é enviado
- **THEN** o servidor recusa

#### Scenario: logo exibido nas listagens
- **GIVEN** um cedente com logo carregado
- **WHEN** a listagem de cedentes é montada
- **THEN** o derivado `thumb` é usado, sem carregar o original

### Requirement: OPS-499 — Identidade visual do tema (4 anexos)
O ai9 **MUST** portar os 4 anexos do tema (`symbol_logo`, `full_logo`, `text_logo`,
`login_bkg_image`) e **MUST** garantir que a ausência de qualquer um deles **não impeça o envio de
e-mail**. Fonte legada: `app/models/app_theme.rb:6-45,48-55`; consumo em
`app/decorators/models/mailer_decorator.rb:9,11,23,25,38,40`.

- Derivados dos 3 logos: `thumb 80`, `preview 250`, `original 1500` (png q100);
  `login_bkg_image`: `thumb`, `preview`, `medium`, `large`, `retina` (jpg, q100→50).
  Todos com `content_type image/*` e **limite 5 MB**.

#### Scenario: tema sem logo carregado
- **GIVEN** um usuário cujo tema não tem `full_logo` nem `symbol_logo`
- **WHEN** um e-mail transacional é montado
- **THEN** o logo padrão da marca é usado e o e-mail é enviado, em vez de o envio estourar no `File.new(...)` e sumir silenciosamente

#### Scenario: anexos de tema seguem as regras de storage
- **GIVEN** os logos de um tema
- **WHEN** eles são exibidos na interface
- **THEN** são servidos pelo mesmo mecanismo de anexo do restante do sistema

> Nota: corrige D-82 (legado: anexos em `public/`) e o risco alto de paridade em que a falta de logo derrubava os e-mails de credenciais e de recuperação de senha

### Requirement: BE-480 — E-mail de boas-vindas / primeiro acesso
O ai9 **MUST** enviar o e-mail de boas-vindas ao usuário recém-criado com um **link de definição de
senha com token expirável**, e **MUST NOT** enviar a senha em texto puro. Fonte legada: gatilho
`app/decorators/controllers/registrations_decorator.rb:22-38`; fachada `lib/notification_facade.rb:2-4`;
mailer `app/decorators/models/mailer_decorator.rb:3-14`; template
`app/views/livetat/mailer19/mailing/send_welcome_email_to_new_generic_user.html.erb`.

- **Gatilho**: criação de usuário quando `@_action_name == "create"`, `@user.errors.blank?` e
  `params[:is_pub_domain] == 1`.
- **Destinatário**: `"<primeiro nome> <e-mail do novo usuário>"`; remetente
  `"Safegold <noreply@safegold.com.br>"`.
- **Conteúdo legado**: `responsible_formal`, `responsible_username`, `responsible_mail`,
  **`responsible_pass` (senha em texto puro)**, `responsible_role_type`, `manager_formal`,
  `manager_role_type`, com logos do tema anexados inline.
- Antes do envio, o legado faz `@user.update_theme(manager.app_theme_id)` — o ai9 **MUST** tolerar
  `manager_id` inválido sem quebrar o cadastro.

#### Scenario: senha nunca trafega
- **GIVEN** um usuário recém-criado pelo console
- **WHEN** o e-mail de boas-vindas é enviado
- **THEN** o corpo contém um link de definição de senha com token expirável e nenhuma senha

#### Scenario: token expirado
- **GIVEN** um link de definição de senha cujo prazo passou
- **WHEN** o usuário o acessa
- **THEN** a página informa que o link expirou e oferece novo envio

#### Scenario: manager inválido não derruba o cadastro
- **GIVEN** um cadastro com `manager_id` que não existe
- **WHEN** o usuário é criado
- **THEN** o cadastro conclui com o tema padrão e o e-mail é enviado, sem exceção por método em objeto nulo

> Nota: corrige D-38 (legado: e-mail de boas-vindas com a senha em texto puro, que fica arquivada na caixa do usuário)

### Requirement: BE-481 — E-mail de recuperação de senha
O ai9 **MUST** enviar o e-mail de recuperação de senha ("Perdeu a senha?") com link de redefinição, de
forma durável. Fonte legada: gatilho `app/decorators/facades/auth_ux19_notification_decorator.rb:7-9`
(sobrescreve `Livetat::AuthUx19::Notification.send_password_reset_instructions`); fachada
`lib/notification_facade.rb:6-8`; mailer `app/decorators/models/mailer_decorator.rb:17-28`; template
`app/views/livetat/mailer19/mailing/send_email_to_recovery_password_user.html.erb`.

- **Destinatário**: `"<primeiro nome> <user.email>"`; assunto `"Perdeu a senha?"`; logos do tema inline.
- O decorator legado cria `alias_method :old_send_password_reset_instructions` e **nunca chama o
  original** — o fluxo padrão da engine fica totalmente substituído.

#### Scenario: e-mail enviado ao solicitar recuperação
- **GIVEN** um usuário existente pedindo recuperação de senha
- **WHEN** a solicitação é processada
- **THEN** um e-mail com link de redefinição é enfileirado de forma durável

#### Scenario: entrega sobrevive a restart
- **GIVEN** a aplicação reiniciada logo após a solicitação
- **WHEN** o worker retoma
- **THEN** o e-mail é entregue

### Requirement: BE-482 — E-mail de confirmação de nova senha
O ai9 **MUST** enviar o e-mail informativo "Nova senha configurada" após a troca de senha. Fonte
legada: gatilho `app/decorators/facades/auth_ux19_notification_decorator.rb:11-13` (sobrescreve
`notify_password_reset_success`); fachada `lib/notification_facade.rb:10-12`; mailer
`app/decorators/models/mailer_decorator.rb:32-43`; template
`app/views/livetat/mailer19/mailing/send_email_to_reset_password_user.html.erb`.

- **Destinatário**: `"<primeiro nome> <user.email>"`; assunto `"Nova senha configurada"`; logos do
  tema inline. É puramente informativo: não contém link nem token.

#### Scenario: aviso após a troca
- **GIVEN** um usuário que acabou de redefinir a senha
- **WHEN** a troca é concluída
- **THEN** ele recebe o aviso de que a senha foi alterada

#### Scenario: nenhum token no corpo
- **GIVEN** o e-mail de confirmação
- **WHEN** o corpo é montado
- **THEN** ele não contém token nem link de autenticação

### Requirement: BE-483 — E-mail de confirmação de recebimento de feedback
O ai9 **MUST** enviar a confirmação de recebimento ao autor de uma mensagem de feedback, com assunto
`"Obrigado, <primeiro nome> :)"`, de forma durável. Fonte legada:
`engines/feedback19/app/controllers/livetat/feedback19/messages_controller.rb:91` →
`engines/feedback19/lib/livetat/feedback19/notification.rb:4-8` →
`engines/feedback19/app/decorators/grind_mailer_decorator.rb:4-36`; template
`engines/mailer19/app/views/livetat/mailer19/mailing/confirm_feedback_to.html.erb` (+ `.text.erb`).

- Envia apenas se `@message.errors.empty?`; registra uma linha em `livetat_mailer_contacts`; o corpo
  varia conforme a configuração de time genérico e conforme o e-mail já pertencer a um usuário
  existente; anexa `logo.png` inline.

#### Scenario: confirmação enviada ao autor
- **GIVEN** uma mensagem de feedback gravada com sucesso
- **WHEN** o envio é processado
- **THEN** o autor recebe a confirmação e o envio fica registrado no log de e-mails

#### Scenario: durabilidade
- **GIVEN** o processo reiniciado logo após a criação da mensagem
- **WHEN** o worker retoma
- **THEN** a confirmação é entregue, em vez de se perder no adapter in-process do legado

> Nota: corrige D-78 (legado: este e-mail caía no ramo `deliver_later` com fila em memória)

### Requirement: BE-484 — E-mail de confirmação de conta
O ai9 **MUST** portar o envio manual de confirmação de conta ("Bem-vindo") **sem expor o token de
autenticação do usuário** e **MUST** tratar destinatário inexistente. Fonte legada:
`engines/mailer19/app/controllers/livetat/mailer19/contacts_controller.rb:27-35`
(rota `POST /mailer/contacts/confirm_account`);
`engines/mailer19/lib/livetat/mailer19/grind_mailer.rb:26-44`;
`engines/mailer19/app/mailers/livetat/mailer19/mailing.rb:14-21`; template
`.../mailing/confirm_account_of.html.erb`.

- É um endpoint disparado **manualmente** (ferramenta de reenvio no console), não automático no
  cadastro. No legado usa o `authentication_token` do usuário como token e o envia por e-mail.

#### Scenario: e-mail de destino inexistente
- **GIVEN** um endereço que não corresponde a nenhum usuário
- **WHEN** o reenvio é solicitado
- **THEN** a resposta é um erro tratado, em vez de exceção por método em objeto nulo

#### Scenario: token de sessão não vaza
- **GIVEN** o e-mail de confirmação de conta
- **WHEN** o corpo é montado
- **THEN** ele não contém o token de autenticação do usuário; qualquer link usa token de uso único e expirável

> Nota: corrige D-38 (legado: material de autenticação enviado por e-mail — mesma família do envio de senha em texto puro)

### Requirement: BE-485 — E-mail de convite para a conta
O ai9 **MUST** portar o convite por e-mail, com assunto
`"<Nome do admin> te convidou para trabalhar em seu projeto!"`, **corrigindo as duas quebras que hoje
impedem o envio**. Fonte legada:
`engines/mailer19/app/controllers/livetat/mailer19/contacts_controller.rb:37-45`
(rota `POST /mailer/contacts/account_invitation`);
`engines/mailer19/lib/livetat/mailer19/grind_mailer.rb:46-64`;
`engines/mailer19/app/mailers/livetat/mailer19/mailing.rb:23-34`; template
`.../mailing/account_invitation.html.erb`.

- Quebras do legado: (a) o controller chama `send_account_invitation_to` com **4 argumentos** enquanto
  o método exige **5** (`email, name, token, deadline, who_invited`) → `ArgumentError` garantido;
  (b) `File.new(who_invited.avatar.path, 'rb')` falha se o administrador não tiver avatar.
- Conteúdo: token de convite com prazo, avatar do administrador inline e logo do tema.

#### Scenario: convite chega ao destinatário
- **GIVEN** um administrador convidando um novo colaborador
- **WHEN** o convite é enviado
- **THEN** o destinatário recebe o e-mail com o link de aceite dentro do prazo

#### Scenario: administrador sem avatar
- **GIVEN** um administrador sem avatar carregado
- **WHEN** o convite é montado
- **THEN** o avatar padrão é usado e o envio conclui

#### Scenario: convite expirado
- **GIVEN** um convite cujo prazo passou
- **WHEN** o link é acessado
- **THEN** o aceite é recusado com mensagem de expiração

> Nota: corrige D-79 (legado: o envio levantava `ArgumentError` e, por cair no ramo in-process, a falha sumia sem registro — o convite provavelmente nunca funcionou em produção)

### Requirement: BE-486 — E-mail de inclusão como observador
O ai9 **MUST** notificar por e-mail o usuário incluído como observador de um contexto de feedback,
com assunto `"<Primeiro nome> te incluiu no <app_name>"`. Fonte legada:
`engines/feedback19/app/controllers/livetat/feedback19/observers_controller.rb:20` →
`engines/feedback19/lib/livetat/feedback19/notification.rb:10-21` → `send_generic_message`; template
`engines/mailer19/app/views/livetat/mailer19/mailing/generic_message.html.erb` (sobrescrito por
`engines/feedback19/app/decorators/mailing_decorator.rb:16-33`).

- Enviado apenas se `@observer.errors.empty?`. O corpo explica que o destinatário passará a receber
  e-mail a cada mensagem em aberto e inclui o e-mail do administrador para contestação.

#### Scenario: notificação de inclusão
- **GIVEN** um administrador incluindo um observador
- **WHEN** a inclusão é gravada com sucesso
- **THEN** o observador recebe o e-mail de inclusão

#### Scenario: inclusão inválida não notifica
- **GIVEN** uma inclusão que falha na validação
- **WHEN** a operação é processada
- **THEN** nenhum e-mail é enviado

### Requirement: BE-487 — E-mail de remoção como observador
O ai9 **MUST** notificar por e-mail o usuário removido da lista de observadores, com assunto
`"<Primeiro nome> te removeu no <app_name>"`. Fonte legada:
`engines/feedback19/app/controllers/livetat/feedback19/observers_controller.rb:70` →
`engines/feedback19/lib/livetat/feedback19/notification.rb:23-34`.

- O corpo informa que as capacidades de observador foram desabilitadas.

#### Scenario: notificação de remoção
- **GIVEN** um observador removido com sucesso
- **WHEN** a remoção é gravada
- **THEN** ele recebe o e-mail informando a desabilitação

#### Scenario: remoção inválida não notifica
- **GIVEN** uma remoção que falha na validação
- **WHEN** a operação é processada
- **THEN** nenhum e-mail é enviado

### Requirement: BE-488 — E-mail aos observadores sobre nova mensagem
O ai9 **MUST** notificar os observadores do contexto a cada nova mensagem de feedback, com assunto
`"Nova mensagem no <app_name>"`, **um e-mail por observador**, e **MUST** escapar o conteúdo enviado
pelo usuário. Fonte legada:
`engines/feedback19/app/controllers/livetat/feedback19/messages_controller.rb:91` →
`engines/feedback19/lib/livetat/feedback19/notification.rb:7,36-74`.

- Corpo com o bloco "DADOS DO USUÁRIO": nome, situação (`state.name`), e-mail, tipo (`context.name`),
  data/hora no formato `%d.%m.%Y %H:%M` e os campos extras `hadouken`/`shoryuken` quando ativos.
- **Regra de visibilidade**: o observador é pulado quando `o.is_intern == 0 && m.is_intern == 1`.

#### Scenario: mensagem interna só vai a observadores internos
- **GIVEN** uma mensagem marcada como interna e observadores internos e externos
- **WHEN** as notificações são disparadas
- **THEN** apenas os observadores internos recebem o e-mail

#### Scenario: conteúdo do usuário escapado
- **GIVEN** uma mensagem de feedback contendo marcação HTML
- **WHEN** o e-mail é montado
- **THEN** o conteúdo é escapado e renderizado como texto, em vez de ser concatenado e marcado como seguro

#### Scenario: um e-mail por observador
- **GIVEN** três observadores elegíveis no contexto
- **WHEN** chega uma mensagem
- **THEN** são enfileirados três envios independentes, e a falha de um não impede os outros

> Nota: corrige D-82 (legado: o corpo era montado por concatenação de string e marcado `html_safe`, permitindo injeção de HTML no e-mail a partir da mensagem do usuário)

### Requirement: BE-489 — E-mail de resposta/nova nota em um feedback
O ai9 **MUST** notificar por e-mail a nova nota em uma conversa de feedback, com assunto variável
(`"<Equipe> respondeu sua mensagem"`, `"Você tem uma nova mensagem #<id>"` ou
`"Conversa com <nome> #<id>"`), e **MUST** exigir autenticação no link da conversa. Fonte legada:
`engines/feedback19/app/controllers/livetat/feedback19/notes_controller.rb:29,36` →
`engines/feedback19/lib/livetat/feedback19/notification.rb:76-106`.

- Enviado apenas se `@note.errors.empty?`. O corpo traz um trecho da nota e o link
  `#{ENV['alias']}/feedbacks/messages/<public_token>`; assunto e texto variam conforme o autor da nota
  e a configuração de time genérico.

#### Scenario: link da conversa não é acesso livre
- **GIVEN** o link da conversa recebido por e-mail
- **WHEN** alguém sem autorização o acessa
- **THEN** o acesso é negado ou limitado por token de uso único e expirável, em vez de liberar a conversa a quem tiver a URL

#### Scenario: assunto conforme o autor
- **GIVEN** uma nota escrita pelo próprio autor original da mensagem
- **WHEN** o e-mail é montado
- **THEN** o assunto usa a variante correspondente ao remetente

> Nota: corrige D-82 (legado: `public_token` na URL dava acesso à conversa sem autenticação)

### Requirement: BE-490 — Mensagem genérica com link (código morto)
O ai9 **MUST NOT** portar `send_generic_message_with_link`: o mailer, o método e o template existem no
legado, mas o grep em `app/` e `engines/` não encontra **nenhum chamador**. Fonte legada:
`engines/mailer19/lib/livetat/mailer19/grind_mailer.rb:84-100`;
`engines/mailer19/app/mailers/livetat/mailer19/mailing.rb:50-65`; template
`.../mailing/generic_message_with_link.html.erb`.

#### Scenario: catálogo de e-mails fechado
- **GIVEN** o catálogo de e-mails do ai9
- **WHEN** ele é listado
- **THEN** ele contém apenas os e-mails com gatilho real no produto, e a mensagem genérica com link não está nele

#### Scenario: descarte com evidência
- **GIVEN** a decisão de descartar este mailer
- **WHEN** o registro da migração é consultado
- **THEN** consta a evidência de zero chamadas no legado

### Requirement: FE-480 — Helper genérico de polling não existe no ai9
O ai9 **MUST NOT** portar o `PollingManager`: o helper genérico de polling do legado — `setInterval`
com período default de **5000 ms**, API `start/stop/reset/execute` e listeners
`didStart/didStop/didExecute`, exposto como global — **MUST** deixar de existir, e toda atualização
periódica de dado **MUST** ser substituída por assinatura de canal Action Cable (ver OPS-488). Fonte
legada: `app/frontend/js/polling_helper.js:1-97` (intervalo em `:47`); exposição global em
`app/frontend/js/index.js.erb:4,31`.

- O único consumidor do helper no legado é o monitor de usuário do widget de navegação (FE-481) — e
  esse consumidor **está desligado**. Não há nenhum outro chamador.
- No ai9 a capacidade equivalente é: **o servidor empurra o evento** quando o dado muda, e o cliente
  reage. Nenhum componente do frontend do ai9 **MUST** consultar a API em intervalo fixo à espera de
  mudança.

#### Scenario: varredura do frontend por polling
- **GIVEN** o código do frontend do ai9
- **WHEN** ele é varrido por consulta periódica de dados
- **THEN** não existe `PollingManager` nem `setInterval` consultando a API por atualização de dado

#### Scenario: necessidade de atualização contínua
- **GIVEN** uma tela que precisa refletir mudança de dado sem intervenção do usuário
- **WHEN** o dado muda no servidor
- **THEN** a tela é atualizada por evento no canal assinado, e não por uma nova requisição disparada por temporizador

> Nota: corrige D-86 (legado: polling a cada 5 s via `setInterval` em `polling_helper.js:47`)

### Requirement: FE-481 — Estado do usuário na sessão aberta chega por evento
O ai9 **MUST** refletir mudanças de estado da conta do usuário logado (desativação, mudança de papel,
bloqueio) na sessão já aberta **por evento de Action Cable**, e **MUST NOT** reintroduzir o monitor de
usuário do legado, que instanciava um `PollingManager` de **1000 ms** batendo em
`GET /users/<id>.json`. Fonte legada: `app/views/pub/base/nav/user/_widget.js.erb:1-20`
(`w.data("user-monitor")`).

- **O monitor já está desativado no legado**: o `.start()` está comentado em
  `_widget.js.erb:18-19`, com a marcação "Desativado na Versão 2.0 - Revisão 2 - Build #5695". O
  objeto é construído e nunca inicia — **não há polling de 1 s rodando hoje**.
- Além de desativado, o monitor era inerte como estava: o callback de `success` é **vazio**, então nem
  quando ligado ele fazia algo com a resposta. Era uma requisição por segundo por usuário logado, sem
  efeito.
- Portanto o requisito aqui é sobre a **capacidade equivalente** — refletir mudança de conta na sessão
  aberta — e **não** sobre ressuscitar a feature do legado.

#### Scenario: conta desativada com sessão aberta
- **GIVEN** um usuário com sessão aberta que é desativado por um administrador
- **WHEN** a desativação é gravada
- **THEN** a sessão é encerrada por evento no canal do usuário, sem nenhuma consulta periódica

#### Scenario: nenhum monitor por temporizador
- **GIVEN** o widget de navegação do ai9
- **WHEN** o tráfego de rede é observado com a tela ociosa
- **THEN** nenhuma requisição periódica ao recurso de usuário é emitida

> Nota: corrige D-86 (legado: polling a cada 1 s via `setInterval` em `_widget.js.erb:7-16`, já desativado no legado — `.start()` comentado em `:18-19`)

### Requirement: FE-483 — Autocomplete de endereço e selects encadeados Estado/Cidade
O ai9 **MUST** portar o preenchimento de endereço por autocomplete do Google Places e os selects
encadeados País → Estado → Cidade, e **MUST** eliminar a corrida de inicialização do legado. Fonte
legada: `app/views/pub/console/parts/my_account/parts/address/_container.js.erb:1-80`;
`.../address/_container.html.erb:33,41`; endpoints em
`app/controllers/pub/console_controller.rb:259-270`.

- Comportamento legado: o script do Maps é carregado sob demanda; os campos são `#query`,
  `#country_select`, `#state_select`, `#city_select` e `#user_info_delivery_location_cep` com máscara
  `99999-999`. Trocar o país dispara AJAX para `pub_console_state_select_path.js`; trocar o estado
  dispara AJAX para `pub_console_city_select_path.js`. Ao escolher um lugar no autocomplete, o
  formulário é preenchido a partir de `place.address_components` invertidos.
- Endereço sem `geometry` produz toast vermelho "Endereço inválido / Escolha uma das opções oferecidas
  durante a busca". Esse retorno de erro **MUST** ser preservado.
- A chave da API do Google **MUST** vir de ENV/credentials e ser restrita por referrer (ver OPS-482 e
  OPS-485).

#### Scenario: seleção de endereço pelo autocomplete
- **GIVEN** o usuário digitando no campo de busca de endereço
- **WHEN** ele escolhe uma das sugestões oferecidas
- **THEN** logradouro, número, bairro, cidade, estado, país e CEP são preenchidos a partir do resultado

#### Scenario: endereço digitado sem escolher sugestão
- **GIVEN** um texto livre que não corresponde a nenhum lugar com `geometry`
- **WHEN** o formulário tenta usá-lo
- **THEN** o erro "Endereço inválido" é exibido e o endereço não é aceito

#### Scenario: troca de estado recarrega as cidades
- **GIVEN** um país e um estado já selecionados
- **WHEN** o estado é trocado
- **THEN** a lista de cidades é recarregada para o novo estado, e a cidade anterior é descartada

#### Scenario: script externo ainda não carregado
- **GIVEN** o usuário interagindo com o campo antes de o script de mapas terminar de carregar
- **WHEN** a interação ocorre
- **THEN** o componente aguarda o carregamento de forma determinística, em vez de depender de um temporizador fixo que pode disparar cedo demais

> Nota: corrige OPS-482 (legado: a inicialização do autocomplete dependia de um `setTimeout(200)`, em corrida com o carregamento do script do Maps)

### Requirement: FE-484 — Limites de anexo da renegociação na interface
O ai9 **MUST** manter os limites de anexo da renegociação visíveis e aplicados na interface — no
máximo **4 arquivos** por renegociação e **5 MB por arquivo** — e **MUST** aplicar os mesmos limites no
servidor, porque no legado a validação existe **apenas no cliente**. Fonte legada:
`app/views/pub/console/parts/renegotiations/detail/tabs/_tab_geral.html.erb:200`;
`.../tabs/_tab_geral.js.erb:90-102`.

- Comportamento legado: seleção múltipla de arquivos (remotipart); o wrapper recebe `data-locked`
  quando `attachments.count >= 4`; ao exceder, o envio é bloqueado e aparece o toast de título
  "Limite excedido", com "O máximo de arquivos permitido para envio é de **4 arquivos**" e "O tamanho
  máximo de cada arquivo permitido para envio é de **5 MB**".
- Os textos e os números **MUST** ser preservados; o que muda é que o limite deixa de ser confiança no
  cliente (ver OPS-495).

#### Scenario: quinto arquivo
- **GIVEN** uma renegociação que já tem 4 anexos
- **WHEN** o usuário tenta anexar mais um
- **THEN** a interface bloqueia o envio e exibe "Limite excedido", e o servidor também recusa caso a requisição seja forjada

#### Scenario: arquivo acima do limite de tamanho
- **GIVEN** um arquivo de 8 MB
- **WHEN** o usuário o seleciona
- **THEN** o envio é recusado com a mensagem de limite de 5 MB, e a recusa é repetida pelo servidor

#### Scenario: contagem reflete exclusões
- **GIVEN** uma renegociação com 4 anexos, da qual um é removido
- **WHEN** o usuário volta a anexar
- **THEN** o envio é liberado, porque a contagem é reavaliada e não fica travada no estado inicial da tela

### Requirement: DB-480 — Geolocalização por entidade (`geolocations`)
O ai9 **MUST** preservar o armazenamento de geolocalização e endereço por entidade e **MUST** mover o
geocode para **job assíncrono**, tirando-o do `before_save`. Fonte legada:
`db/migrate/20160302002809_create_geolocations.rb:3-24`; model `app/models/geolocation.rb`. O contrato
de colunas está registrado em DB-592 (`openspec/specs/data-schema/spec.md`).

- Colunas legadas: `geolocatable_type`/`geolocatable_id` (polimórfico, com índice), `lat`, `lng`,
  `ref_lat`, `ref_lng` `decimal(10,6)`, `city`, `state`, `cep`, `neighborhood`, `country`,
  `street_number` int, `address`, `complement`, `full_address`, `auto_loading` int d0, `distance`
  float, `distance_unity` string, timestamps. Uma linha por entidade geolocalizada.
- `auto_loading = 1` faz o `before_save` **apagar** todos os campos de endereço e re-geocodificar;
  `auto_loading = 0` preserva o que foi digitado. Esse contrato de duas vias **MUST** ser preservado,
  mas executado fora do ciclo de save (ver OPS-481).
- A validação `check_uniqueness` (`geolocation.rb:174-176`) roda **em todo save** e só barra na
  criação. No ai9 a unicidade de uma geolocalização por entidade **MUST** ser garantida por **índice
  único** no par polimórfico, não por validação de aplicação.

#### Scenario: entidade salva com endereço a resolver
- **GIVEN** uma entidade com coordenadas e `auto_loading` ligado
- **WHEN** ela é salva
- **THEN** o save retorna imediatamente e o geocode acontece em job, em vez de o save ficar preso na chamada externa

#### Scenario: endereço digitado é preservado
- **GIVEN** uma geolocalização com `auto_loading` desligado e endereço preenchido à mão
- **WHEN** ela é salva de novo
- **THEN** os campos de endereço permanecem exatamente como foram digitados

#### Scenario: segunda geolocalização para a mesma entidade
- **GIVEN** uma entidade que já tem geolocalização
- **WHEN** uma segunda linha é inserida para a mesma entidade
- **THEN** o banco recusa por índice único, e não apenas na criação pela camada de aplicação

### Requirement: DB-481 — Registro de e-mails enviados (`livetat_mailer_contacts`)
O ai9 **MUST** preservar o registro de e-mails enviados e **MUST** ampliá-lo para registrar **status de
entrega**, porque o legado registra apenas a intenção de envio. Fonte legada:
`engines/mailer19/db/migrate/20160409121840_create_livetat_mailer_contacts.rb`;
`.../20170519223014_*` e `.../20170519223026_*` (remoção e readição de `message`); model
`engines/mailer19/app/models/livetat/mailer19/contact.rb`. O contrato de colunas está registrado em
DB-596 (`openspec/specs/data-schema/spec.md`).

- Colunas legadas: `sender`, `target` (e-mail de destino), `target_name`, `subject`, `message`,
  timestamps. É o **único log de e-mails** do sistema.
- O legado **não registra sucesso nem falha de entrega**: a linha é gravada quando o envio é
  solicitado, e nada distingue entregue de perdido — o que, somado à perda silenciosa de D-78, torna o
  log enganoso.
- No ai9 **MUST** haver status de entrega (enfileirado, entregue, falho, com o erro), correlação com o
  job de envio e índice em `target` e em `created_at`. A tabela cresce a cada e-mail enviado e **MUST**
  ter política de retenção declarada.
- A listagem do legado (`Livetat::Mailer19::ContactsController#index`) usa `limit(6)` com
  `offset(offset * 5)` — paginação inconsistente, que **pula ou repete registros**. No ai9 a paginação
  **MUST** usar o mesmo tamanho de página no limite e no deslocamento.

#### Scenario: e-mail que falha na entrega
- **GIVEN** um envio recusado definitivamente pelo servidor SMTP
- **WHEN** o registro é consultado
- **THEN** ele consta como falho, com o erro correspondente, em vez de parecer igual a um e-mail entregue

#### Scenario: navegação entre páginas do log
- **GIVEN** um log com mais registros do que cabem em uma página
- **WHEN** o operador avança de página
- **THEN** nenhum registro é pulado nem repetido, ao contrário do `limit(6)` com `offset(offset * 5)` do legado

#### Scenario: busca pelo destinatário
- **GIVEN** um volume grande de registros
- **WHEN** o log é filtrado por endereço de destino
- **THEN** a consulta usa índice, em vez de varrer a tabela inteira

### Requirement: DB-482 — Colunas de anexo dos modelos migram para o motor único
O ai9 **MUST** substituir as quatro colunas por anexo do Paperclip (`<attr>_file_name`,
`<attr>_content_type`, `<attr>_file_size`, `<attr>_updated_at`) pelo motor único de anexos do ai9
(ver OPS-491 e OPS-492), e **MUST** migrar os binários correspondentes. Fonte legada:
`app/models/{project,picture,provider,carrier,app_theme,renegotiation_attachment}.rb`;
`app/decorators/models/user_decorator.rb:11`; `engines/auth19/app/models/livetat/auth/user.rb:4`.

- São **11 anexos** no legado: `users.avatar`, `projects.avatar`, `renegotiation_attachments.file`,
  `pictures.image`, `providers.logo`, `carriers.logo` e os quatro de `app_themes`
  (`symbol_logo`, `full_logo`, `text_logo`, `login_bkg_image`) — 44 colunas ao todo.
- Os binários vivem em `public/system/:attachment/:id/…` **no disco do servidor legado**: são
  acessíveis sem autenticação e não sobrevivem a container efêmero nem a escala horizontal.
- A migração de dados **MUST** copiar cada arquivo e reanexá-lo à entidade correspondente, e **MUST**
  reportar todo registro cujas colunas indiquem um anexo cujo arquivo não existe mais no disco.
- As colunas Paperclip **MUST NOT** ser recriadas no esquema do ai9.

#### Scenario: anexo com registro mas sem arquivo
- **GIVEN** uma linha com `<attr>_file_name` preenchido cujo arquivo não existe em `public/system/`
- **WHEN** o ETL roda
- **THEN** o caso é reportado no relatório de migração de arquivos, em vez de produzir um anexo quebrado silenciosamente

#### Scenario: acesso ao arquivo migrado
- **GIVEN** um anexo já migrado
- **WHEN** um anônimo tenta baixá-lo pela URL antiga ou por adivinhação de caminho
- **THEN** o acesso é negado; o arquivo é servido por URL assinada e com prazo, a partir de storage privado

#### Scenario: esquema sem colunas de anexo
- **GIVEN** o esquema do ai9
- **WHEN** ele é inspecionado
- **THEN** nenhuma das 44 colunas Paperclip existe, e todo anexo é resolvido pelo motor único

> Nota: corrige D-82 (legado: anexos servidos por URL pública a partir de `public/system/`, sem autenticação)
