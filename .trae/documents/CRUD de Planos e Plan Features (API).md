## Objetivo

Criar uma página pública em `/build`, com o mesmo layout/tema da Home, exibindo o conteúdo do README do repositório.

## Rotas

* Adicionar rota pública: `path: "/build"` em `frontend/src/app/App.tsx` fora do `ProtectedRoute`.

* Não adicionar links de navegação para `/build` em nenhum lugar (apenas acesso digitando a URL).

## Página `BuildPage`

* Criar `frontend/src/app/pages/BuildPage.tsx` reutilizando o topo/tema da `HomePage` (toggle de tema, marca, container, cores e gradientes).

* Estrutura: header igual ao da Home + seção principal com título e o conteúdo renderizado do README.

## Renderização do README.md

* Importar o arquivo do repositório como string com Vite: `import readme from '../../../README.md?raw'`.

* Usar `react-markdown` + `remark-gfm` para converter e renderizar Markdown com componentes estilizados (h1–h4, p, ul/ol, code) seguindo a paleta atual (dark/light).

* Aplicar classes Tailwind consistentes com a Home (tipografia, espaçamento, cores) sem vínculos na navegação.

## Ajuste Vite (dev)

* Permitir importar arquivo fora de `frontend/` no dev server adicionando `server.fs.allow` ao `vite.config.ts` para englobar a raiz do monorepo.

## Segurança/Acesso

* Página pública (sem guard); manter rotas protegidas como estão.

* Garantir que `/build` não aparece em menus/links, mantendo o requisito “apenas digitando /build”.

## Validação

* Rodar `pnpm dev` e acessar `http://localhost:5173/build` para verificar tema, layout e renderização completa do README.

* Testar também build de produção (`pnpm build`) e servir via Rails (`backend/public`) acessando `/build` diretamente.

## Arquivos a alterar/criar

* Alterar: `frontend/src/app/App.tsx` (nova rota).

* Criar: `frontend/src/app/pages/BuildPage.tsx`.

* Alterar: `frontend/vite.config.ts` (incluir `server.fs.allow`).

