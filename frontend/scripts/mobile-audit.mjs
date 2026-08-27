/**
 * Passada de mobile (DEC-100) nas fatias fechadas — renderiza cada tela em 390x844,
 * nos dois modos, logado, e MEDE o que `tsc`/`vitest` nao veem.
 *
 * O que ele mede, e por que:
 *  - rolagem horizontal da pagina (criterio 3 da §5.4.8) e QUEM a causa;
 *  - `<table>` viva no telefone (o "overflow-x fingindo de mobile" que a §5.4.8 proibe);
 *  - alvo de toque abaixo de 44 px em elemento interativo visivel (criterio 1);
 *  - o ultimo elemento da lista contra o topo da `MobileBottomBar` (barra comendo conteudo);
 *  - sobreposicao entre o conteudo e as duas barras do app (empilhamento);
 *  - erro de console e falha de rede.
 *
 * Contraste NUNCA por pixel: no headless com --disable-gpu o `backdrop-filter` compoe
 * errado. Quando precisar, leia `getComputedStyle`.
 *
 * Rodar de `frontend/`:  node scripts/mobile-audit.mjs [rota,rota,...]
 */
const PLAYWRIGHT_CORE =
  process.env.PLAYWRIGHT_CORE ||
  '/home/vinao/workspace/templates-testes/node_modules/playwright-core/index.mjs'
const { chromium } = await import(PLAYWRIGHT_CORE)
import { execFileSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'

const FRONT = 'http://localhost:5173'
const API = 'http://localhost:3000'
const EMAIL = process.env.SWEEP_EMAIL || 'vinaoxd@gmail.com'
const EXEC =
  process.env.CHROME_PATH ||
  '/home/vinao/.cache/puppeteer/chrome/linux-150.0.7871.24/chrome-linux64/chrome'
const OUT = process.env.OUT_DIR || '/tmp/claude-1000/-home-vinao-workspace-ai9/78cf7ed3-b766-4559-99ac-f61cd18b1f0d/scratchpad/shots'
mkdirSync(OUT, { recursive: true })

const IDS = {
  carrier: '825f1cdd-32ce-4a22-9357-ab7c7597759b',
  project: '0703ea82-d621-486c-83b2-9f5aa3085c61',
  company: 'cc6ff79b-6c8d-4227-9800-9e67ad3a9c42',
  provider: '137130ae-727a-4ecf-b30f-4db92ea4ef4d',
  reneg: '1b5d1c8d-cfb7-4dff-ab0e-4b8bda100e7b',
}

const TODAS = [
  // S3 — catalogos globais
  ['S3', '/carriers'],
  ['S3', `/carriers/${IDS.carrier}`],
  ['S3', '/carrier-groups'],
  ['S3', '/segments'],
  ['S3', '/sub-segments'],
  ['S3', '/project-guarantee-types'],
  // S4 — projeto e empresas
  ['S4', '/projects'],
  ['S4', `/projects/${IDS.project}`],
  ['S4', '/companies'],
  ['S4', `/companies/${IDS.company}`],
  ['S4', '/providers'],
  ['S4', `/providers/${IDS.provider}`],
  ['S4', '/project-guarantees'],
  ['S4', '/project-carrier-connections'],
  // S9 — renegociacoes
  ['S9', '/renegotiations'],
  ['S9', '/renegotiations/new'],
  ['S9', `/renegotiations/${IDS.reneg}`],
  // S10 — indicadores
  ['S10', '/indicators'],
  ['S10', '/indicator-entries'],
  ['S10', '/indicator-connections'],
  // S11 — disponibilidades
  ['S11', '/availability'],
  ['S11', '/project-availabilities'],
  ['S11', '/availability-templates'],
  // S12 — contratos, ajuda e FAQ
  ['S12', '/admin/contracts'],
  ['S12', '/help/items'],
  ['S12', '/faq'],
  // S5 — risco
  ['S5', '/risk'],
  ['S5', '/risk-controls'],
  ['S5', '/risk-operation-types'],
  ['S5', '/risk-movement-types'],
  // S2 — console e navegacao
  ['S2', '/dashboard'],
  ['S2', '/messages'],
  ['S2', '/platform/whatsapp'],
]

const filtro = process.argv[2] ? process.argv[2].split(',') : null
const ROTAS = filtro ? TODAS.filter(([, r]) => filtro.some((f) => r.includes(f))) : TODAS

function getCode() {
  const out = execFileSync(
    'bin/rails',
    [
      'runner',
      `u = User.find_by(email: ${JSON.stringify(EMAIL)}); c = rand(100000..999999).to_s; LoginCode.create!(destination: u.email, method: 'email', code: c, expires_at: 30.minutes.from_now, attempts: 0, user: u); puts "CODE=#{c}"`,
    ],
    { cwd: '/home/vinao/workspace/ai9/backend', encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }
  )
  const m = out.match(/CODE=(\d{6})/)
  if (!m) throw new Error('nao consegui cunhar codigo: ' + out.slice(-300))
  return m[1]
}

/** Roda DENTRO da pagina. Devolve o diagnostico bruto de layout. */
const SONDA = () => {
  const vw = window.innerWidth
  const doc = document.documentElement
  const visivel = (el) => {
    const r = el.getBoundingClientRect()
    if (r.width === 0 || r.height === 0) return false
    const cs = getComputedStyle(el)
    if (cs.visibility === 'hidden' || cs.display === 'none' || cs.opacity === '0') return false
    return true
  }
  const nome = (el) => {
    const cls = (typeof el.className === 'string' ? el.className : '').slice(0, 90)
    const txt = (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40)
    return `${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''}.${cls}${txt ? ' «' + txt + '»' : ''}`
  }

  // 1. quem estoura a largura
  const estouram = []
  for (const el of document.querySelectorAll('body *')) {
    if (!visivel(el)) continue
    const r = el.getBoundingClientRect()
    if (r.right > vw + 1 || r.left < -1) {
      const cs = getComputedStyle(el)
      // ignora o que rola dentro de si mesmo com overflow proprio
      let pai = el.parentElement, contido = false
      while (pai && pai !== document.body) {
        const pcs = getComputedStyle(pai)
        if (pcs.overflowX === 'auto' || pcs.overflowX === 'scroll' || pcs.overflowX === 'hidden') { contido = true; break }
        pai = pai.parentElement
      }
      if (!contido) estouram.push({ el: nome(el), left: Math.round(r.left), right: Math.round(r.right), overflowX: cs.overflowX })
    }
  }

  // 2. tabelas vivas
  const tabelas = [...document.querySelectorAll('table')].filter(visivel).map((t) => {
    const r = t.getBoundingClientRect()
    let pai = t.parentElement, rolagem = null
    while (pai && pai !== document.body) {
      const pcs = getComputedStyle(pai)
      if (pcs.overflowX === 'auto' || pcs.overflowX === 'scroll') { rolagem = nome(pai); break }
      pai = pai.parentElement
    }
    return { largura: Math.round(r.width), colunas: t.querySelectorAll('thead th').length, linhas: t.querySelectorAll('tbody tr').length, rolagem }
  })

  // 3. alvos de toque.
  //
  // A caixa do elemento NAO e o alvo: `::after` invisivel (interruptor, caixa de
  // marcacao sem rotulo) estende a area que RESPONDE sem mudar um pixel do desenho,
  // e `getBoundingClientRect` continua devolvendo o tamanho do desenho. Por isso a
  // medida final e por TOQUE: se o ponto a 20 px acima e a 20 px abaixo do centro
  // ainda cai no proprio elemento (ou no rotulo que o comanda), o polegar acerta.
  const alvos = []
  const sel = 'button, a[href], [role="button"], [role="tab"], [role="switch"], input[type="checkbox"], input[type="radio"], select, summary'
  const respondePor = (x, y, el) => {
    const alvo = document.elementFromPoint(x, y)
    if (!alvo) return false
    if (alvo === el || el.contains(alvo) || alvo.contains(el)) return true
    // Caixa de marcacao: quem responde e o <label>, e o clique chega no input.
    const rotulo = alvo.closest('label')
    return !!(rotulo && (rotulo.contains(el) || rotulo.htmlFor === el.id))
  }
  for (const el of document.querySelectorAll(sel)) {
    if (!visivel(el)) continue
    const r = el.getBoundingClientRect()
    if (r.top > window.innerHeight * 3) continue
    if (r.height >= 44 && r.width >= 24) continue
    const cx = Math.round(r.left + r.width / 2)
    const cy = Math.round(r.top + r.height / 2)
    // `elementFromPoint` so enxerga o que esta DENTRO da janela: para o que ficou
    // abaixo da dobra a medida cai no `::after`, que e como a area estendida e feita.
    const dentroDaJanela = cy - 20 >= 0 && cy + 20 <= window.innerHeight
    let estendido
    if (dentroDaJanela) {
      estendido = respondePor(cx, cy - 20, el) && respondePor(cx, cy + 20, el)
    } else {
      const depois = getComputedStyle(el, '::after')
      estendido = depois.content !== 'none' && parseFloat(depois.height) >= 44
    }
    if (!estendido) alvos.push({ el: nome(el), h: Math.round(r.height), w: Math.round(r.width) })
  }

  // 4. barras do app
  const topBar = document.querySelector('[data-mobile-topbar], header.md\\:hidden, .z-appbar')
  const bottom = [...document.querySelectorAll('nav')].find((n) => {
    const r = n.getBoundingClientRect()
    return r.bottom >= window.innerHeight - 2 && r.width >= vw - 2
  })

  return {
    vw,
    scrollWidth: doc.scrollWidth,
    bodyScrollWidth: document.body.scrollWidth,
    scrollHeight: doc.scrollHeight,
    estouram: estouram.slice(0, 12),
    tabelas,
    alvos: alvos.slice(0, 25),
    temTopBar: !!topBar,
    temBottomBar: !!bottom,
    bottomBarTop: bottom ? Math.round(bottom.getBoundingClientRect().top) : null,
    temAlert: document.querySelectorAll('[role="alert"]').length,
    temStatus: document.querySelectorAll('[role="status"]').length,
    titulo: (document.querySelector('h1, h2')?.textContent || '').trim().slice(0, 60),
    texto: (document.body.innerText || '').replace(/\s+/g, ' ').slice(0, 400),
  }
}

/** Rola ate o fim e mede o ultimo bloco de conteudo contra a barra de abas. */
const SONDA_FIM = () => {
  const main = document.querySelector('main')
  if (!main) return null
  main.scrollTop = main.scrollHeight
  const nav = [...document.querySelectorAll('nav')].find((n) => {
    const r = n.getBoundingClientRect()
    return r.bottom >= window.innerHeight - 2 && r.width >= window.innerWidth - 2
  })
  const navTop = nav ? nav.getBoundingClientRect().top : window.innerHeight
  // ultimo elemento com texto dentro do main
  let ultimo = null
  for (const el of main.querySelectorAll('*')) {
    if (el.children.length) continue
    const t = (el.textContent || '').trim()
    if (!t) continue
    // `sr-only` e um retangulo de 1px fora da vista: contar como "conteudo comido"
    // e um falso positivo, e o `aria-hidden` idem.
    if (el.closest('[aria-hidden="true"]')) continue
    const r = el.getBoundingClientRect()
    if (r.height <= 1 || r.width <= 1) continue
    if (!ultimo || r.bottom > ultimo.bottom) ultimo = { bottom: r.bottom, texto: t.slice(0, 40) }
  }
  return {
    navTop: Math.round(navTop),
    ultimoBottom: ultimo ? Math.round(ultimo.bottom) : null,
    ultimoTexto: ultimo?.texto,
    comido: ultimo ? ultimo.bottom > navTop + 1 : false,
    scrollTop: Math.round(main.scrollTop),
    scrollHeight: Math.round(main.scrollHeight),
    clientHeight: Math.round(main.clientHeight),
  }
}

const relatorio = []

async function rodar(theme) {
  const browser = await chromium.launch({
    executablePath: EXEC,
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--font-render-hinting=none'],
  })
  const ctx = await browser.newContext({
    colorScheme: theme,
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
    userAgent:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  })
  const page = await ctx.newPage()
  const erros = []
  page.on('console', (m) => { if (m.type() === 'error') erros.push(m.text().slice(0, 200)) })
  page.on('pageerror', (e) => erros.push('PAGEERROR ' + e.message.slice(0, 200)))

  await page.addInitScript((t) => {
    try {
      localStorage.setItem('theme-storage', JSON.stringify({ state: { theme: t }, version: 0 }))
      localStorage.setItem('theme', t)
    } catch {}
  }, theme)

  await page.goto(`${FRONT}/login`, { waitUntil: 'domcontentloaded' })
  const code = getCode()
  const login = await page.evaluate(
    async ([api, email, c]) => {
      const r = await fetch(`${api}/auth/v1/magic_login/validate_code`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ identifier: email, code: c, method: 'email' }),
      })
      return { status: r.status, body: (await r.text()).slice(0, 300) }
    },
    [API, EMAIL, code]
  )
  if (login.status !== 200) throw new Error('login falhou: ' + JSON.stringify(login))

  for (const [fatia, rota] of ROTAS) {
    erros.length = 0
    const item = { theme, fatia, rota }
    try {
      await page.goto(`${FRONT}${rota}`, { waitUntil: 'domcontentloaded', timeout: 30000 })
      // "Verificando sessao..." e o RootRedirect/ProtectedRoute revalidando o refresh:
      // medir com ele na tela mede a tela errada.
      await page
        .waitForFunction(() => !/Verificando sess/.test(document.body.innerText), null, { timeout: 20000 })
        .catch(() => {})
      await page.waitForTimeout(2600)
      item.url = new URL(page.url()).pathname
      item.sonda = await page.evaluate(SONDA)
      const slug = rota.replace(/[^a-z0-9]+/gi, '_')
      await page.screenshot({ path: `${OUT}/${theme}${slug}.png`, fullPage: false })
      item.fim = await page.evaluate(SONDA_FIM)
      await page.waitForTimeout(300)
      await page.screenshot({ path: `${OUT}/${theme}${slug}__fim.png`, fullPage: false })
      item.erros = [...new Set(erros)].filter((e) => !/DevTools|preloaded using link preload|Download the React/i.test(e)).slice(0, 5)
    } catch (e) {
      item.falha = String(e.message).slice(0, 200)
    }
    relatorio.push(item)
    const s = item.sonda
    console.log(
      `[${theme}] ${fatia.padEnd(4)} ${rota.padEnd(46)} ` +
        (item.falha
          ? 'FALHA ' + item.falha
          : `sw=${s.scrollWidth}/${s.vw}${s.scrollWidth > s.vw ? ' <<HSCROLL' : ''}` +
            ` tab=${s.tabelas.length}` +
            ` alvos<44=${s.alvos.length}` +
            ` comido=${item.fim?.comido}` +
            ` alert=${s.temAlert}` +
            (item.erros?.length ? ` ERR=${item.erros.length}` : ''))
    )
  }
  await browser.close()
}

await rodar('light')
await rodar('dark')
writeFileSync(`${OUT}/relatorio.json`, JSON.stringify(relatorio, null, 2))
console.log('\nJSON em ' + OUT + '/relatorio.json')
