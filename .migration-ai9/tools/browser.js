#!/usr/bin/env node
/**
 * Prova a tela RENDERIZANDO. Sem instalar nada.
 *
 * Esta árvore não tem o pacote `playwright`, mas a máquina tem o `playwright-core`
 * no repo vizinho `templates-testes` e os binários do Chromium no cache do
 * playwright. Isto costura os dois.
 *
 * Uso:
 *   node .migration-ai9/tools/browser.js /permissions --as=admin --out=perm --text
 *   node .migration-ai9/tools/browser.js /charges --as=og --dark
 *
 *   --as=og|admin|gerente|colab|readonly   faz o login de verdade (padrão: admin)
 *   --as=none                              não loga (tela pública)
 *   --out=<nome>                           nome do PNG (padrão: shot)
 *   --dark                                 captura também em modo escuro
 *   --text                                 imprime o innerText da página
 *   --wait=<ms>                            espera extra após carregar (padrão: 2500)
 *   --viewport=<L>x<A>                     tamanho da janela (padrão: 1440x900; telefone: 390x844)
 *
 * Variáveis: `BROWSER_OUT` (destino dos PNG), `APP_URL` (padrão localhost:5173).
 */
const path = require('path')
const fs = require('fs')
const { execFileSync } = require('child_process')
const { chromium } = require('/home/vinao/workspace/templates-testes/node_modules/playwright-core')

const CHROME = path.join(process.env.HOME, '.cache/ms-playwright/chromium-1234/chrome-linux64/chrome')
const OUT = process.env.BROWSER_OUT || '/tmp/sfg-shots'
// SEMPRE `localhost`, NUNCA `127.0.0.1`: o CORS do backend libera só a primeira.
// De `127.0.0.1` todo fetch falha e a tela mente "Erro ao enviar código".
const APP = process.env.APP_URL || 'http://localhost:5173'

// Contas do seed de demonstração (`backend/db/seeds/demo/ledger.rb`).
const CONTAS = {
  og: 'suporte@livetat.test',
  admin: 'helena.moreira@safegold.test',
  gerente: 'gustavo.lins@safegold.test',
  colab: 'camila.duarte@safegold.test',
  readonly: 'tereza.machado@safegold.test',
}

const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || `=${d}`).split('=')[1]
const flag = (n) => process.argv.includes(`--${n}`)

// O código volta no corpo da resposta em dev, mas o endpoint tem teto de 5 envios
// por 15 min — ler do banco é o caminho que não esbarra nisso.
//
// O `.env` liga `RAILS_LOG_TO_STDOUT`, então a saída do `runner` vem afogada em
// log (dotenv, SQL, ANSI). Marcar o valor e pescá-lo por regex é o que sobrevive
// a isso — capturar o stdout inteiro devolve lixo.
const codigoDe = (email) => {
  const saida = execFileSync(
    'bundle',
    [
      'exec',
      'rails',
      'runner',
      `u=User.find_by(email:${JSON.stringify(email)}); puts "<<CODE:#{LoginCode.where(user_id:u.id, used_at:nil).where("expires_at > ?", Time.current).order(created_at: :desc).first&.code}>>"`,
    ],
    {
      cwd: path.join(__dirname, '../../backend'),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      env: { ...process.env, RAILS_LOG_TO_STDOUT: '', RAILS_LOG_LEVEL: 'error' },
    },
  )
  return (saida.match(/<<CODE:(\d{6})>>/) || [])[1]
}

async function login(page, papel) {
  const email = CONTAS[papel]
  if (!email) throw new Error(`papel desconhecido: ${papel} (use ${Object.keys(CONTAS).join('|')})`)

  await page.goto(APP, { waitUntil: 'networkidle' })
  await page.locator('input').first().fill(email)
  await page.getByRole('button', { name: /entrar/i }).click()

  // Duas travas diferentes barram aqui, e vale saber qual é qual:
  //   * teto de envio — 5 códigos por 15 min POR DESTINO ("Muitas solicitações");
  //   * força bruta — POR IP ("Muitas tentativas"), e esta dispara com **5
  //     identificadores distintos** do mesmo IP em 15 min (`login_attempt.rb:63`).
  // A segunda é a que morde quem usa esta ferramenta: alternar `--as=` entre papéis
  // para conferir várias telas tranca o IP inteiro. Não é defeito do app — é a trava
  // funcionando. Sem esta checagem o estouro vira um timeout genérico esperando os 6
  // campos, e se perde tempo procurando defeito onde não há.
  const barrado = page.getByText(/muitas (tentativas|solicitações)/i)
  const codigoNaTela = page.locator('input >> nth=5')
  await Promise.race([
    codigoNaTela.waitFor({ timeout: 15000 }).catch(() => {}),
    barrado.waitFor({ timeout: 15000 }).catch(() => {}),
  ])
  if (await barrado.isVisible().catch(() => false)) {
    const texto = (await barrado.textContent().catch(() => '')) || ''
    throw new Error(
      /solicita/i.test(texto)
        ? `teto de envio atingido para ${email} (5 códigos por 15 min) — espere ou use outro --as=`
        : 'trava de força bruta ativa NESTE IP (5 identificadores distintos em 15 min) — ' +
          'trocar de --as= não ajuda; espere a janela virar',
    )
  }
  await codigoNaTela.waitFor({ timeout: 5000 })

  const codigo = codigoDe(email)
  // Sem o filtro de validade se pega um código velho, a tela recusa em silêncio
  // e o sintoma vira "a navegação nunca acontece" — 20s de timeout por nada.
  if (!codigo) throw new Error(`nenhum código VÁLIDO em aberto para ${email} (expira em 5 min)`)
  const campos = await page.locator('input').all()
  for (let i = 0; i < 6; i++) await campos[i].fill(codigo[i])

  // O formulário envia sozinho no último dígito — não existe botão "Verificar".
  //
  // `waitForURL` NÃO serve aqui: a troca de rota é do router do React, sem evento
  // `load`, então ele espera uma navegação que nunca acontece e estoura o timeout.
  // Pesquisar o `location` é o que enxerga a navegação do SPA.
  await page.waitForFunction(
    () => location.pathname !== '/' && !location.pathname.startsWith('/login'),
    null,
    { timeout: 20000 },
  )
}

;(async () => {
  const rota = process.argv[2] || '/'
  const papel = arg('as', 'admin')
  const nome = arg('out', 'shot')
  const espera = parseInt(arg('wait', '2500'), 10)

  // `--viewport=390x844` — o telefone da DEC-100. Sem isto só dava para provar o
  // desktop, e a passada de mobile achou 35 destinos inalcançáveis justamente
  // porque ninguém conseguia OLHAR a tela estreita.
  const [larguraTxt, alturaTxt] = arg('viewport', '1440x900').split('x')
  const viewport = { width: parseInt(larguraTxt, 10) || 1440, height: parseInt(alturaTxt, 10) || 900 }

  const browser = await chromium.launch({ executablePath: CHROME, args: ['--no-sandbox'] })
  const page = await browser.newPage({ viewport })

  const erros = []
  page.on('console', (m) => m.type() === 'error' && erros.push(m.text().slice(0, 200)))
  page.on('pageerror', (e) => erros.push('pageerror: ' + e.message.slice(0, 200)))

  try {
    if (papel !== 'none') {
      await login(page, papel)
      console.log(`login ok: ${papel}`)
    }
    await page.goto(APP + rota, { waitUntil: 'networkidle' })
    await page.waitForTimeout(espera)

    fs.mkdirSync(OUT, { recursive: true })
    await page.screenshot({ path: `${OUT}/${nome}.png`, fullPage: true })
    console.log(`shot: ${OUT}/${nome}.png`)

    if (flag('dark')) {
      await page.evaluate(() => document.documentElement.classList.add('dark'))
      await page.waitForTimeout(800)
      await page.screenshot({ path: `${OUT}/${nome}-dark.png`, fullPage: true })
      console.log(`shot: ${OUT}/${nome}-dark.png`)
    }

    console.log('url:', page.url())
    if (flag('text')) console.log('---\n' + (await page.innerText('body')).slice(0, 3000))
    // Erro de console não reprova sozinho, mas some do relatório se ninguém imprimir.
    if (erros.length) console.log('ERROS DE CONSOLE:\n  ' + erros.join('\n  '))
  } finally {
    await browser.close()
  }
})().catch((e) => {
  console.error('FALHOU:', e.message)
  process.exit(1)
})
