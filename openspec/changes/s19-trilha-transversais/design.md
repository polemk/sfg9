# Design: S19 — Trilha de auditoria e transversais de domínio e UI

> Origem: `.migration-ai9/map/data-infra.md` §2.7 (`misc-domain`) e §2.1 (`DB-591`), mais
> `OPS-126` de `map/projects-cadastros.md`. Fatia interna **S-14** do mapa de bloco.
> Nasceu do fechamento do Phase 2: 27 IDs transversais sem dono, porque S13 apontava a trilha
> para S2 e S2 nunca a reivindicou.

## Context

**A trilha, no legado.** `Tracking` é polimórfica em dois níveis: `trackable` (o objeto) e
`trackable_parent` (o pai). Autor obrigatório, destinatário opcional, `kind` (`"JOB"` entre
outros) e um `resume` em pt-BR limitado a 300 caracteres. O `TrackingFacade` tem **20
emissores**, sempre no quarteto `request → start → progress → finish`. A coluna `type` (STI)
está **sempre `NULL`**.

Três defeitos medidos:
- `resume` maior que 300 faz o `save` retornar `false`; nenhum chamador verifica. **O evento
  é perdido**, e é sempre o evento do caso complicado.
- `TrackingFacade.track_new_project` é chamado e **não existe** (`BE-434`).
- `type` colide com o mecanismo de STI do Rails sem nunca ter sido usada.

**A trilha, na base ai9.** Não há. `backend/app/models/permission_audit_log.rb` é auditoria
ad hoc de um assunto só. `paper_trail` está no Gemfile **sem nenhum uso** (**C-12**).

**Os helpers.** 15 helpers de view Ruby. Um deles, `create_console_menu`, é o menu inteiro
por papel e permissão — e é de **S2**. Os outros 14 formam o vocabulário visual do produto.

## Goals / Non-Goals

**Goals**
- Uma trilha **imutável**, que nunca perde evento e nunca é editada.
- Trilha **filtrável de verdade**: campos estruturados além do texto.
- Um utilitário por conceito de formatação — nunca dois.
- Retirar da validação de model a única chamada de rede que havia lá.

**Non-Goals**
- **Não** adotar `paper_trail`. A semântica é evento de negócio, não versionamento.
- **Não** tocar no menu (S2), no `MovementKind` nem no `Entry` (S6).
- **Não** portar geocoding: a distância de `BE-433` é cálculo sobre coordenadas **recebidas**,
  não resolução de endereço (o geocoding está bloqueado por Q-04, em S13).
- **Não** guardar payload completo do objeto na trilha (Q-23).

## Decisões

### D1 — Evento nunca se perde: truncamento explícito

`resume` é truncado **explicitamente**, com marca de truncamento, e o evento é gravado. A
alternativa do legado — deixar a validação de tamanho falhar e ignorar o retorno — troca "o
texto ficou incompleto" por "o evento não existiu", e é a troca errada numa trilha de
auditoria: um resumo cortado ainda diz **quem fez o quê e quando**.

O texto integral, quando importa, vai para o payload `jsonb`.

### D2 — Campos estruturados **além** do texto, não em vez dele

O legado guarda uma frase em pt-BR. É legível e **não é consultável**: "todos os eventos de
extensão de operação do último mês" não sai de um `LIKE`. Passam a existir `event`, `entity`
e `payload` (`jsonb`), com o `resume` preservado para exibição — porque a frase é o que a
timeline mostra, e reescrevê-la a partir dos campos seria mudar o texto que o usuário conhece.

Índices em `[trackable_type, trackable_id]` e `[trackable_parent_type, trackable_parent_id]`
— o legado não tinha nenhum, e a tela da trilha filtra pelos dois.

### D3 — Imutabilidade é regra do model, não convenção

Sem `update` e sem `destroy` no `Tracking`. Uma trilha que pode ser editada não é trilha.
A tentativa levanta; não é ignorada em silêncio.

### D4 — A coluna `type` não vem

STI sempre `NULL` em toda a origem, e o nome colide com o mecanismo de herança do Rails —
criar a coluna significaria o Rails tentar instanciar classes a partir dela. A evidência
(contagem de distintos na origem) é produzida pelo dry-run de S14.

### D5 — `random_color` vira determinística

O legado gera cor aleatória por renderização: o mesmo item muda de cor a cada carga da
página, o que anula o propósito de uma cor de identificação. Vira hash determinístico sobre
o id — mesma entrada, mesma cor. Não é paridade; é o comportamento pretendido.

### D6 — `UriValidator` perde a verificação de disponibilidade

O legado faz uma requisição HTTP **dentro da validação do model**. Isso transforma salvar um
registro em chamada de rede, dentro da transação, com timeout desconhecido — e faz um
registro válido ser recusado porque um site estava fora do ar por dez segundos. Fica o
formato; a disponibilidade, se um dia for requisito, é verificação assíncrona.

### D7 — Ordenação multi-coluna com allowlist

O legado recebe **arrays paralelos** de chaves e estilos vindos do cliente. Vira um
utilitário único, e o portão é a **allowlist de colunas**: chave vinda do cliente e
interpolada em `ORDER BY` é injeção de SQL esperando acontecer. O utilitário é compartilhado
porque `MovementKind` (S6) é apenas o primeiro consumidor.

### D8 — Datas em ISO-8601 na fronteira inteira

`days_js_array` monta datas em formato próprio para o datepicker. O contrato passa a ser
ISO-8601 em toda a troca cliente↔servidor, e a formatação para exibição acontece **só** na
camada de apresentação. Formato de data ambíguo na fronteira é a fonte clássica de
"dia/mês trocados", que num sistema de vencimentos é erro financeiro.

### D9 — `public_create_user?` nasce `false`, e a flag sozinha não basta

A flag é a trava do **D-39** (auto-cadastro público). Mas a base ai9 tem `pre_register`,
`complete_registration` e `visitor_signup*` na allowlist pública (`api/root.rb:35-46`) — uma
porta que **não veio do legado**. A flag desligada não fecha a rota. Por isso a decisão está
escrita nas duas pontas: a flag aqui, a allowlist em S1.

## Risks

| Risco | Mitigação |
| ----- | --------- |
| **Médio** — ordem com S13: os jobs emitem trilha | Se S13 rodar antes, cria o **mínimo** (tabela + serviço) e S19 constrói a leitura em cima. Já estava escrito na Fronteiras de S13 |
| **Médio** — trilha vira o maior objeto do banco | Payload `jsonb` **enxuto** (Q-23), não cópia do registro; e o `resume` truncado, não ilimitado |
| **Médio** — `format_money` divergir da gravação | Lê o **mesmo** conjunto golden de `Sfg::Coercion` (S18), exercitado nos dois lados |
| **Baixo** — `BE-434` (método inexistente) | Ou o método passa a existir, ou a chamada sai; a decisão é registrada, e não fica um `NoMethodError` latente |
| **Baixo** — trilha aberta a todo papel | Q-21: trilha global só a og/admin; histórico do objeto para quem vê o objeto |

## Migration Plan

1. Migration `create_trackings` (sem `type`, com os dois índices polimórficos e o `jsonb`).
2. `Tracking` imutável + `Sfg::TrackingService` com truncamento explícito.
3. Emissores de ciclo de vida (quarteto), consumidos pelos jobs de S13.
4. Endpoints de listagem e detalhe, com autorização por papel (Q-21).
5. Entity e widget de timeline; mapa tipo → cor/ícone.
6. Utilitários de formatação, um por conceito, e o contrato ISO-8601.
7. Validators e o utilitário de ordenação com allowlist.

## Open Questions

- **Q-21** — trilha global visível a que papéis? Default: og/admin.
- **Q-22** — a distância geográfica tem consumidor? Default: porto o cálculo condicional.
- **Q-23** — payload completo na trilha? Default: **não**.
