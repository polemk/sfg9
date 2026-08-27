/**
 * A âncora da captação: quem é a PESSOA e qual é a VISITA.
 *
 * Ver docs/CAPTACAO-PADRONIZADA.md. Este arquivo é IDÊNTICO nos três apps
 * (facil, brsw, goat) de propósito — divergir aqui quebra a comparação entre
 * posto e hub.
 *
 * O viewer é a PESSOA, não a aba. É isso que dá sentido a `visits_count`,
 * a `mudou_de_origem?` e à atribuição de primeiro toque: quem vê o story hoje,
 * clica na bio amanhã e volta pelo vídeo depois é UMA pessoa que voltou três
 * vezes. Com a âncora em `sessionStorage` — que morre junto com a aba — cada
 * um desses acessos virava uma pessoa nova, e todo viewer nascia com
 * `visits_count = 1`. O modelo estava certo; a âncora é que não sustentava.
 */

const CHAVE_VISITOR = 'ai9_visitor_id';
const CHAVE_SESSAO = 'ai9_session_id';
const CHAVE_SESSAO_VISTA = 'ai9_session_last_seen';

/**
 * 30 minutos de silêncio encerram a visita. É a MESMA janela que o backend usa
 * em `Viewer::JANELA_DE_VISITA` para decidir se a pessoa "voltou" — se as duas
 * pontas discordarem, o contador de visitas mente.
 */
const JANELA_DE_VISITA_MS = 30 * 60 * 1000;

/** Dois anos: o suficiente para reconhecer quem volta, sem virar eterno. */
const VALIDADE_DO_COOKIE_S = 60 * 60 * 24 * 365 * 2;

function temJanela(): boolean {
    return typeof window !== 'undefined' && typeof document !== 'undefined';
}

function novoId(): string {
    // crypto.randomUUID não existe em navegador antigo nem em http sem TLS.
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
        return crypto.randomUUID();
    }
    return `v-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

function lerCookie(nome: string): string | null {
    if (!temJanela()) return null;
    const achado = document.cookie
        .split('; ')
        .find((par) => par.startsWith(`${nome}=`));
    return achado ? decodeURIComponent(achado.slice(nome.length + 1)) : null;
}

function gravarCookie(nome: string, valor: string) {
    if (!temJanela()) return;
    // SameSite=Lax porque a pessoa chega por link de anúncio (navegação de
    // topo, que o Lax permite); Secure só em https para não sumir no dev local.
    const seguro = window.location.protocol === 'https:' ? '; Secure' : '';
    document.cookie =
        `${nome}=${encodeURIComponent(valor)}; path=/; max-age=${VALIDADE_DO_COOKIE_S}; SameSite=Lax${seguro}`;
}

function lerLocal(chave: string): string | null {
    try {
        return localStorage.getItem(chave);
    } catch {
        // Navegação anônima com storage bloqueado: o cookie segura sozinho.
        return null;
    }
}

function gravarLocal(chave: string, valor: string) {
    try {
        localStorage.setItem(chave, valor);
    } catch {
        /* idem */
    }
}

/**
 * A PESSOA. Sobrevive a fechar a aba, fechar o navegador e voltar semana que vem.
 *
 * Guardado nos DOIS lugares de propósito: o cookie atravessa subdomínio (o mesmo
 * negócio atende em vários) e sobrevive a limpezas que zeram só o storage; o
 * localStorage sobrevive a limpezas que zeram só cookie. Quem existir manda, e
 * o outro é reescrito — assim uma limpeza parcial não cria pessoa nova.
 */
export function visitorId(): string {
    if (!temJanela()) return 'sem-janela';

    const doCookie = lerCookie(CHAVE_VISITOR);
    const doLocal = lerLocal(CHAVE_VISITOR);
    const atual = doCookie || doLocal;

    if (atual) {
        if (!doCookie) gravarCookie(CHAVE_VISITOR, atual);
        if (!doLocal) gravarLocal(CHAVE_VISITOR, atual);
        return atual;
    }

    const novo = novoId();
    gravarCookie(CHAVE_VISITOR, novo);
    gravarLocal(CHAVE_VISITOR, novo);
    return novo;
}

/**
 * A VISITA. Continua a mesma entre abas e depois de fechar o navegador, desde
 * que a pessoa volte dentro da janela; 30 min de silêncio abrem uma visita nova.
 *
 * Chamar isto também RENOVA o relógio — é o "ainda estou aqui".
 */
export function sessionId(): string {
    if (!temJanela()) return 'sem-janela';

    const agora = Date.now();
    const vistaEm = Number(lerLocal(CHAVE_SESSAO_VISTA) || 0);
    const atual = lerLocal(CHAVE_SESSAO);
    const expirou = !vistaEm || agora - vistaEm > JANELA_DE_VISITA_MS;

    const id = atual && !expirou ? atual : novoId();
    if (id !== atual) gravarLocal(CHAVE_SESSAO, id);
    gravarLocal(CHAVE_SESSAO_VISTA, String(agora));
    return id;
}

/** Só renova o relógio da visita, sem devolver nada. */
export function tocarVisita(): void {
    if (!temJanela()) return;
    gravarLocal(CHAVE_SESSAO_VISTA, String(Date.now()));
}

const CHAVE_TOQUE = 'ai9_session_attrs';

/**
 * O TOQUE: de onde a pessoa veio DESTA vez. Mora aqui junto da pessoa e da
 * visita porque é a terceira peça da mesma âncora, e porque a regra abaixo já
 * escapou uma vez por estar solta dentro de um componente.
 *
 * Um toque é ATÔMICO. Chegou parâmetro na URL, é um toque novo e ele substitui
 * o anterior INTEIRO — não se mescla campo a campo. Mesclar fabricava uma
 * origem que nunca existiu: quem chegou por story do Instagram
 * (utm_content=story-b) e voltou por um link do Google, que não carrega
 * criativo, ficava com utm_source=google levando o criativo do story. O
 * backend recebia a quimera já pronta e a gravava fielmente, então consertar
 * só o lado de lá não resolvia.
 *
 * Sem parâmetro nenhum o toque anterior fica de pé: é navegação interna, e
 * apagar aqui perderia de onde a pessoa veio no meio da própria visita.
 */
export function guardarToque(novos: Record<string, string>): Record<string, string> {
    if (!temJanela()) return novos;

    if (Object.keys(novos).length > 0) {
        try {
            sessionStorage.setItem(CHAVE_TOQUE, JSON.stringify(novos));
        } catch {
            /* storage bloqueado: o toque vale só para os eventos desta carga */
        }
        return novos;
    }

    return toqueGuardado();
}

/** O toque em vigor, para os eventos que chegam sem parâmetro na URL. */
export function toqueGuardado(): Record<string, string> {
    if (!temJanela()) return {};
    try {
        return JSON.parse(sessionStorage.getItem(CHAVE_TOQUE) || '{}');
    } catch {
        return {};
    }
}
