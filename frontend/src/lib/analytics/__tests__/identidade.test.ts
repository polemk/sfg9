import { beforeEach, describe, expect, it } from 'vitest';

import { guardarToque, sessionId, toqueGuardado, visitorId } from '../identidade';

// A âncora da captação. Ver docs/CAPTACAO-PADRONIZADA.md.
//
// Este arquivo existe porque a regra do toque escapou solta dentro do
// AnalyticsProvider e fabricou, em PRODUÇÃO, uma origem que nunca aconteceu.
describe('identidade', () => {
    beforeEach(() => {
        localStorage.clear();
        sessionStorage.clear();
        document.cookie.split(';').forEach((c) => {
            document.cookie = `${c.split('=')[0].trim()}=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/`;
        });
    });

    describe('a pessoa', () => {
        it('é a mesma entre chamadas', () => {
            expect(visitorId()).toBe(visitorId());
        });

        it('espelha no cookie e no localStorage', () => {
            const id = visitorId();

            expect(localStorage.getItem('ai9_visitor_id')).toBe(id);
            expect(document.cookie).toContain(`ai9_visitor_id=${id}`);
        });

        // Uma limpeza que zera só um dos dois lados não pode inventar pessoa
        // nova: quem sobreviveu reescreve o outro.
        it('se reconstrói do cookie quando o localStorage some', () => {
            const id = visitorId();
            localStorage.clear();

            expect(visitorId()).toBe(id);
        });

        it('se reconstrói do localStorage quando o cookie some', () => {
            const id = visitorId();
            document.cookie = 'ai9_visitor_id=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/';

            expect(visitorId()).toBe(id);
        });
    });

    describe('a visita', () => {
        it('continua a mesma dentro da janela', () => {
            expect(sessionId()).toBe(sessionId());
        });

        it('abre uma nova depois de 30 minutos de silêncio', () => {
            const primeira = sessionId();
            const passado = Date.now() - 31 * 60 * 1000;
            localStorage.setItem('ai9_session_last_seen', String(passado));

            expect(sessionId()).not.toBe(primeira);
        });

        it('não confunde a visita com a pessoa', () => {
            const pessoa = visitorId();
            localStorage.setItem('ai9_session_last_seen', String(Date.now() - 31 * 60 * 1000));
            sessionId();

            expect(visitorId()).toBe(pessoa);
        });
    });

    describe('o toque', () => {
        // O defeito que chegou a produção: o toque era mesclado campo a campo,
        // então quem chegou por story do Instagram e voltou por um link do
        // Google — que não carrega criativo — ficava com utm_source=google
        // levando o utm_content do story. Uma origem que nunca existiu.
        it('substitui o toque anterior INTEIRO', () => {
            guardarToque({ utm_source: 'instagram', utm_campaign: 'lancamento', utm_content: 'story-b' });

            const agora = guardarToque({ utm_source: 'google', utm_campaign: 'busca' });

            expect(agora).toEqual({ utm_source: 'google', utm_campaign: 'busca' });
            expect(agora.utm_content).toBeUndefined();
            expect(toqueGuardado()).toEqual(agora);
        });

        // Navegação interna não traz parâmetro. Apagar aqui perderia de onde a
        // pessoa veio no meio da própria visita.
        it('mantém o toque quando não vem parâmetro nenhum', () => {
            const chegada = { utm_source: 'instagram', utm_content: 'story-b' };
            guardarToque(chegada);

            expect(guardarToque({})).toEqual(chegada);
            expect(toqueGuardado()).toEqual(chegada);
        });

        it('começa vazio', () => {
            expect(toqueGuardado()).toEqual({});
        });

        it('aceita um toque só com click id, sem utm', () => {
            const agora = guardarToque({ gclid: 'Gcl123' });

            expect(agora).toEqual({ gclid: 'Gcl123' });
        });
    });
});
