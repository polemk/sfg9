# Defeitos do legado encontrados no inventário

Regra do skill: **preservar comportamento** é o padrão, mas um defeito não é
comportamento a preservar — é decisão consciente no Phase 2. Cada item aqui recebe
um veredito: `corrigir` (o ai9 nasce certo, com cenário de spec novo + linha no
improvements-log), `preservar` (o negócio depende do comportamento atual, por mais
estranho que seja) ou `perguntar` (só o usuário decide).

Nada aqui pode ser resolvido por omissão — todo item vira decisão registrada.

| # | Defeito | Fonte | Impacto | Veredito proposto |
| - | ------- | ----- | ------- | ----------------- |
| D-01 | `GET /api/v1/project_availability` **sem autorização**: herda de `ApplicationController` (não do `PubApplicationController`) e faz `Project.find(params[:id])` sem escopo — qualquer requisição lê a disponibilidade de qualquer projeto por id | `app/controllers/api/v1/project_availability_controller.rb` | **Vazamento de dados entre clientes.** Grave | **corrigir** — no ai9 o endpoint nasce autenticado e escopado ao tenant. Não se replica um IDOR |
| D-02 | Decaimento composto no valor de disponibilidade: `before_validation` grava `original_value = value` a cada mudança de `value`, e `update_value` reescreve `value = original_value * (dias úteis até a data / dias úteis do mês)`. O controller faz `update` seguido de `save`, e o `after_save` re-salva pai/mirror → o multiplicador é reaplicado sobre valor já corrigido | `app/models/availability_entry.rb`; `app/controllers/pub/availability_entries_controller.rb:42,44` | Valores financeiros divergem a cada salvamento repetido | **perguntar** — pode haver dependência contábil no valor atual. Precisa de reconciliação com dados reais antes de decidir |
| D-03 | Dias úteis contam apenas seg–sex, **sem feriados** | `app/models/availability_entry.rb` (cálculo de `update_value`) | Datas de referência erradas em meses com feriado | **perguntar** — se o negócio quer feriados, é mudança de resultado financeiro |
| D-04 | Guarda "não pode desativar template obrigatório" nunca roda no fluxo real: a validação vive em `project_availability_template.rb:141-169` (e ainda filtra por `project_id: self.id`, o que é bug), mas a rota `deactivate` enfileira job que chama `background_deactivate` (linha 744), que só faz `is_active = 0` | `app/models/project_availability_template.rb:141-169,744` | Templates obrigatórios podem ser desativados | **corrigir** — a intenção do código é clara; o ai9 aplica a regra no serviço, não só na validação |
| D-05 | Os 5 jobs de template engolem exceção no `rescue`, `destroy_failed_jobs?` é `false`, não há retry, e só `background_activate`/`background_deactivate` chamam `unlocked!` → **template fica travado para sempre** se o job falhar | `lib/project_availability_template_*_job.rb` | Registro inutilizável sem intervenção manual no banco | **corrigir** — no ai9: Sidekiq com retry, `ensure` liberando o lock, e falha visível |
| D-06 | Coluna `default_position` é usada em `availability_templates_controller.rb:22` mas **não existe em nenhuma migration** | `app/controllers/pub/availability_templates_controller.rb:22` | Busca de templates globais provavelmente quebrada em produção | ~~**perguntar**~~ → **RESPONDIDO em 26/08/2026 pelo dump de produção: a coluna NÃO existe no banco real** (zero ocorrências no dump inteiro, nenhuma migration a cria). Não é "provavelmente quebrada": está quebrada. O desdobramento — o que o `ORDER BY` faz e o que o ai9 põe no lugar — é o **D-126** |
| D-07 | Parâmetros de busca `q`/`l`/`o` são aceitos mas nunca aplicados em 3 endpoints | ver `inventory/availability.md` | Busca/paginação silenciosamente ignorada | **corrigir** — no ai9 os parâmetros funcionam |
| D-08 | Mirror soma sem respeitar `is_cumulative`/`is_debit`; sinal de débito só é aplicado em folhas, nunca em subtotais | `app/models/availability_entry.rb` | Subtotais podem estar com sinal errado | **perguntar** — muda número exibido ao cliente |

| D-09 | **Matemática financeira duplicada e divergente**: 26 fórmulas em Ruby (`receivable_entry.rb:38-118`, num único `before_validation`) e uma segunda implementação em JavaScript (`_body.js.erb:339-504`). O JS não calcula `taxa_desconto_nominal_*`, `custo_efetivo_com_float_*`, `multiplicador_*` nem os `*_percent` das deduções | `app/models/receivable_entry.rb:38-118`; `app/views/pub/console/parts/receivables/new/_body.js.erb:339-504` | O que o usuário vê na tela pode não bater com o que o servidor grava | **corrigir** — no ai9 a fórmula vive **em um lugar só** (serviço no backend); o front consome o resultado. Preview em tempo real via endpoint de cálculo, nunca reimplementando a conta |
| D-10 | Guardas de divisão por zero (`valor_liquido == 0`, `prz_med_pond_emp == 0`) **só existem no cliente**. O servidor aceita e grava `Infinity`/`NaN` | idem D-09 | Registro financeiro corrompido gravado no banco | **corrigir** — validação no servidor. Nunca confiar em guarda de cliente |
| D-11 | **`after_commit` de integração com risco dispara duas vezes no cadastro**: a `RiskOperation` é criada no 1º commit com `valor_liquido` ainda **sem as tarifas**, e o 2º commit só atualiza tipo/subtipo. O próprio código admite o bug no comentário da linha 123 | `app/models/receivable_entry.rb:124-175`; `app/controllers/pub/receivables_controller.rb:77,89` | **Há dados históricos com valor de operação de risco errado.** Não é só bug de código — é dado sujo em produção | **corrigir** no ai9 **e** tratar no script de migração de dados: o backfill precisa recalcular, não copiar. Precisa de decisão do usuário sobre reprocessar o histórico |
| D-12 | **Domínio financeiro sem índices e sem foreign keys**: 1 único índice em todo o domínio (o polimórfico de `receipts`), nenhuma FK. `receivable_taxes` é lida 4× por save sem índice em `receivable_entry_id`. Volume: 7.746 recebíveis / 15.712 tarifas | migrations de `receivable_*` | Performance e integridade referencial. Órfãos prováveis | **corrigir** — no ai9 nascem com FK + índice (mandato de performance do skill). O script de dados precisa detectar e reportar órfãos antes de inserir |
| D-13 | **Valores em R$ guardados como `float`**, arredondamento inconsistente (2 vs 4 casas na mesma base), `Receipt#value` sem arredondamento | models de `receivable_*` e `receipt` | Erro de centavo acumulado em dinheiro | **corrigir** — `decimal` com escala definida no ai9. **Atenção:** muda resultado exibido; precisa de reconciliação contra o legado antes do cutover |
| D-14 | `calc_valor_liq_correto` usa **aproximação linear** em vez de desconto composto — e alimenta o campo `status` | `app/models/receivable_entry.rb` | O status "OK/Diferença" pode estar classificando errado | **perguntar** — é regra de negócio, não descuido óbvio |
| D-15 | Alíquotas de IOF **hardcoded sem vigência** | `app/models/receivable_entry.rb` | Alíquota muda por lei; sem vigência, recálculo histórico fica errado | **corrigir** — tabela de alíquotas com vigência no ai9 |
| D-16 | `receivable_id` no search **escapa do filtro de projeto** | `app/controllers/pub/receivables_controller.rb` | Vazamento de dado entre projetos (mesma classe do D-01) | **corrigir** |
| D-17 | `user_is_readonly` **não é checado em nenhum controller** | busca no legado por `user_is_readonly` | Usuário somente-leitura consegue escrever | **corrigir** — a intenção do campo é inequívoca |
| D-18 | Cobrança com status "Faturado" continua **editável pela API** | `app/controllers/pub/charges_controller.rb` | Alteração de documento já faturado | **corrigir** |
| D-19 | Não existe fluxo de baixa/liquidação nem status de vencimento (só OK/Diferença); `is_active` dos catálogos nunca é aplicado; ordenação por coluna é visível mas inoperante; rotas mortas (`receivables#index/show/new/edit`, `index` dos catálogos) | ver `inventory/receivables.md` | Funcionalidade prometida na UI que não existe | **perguntar** — decidir por item: implementar de verdade no ai9 ou remover da UI |

| D-20 | **Paginação e ordenação server-side nunca funcionaram** nos 6 endpoints de `search`: o padrão `@x.where!(...).order(...).limit(...).offset(...)` descarta tudo depois do `where!` (a relação nova não é atribuída). Só `companies#search` com `order_mode=dash` aplica de fato, via `limit!`/`offset!`. Além disso o navegador de páginas de Empresas muta `container.getData()` mas o proxy envia `holder.getData()` (fixo em l=50/o=0), e `@total_count` é a contagem da página | `app/controllers/pub/*_controller.rb` (padrão repetido); `companies_controller.rb:20-22` | **A UI de paginação é decorativa** — o usuário acha que está navegando e não está. Também explica lentidão: sempre traz tudo | **corrigir** — paginação real no ai9 (mandato de performance do skill). Mudança visível e desejada |
| D-21 | Features quebradas em produção: criar Segmento **sempre falha** (model exige `user_id`, `segment_params` não o permite); ordenar Grupos de Portadores dá **500** (`CarrierGroup.prepare_ordering` não existe); cabeçalhos "Grupo"/"Agente Financeiro"/"# Projetos" de Portadores dão **500** (sem `data-key`) | `segments_controller.rb:121-127`; `carrier_groups_controller.rb:28` | Funções que o usuário tenta usar e falham | **corrigir** — no ai9 nascem funcionando |
| D-22 | `index`/`show` das 6 entidades apontam para templates inexistentes → **detalhes de Portador e Fornecedor inacessíveis**, apesar de HTML + SCSS completos no repositório | views de `pub/console/parts/{carriers,providers}` | Telas prontas e pagas que ninguém consegue abrir | **perguntar** — portar as telas (o HTML existe, é barato) ou descartar? Recomendo portar |
| D-23 | **Autorização é só de UI**: nenhum endpoint valida papel nem `user_is_readonly` (generaliza o D-17). Some-se o escopo frouxo: `carriers`/`carrier_groups`/`segments`/`sub_segments` são globais enquanto `companies`/`providers` são por projeto, e ambos escapam do escopo em casos específicos | controllers de `pub/` | Qualquer usuário autenticado consegue chamar qualquer endpoint. **Grave** | **corrigir** — autorização no servidor por padrão no ai9. Define também o desenho de multi-tenancy |
| D-24 | Excluir Portador **destrói em cascata os `risk_controls`**; e todas as exclusões bloqueadas por `restrict_with_error` respondem **200** (o `destroy/handle.js.erb` de companies é arquivo vazio) → falham em silêncio | associações dos models; `views/pub/console/parts/companies/destroy/handle.js.erb` | Perda de dado de risco por exclusão em cascata; e erro invisível ao usuário | **corrigir** — cascata revista + resposta de erro real. Perda silenciosa de dado financeiro não se preserva |
| D-25 | `bank_code` é `integer` → **zeros à esquerda são corrompidos** (banco 001 vira 1); `providers.cnaes` guarda YAML enquanto `atividades` guarda JSON na mesma tabela | migrations de `carriers`/`providers` | Código de banco inválido; dois formatos serializados na mesma entidade | **corrigir** — `string` para código de banco, um formato só. Script de dados precisa re-padronizar |
| D-26 | `Project#reset` usa `segment_id = 1` **hardcoded** | `app/models/project.rb` | Depende de um id específico existir no banco | **corrigir** |
| D-27 | Consulta de CNPJ na ReceitaWS **viva no backend, morta na UI**: botão comentado e JS com ERB escapado (`<%%=`) | `app/helpers/cnpj_api.rb` + view de empresas | Integração paga/configurada que ninguém usa | **perguntar** — religar o autopreenchimento por CNPJ no ai9? |

| D-28 | **O "tenant corrente" é definido por cookie do cliente**: `cached_info` traz `default_project_id` e o servidor valida apenas que o projeto *existe*, não que o usuário tem membership nele | `app/controllers/pub/console_controller.rb:285-312` | `default_project` é o escopo de praticamente todo o sistema. Trocar o cookie troca de tenant. **É a falha mais grave achada até aqui** | **corrigir** — no ai9 o tenant vem da sessão/JWT e é validado contra membership a cada request. Nunca de cookie do cliente |
| D-29 | `projects#search` aceita `project_id`/`importing_id` que **ignoram o escopo de membership**; `project_guarantees#search` idem | `projects_controller.rb:15-23`; `project_guarantees_controller.rb:22` | Mesma classe do D-01/D-16: leitura de dado de outro tenant por id | **corrigir** |
| D-30 | `has_safegold_management` é um **carimbo denormalizado** propagado para 6 tabelas (companies, availability/receivable entries, renegotiations, risk_controls/entries), mas **só `companies` é atualizado em massa** quando a flag muda → histórico inconsistente por design | `app/models/project.rb`, `projects_controller.rb` (action `has_safegold_management`) | Registros antigos ficam com o carimbo errado; qualquer relatório que filtre por ele mente | **perguntar** — o carimbo é intencional (foto do momento) ou é bug? Muda o desenho do modelo no ai9 |
| D-31 | `has_bi` **não é lido em lugar nenhum** do repositório — só grava e exibe no detalhe | `app/models/project.rb`, `projects_controller.rb` | Feature flag morta na aplicação — mas pode ter consumidor externo (BI de terceiro lendo o banco) | **perguntar** — existe consumidor externo? Se não, é remoção |
| D-32 | Ordenação de garantias aponta para `risk_operations.title`, tabela **fora do join** | `project_guarantees_controller.rb` | 500 ao ordenar | **corrigir** |
| D-33 | `deactive_and_reorder!` e `set_new_position!`: as regras de template obrigatório vivem fora do caminho HTTP (reforça o D-04) | `app/models/project_availability_template.rb` | Regra que não roda | **corrigir** |

| D-34 | **Escalação de privilégio.** `PUT /users/:id/abilities` **ignora o `:id`** e altera qualquer ability do sistema. Impersonation (`POST /u/users/:id/impersonate`), update/delete de usuário e memberships não checam nada no backend. Os gates (`og?`, `admin?`, `may?("user_is_readonly")`) existem **só nas views ERB** | `app/controllers/pub/users_controller.rb`, `pub/memberships_controller.rb`, `pub/permissions_controller.rb` | **Qualquer sessão autenticada vira admin por POST direto, e pode se passar por qualquer usuário.** Junto com D-28, é a falha mais séria do legado | **corrigir** — obrigatório. Autorização no servidor em todo endpoint; impersonation restrita e auditada |
| D-35 | Permissões são um sistema próprio (não CanCan): `RoleType → Role → Ability` como linhas no banco (17 abilities, com `conditional`/`limit`), materializadas por `AbilityFactory`; os métodos `user.may_create_users?` são **definidos na classe em runtime** (`after_initialize :include_ability_methods`). Alterar a ability de um RoleType **não propaga** para usuários existentes | `app/decorators/models/ability_factory_decorator.rb`, `user_decorator.rb` | Mudança de permissão não tem efeito em quem já existe — administrador acha que revogou acesso e não revogou | **corrigir** — no ai9 permissão é resolvida por consulta, não congelada no usuário |
| D-36 | ~~`default_role_type = "Visitor"` e `minimal_type_to_sign_up_through_web = "Manager"` apontam para RoleTypes que o `db/seeds.rb` destroi~~ **CORRIGIDO 24/08: o sintoma previsto NAO ocorre.** `config/application.rb:84` sobrescreve `"Manager"` por `"Admin"`, que existe; e `default_role_type` e `""` (`application.rb:65`), nao `"Visitor"` | `config/application.rb:65,84`; `db/seeds.rb:40-95` | Nenhum — o `NoMethodError` que eu previa nao acontece. O problema real do cadastro publico e o **D-39** (cria Admin) | **resolvido/reclassificado** — verificado no caminho de execucao real pela matriz de autorizacao |
| D-37 | Token de reset de senha só é gerado se `reset_password_sent_at` for nil → **nunca expira e nunca rotaciona** | engine `auth19` / fluxo de reset | Link de reset antigo continua válido para sempre | **corrigir** — token de uso único com expiração |
| D-38 | E-mail de boas-vindas envia **a senha em texto puro** | engine `mailer19` / template de boas-vindas | Senha trafega e fica arquivada na caixa do usuário | **corrigir** — obrigatório. Envia-se link de definição de senha, nunca a senha |
| D-39 | Cadastro público (`PUBLIC_CREATE_USER = 1`) cria usuário **Admin** | fluxo de registro + `SFG::Metadata` | Qualquer pessoa na internet vira admin | **corrigir** — obrigatório |
| D-40 | OmniAuth com `provider_ignores_state: true` | engine `auth_omni19` | Desliga a proteção CSRF do fluxo OAuth | **corrigir** (se o login social for mantido; ver D-41) |
| D-41 | Login por Facebook: credenciais são placeholders (`FACEBOOK_APP_ID = 0`) e o botão não é renderizado | `SFG::Metadata`, views de auth | Integração morta | **perguntar** — descartar de vez ou reativar no ai9? |
| D-42 | Fluxos duplicados no auth: **2** telas de reset de senha, **2** páginas de "esqueci a senha", **2** actions de novo/editar usuário | views de `auth_ux19` + `pub/users` | Manutenção divergente; o usuário pode cair na versão errada | **corrigir** — um fluxo só no ai9 |
| D-43 | Rotas mortas/quebradas: `users#detail`, `show_info`, `pub/permissions/index`, redirect pós-login para `/u/console/profile` (resource inexistente), e `update_info` usa `update_attributes` — **removido no Rails 6.1** | `pub/users_controller.rb`, `pub/permissions_controller.rb`, `config/routes.rb` | `update_info` está quebrado em produção | **corrigir** o que é feature real; **descartar** o que é rota morta (com evidência) |
| D-44 | Dois campos concorrentes de conta ativa (`is_active` × `deactivated`) e `legacy_password` guardando hash **Django** | schema de usuário | Ambiguidade sobre quem pode logar; e há usuários com hash de outro framework | **perguntar** — qual campo manda? E o que fazer com os hashes Django na migração (forçar reset?) |

| D-45 | `update_values` **sobrescreve o próprio estado**: a linha que calcula `INCONSISTENT` é anulada pela linha seguinte. O estado "Inconsistente" só existe no instante da criação — o scope, o filtro da tela e a coluna "Estado" nunca mais o mostram | `app/models/renegotiation.rb:122-123` | O alerta de inconsistência da renegociação **não funciona**. A consistência real só sobrevive em `installment_status` (igualdade exata `installments_main_value_with_interest == total_debt`) | **corrigir** — a intenção do código é inequívoca |
| D-46 | `calculate_current_value` (VP de anuidade) **reatribui `current_installment_value = vp.round(2)`**, e é chamado depois de `current_installment_value` já ter sido calculado → a coluna "Valor Parcela" passa a conter o **VP** sempre que há juros > 0 e saldo > 0 | `app/models/renegotiation.rb:175-183` | O número que o usuário lê como "valor da parcela" é outra coisa | **perguntar** — é dinheiro exibido ao cliente; precisa de reconciliação antes de mudar |
| D-47 | `correct_value = total_debt` sempre; `interest_rate_correction` e `grace_period` **nunca são lidos** → **não existe correção monetária nem carência de fato**, apenas campos de cadastro | `app/models/renegotiation.rb` | A tela promete correção e carência; o sistema não aplica nenhuma das duas | **perguntar** — implementar de verdade no ai9 ou remover os campos da UI? Muda valor financeiro |
| D-48 | `geral_update_values` monta um hash de 7 valores formatados e **o descarta**, respondendo `@renegotiation.to_json` cru. Não recalcula nada — só lê o que o último `update_values!` (ou o cron diário) persistiu | `app/controllers/pub/renegotiations_controller.rb:60-81` | O endpoint "atualizar valores gerais" não atualiza valor nenhum | **corrigir** — implementar o recálculo que o código claramente pretendia |
| D-49 | Filtro `state=empty` **aborta a action com 500** | `app/controllers/pub/renegotiations_controller.rb` (search) | Erro ao usar um filtro da própria tela | **corrigir** |
| D-50 | Limites de anexo (4 arquivos / 5 MB, de `SFG::Metadata`) **só existem no JavaScript**, e a checagem de quantidade está quebrada por seletor errado (`.lesson_attachment_content_wrapper` — nome de outro produto) | view de anexos de renegociação | Servidor aceita qualquer quantidade e tamanho de arquivo | **corrigir** — validação no servidor (mesma classe do D-10) |
| D-51 | Remoção em lote parcialmente aplicada é reportada ao usuário como **falha total** | `renegotiations_controller.rb` (`batch_destroy_installments`) | Usuário reexecuta e apaga a mais | **corrigir** |
| D-52 | Sem validação para: pagamento **maior que a parcela**, mora **negativa**, e `renegotiation_id` do pagamento **divergente** do da parcela | `app/models/renegotiation_payment.rb` | Pagamento pode ser lançado na renegociação errada; saldo negativo | **corrigir** |
| D-53 | A aba PAGAMENTOS está **comentada** na view — é a causa do painel de pagamento não fechar após salvar | view de renegociações (aba de pagamentos) | Bug de UX visível em produção | **corrigir** |
| D-54 | O cron diário `CRONFacade.update_renegotiations_counters` existe **só** para reprocessar `overdue_installments` | `lib/cron_facade.rb`, `config/schedule.prod.rb` | Contador de parcelas vencidas fica até 24 h desatualizado | **corrigir** — no ai9 vira cálculo em consulta (ou Sidekiq + Cable), não varredura diária de tabela inteira |

| D-55 | **O motor de temas não pinta nada.** `app/frontend/css/pub/templates/app_theme_template.css` está 100% dentro de blocos `/* */` — o `cached_css` injetado em `<style>` (console, sign_in, sign_up, reset) é só comentário | `app/frontend/css/pub/templates/app_theme_template.css`; `app/models/app_theme.rb` | Em cascata: `override_css` é salvo e nunca renderizado; `font_name`/`bar_font_name` e todo o `login_bkg_*` são inertes. O tema **de fato** só controla os logos da barra/login e o branding dos 3 e-mails transacionais | **corrigir** — no ai9 o tema é real (tokens CSS light+dark). Ver nota de escopo abaixo |
| D-56 | **Upload com detecção de spoofing desativada**: `Paperclip::MediaTypeSpoofDetector#spoofed?` sobrescrito para sempre retornar `false`, com upload indo para `public/system/` (servido publicamente) | initializer do Paperclip | Qualquer arquivo pode se passar por imagem e ficar acessível publicamente — inclui execução se o servidor interpretar o tipo | **corrigir** — obrigatório. Validação real de tipo + storage privado com URL assinada |
| D-57 | **5 controllers sem autenticação**: nenhum dos controllers de temas e dos 4 de help sobrescreve `requires_current_user?` → respondem sem sessão (só CSRF protege). Inclui `POST /app_themes/:id/active` e `DELETE /app_themes/:id` | `pub/app_themes_controller.rb`, `pub/help*_controller.rb` | Deleção e ativação de tema sem login | **corrigir** |
| D-58 | **Busca de ajuda cega para o conteúdo atual**: `HelpItem` tem `has_rich_text :description` **e** a coluna legada `help_items.description`. A associação sobrescreve o leitor, a coluna nunca mais é escrita, mas as duas buscas fazem `WHERE help_items.description ILIKE …` na **coluna** | `app/models/help_item.rb`; `pub/help_items_controller.rb` (`search_faq`, `search`) | **Nada criado depois de 04/2019 é encontrado por busca de conteúdo.** Bônus: a validação `presence` do rich text nunca falha → itens de ajuda vazios são aceitos | **corrigir** — busca no conteúdo real. Na migração de dados, decidir o que fazer com a coluna órfã |
| D-59 | `active`/`default!` sem transação e olhando só `GlobalTheme` → pode gerar **dois temas padrão ou nenhum**. Excluir tema em uso órfã `livetat_auth_users.app_theme_id` e quebra o console | `app/models/app_theme.rb` | Console quebrado para os usuários que apontavam para o tema excluído | **corrigir** |
| D-60 | `:id` está no `permit` de `app_theme_params` (mass assignment do próprio id) | `pub/app_themes_controller.rb` | Sobrescrita de registro por id forjado | **corrigir** |
| D-61 | Editar tema pode estar quebrado por dois caminhos: `update_attributes` (removido no Rails 6.1) no `update`, e um save flutuante que faz `POST /app_themes/{id}` (rota inexistente) com a chave malformada `app_theme[app_theme[login_bkg_style]]` | `pub/app_themes_controller.rb` + view de temas | Tela de tema não salva | **corrigir** (mesma família do D-43) |
| D-62 | `Pub::HelpController` inteiro **não tem rota nem templates**; as actions `#index` dos 3 CRUDs de help e `index`/`show`/`new`/`edit` de temas apontam para templates inexistentes ou locals errados → **500** | `pub/help_controller.rb`, `pub/help_*_controller.rb`, `pub/app_themes_controller.rb` | Telas que dão erro ao abrir | **corrigir** o que é feature real; **descartar** o que é rota morta, com evidência |
| D-63 | `/u/console/themes` pode estar **inalcançável em produção**: `themes` não tem `when` no `fetch_resource` e o `else` reescreve `@resource[:id] = "dash"`; não há item de menu apontando para lá | `pub/console_controller.rb` (`fetch_resource`) | A tela de temas talvez nunca abra hoje | **perguntar** — precisa de verificação em runtime no ambiente real |
| D-64 | **O fluxo de aceite de contrato esta morto em producao, por 3 motivos independentes**: o bloqueio de acesso esta comentado (`pub_application_controller.rb:55-63`), os dois botoes "ACEITAR" estao comentados nas views, e `is_pending` explode porque `has_many :contracts, through: :contract_deals, source: :contract_deal` e associacao invalida (`user_decorator.rb:40`) -> `/contract/:type` da **500** para usuario logado. O aceite real e **implicito e automatico** no `after_create :create_contracts`; os checkboxes de sign-up e Minha Conta nao sao lidos por controller nenhum | `pub_application_controller.rb:55-63`; `contracts/header/_toolbar_body.html.erb:18-25`; `header/_body.html.erb:24-48`; `user_decorator.rb:40` | **Consequencia juridica**: o sistema registra aceite de contrato que o usuario nunca deu conscientemente | **perguntar** — e decisao de produto **e juridica**, nao tecnica. Reativar o bloqueio + aceite explicito, ou assumir o aceite implicito? |
| D-65 | `contract_deals` **nao guarda IP, user-agent nem snapshot do texto** aceito | `app/models/contract_deal.rb` | Aceite sem prova do que foi aceito e de onde | **perguntar** — decisao juridica. Recomendo registrar os tres no ai9 |
| D-66 | Excluir um indicador **apaga toda a serie historica**: `has_many :entries, dependent: :delete_all` (`indicator.rb:4`). A confirmacao da UI so diz "A operacao nao pode ser desfeita", sem mencionar os lancamentos; na tela de indicadores especificos a exclusao **nem tem confirmacao** | `app/models/indicator.rb:4` | Perda irreversivel de historico com um clique | **corrigir** — soft delete + confirmacao que diz o que sera perdido |
| D-67 | `constantize` de **input do usuario** | ver `inventory/indicators-contracts.md` | Instanciacao de classe arbitraria a partir de parametro — caminho para execucao de codigo | **corrigir** — obrigatorio. Allowlist, nunca `constantize` de input |
| D-68 | `user_id` e `id` no `permit` de entries e deals (mass assignment) | controllers de indicator_entries e contract_deals | Atribuir lancamento a outro usuario / sobrescrever registro por id forjado | **corrigir** (mesma familia do D-60) |
| D-69 | `redirect_url` **sem allowlist**, interpolado direto no JS | fluxo de contratos (`/contract/:type/:acceptable/:redirect_url`) | Open redirect + injecao de script | **corrigir** — obrigatorio |
| D-70 | `indicator_entries` denormaliza `title`/`key`/`value_type`, e o `update_all` **reescreve o historico** ao editar o indicador | `app/models/indicator.rb`, `indicator_entry.rb` | Lancamento antigo passa a mentir sobre como era o indicador na epoca | **perguntar** — a denormalizacao e intencional (foto do momento) ou e bug? Mesma pergunta do D-30 |
| D-71 | `indicator.key` ("Chave de Integracao") **nao tem nenhum consumidor no repositorio** | `app/models/indicator.rb` | Campo possivelmente morto — ou usado por integracao externa | **perguntar** — existe consumidor externo? |
| D-72 | **A formula de remuneracao e percentual flat, sem prazo e sem arredondamento explicito**: `value = operation_value * (fee/100.0)` (`receipt.rb:63`). Nem `agreed_rate`, nem `issue_date`/`due_date`, nem `balance` entram no calculo. O arredondamento e acidental (cast `float` -> `decimal(15,2)`). **Zero testes cobrem isso** | `app/models/receipt.rb:63` | A remuneracao pode nao ser o que o negocio pensa que e | **perguntar** — confirmar a formula pretendida com o usuario antes de reimplementar. E dinheiro |
| D-73 | **`balance` e resetado em todo save e nunca e movimentado**: `before_validation` sem `on:` forca `original_balance = -abs(valor)` e `balance = original_balance` a cada update. Nao existe, em lugar nenhum do legado, codigo que de baixa no saldo | `app/models/structured_operation.rb:37-38` | Ou falta uma funcionalidade inteira (baixa de saldo), ou a coluna e decorativa | **perguntar** — feature faltando ou coluna morta? Muda o escopo da migracao |
| D-74 | `is_on_variable` e `agreed_rate` **sem nenhum consumidor**; remuneracao apagada gera **recibos orfaos**; `resource_kinds` e `resource_sources` tem o mesmo rotulo na UI ("Tipos de Recursos"); `receivable_entries.resource_kind_id` nunca e preenchido | ver `inventory/structured-operations.md` | Campos e telas que nao fazem nada; dado orfao | **perguntar** por item na consolidacao |
| D-75 | Filtro de periodo com **semantica invertida**: `due_date >= from AND issue_date <= to` | controller de structured_operations | Resultado de busca nao e o que o usuario pede | **corrigir** |
| D-76 | Leitura e **escrita** cross-project via `structured_operation_id` sem escopo | controller de structured_operations | Mesma familia do D-01/D-16/D-29 — mas aqui tambem **escrita** | **corrigir** — obrigatorio |
| D-77 | `structured_operation_taxes` e **rota orfa comprovada**: as 2 unicas ocorrencias no repositorio sao as proprias linhas `routes.rb:107-108`. Alem disso 5 actions `index` e 3 `show` renderizam templates inexistentes, e `structured_operations#new/#edit` referenciam ivars que o controller nao define (`@first_company`, `@structured_operation_types`) — o fluxo real passa por `console_controller.rb:206-231` | `config/routes.rb:107-108`; controllers de structured_operations | Rotas que dao 500 ou nao fazem nada | **descartar** as comprovadamente orfas (com evidencia no ledger); **corrigir** as que sao feature real |
| D-78 | **Quase todo e-mail do sistema se perde em deploy/restart.** `smtp_settings.delivering` recebe a String `"async"` e e comparada com o Symbol `:async` -> o ramo `.delay` **nunca roda**; todos os e-mails de `mailer19`/`feedback19` saem por `deliver_later` no adapter in-process. So os 3 do `NotificationFacade` sao duraveis | config de `smtp_settings` + engines `mailer19`/`feedback19` | E-mail transacional perdido silenciosamente a cada restart do servidor | **corrigir** — no ai9 todo e-mail vai por Sidekiq com retry |
| D-79 | **Todos os jobs fazem `rescue => e` interno e nao relancam**: o delayed_job marca sucesso e **nunca retenta**. `InsertProjectsOnDefaultUserJob` tem `rescue` **vazio** (falha sem log e sem Tracking) | `lib/*_job.rb` | Job que falha some sem deixar rastro; ninguem descobre | **corrigir** — generaliza o D-05. Sidekiq com retry e falha visivel |
| D-80 | `projects.job_id` e `project_availability_templates.job_id` sao **FK para a tabela `delayed_jobs`** | migrations de `projects` e `project_availability_templates` | Acoplamento que **nao sobrevive ao Sidekiq**; e se o worker nao roda, itens ficam `locked` para sempre | **corrigir** — decisao de modelagem para o Phase 2: estado de processamento na propria entidade, nao FK para a fila |
| D-81 | Convite por e-mail **quebrado**: chamado com 4 argumentos, exige 5 | ver `inventory/jobs-integrations.md` (BE-485) | Convite nunca e enviado | **corrigir** |
| D-82 | Anexos: `do_not_validate_attachment_file_type`, limites so em JavaScript, spoof detector monkey-patchado para `false`, e arquivos servidos de `public/` **sem autenticacao** | initializer do Paperclip; views de anexo | Generaliza D-50 e D-56: qualquer arquivo, de qualquer tipo, publicamente acessivel por quem descobrir a URL. **Inclui anexos de renegociacao — documento financeiro de cliente** | **corrigir** — obrigatorio. Storage privado + URL assinada + validacao de tipo no servidor |
| D-83 | **Geocoder sincrono no `before_save`** com `timeout: 12000` (~3h20) e **sem cache** | config do Geocoder + models com geocoding | Um save pode travar a request por horas se o servico externo pendurar | **corrigir** — geocoding assincrono, com timeout de segundos e cache |
| D-84 | `wicked_pdf`/`wkhtmltopdf` declarados no Gemfile mas **zero PDFs sao gerados** no legado | `Gemfile.linux` | A gem esta la, a feature nao existe | **perguntar** — geracao de PDF (recibo/relatorio) e esperada e nunca foi feita, ou a gem e residuo? Muda o escopo |
| D-85 | **Segredos commitados**: chave privada DKIM, senha SMTP e token da ReceitaWS no repositorio; alem de `VERIFY_NONE` na conexao | config/initializers e credentials do legado | Vazamento de credencial (mesma familia do achado da Google Maps key) + TLS sem verificacao | **corrigir** no ai9 (tudo em ENV/credentials) **e** acao externa do usuario: **rotacionar os tres segredos** |
| D-86 | **Polling** (proibido no ai9): `PollingManager` (`polling_helper.js:47`, 5 s); monitor de usuario de 1 s (`_widget.js.erb:7-16`, ja desativado no legado); progresso de job (`live_progress_percent`, hoje so atualiza com recarga manual) | `polling_helper.js:47`; `_widget.js.erb:7-16` | Mandato do skill: nada de polling no app migrado | **corrigir** — os tres viram Action Cable no ai9. O resto dos `setInterval` e jQuery Mobile de terceiros, nao e polling de dados |
| D-87 | **Nao existe dashboard.** `dash` e so um redirecionador por papel (`og?`->users, admin/manager->projects ou receivables, demais->my_account ou results). `DashController#index/#show/#search` estao **todos quebrados** por template ausente | `parts/dash/_body.js.erb:8-24`; `pub/dash_controller.rb` | Nao ha widget, periodo, filtro nem agregacao | **perguntar** — dashboard no ai9 e **feature nova, sem paridade**. Precisa de definicao de escopo com o usuario, senao vira invencao |
| D-88 | **Secao "Mensagens"/observers e orfa E insegura**: sem item de menu, `admin_messages` nao esta no `case` de titulos e e rebaixado para `dash`, `#index` nao tem rota nem view. Pior: `dash`, `admin_messages` e `console_observers` herdam `requires_current_user? == false` -> `search_console_observers` lista **todos os e-mails de observers, sem paginacao e sem checagem de papel, para anonimos** | `console_controller.rb:402-405`; `pub/console_observers_controller.rb` | **Vazamento de base de e-mails sem autenticacao.** Mesma familia do D-57 | **corrigir** — obrigatorio |
| D-89 | `current_user.viewing` (`console_controller.rb:15`) **nao existe** -> qualquer UUID no `:topic` da **500** | `pub/console_controller.rb:15` | Erro em caminho de navegacao normal | **corrigir** |
| D-90 | O flag `locked` do menu le `g[:locked]` (do **grupo**) mas e setado nos **itens** -> availability, charges, project_availabilities e availability_templates estao **destravados** | montagem do menu (navkit / console) | **REAVALIADO 24/08 (DEC-15.1): o usuario confirmou que essas telas estao VIVAS em producao.** O 'bug' produz o comportamento correto — as telas devem mesmo estar acessiveis | **preservar o efeito, corrigir o mecanismo**: no ai9 o `locked` passa a ser lido do item (correto), mas **nenhum dos 4 nasce marcado**. Producao e a verdade, nao a intencao aparente do codigo |
| D-91 | `@total_count` de admin_messages **ignora os filtros**; `openEdit` grava `companyId` mas o proxy le `observerId`; `update_attributes` (removido no Rails 6.1) na edicao de observer; ordenacao por nome em vez de data; `default_topic` nunca consumido | `pub/admin_messages_controller.rb`, `pub/console_observers_controller.rb` e views | Contagem errada, edicao quebrada | **corrigir** |
| D-92 | **Estado de navegacao inteiramente em memoria JS**: `dashHolder.getData().resourceId/resourceTopic/resourceSection` e a unica fonte de verdade; a URL e so espelhada por `window.history.replaceState` (nunca `pushState`) -> o botao **Voltar sai do console**. O unico estado persistido e o cookie `cached_info` | views do console + helpers JS | Sem deep-link, sem historico, sem compartilhar URL de tela | **corrigir** — o ai9 usa roteador real com histórico e deep-link por area. **Nao** reproduzir o esquema `resource/topic/section` |
| D-93 | **O sinal da exposicao ao risco e contraditorio.** `original_balance` e forcado a negativo (`risk_operation.rb:34`), debitos somam e creditos subtraem (`risk_movement_type.rb:53-61`), e ainda assim `limite_utilizado_on` multiplica a soma dos saldos por **-1** (`risk_control.rb:123`). Nas duas leituras possiveis a utilizacao sai invertida | `risk_operation.rb:34`; `risk_movement_type.rb:53-61`; `risk_control.rb:123` | Contamina **limite disponivel, percentual de utilizacao e o alerta vermelho** — o painel de risco pode estar mostrando o oposto da realidade. E o nucleo do produto | **perguntar** — BLOQUEADOR. Nada disso pode ser portado antes de o negocio confirmar a convencao de sinal |
| D-94 | **O ciclo de vida da operacao de risco e decorativo.** `is_ended` nao bloqueia movimento, nao bloqueia prorrogacao e nao retira a operacao da janela de exposicao (`risk_control.rb:76-79`); **renovar nao encerra a original** (`risk_operation.rb:113-139`), entao as duas consomem limite simultaneamente; prorrogar aceita data retroativa e operacao ja encerrada (`risk_operation_extension.rb:8-11`). Nao existe maquina de estados | `risk_control.rb:76-79`; `risk_operation.rb:113-139`; `risk_operation_extension.rb:8-11` | Limite de credito consumido em dobro na renovacao; operacao encerrada continua movimentando | ~~**corrigir** — maquina de estados real no ai9. A renovacao em dobro e erro de exposicao financeira, nao comportamento a preservar~~ **REVOGADO pela DEC-35 (25/08/2026): REPLICAR.** Ver a nota abaixo |

> ### D-94 — o veredito acima foi REVOGADO pela DEC-35. Leia antes de "corrigir"
>
> **A DEC-35 (25/08/2026) manda REPLICAR o ciclo de vida.** O orquestrador levantou
> a objecao antes de perguntar — apresentou este mesmo veredito ("corrigir — a
> renovacao em dobro e erro de exposicao financeira") — e o usuario **reafirmou
> replicar**. Vale o DEC-30.
>
> **O que a S7 entregou, em consequencia:**
>
> - **renovar NAO encerra a original.** As duas ficam vivas e as duas consomem
>   limite ao mesmo tempo. `Risk::RenewalService#create` nao toca em `is_ended`, e
>   ha golden travando os dois lados
>   (`spec/services/risk/renewal_and_extension_spec.rb`);
> - **`is_ended` continua rotulo**: nao bloqueia movimento, nao bloqueia
>   prorrogacao e **nao** retira a operacao de `operations_on`. As tres
>   nao-consequencias tem teste proprio (`spec/models/risk_operation_spec.rb`);
> - a operacao encerrada continua **faturavel** (`available_for_receipt`).
>
> **A unica metade do D-94 que FOI corrigida** e a que a propria DEC-35 nao
> alcanca, porque nao e ciclo de vida: **prorrogar deixou de aceitar data
> retroativa**. No legado so o `minDate` do datepicker impedia, e por requisicao
> direta dava para **encurtar** o vencimento, jogando movimentos legitimos para
> fora da janela de `BE-274`. Agora ha validacao de servidor e `CHECK` no banco
> (`BE-277`). Isso nao contraria a DEC-35: nao preserva numero nenhum: impede
> gravar registro incoerente do zero.
>
> **O `tasks.md` e o `proposal.md` da S7 (Phase 2) pediam o contrario** (IMP-R1:
> "renovar encerra a original"). Foram escritos ANTES da DEC-35 e estao riscados
> la, com o numero da DEC que os anulou. A propria DEC diz: *"um teste que exija
> encerramento automatico esta errado contra esta DEC."*
>
> **QA do Phase 4: a exposicao contada em dobro na renovacao NAO e regressao.**
| D-95 | Colunas "Liquidavel"/"Pre" exibem o **utilizado** (`company.rb:158,161`), e `liq`/`pre` do payload de totais devolvem **percentuais** (`company.rb:79-82`) | `app/models/company.rb:79-82,158,161` | Numero na tela nao e o que o rotulo diz | **perguntar** — confirmar qual e o numero pretendido |
| D-96 | "Vencido" e **flag manual**, nao derivado da data | models de risco | Operacao vencida so aparece como vencida se alguem marcar | **perguntar** — derivar da data no ai9? Muda o que o painel mostra |
| D-97 | `on_duplicate_key_update: [:date, movement_value]` sem simbolo em `movement_value` -> **`NameError` ao editar movimento com par duplicado** | `app/models/risk_movement.rb:40` | Erro 500 em operacao normal | **corrigir** |
| D-98 | `destroy` de operacao de risco responde **sempre 200 com toast de sucesso**, mesmo quando barrado por recibo vinculado; e `@total_count` e calculado **depois** do `limit` (paginacao errada) | controllers de risco | Usuario acha que excluiu e nao excluiu (mesma familia do D-24) | **corrigir** |
| D-99 | **Toda a arvore de views de `RiskEntry` foi removida** — os 9 endpoints estouram `MissingTemplate`; e todas as actions REST `index`/`show` dos 6 controllers de risco renderizam templates inexistentes. So a navegacao via `pub/console` funciona | views de `pub/console/parts/risk_*` | Endpoints que so dao erro | **perguntar** — `RiskEntry` e feature a recuperar ou a descartar? A tabela existe e tem dado |
| D-100 | `risk_operations#search` **vaza o escopo de projeto** quando vem `risk_operation_id` | controller de risk_operations | Mesma familia do D-01/D-16/D-29/D-76 | **corrigir** |
| D-101 | A paleta `accent_indicator_positive`/`negative` (#217B55/#7D1F1E) esta definida em `colors.scss:15-16` mas **nao e usada em nenhuma tela de risco** — o modulo pinta com #31D86C/#F8333C | `app/frontend/css/pub/colors.scss:15-16` | Duas paletas de semaforo concorrentes | **corrigir** — um par so de tokens semanticos (positivo/negativo) no ai9, em light e dark |
| D-102 | **Timestamps gravados em horario de Brasilia, nao UTC**: `config/application.rb:28-29` usa `default_timezone = :local`. E o offset **nao e constante** — houve horario de verao ate 2019 | `config/application.rb:28-29` | Ler esses dados no Rails 8 (que usa `:utc`) **desloca todo o historico, e por quantidades diferentes conforme a epoca**. Atinge vencimento de parcela, data de operacao, tudo | **corrigir** — conversao explicita por faixa de data no ETL, com tabela de DST. Nao e um `AT TIME ZONE` unico |
| D-103 | **Zero foreign keys no banco**: existe exatamente **uma** em todo o schema (`active_storage_attachments.blob_id`). As ~40 FKs sao so de aplicacao, e **nenhuma** das 20+ unicidades compostas tem indice unico | as 139 migrations | Somado ao salto de PK `integer` -> `uuid` do ai9 (34 das 96 tabelas), o ETL **religa registros errados em silencio** se nao houver tabela de correspondencia. Orfaos e duplicatas em producao sao provaveis | **corrigir** — obrigatorio: tabela de-para `legacy_id -> uuid` no ETL, e contagem de orfaos/duplicatas **antes** do Phase 3. Generaliza D-12 |
| D-104 | **Dinheiro calculado com `float`**: `remunerations.value` e `receipts.fee` sao float multiplicando `decimal(15,2)` para produzir o valor faturado; mais ~30 floats de taxa em `receivable_entries` | migrations de `remunerations`, `receipts`, `receivable_entries` | Se o ai9 recalcular com `BigDecimal`, **os totais nao batem no Phase 4** — e vira caca a um "bug" que na verdade e a correcao. Generaliza D-13 | **perguntar** — BLOQUEADOR de paridade. Precisa de decisao explicita: replicar o erro do float para bater numero, ou corrigir e aceitar divergencia documentada? |
| D-105 | `app/models/legacy/` **nao e dado do Safegold**: e um **ETL de mao unica ja executado em 2021** que trouxe o sistema **Django/Python** anterior. Sao 11 models-espelho com `establish_connection :sfg_legacy` apontando para o banco `SG20210329`, cada um com `Adapter.adapt` gravando no model novo com `legacy_id`, mais 4 interceptors de correcao. O dump `db/seed_assets/sfg_legacy_full.sql` (9 MB) esta commitado | `app/models/legacy.rb`, `app/models/legacy/**`, `db/seed_assets/sfg_legacy_full.sql` | Migrar isso seria portar um ETL morto | **descartar** o codigo, a conexao e o dump. **MAS preservar as colunas `legacy_*`** — sao a unica prova de proveniencia dos borderos de 2016-2021 |
| D-106 | `legacy_password` guarda **hash Django** em coluna propria (ver D-44) | schema de usuario | Dado sensivel parado no banco, de um sistema que nao existe mais | **perguntar** — pode dropar na migracao? Se algum usuario ainda depende dele para logar, precisa de reset forcado antes |
| D-107 | **Nao esta claro qual e o banco de producao**: `config/database.centos.yml` diz **PostgreSQL** e `config/database.linux.yml` diz **mysql2** — e ambos tem **senha em texto puro commitada** | `config/database.centos.yml`, `config/database.linux.yml` | O ETL e escrito diferente para cada um; e sao mais segredos vazados (familia D-85) | **perguntar** — qual e a producao real? E **rotacionar** as senhas commitadas |
| D-108 | `contracts.description` e gravada pelo seed mas **nenhuma migration a cria** | `db/seeds.rb` vs `db/migrate/**` | **E a evidencia mais forte de que existe schema fora das migrations** (junto com `default_position` do D-06) | **corrigir** via `pg_dump` — reforca o bloqueador ja registrado |
| D-109 | **Senha deterministica na importacao de usuarios**: `"<primeironome>#6230"` | `app/models/legacy/u.rb:28` | Todo usuario importado do Django tem senha **adivinhavel a partir do nome**. Se algum nunca trocou, a conta esta aberta. Combinado com D-39 (cadastro publico cria Admin) e D-34 (escalacao), o comprometimento e trivial | **corrigir** — obrigatorio. Na migracao: forcar reset de senha para todo usuario com `legacy_password` ou senha nunca trocada |
| D-110 | `GET /api/v1/trackings` parte de `Tracking.all` **sem escopo algum** | `app/controllers/api/v1/trackings_controller.rb` | Toda a base de rastreamento exposta (familia D-01/D-88) | **corrigir** |
| D-111 | `UriValidator` faz **GET na URL fornecida pelo usuario** | `app/validators/uri_validator.rb` | **SSRF**: o servidor pode ser usado para varrer a rede interna ou atingir metadata de cloud | **corrigir** — obrigatorio. Validar formato, nunca buscar a URL |
| D-112 | `smtp_settings_port` existe no yml e e lida pelo engine, mas `application.rb` **nunca a atribui** -> **SMTP sem porta** | `config/application.rb` vs `config/application.*.yml` | Reforca o D-78: o envio de e-mail esta mal configurado por dois caminhos independentes | **corrigir** |
| D-113 | **Producao roda Ruby 2.6.1 / Rails 6.0.3.2**, enquanto o dev roda 3.0.2 / 6.1.4 | `Gemfile.prod` vs `Gemfile.linux` | O que foi inventariado a partir do codigo pode nao ser o que roda em producao. Alguns defeitos (ex.: `update_attributes`, removido no 6.1) **so quebram no dev** — em producao funcionam | **perguntar** — CRITICO para a paridade: qual versao e a verdade? Muda o veredito de varios defeitos (D-43, D-61, D-91) |
| D-114 | **O legado nao tem nenhum teste** | repositorio inteiro | Nao ha rede de seguranca nem especificacao executavel do comportamento atual | **corrigir** — os testes de caracterizacao do ai9 passam a ser a primeira especificacao executavel que o Safegold tem |
| D-115 | **0 de 717 views usam `t()`** — UI 100% pt-BR hardcoded | `app/views/**` | Sem i18n. Nao e defeito se o produto e so pt-BR | **perguntar** — o ai9 deve nascer com i18n (custo baixo agora, alto depois) ou seguir pt-BR fixo? |
| D-116 | **4 gems declaradas e nunca usadas**: `extensobr`, `deep_cloneable`, `activerecord-import`, `apipie-rails` | `Gemfile.linux` | Consequencia importante: `apipie-rails` sem uso significa que **nao existe documentacao de API publicada** no legado | **descartar** as gems. A doc de API vira entregavel novo no ai9 (Grape + Swagger ja existe na base) |
| D-117 | Helpers com regra de negocio escondida: `format_money:11` renderiza vazio/nil como **R$ 0,00** (esconde dado faltante); `days_js_array:90` emite **%m/%d/%Y americano** na fronteira com o datepicker enquanto a UI e dd/mm; `slice_in:76` distribui round-robin e nao sequencial; `pluralize_for` gera "messs"; `week_days` gera "Segunda-feira-feira"; `tracking_color/icon` recebem o evento e o **ignoram** | `app/helpers/application_helper.rb:11,15,76,90` e adjacentes | `format_money` e o mais serio: **campo nulo e campo zerado ficam indistinguiveis** num sistema financeiro | **corrigir** — `format_money` distingue nulo de zero no ai9; os bugs de formatacao/pluralizacao viram implementacao correta |
| D-118 | `create_console_menu:100-172` **e a especificacao de fato da navegacao**: 6 grupos com gate por projeto (`projects.count > 0`), por papel (`og?/admin?/manager?`), por permissao (`may?("user_is_readonly")`) e **4 itens com `locked: true`** | `app/helpers/application_helper.rb:100-172` | Nao e defeito — e **o documento de requisitos da navegacao**, escondido num helper. O `navkit` nao manda; este helper manda | **preservar** (a regra), **corrigir** (o lugar): no ai9 vira configuracao de rotas + permissoes declarativa. Combina com D-90 (o `locked` esta quebrado) |
| D-119 | Chaves de config mortas: `paperclip_path` (zero leituras), `REDIS_URL` (ActionCable nao e carregado), `RAILS_SERVE_STATIC_FILES` (forcado) | `config/application.*.yml` | Config que engana quem le | **descartar** |
| D-120 | **A engine `navkit` esta morta E nao e a navegacao do console.** Tres provas de que nao carrega: falta `lib/livetat_navkit.rb` (o `Bundler.require` engole o LoadError), ela faz `require "livetat_ux_kit"` que nao existe, e o pack `site_gems` so e usado pelo layout `site.html.erb`, que nenhum controller carrega. Alem disso ela e um kit de navegacao **matricial** (grade MxN, swipe, sem permissao por item) para sites institucionais — e os itens configurados no SFG sao **de um site de colegio** | `engines/navkit/**`; `Gemfile.linux` | Confirma o **D-118**: a navegacao real do console vem de `application_helper.rb:100-172` (`create_console_menu`), renderizada em `console/base/menu/_container.html.erb` com estado ativo por `data-url` em `js/simple_menu.js` | **descartar** a engine inteira. A navegacao do ai9 se baseia no `create_console_menu`, nao no navkit |
| D-121 | **Todos os overrides `deface` estao inertes** — apontam para a engine `materialize_wrapper19`, que nao existe no projeto | `app/overrides/**` (ou equivalente) + `Gemfile.linux` | Customizacoes de view que o time acha que estao ativas e nao estao | **descartar** — mas conferir se alguma delas descreve comportamento pretendido que se perdeu |
| D-122 | **Sprockets desligado torna todo o `app/assets` das engines morto** | config de assets + engines | Assets das engines nunca sao servidos | **descartar** |
| D-123 | Tela de "link expirado" quebrada | `auth_ux19` | Usuario com link vencido cai num erro em vez da mensagem (agrava o D-37, em que o token nunca expira) | **corrigir** |
| D-124 | Metodo com **nome ofensivo** no codigo | `registrations_controller.rb:113,189` | Nao e defeito funcional, mas nao se leva para a base nova | **corrigir** — renomear na migracao (o ai9 usa identificadores em ingles, descritivos) |
| D-125 | `ux_kit19` esta **parcialmente viva**: o JS/SCSS via webpack e `DateTime.dinosaurs`/`.mars` sao usados em 4 controllers, mas o helper Ruby e os widgets ERB estao **mortos e duplicados no app** | `engines/ux_kit19/**` | Codigo duplicado com duas fontes de verdade | **descartar** a parte morta; portar os componentes vivos para a biblioteca de componentes do ai9 |
| D-126 | **`ORDER BY default_position` derruba a listagem de padrões de disponibilidade — em produção, há anos.** A coluna não existe no banco (medido no dump de 26/08/2026: zero ocorrências, nenhuma migration a cria) e o legado a usa **como coluna SQL**: `order!(default_position: :asc)` emite `ORDER BY default_position ASC` e o Postgres levanta `UndefinedColumn`. Mais duas views chamam `at.default_position` **como método**, e **não há método no model** | `app/controllers/pub/availability_templates_controller.rb:22`; `app/views/pub/console/parts/availability_templates/list/_child_widget.html.erb:40` (+2 views) | A tela só parava de atualizar, sem mensagem. É a resposta do **D-06** | **corrigir** — é uma das exceções previstas no DEC-30 ("não há legado a replicar"): não existe comportamento validado a preservar, existe erro. A S11 ordena pela **hierarquia** (`sort_key`); a coluna `default_position` existe no ai9 por DEC-79 e o ETL a carrega se aparecer, mas **não ordena nada**. ⚠ **O número 126 é deliberado**: `analise-dump-producao.md` batizou este defeito de "D-125", mas o D-125 acima já existia (o `ux_kit19`). Colisão desfeita em 26/08/2026 — o D-125 do `ux_kit19` não foi tocado |

## Bloqueadores de dados a resolver antes do Phase 3
**Não existe `db/schema.rb` nem `db/structure.sql` versionado no legado.** O DDL real
precisa ser extraído do banco de produção (`pg_dump --schema-only`) antes de escrever
a migração de dados — reconstruir o esquema só a partir das 104 migrations é
arriscado (ver D-06: há coluna em uso que nenhuma migration cria). Isso é uma
dependência externa: **precisa do usuário**.

**Dump de `livetat_auth_role_types` (nomes + `hierarchy`).** Sem os RoleTypes reais
(principalmente o "Gerente") não dá para reproduzir o corte de hierarquia do login
nem o `role_types_for_filter`. O `db/seeds.rb` não serve como fonte — ele destrói os
tipos que a configuração referencia (D-36). **Precisa do usuário.**

**Volumetria do dominio de risco.** O dump `db/seed_assets/sfg_legacy_full.sql` e do
sistema **Django anterior** e nao contem tabelas `risk_*` — nao ha como estimar volume
sem o banco real. Reforca o pedido de `pg_dump` ja registrado acima.

**Qual e a versao de producao (D-113).** `Gemfile.prod` aponta Ruby 2.6.1 / Rails
6.0.3.2; `Gemfile.linux` (dev) aponta 3.0.2 / 6.1.4. **Todo o inventario foi feito
lendo o codigo**, entao alguns defeitos catalogados podem nao existir na producao
real (e vice-versa). Isto precisa de confirmacao **antes** do Phase 2 fechar o mapa.

**Rotacao de segredos (acao do usuario, fora deste repo).** Estao commitados no
legado: `secret_key_base`, token da ReceitaWS, senha do banco (nos dois
`database.*.yml`), **chave privada DKIM**, senha SMTP e a Google Maps API key. Todos
precisam ser rotacionados independentemente da migracao — o historico do git ja os
expos.

---

## Defeitos achados ao escrever os textos de ajuda (25/08/2026, DEC-88)

Nao estavam catalogados. Apareceram porque alguem teve de **ler formula por formula** para
descrever 91 campos — que e um tipo de varredura que nenhuma passada anterior tinha feito.

### D-121 — `data_credito` em branco impede, em silencio, a criacao da operacao de risco

`receivable_entry.rb:162` passa `due_date: self.data_credito`, e `risk_operation.rb:61` **exige**
`due_date`. Com o campo em branco, o `create` dentro do `after_commit` **falha sem excecao e sem
aviso**: o bordero salva normalmente e a operacao de risco **simplesmente nao existe**.

Familia do **D-11**, caminho diferente: la o valor nasce errado, aqui o **registro nao nasce**. E
pior de detectar, porque nao ha numero divergente para conferir — ha uma ausencia.

**Veredito: corrigir.** Nao cai no DEC-30: nao ha numero a preservar, ha um registro que deveria
existir e nao existe. O ai9 valida a presenca antes e recusa a gravacao com mensagem, em vez de
gravar pela metade. **Tarefa do ETL (S14):** contar quantos borderos historicos ficaram sem
operacao de risco por esta causa e listar.

### D-122 — cinco campos do formulario de recebiveis testam a variavel errada

`receivables/new/_body.html.erb:297,303,312,319,329` fazem
`@receivable.checagem_iof.blank? ? 0 : @receivable.<campo>` para **`recompra`, `retencao`,
`fomento`, `outros` e `total_deducoes`**. Copy-paste do bloco de IOF: os cinco campos testam
`checagem_iof` em vez de si mesmos.

**Efeito:** ao editar um bordero em que a checagem de IOF esta nula, **os cinco aparecem R$ 0,00
mesmo tendo valor gravado**. O dado esta no banco; a tela mente.

**Veredito: corrigir.** Excecao ao DEC-30 pelo mesmo criterio do DEC-70: **nao ha numero a
preservar** — o numero correto ja esta gravado, o defeito e so de exibicao. Replicar seria
esconder dado real de proposito.

### D-123 — duas colunas de taxa sem guarda de divisao por zero

`taxa_desconto_nominal_despesas_iof_bancos` (`receivable_entry.rb:69`) e `_emp` (`:83`) **nao tem
guarda nenhuma**, ao contrario das quatro irmas da mesma familia. Com `vlr_bruto_final` zero,
gravam **`Infinity`** ou **`NaN`** no banco.

E o **D-10** concretizado em duas colunas nomeadas. `Infinity` em coluna numerica contamina
qualquer agregacao que a inclua.

**Veredito: corrigir** (guarda igual a das quatro irmas). Excecao ao DEC-30: `NaN` nao e um numero
a preservar. **Tarefa do ETL:** detectar e reportar linhas historicas com `Infinity`/`NaN` nessas
duas colunas — elas existem no banco de producao se algum bordero foi salvo com bruto zero.

### Correcoes ao material, achadas na mesma varredura

- **`multiplicador_pm_float` multiplica pelo prazo medio do BANCO** (`:105`); o float acordado
  **nao entra na conta**, apesar do nome do campo.
- **A DEC-32 e na variante _sem IOF_**, nao na principal: a guarda assimetrica esta em
  `custo_efetivo_pz_med_banco_sem_iof` (`:74` usa o prazo da empresa; `:78` usa o do banco).
- **`taxa_desconto_nominal_despesas_bancos` (`:68`) e `_emp` (`:82`)** calculam as despesas **sem**
  IOF (`valor_total_tarifas - tarifas_iof`), mas a guarda que anula o campo e `tarifas_iof < 1` —
  **sem IOF lancado, a taxa "sem IOF" sai em branco**, que e o oposto do esperado.
- **23 dos 65 campos de recebiveis nao sao exibidos em tela nenhuma** no legado: sao calculados no
  `before_validation` e gravados. Os textos foram escritos para todos; o tooltip so aparece se o
  campo for exibido no ai9.
- **Duas chaves de YAML nao batem com o campo que o operador ve:** `description` (risco e
  estruturadas) aponta para o campo `observation`, e `balance` aponta para `original_balance`
  ("Saldo Inicial"). Os textos descrevem **o campo visivel**, nao o nome da chave.

## Defeitos achados na S4 (26/08/2026, lendo a fonte antes de escrever)

### D-124 — `projects` tem DUAS colunas de cidade, e o formulário escreve numa enquanto a tela lê a outra

`db/migrate/20210301170412_create_projects.rb` cria **`city`** e **`address_city`**, as duas
`string`, as duas no `permit` (`pub/projects_controller.rb:253-254`), as duas com rótulo de erro
traduzido (`:217` "Cidade" e `:218` "Cidade").

- O **formulário escreve `address_city`**: `projects/new/_body.html.erb:111` tem um único campo de
  cidade, e ele é `f.text_field :address_city`.
- O **endereço formatado lê `city`**: `project.rb:beauty_address` faz
  `has_city = !self.city.blank?` e `text += self.city if has_city`.

**Consequência:** a cidade digitada no cadastro do projeto **nunca aparece** no endereço formatado.
Como as duas colunas existem e as duas são aceitas, um ETL ou um `update` pelo console pode ter
preenchido `city` em parte da base — então o defeito é intermitente por registro, que é a forma
mais difícil de perceber.

`wipe_data` (`project.rb:720-721`) limpa **as duas**, o que confirma que quem escreveu a limpeza
sabia que existiam duas e não resolveu qual valia.

**Veredito: corrigir, com fusão de coluna.** Exceção ao DEC-30 pelo mesmo critério do D-25 (dois
formatos para o mesmo dado): não há regra de negócio a preservar em ter duas cidades. A S4 porta
**uma** coluna, `address_city` (a que o formulário escreve), e `Project#formatted_address` lê dela.
**Tarefa do ETL (S14):** ao carregar, usar `COALESCE(address_city, city)` e **reportar** as linhas
em que as duas estão preenchidas e divergem — essas são decisão humana, não merge automático.

**Achado junto, mesma família:** `beauty_address` também ignora `address_type` ("Rua", "Avenida"),
que o formulário pede e o banco guarda. A S4 o inclui no endereço formatado.

---

## Defeitos achados EXECUTANDO o ETL contra o dump de produção (S14, 26/08/2026)

Os oito abaixo não vieram de leitura de código: vieram de `rake sfg_etl:introspect`,
`sfg_etl:dry_run`, `sfg_etl:attachments` e `sfg_etl:reconcile` rodando contra
`sfg-31-may-25.sql` (782.742 linhas) e `sfg-31-may-25.tar` (467 arquivos), **sem restaurar o
banco e sem extrair o acervo**. Cada número aqui foi medido, não estimado.

### D-127 — 669 das 1.134 participações têm um papel que o próprio model do legado nunca declarou

`Membership` declara quatro papéis (`membership.rb:18-21`): "Responsável", "Participante",
"Coordenador", "Gestor". O que existe em produção:

| valor em `memberships.role` | linhas | está no model? |
| --------------------------- | -----: | -------------- |
| `Participante` | 448 | sim |
| `Responsável` | 17 | sim |
| **`Gerente`** | **655** | **não** |
| **`Colaborador`** | **14** | **não** |

Os 669 fora do vocabulário foram escritos pelo **ETL Django→Rails de 2021**:
`app/models/legacy/membership.rb:17` grava
`role: old_user.is_staff ? ::U.MANAGER : old_user.is_superuser ? ::U.ADMIN : ::U.COLAB` —
isto é, **o papel GLOBAL do usuário no campo de papel do PROJETO**, pela mesma expressão de
precedência invertida do **Q-16**. Nenhum papel "Admin" sobreviveu, o que é coerente: com
`is_staff` vencendo, quem era os dois virou "Gerente".

**Consequência direta:** o `CHECK` de `memberships` no ai9 aceita só
`responsavel|participante|coordenador|gestor`. Como está, **59% das participações são
recusadas na carga**. O de-para do conversor (`Converters::Memberships::ROLE_MAP`) não os
conhece, e o dry-run **aborta** — que é o comportamento certo.

**Veredito: perguntar.** Não há como mapear "Gerente" e "Colaborador" sem inventar
semântica: eles não descrevem função no projeto, descrevem o papel global de 2021. As saídas
plausíveis são (a) mapear os dois para `participante`, tratando-os como lixo do ETL antigo;
(b) mapear "Gerente"→`gestor` e "Colaborador"→`participante`; (c) ampliar o vocabulário do
ai9. **A decisão é do usuário** — `role` não autoriza nada (DEC-18.6), mas é o que a tela de
membros mostra, e escolher errado renomeia 669 vínculos.

### D-128 — `is_active` não é o flag de bloqueio do legado; `deactivated` é

`livetat_auth_users.deactivated` é o **único `boolean`** do schema inteiro do legado, e é o
que o produto lê: recusa o login (`sessions_decorator.rb:12`), derruba a sessão a cada
request (`pub_application_controller.rb:45`), é o que os botões de ligar/desligar escrevem
(`users_controller.rb:149,154`) e o que a lista de usuários mostra
(`users/list/_widget.html.erb:20,62`). **`is_active` não tem um único leitor.**

Cruzamento medido em produção (135 usuários):

| `is_active` | `deactivated` | usuários |
| ----------- | ------------- | -------: |
| 1 | f | **50** |
| 1 | t | **72** |
| 0 | t | **13** |

`is_active = 0` é **subconjunto** de `deactivated = true`. O conversor de usuários bloqueava
só por `is_active`: **72 contas hoje impedidas de entrar no legado entrariam no ai9**.

**Veredito: corrigido em 26/08/2026** (`Converters::Users.blocked?` passa a bloquear pela
união das duas, 85 contas, e `blocked_reason` nomeia qual coluna desligou cada uma). Não é
regra nova: é a **regra da DEC-39** aplicada à coluna certa, e cai na exceção de
segurança/autorização do DEC-30.

### D-129 — três renegociações com ano impossível (`0009`, `0020`)

`renegotiations#24` = `0020-08-21`, `#54` = `0020-09-21`, `#47` = `0009-12-21`. É `21`
digitado como ano num campo que aceitou. Distribuição do resto: 2017 (1), 2019 (19), 2020
(25), 2021 (57), 2022 (41), 2023 (14), 2024 (9).

**Impacto:** qualquer conta de idade, atraso ou agrupamento por ano trata essas três como se
fossem do ano 9 e do ano 20. No ai9 `renegotiation_date` é `date null: false` e aceita
igual.

**Veredito: perguntar.** Não há como inferir a data certa a partir do que está gravado — só
o cliente sabe. **Tarefa do ETL:** já são reportadas pelo somatório por ano (aparecem como
buckets `0009` e `0020`). O ai9 deve **rejeitar ano fora de uma faixa plausível na criação**,
o que é correção de formulário, não de dado histórico.

### D-130 — `carriers.bank_code` é preenchido com código de fantasia em 229 dos 328 portadores

`8888` × 181, `999` × 31, `9999` × 13, `888` × 4, mais **83 nulos**. Sobram 20 portadores com
código plausivelmente real.

**Impacto:** índice único em `bank_code` é impossível, e qualquer junção por código de banco
associa 181 portadores entre si. Complementa o **D-25** (o `bank_code` `integer` corrompia
zeros à esquerda): além de corromper, o campo virou depósito de valor de preenchimento.

**Veredito: preservar o dado, não indexar.** Não há o que corrigir sem inventar código de
banco. O que muda é a expectativa: nenhuma regra do ai9 pode assumir `bank_code` único nem
significativo.

### D-131 — 72 dos 135 usuários têm `username` string VAZIA (não nula)

Não é o mesmo que "sem username". Um índice único em `username` recusa a segunda string
vazia; um índice único que trate `''` como valor recusa 71 usuários na carga.

**Veredito: corrigir na conversão** — `''` vira `NULL` (o conversor já faz
`row['username'].presence`). Fica registrado porque a decisão precisa estar escrita: no
Postgres `NULL` não colide em índice único, string vazia colide.

### D-132 — 7 usuários apontam para `projects#0`

`livetat_auth_users.default_project_id = 0` em 7 linhas (pk 3, 5, 102, 113, 118, 119, 121).
`0` era o default de coluna inteira sem FK. Mesma família do **DB-120**
(`availability_templates.top_parent_id = 0`).

**Veredito: preservar como órfão contado.** O conversor resolve pelo de-para, não acha
correspondência e grava `NULL` — que é o certo, porque `current_project_id` no ai9 é
preferência revalidada contra `memberships` a cada request.

### D-133 — um anexo de renegociação tem 0 byte, no banco e no disco

`renegotiation_attachments#45`, `ANEXO_INSTRUMENTO_DE_GARANTIA.pdf`, `file_file_size = 0`,
`file_content_type = inode/x-empty`, e o arquivo existe no acervo com 0 byte.

**Por que isto importa mais do que um número:** a reconciliação de **contagem** e a de
**tamanho** passam as duas — banco 0 = disco 0. Um instrumento de garantia vazio só aparece
quando alguém olha o conteúdo. É o contraexemplo do "acervo reconciliado 100%".

**Veredito: perguntar.** Migrar um PDF vazio reproduz no ai9 a mesma promessa quebrada do
legado (anexo listado, download inútil). As saídas são migrar como está e listar, ou não
migrar a linha e registrar a ausência.

### D-134 — `User#avatar` e `Project#avatar` gravam na MESMA pasta

O `:attachment` do Paperclip é o nome do anexo pluralizado e **não inclui o model**: os dois
usam `public/system/avatars/:id/`. O usuário 62 e o projeto 62 dividem a pasta, e só não
colidem porque o `:basename` difere. O mesmo vale para `Carrier#logo` e `Provider#logo`
(`logos/:id/`), que em produção têm 0 linha cada.

**Impacto medido:** nenhum arquivo perdido (`avatars/62/` tem `missing_original.jpg` do
usuário e `1610222783781_original.jpg` do projeto). O risco é de **quem for casar registro
com arquivo por pasta** — foi o primeiro erro cometido nesta análise, e ele devolveu o
avatar do usuário no lugar do avatar do projeto.

**Veredito: nada a corrigir no legado; regra para o ETL.** `Sfg::Etl::Attachments#locate`
casa por **basename**, nunca por pasta, e há teste que prova os dois casos.

**Achado adjacente:** **121 dos 135 avatares de usuário são o mesmo placeholder
`missing.jpg` (7.327 B).** Só 14 pessoas têm foto de verdade — o que muda a expectativa de
como a lista de usuários vai parecer depois da carga.

---

## D-135 — o tooltip da correção por dias úteis mostra uma conta que **não fecha** (26/08/2026)

**Achado pelo usuário**, abrindo o Painel de Disponibilidade. Não é do legado: é defeito da
**melhoria** que o ai9 introduziu (FE-134, "os DOIS valores visíveis").

### O que aparece na tela

> *"Corrigido por dias úteis: R$ 786.276,16 × 57,1% de dias úteis decorridos = R$ 786.276,16"*

O mesmo número dos dois lados de uma multiplicação por 57,1%. A conta é falsa **na cara**.

### Por que acontece

`api/entities/availability_entry.rb:38` **calcula o multiplicador na hora da leitura**:

```ruby
expose :business_days_multiplier do |e|
  e.adjusted? && e.date.present? ? Sfg::BusinessDays.multiplier(e.date).round(6) : nil
end
```

É o multiplicador que **valeria hoje para aquela data**, não o que **foi aplicado** quando o
lançamento foi gravado. O `value` guardado veio de outro momento — e é o **D-02** que explica
por quê: o legado reaplica o multiplicador sobre valor já corrigido a cada salvamento, então
`value` e `original_value` guardam a foto de uma passada qualquer, não uma relação estável com
o multiplicador de hoje.

Medido no banco de desenvolvimento: **4.233 lançamentos, 3.971 com `original_value <> value`
e 262 com os dois iguais.** Nesses 262 o tooltip afirma uma correção que visivelmente não
existe no par de números.

### Por que importa mais do que parece

O tooltip existe **exatamente** para tornar a correção auditável — no legado o usuário digitava
X e via Y sem explicação nenhuma. Um explicador que mostra `X × 57,1% = X` é pior que a
ausência dele: convida o operador a desconfiar do número certo, ou a confiar no errado.

### As saídas (decisão do usuário — envolve número financeiro na tela)

1. **Derivar a porcentagem do par guardado** (`value / original_value`): a conta sempre fecha,
   e o tooltip passa a explicar **o que aconteceu**. Nos 262 empatados ele diria "× 100%", que é
   a verdade daquele registro.
2. **Separar as duas informações**: mostrar o par guardado como par ("base X → aplicado Y") e o
   multiplicador de hoje como linha à parte, rotulada como projeção. Mais honesto, mais longo.
3. **Persistir o multiplicador aplicado** numa coluna no momento do salvamento. É o mais
   correto e o único que sobrevive a mudança de calendário — e é mudança de esquema, com
   backfill indefinido para os registros que já existem.

> **VEREDITO (26/08/2026) — FICA COMO ESTA. DEC-114.** O usuario leu as tres saidas e
> escolheu nao mexer: *"vamos manter como esta"*. Nao e divida nem pendencia — e `dropped`
> consciente. O D-02 que origina o descasamento e comportamento do legado replicado de
> proposito, e qualquer saida mudaria numero na tela ou o esquema as vesperas da apresentacao.
> **Nao reabrir sem pedido explicito.**

**Dono:** S11 (disponibilidades). **Relacionado:** D-02, D-03.

---

## D-B20 — "Limite utilizado" NÃO é o principal em aberto: é `Σ liquidações − Σ encargos`

**Achado em 26/08/2026, medindo o banco de demonstração** (S20). Não é defeito da
migração: é o legado replicado por **DEC-01** e **DEC-30**, e fica escrito aqui porque
ninguém que ler o nome da coluna vai adivinhar.

### A cadeia, linha a linha

1. `../sfg/app/models/risk_operation.rb:34` — `original_balance = (-1) * original_balance.abs`.
   A operação **nasce** com o principal **negativo**.
2. `risk_operation.rb:39-52` — o `after_create` lança, para tipo **sem** pré-faturamento,
   um movimento de **Liberação do Recurso** de `movement_value = operation_value`.
3. `risk_movement_type.rb:53-61` — `parse_credit_type_value`: **débito = +1**, crédito = −1.
4. `risk_operation.rb:102-110` — a cadeia é `balance = anterior + (sinal × valor)`,
   partindo de `original_balance`.

Ou seja: `−V + V = 0`. **O saldo de uma operação recém-aberta é ZERO**, e como
`limite_utilizado_on = saldo × −1` (`risk_control.rb:91-101`), ela **não consome limite
nenhum**. O que move o utilizado é o que vem depois:

```
utilizado(controle, data) = Σ liquidações − Σ encargos     (operações vigentes na data)
```

Um **crédito** (Liquidação, Valor Transferido) **aumenta** o limite utilizado; um débito
(juros, IOF, ad valorem) o **reduz**, e um limite só com operações vivas sem amortização
mostra utilizado **negativo**.

### Por que importa, e o que ela custou

O seed de demonstração dimensionava as operações pela convenção oposta (saldo partindo de
zero, débito empurrando para baixo) e por isso **acertava o alvo no razão e errava na
tela**: 92% no razão, **14%** no painel de risco. Medido nos 96 limites do `sfg9_dev`
antes da correção: **todos em 0–30%**, com máximo de **16,0%** — a tela de Controle de
Risco não tinha um só exemplo de limite apertado, e o cartão "Limites no teto" da tela
inicial vinha zerado em todos os 12 projetos. Um cartão que só sabe dizer zero **não
distingue "não há limite estourado" de "a conta está quebrada"**.

É o mesmo modo de falha da tarefa 8.14 da S20 (o razão e o painel medindo coisas
diferentes), uma camada mais fundo.

### O que foi feito, e o que NÃO foi

**Não foi corrigido.** A fórmula é `BE-243`, travada por golden e por DEC-01/DEC-30 — e o
`parity-ledger` trava os números. O que mudou é do lado do **seed**: `Demo::Ledger::Operations.legacy_exposure`
replica a fórmula do sistema em Ruby puro, e o plano de utilização
(`Demo::Ledger::Controls::UTILIZATION_PLAN`) mira **esse** número, produzindo o consumo
por amortização parcial de operação viva — nunca escrevendo saldo à mão.

**Dono:** S5 (fórmula) / S20 (seed). **Relacionado:** DEC-01, DEC-02, D-93, BE-243, BE-264.
