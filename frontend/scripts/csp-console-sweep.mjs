/**
 * Varredura de console com o CSP BLOQUEANTE ligado (DEC-48), em light e dark.
 *
 * Existe porque o modo de falha do CSP e SILENCIOSO: recurso bloqueado nao produz erro
 * na tela, so some. `tsc --noEmit` limpo e `rspec` verde nao pegam nada disso.
 *
 * O que ele escuta, e por que cada parte importa:
 *  - `securitypolicyviolation` — **o unico evento que denuncia recurso bloqueado por
 *    CSP**. Nao vira `console.error` em todos os casos e nao vira `requestfailed`;
 *  - light **e** dark, porque tema troca imagem, fonte e SVG;
 *  - `document.fonts`, porque `font-src`/`style-src` mal configurados derrubam a
 *    tipografia inteira sem uma linha de erro;
 *  - o codigo de login e cunhado direto no banco, nao pelo `request_code`, para nao
 *    esbarrar no limite de reenvio.
 *
 * OBRIGATORIO repetir toda vez que uma tela passar a carregar recurso externo novo
 * (mapa, grafico, fonte, iframe, CDN). Ver `.migration-ai9/platform-runbook.md`.
 *
 * Pre-requisitos: backend em :3000, frontend em :5173, um usuario no banco.
 * Rodar (de `frontend/`):
 *   node scripts/csp-console-sweep.mjs
 *
 * Dependencias externas ao repo (por isso os caminhos sao parametrizaveis):
 *   PLAYWRIGHT_CORE  modulo `playwright-core/index.mjs`
 *   CHROME_PATH      binario do Chromium
 */
const PLAYWRIGHT_CORE =
  process.env.PLAYWRIGHT_CORE ||
  '/home/vinao/workspace/templates-testes/node_modules/playwright-core/index.mjs'
const { chromium } = await import(PLAYWRIGHT_CORE)

const FRONT = 'http://localhost:5173'
const API = 'http://localhost:3000'
const EMAIL = process.env.SWEEP_EMAIL || 'vinaoxd@gmail.com'

const ROUTES = [
  '/login',
  '/',
  '/dashboard',
  '/users',
  '/profile',
  '/media',
  '/admin/credentials',
  '/admin/chat/flows',
  '/admin/chat/builder',
  '/admin/chat/executions',
]

const EXEC =
  process.env.CHROME_PATH ||
  '/home/vinao/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome'

import { execFileSync } from 'node:child_process'

// O endpoint de request_code tem limite de reenvio; a varredura cunha o codigo
// direto no banco para nao depender dele (e para nao gastar o limite do usuario).
function getCode() {
  const out = execFileSync(
    'bin/rails',
    [
      'runner',
      `u = User.find_by(email: ${JSON.stringify(EMAIL)}); c = rand(100000..999999).to_s; LoginCode.create!(destination: u.email, method: 'email', code: c, expires_at: 5.minutes.from_now, attempts: 0, user: u); puts "CODE=#{c}"`,
    ],
    { cwd: '/home/vinao/workspace/ai9/backend', encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }
  )
  const m = out.match(/CODE=(\d{6})/)
  if (!m) throw new Error('nao consegui cunhar codigo: ' + out.slice(-300))
  return m[1]
}

const findings = []

async function sweep(theme) {
  const browser = await chromium.launch({ executablePath: EXEC, headless: true, args: ['--no-sandbox'] })
  const ctx = await browser.newContext({ colorScheme: theme, viewport: { width: 1440, height: 900 } })
  const page = await ctx.newPage()

  let current = '(setup)'
  const note = (kind, text) => findings.push({ theme, route: current, kind, text })

  page.on('console', (m) => {
    if (m.type() === 'error' || m.type() === 'warning') note(m.type(), m.text())
  })
  page.on('pageerror', (e) => note('pageerror', e.message))
  page.on('requestfailed', (r) => note('requestfailed', `${r.url()} :: ${r.failure()?.errorText}`))

  // securitypolicyviolation e o unico evento que denuncia recurso bloqueado por CSP:
  // ele NAO gera console.error em todos os casos e NAO gera requestfailed.
  await ctx.exposeBinding('__cspViolation', (_src, d) => note('CSP', d))
  await ctx.addInitScript(() => {
    document.addEventListener('securitypolicyviolation', (e) => {
      // eslint-disable-next-line no-undef
      window.__cspViolation(
        `${e.violatedDirective} bloqueou ${e.blockedURI || '(inline)'} (${e.sourceFile || ''}:${e.lineNumber || ''})`
      )
    })
  })

  // 1. Tema fixado antes de qualquer render.
  await page.addInitScript((t) => {
    try {
      localStorage.setItem('theme-storage', JSON.stringify({ state: { theme: t }, version: 0 }))
      localStorage.setItem('theme', t)
    } catch {}
  }, theme)

  // 2. Login: valida o codigo de dentro da pagina para o cookie HttpOnly de refresh
  //    cair no contexto do browser.
  current = '(login)'
  await page.goto(`${FRONT}/login`, { waitUntil: 'networkidle' })
  const code = getCode()
  const loginResult = await page.evaluate(
    async ([api, email, c]) => {
      const r = await fetch(`${api}/auth/v1/magic_login/validate_code`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ identifier: email, code: c, method: 'email' }),
      })
      return { status: r.status, body: (await r.text()).slice(0, 200) }
    },
    [API, EMAIL, code]
  )
  if (loginResult.status !== 200) {
    findings.push({ theme, route: '(login)', kind: 'FATAL', text: JSON.stringify(loginResult) })
  }

  for (const route of ROUTES) {
    current = route
    try {
      await page.goto(`${FRONT}${route}`, { waitUntil: 'networkidle', timeout: 25000 })
      await page.waitForTimeout(1200)
      const url = new URL(page.url())
      if (url.pathname === '/login' && route !== '/login' && route !== '/') {
        findings.push({ theme, route, kind: 'REDIRECT', text: 'caiu no /login (sessao nao restaurada)' })
      }
      // Prova de que a tipografia carregou: font-src/style-src mal configurados
      // derrubam a fonte sem uma linha de erro.
      const fonts = await page.evaluate(() =>
        Array.from(document.fonts).filter((f) => f.status === 'loaded').map((f) => f.family)
      )
      findings.push({ theme, route, kind: 'fonts', text: [...new Set(fonts)].join(', ') || '(nenhuma)' })
    } catch (e) {
      findings.push({ theme, route, kind: 'NAVFAIL', text: String(e.message).slice(0, 160) })
    }
  }

  await browser.close()
}

await sweep('light')
await sweep('dark')

const ruido = /Download the React DevTools|Warning: ReactDOM|was preloaded using link preload/i
const relevantes = findings.filter((f) => f.kind !== 'fonts' && !ruido.test(f.text))

console.log('=== FONTES CARREGADAS ===')
for (const f of findings.filter((x) => x.kind === 'fonts')) {
  console.log(`${f.theme.padEnd(5)} ${f.route.padEnd(26)} ${f.text}`)
}
console.log('\n=== ACHADOS (%d) ===', relevantes.length)
for (const f of relevantes) {
  console.log(`[${f.theme}] ${f.route} :: ${f.kind} :: ${f.text.slice(0, 300)}`)
}
const csp = relevantes.filter((f) => f.kind === 'CSP')
console.log(`\nVIOLACOES DE CSP: ${csp.length}`)

// Sai diferente de zero quando ha violacao ou falha dura: assim isto pode virar portao.
const duros = relevantes.filter((f) => ['CSP', 'FATAL', 'NAVFAIL', 'pageerror'].includes(f.kind))
process.exit(duros.length ? 1 : 0)
