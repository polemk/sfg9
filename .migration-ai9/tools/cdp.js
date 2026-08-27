// Driver CDP minimo: sobe nada, so conversa com um chromium ja aberto com
// --remote-debugging-port. Usa o `ws` que ja existe no node_modules do front.
const WebSocket = require('/home/vinao/workspace/ai9/frontend/node_modules/ws')
const fs = require('fs')
const OUT = process.env.CDP_OUT || '/tmp/cdp-shots'
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, {recursive: true})

const wsUrl = process.argv[2]
const ws = new WebSocket(wsUrl, { perMessageDeflate: false, maxPayload: 256*1024*1024 })
let id = 0
const pend = new Map()
const send = (method, params={}, sessionId) => new Promise((res, rej) => {
  const m = ++id
  pend.set(m, {res, rej})
  ws.send(JSON.stringify({id: m, method, params, ...(sessionId?{sessionId}:{})}))
})
ws.on('message', (d) => {
  const msg = JSON.parse(d)
  if (msg.id && pend.has(msg.id)) {
    const {res, rej} = pend.get(msg.id); pend.delete(msg.id)
    msg.error ? rej(new Error(method_err(msg))) : res(msg.result)
  }
})
const method_err = (m) => JSON.stringify(m.error)
const sleep = (ms) => new Promise(r => setTimeout(r, ms))

const evalJs = async (expr) => {
  const r = await send('Runtime.evaluate', {expression: expr, awaitPromise: true, returnByValue: true})
  if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails.exception?.description || r.exceptionDetails))
  return r.result.value
}
const shot = async (name) => {
  const r = await send('Page.captureScreenshot', {format: 'png', captureBeyondViewport: false})
  fs.writeFileSync(`${OUT}/${name}.png`, Buffer.from(r.data, 'base64'))
  console.log('  shot:', name)
}

ws.on('open', async () => {
  try {
    await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable')
    await send('Emulation.setDeviceMetricsOverride', {width: 1440, height: 900, deviceScaleFactor: 1, mobile: false})

    const steps = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
    for (const s of steps) {
      if (s.goto) { await send('Page.navigate', {url: s.goto}); await sleep(s.wait || 2500); console.log('  goto:', s.goto) }
      if (s.eval) { const v = await evalJs(s.eval); console.log('  eval:', JSON.stringify(v)?.slice(0, 900)) }
      if (s.sleep) await sleep(s.sleep)
      if (s.shot) await shot(s.shot)
    }
    ws.close(); process.exit(0)
  } catch (e) { console.error('ERRO:', e.message); process.exit(1) }
})
