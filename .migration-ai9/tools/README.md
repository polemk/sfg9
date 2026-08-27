# Ferramentas de verificação visual

**Por que existem.** Por toda a migração o portão do front foi `tsc --noEmit`, que prova
que o código **carrega**, não que ele **funciona**. O preço já apareceu três vezes. A mais
recente: um `Sheet` do Radix usado **sem `SheetContent`** na trilha de auditoria —
type-check verde, spec verde, e clicar em "Ver detalhes" não fazia nada, porque o conteúdo
era montado no fluxo da página, fora da tela. Só o usuário abrindo o app achou.

## `browser.js` — use este

Costura o `playwright-core` do repo vizinho `templates-testes` com os binários do Chromium
do cache do playwright. **Nada a instalar.**

```bash
node .migration-ai9/tools/browser.js /permissions --as=admin --out=perm --text --dark
node .migration-ai9/tools/browser.js /charges --as=og
node .migration-ai9/tools/browser.js / --as=none --out=login     # tela pública
```

| Flag | O que faz |
| --- | --- |
| `--as=og\|admin\|gerente\|colab\|readonly` | faz o login **de verdade** (padrão `admin`) |
| `--as=none` | não loga |
| `--out=<nome>` | nome do PNG (padrão `shot`) |
| `--dark` | captura também em modo escuro |
| `--text` | imprime o `innerText` da página |
| `--wait=<ms>` | espera extra após carregar (padrão 2500) |
| `--viewport=<L>x<A>` | tamanho da janela (padrão `1440x900`; o telefone da DEC-100 é `390x844`) |

Destino dos PNG: `BROWSER_OUT` (padrão `/tmp/sfg-shots`). App: `APP_URL`.
Erros de console e `pageerror` são impressos ao fim — **leia-os**, eles não reprovam
sozinhos mas somem do relatório se ninguém olhar.

## Quatro armadilhas que custaram tempo

1. **Use `http://localhost:5173`, NUNCA `http://127.0.0.1:5173`.** O CORS do backend libera
   a origem `localhost`; de `127.0.0.1` **todo fetch falha** e a tela mostra "Erro ao enviar
   código". Parece defeito do app e não é.
2. **A sessão não dá para injetar.** O access token vive só em memória
   (`lib/api/tokenStore`) e o refresh em cookie `HttpOnly` — não há nada no `localStorage`
   para plantar. É preciso passar pela tela de login. É o que o `login()` faz.
3. **Alternar `--as=` tranca o IP.** A trava de força bruta dispara com **5 identificadores
   distintos do mesmo IP em 15 min** (`login_attempt.rb:63`) — conferir cinco telas com cinco
   papéis diferentes barra a sexta. **Não é defeito: é a trava funcionando.** O script
   distingue as duas mensagens ("Muitas solicitações" = teto por destino, 5 por 15 min;
   "Muitas tentativas" = força bruta por IP) para não mandar você caçar fantasma.
4. **O código expira em 5 minutos** e a saída do `rails runner` vem afogada em log
   (`RAILS_LOG_TO_STDOUT` no `.env`). O script filtra por validade e pesca o valor por
   marcador — sem isso se pega um código velho, a tela recusa em silêncio e o sintoma vira
   "a navegação nunca acontece".

Detalhe do formulário: os 6 campos do código **enviam sozinhos** no último dígito. Não
existe botão "Verificar" para clicar, e `page.waitForURL` não enxerga a troca de rota do
React (não há evento `load`) — é `waitForFunction` sobre o `location`.

## `cdp.js` — o plano B

Fala **CDP cru** com um Chromium headless já aberto, usando o `ws` do `node_modules` do
front. Só vale se o `templates-testes` sumir da máquina.

```bash
~/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome \
  --headless=new --disable-gpu --no-sandbox \
  --remote-debugging-port=9333 --user-data-dir=/tmp/cdp/profile about:blank &
echo "ANOTE ESTE PID: $!"     # mate por ELE, nunca por padrão amplo

WSURL=$(curl -s http://127.0.0.1:9333/json/list \
  | python3 -c "import sys,json;print([t['webSocketDebuggerUrl'] for t in json.load(sys.stdin) if t['type']=='page'][0])")

CDP_OUT=/tmp/cdp/shots node .migration-ai9/tools/cdp.js "$WSURL" passos.json
```

`passos.json` é uma lista de `{"goto"|"eval"|"sleep"|"shot"}`.

## Contas do seed de demonstração

`backend/db/seeds/demo/ledger.rb`: `suporte@livetat.test` (OG),
`helena.moreira@safegold.test` (Admin), `gustavo.lins@safegold.test` (Gerente),
`camila.duarte@safegold.test` e `rafael.antunes@safegold.test` (Colaborador),
`tereza.machado@safegold.test` (somente leitura).
