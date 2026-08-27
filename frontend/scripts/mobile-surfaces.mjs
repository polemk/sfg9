/**
 * Abre as superficies FLUTUANTES de cada tela em 390x844 e mede — §5.4.4 e §5.4.8.
 *
 * "Fechado, tudo parece perfeito": um popover preso dentro de um ancestral com
 * `transform`/`backdrop-filter`/`z` so aparece atras do conteudo quando esta ABERTO.
 * A varredura de layout (mobile-audit.mjs) nao pega isso.
 *
 * O que ele faz por tela:
 *  1. abre a folha "Mais" da barra de abas e confere que ela esta no `body` e VISIVEL;
 *  2. abre o seletor de modo do cabecalho;
 *  3. clica no primeiro gatilho de acao de linha ("...") e mede a folha;
 *  4. abre o primeiro `combobox`/`select` da tela.
 *
 * Em cada caso mede o elemento no PONTO CENTRAL (elementFromPoint): se o que responde
 * no centro do painel nao for o proprio painel, ele esta atras de alguma coisa.
 * Contraste por getComputedStyle, nunca por pixel.
 *
 * Rodar de `frontend/`:  node scripts/mobile-surfaces.mjs [rota,rota]
 */
const PLAYWRIGHT_CORE =
  process.env.PLAYWRIGHT_CORE ||
  '/home/vinao/workspace/templates-testes/node_modules/playwright-core/index.mjs'
const { chromium } = await import(PLAYWRIGHT_CORE)
import { execFileSync } from 'node:child_process'
import { mkdirSync } from 'node:fs'

const FRONT = 'http://localhost:5173'
const API = 'http://localhost:3000'
const EMAIL = process.env.SWEEP_EMAIL || 'vinaoxd@gmail.com'
const EXEC =
  process.env.CHROME_PATH ||
  '/home/vinao/.cache/puppeteer/chrome/linux-150.0.7871.24/chrome-linux64/chrome'
const OUT =
  process.env.OUT_DIR ||
  '/tmp/claude-1000/-home-vinao-workspace-ai9/78cf7ed3-b766-4559-99ac-f61cd18b1f0d/scratchpad/surf'
mkdirSync(OUT, { recursive: true })

const ROTAS = (process.argv[2] || '/carriers,/renegotiations,/risk-controls,/project-availabilities,/indicators,/faq,/help/items,/messages,/admin/contracts')
  .split(',')

function getCode() {
  const out = execFileSync(
    'bin/rails',
    [
      'runner',
      `u = User.find_by(email: ${JSON.stringify(EMAIL)}); c = rand(100000..999999).to_s; LoginCode.create!(destination: u.email, method: 'email', code: c, expires_at: 30.minutes.from_now, attempts: 0, user: u); puts "CODE=#{c}"`,
    ],
    { cwd: '/home/vinao/workspace/ai9/backend', encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }
  )
  return out.match(/CODE=(\d{6})/)[1]
}

/** Mede um painel aberto: esta no body? responde no centro? tem contraste contra o de tras? */
const MEDIR = (seletor) => {
  const painel = document.querySelector(seletor)
  if (!painel) return { achou: false }
  const r = painel.getBoundingClientRect()
  const cx = Math.round(r.left + r.width / 2)
  const cy = Math.round(r.top + Math.min(r.height / 2, 60))
  const noTopo = document.elementFromPoint(cx, cy)
  const cs = getComputedStyle(painel)
  // Ancestral que cria contexto de empilhamento (o defeito da §5.4.4).
  let pai = painel.parentElement
  const prisoes = []
  while (pai && pai !== document.documentElement) {
    const p = getComputedStyle(pai)
    if (
      p.transform !== 'none' ||
      p.filter !== 'none' ||
      p.backdropFilter !== 'none' ||
      (p.opacity !== '' && Number(p.opacity) < 1) ||
      p.isolation === 'isolate' ||
      p.willChange === 'transform'
    ) {
      prisoes.push(`${pai.tagName.toLowerCase()}.${String(pai.className).slice(0, 40)} [transform=${p.transform !== 'none'} backdrop=${p.backdropFilter !== 'none'} opacity=${p.opacity}]`)
    }
    pai = pai.parentElement
  }
  return {
    achou: true,
    noBody: painel.parentElement === document.body || painel.closest('body > div') !== null,
    rect: { t: Math.round(r.top), l: Math.round(r.left), w: Math.round(r.width), h: Math.round(r.height) },
    respondeNoCentro: !!(noTopo && (painel === noTopo || painel.contains(noTopo))),
    quemResponde: noTopo ? `${noTopo.tagName.toLowerCase()}.${String(noTopo.className).slice(0, 50)}` : null,
    bg: cs.backgroundColor,
    cor: cs.color,
    opacidade: cs.opacity,
    prisoes,
    // alvos de toque dentro do painel
    alvosPequenos: [...painel.querySelectorAll('button, a[href], [role="menuitem"], [role="menuitemradio"], [role="option"]')]
      .map((e) => ({ h: Math.round(e.getBoundingClientRect().height), t: (e.textContent || '').trim().slice(0, 24) }))
      .filter((x) => x.h > 0 && x.h < 44),
  }
}

const achados = []

async function rodar(tema) {
  const browser = await chromium.launch({
    executablePath: EXEC,
    headless: true,
    args: ['--no-sandbox', '--disable-gpu'],
  })
  const ctx = await browser.newContext({
    colorScheme: tema,
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
  })
  const page = await ctx.newPage()
  await page.addInitScript((t) => {
    localStorage.setItem('theme-storage', JSON.stringify({ state: { theme: t }, version: 0 }))
    localStorage.setItem('theme', t)
  }, tema)
  await page.goto(`${FRONT}/login`, { waitUntil: 'domcontentloaded' })
  const code = getCode()
  await page.evaluate(
    async ([api, email, c]) => {
      await fetch(`${api}/auth/v1/magic_login/validate_code`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ identifier: email, code: c, method: 'email' }),
      })
    },
    [API, EMAIL, code]
  )

  for (const rota of ROTAS) {
    const slug = rota.replace(/[^a-z0-9]+/gi, '_')
    await page.goto(`${FRONT}${rota}`, { waitUntil: 'domcontentloaded', timeout: 30000 })
    await page.waitForFunction(() => !/Verificando sess/.test(document.body.innerText), null, { timeout: 20000 }).catch(() => {})
    await page.waitForTimeout(2200)

    // 1. folha "Mais" da barra de abas
    const mais = page.locator('nav[aria-label="Navegação principal"] button', { hasText: 'Mais' })
    if (await mais.count()) {
      await mais.first().click()
      await page.waitForTimeout(500)
      const m = await page.evaluate(MEDIR, '[role="dialog"][aria-label="Todos os menus"]')
      achados.push({ tema, rota, superficie: 'MobileNavSheet', ...m })
      await page.screenshot({ path: `${OUT}/${tema}${slug}__nav.png` })
      await page.keyboard.press('Escape')
      await page.waitForTimeout(300)
    } else {
      achados.push({ tema, rota, superficie: 'MobileNavSheet', achou: false, obs: 'sem aba Mais' })
    }

    // 2. seletor de modo do cabecalho
    const modo = page.locator('header button[aria-haspopup="menu"]')
    if (await modo.count()) {
      await modo.first().click()
      await page.waitForTimeout(400)
      const m = await page.evaluate(MEDIR, '[role="menu"][aria-label="Modo do menu"]')
      achados.push({ tema, rota, superficie: 'seletorDeModo', ...m })
      if (rota === ROTAS[0]) await page.screenshot({ path: `${OUT}/${tema}${slug}__modo.png` })
      await page.keyboard.press('Escape')
      await page.waitForTimeout(300)
    }

    // 3. folha de acoes de linha
    const gatilho = page.locator('main button[aria-label*="Ações"], main button[aria-haspopup="menu"]').first()
    if (await gatilho.count()) {
      await gatilho.click({ timeout: 4000 }).catch(() => {})
      await page.waitForTimeout(500)
      const m = await page.evaluate(MEDIR, '[role="dialog"][aria-label^="Ações"]')
      if (m.achou) {
        achados.push({ tema, rota, superficie: 'MobileRowActions', ...m })
        await page.screenshot({ path: `${OUT}/${tema}${slug}__acoes.png` })
        await page.keyboard.press('Escape')
        await page.waitForTimeout(300)
      }
    }

    // 4. primeiro combobox da tela
    const combo = page.locator('main [role="combobox"], main button[aria-haspopup="listbox"]').first()
    if (await combo.count()) {
      await combo.click({ timeout: 4000 }).catch(() => {})
      await page.waitForTimeout(500)
      const m = await page.evaluate(MEDIR, '[role="listbox"]')
      if (m.achou) {
        achados.push({ tema, rota, superficie: 'select', ...m })
        await page.screenshot({ path: `${OUT}/${tema}${slug}__select.png` })
        await page.keyboard.press('Escape')
      }
    }
  }
  await browser.close()
}

await rodar('light')
await rodar('dark')

for (const a of achados) {
  const flag =
    !a.achou ? 'NAO ABRIU' :
    !a.respondeNoCentro ? '<<< ATRAS DE ' + a.quemResponde :
    a.prisoes.length ? '<<< PRESO EM ' + a.prisoes[0] :
    a.alvosPequenos?.length ? `alvos<44: ${a.alvosPequenos.length} (${a.alvosPequenos.slice(0, 3).map((x) => x.h + 'px ' + x.t).join(' | ')})` :
    'ok'
  console.log(`[${a.tema}] ${a.rota.padEnd(24)} ${a.superficie.padEnd(16)} bg=${a.bg || '-'} ${flag}`)
}
console.log('\ncapturas em ' + OUT)
