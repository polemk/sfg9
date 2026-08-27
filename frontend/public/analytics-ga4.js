/*
 * Google Analytics 4 — DEC-87.
 *
 * Este arquivo existe no repositorio e NAO faz nada por padrao. Ele so e referenciado
 * pelo `index.html` quando `VITE_GA_ENABLED=true` no build (ver `vite.config.ts`), e
 * mesmo referenciado NAO carrega o gtag.js ate haver consentimento explicito.
 *
 * Por que tanto cuidado, em ordem de importancia:
 *
 * 1. **O do legado esta quebrado e ninguem percebeu.** O ID e GA4
 *    (`GOOGLE_ANA_APP_ID = "G-7E78XXZX5X"`, `SFG/metadata.rb:7`) e o snippet e
 *    Universal Analytics (`livetat/analytics/_google.js.erb:1-8`, `analytics.js` +
 *    `ga('create', ...)`). Um ID `G-` nao funciona com `ga()`: hoje o legado nao
 *    coleta absolutamente nada. O que entra aqui e o snippet GA4 CORRETO.
 * 2. **Sem consentimento nao ha coleta.** No legado o snippet e injetado na primeira
 *    linha de quatro entrypoints, sem consentimento nenhum. Sistema interno com dado
 *    financeiro mandando telemetria a terceiro e decisao do cliente, nao default.
 * 3. **O CSP e a segunda trava.** Enquanto a flag estiver desligada, a politica de
 *    `csp.config.ts` NAO libera `googletagmanager.com` nem `google-analytics.com`.
 *    Ligar a coleta exige mexer nos dois lugares.
 *
 * PENDENTE, e a pendencia e do produto, nao deste arquivo: a interface que pede o
 * consentimento. Enquanto ela nao existir, `grantConsent()` nunca e chamado e nada e
 * enviado — que e o comportamento correto para quem esta desligado.
 */
;(function () {
  'use strict'

  var script = document.currentScript
  var measurementId = (script && script.getAttribute('data-measurement-id')) || ''

  window.dataLayer = window.dataLayer || []
  function gtag() {
    window.dataLayer.push(arguments)
  }
  window.gtag = gtag

  // Consent Mode v2: tudo negado ANTES de qualquer coisa. Se um dia o gtag.js for
  // carregado sem passar por `grantConsent`, ele ja nasce sem permissao de gravar.
  gtag('consent', 'default', {
    ad_storage: 'denied',
    ad_user_data: 'denied',
    ad_personalization: 'denied',
    analytics_storage: 'denied',
    functionality_storage: 'denied',
    personalization_storage: 'denied',
    security_storage: 'granted',
    wait_for_update: 500,
  })

  var loaded = false

  function loadGtag() {
    if (loaded || !measurementId) return
    loaded = true

    var tag = document.createElement('script')
    tag.async = true
    tag.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(measurementId)
    document.head.appendChild(tag)

    gtag('js', new Date())
    gtag('config', measurementId, { anonymize_ip: true })
  }

  window.sfgAnalytics = {
    measurementId: measurementId,
    isLoaded: function () {
      return loaded
    },
    /** Chamado pela interface de consentimento. So aqui o gtag.js entra na pagina. */
    grantConsent: function () {
      gtag('consent', 'update', { analytics_storage: 'granted' })
      loadGtag()
    },
    revokeConsent: function () {
      gtag('consent', 'update', { analytics_storage: 'denied' })
    },
  }
})()
