-- ============================================================================
-- Safegold — consultas ao banco LEGADO de producao
-- ============================================================================
-- Rode TUDO de uma vez e me mande a saida inteira, na ordem.
-- Sao 8 perguntas que nao precisam de opiniao, precisam de um numero: juntas
-- elas resolvem 27 IDs de inventario que hoje estao parados.
--
-- Tudo aqui e SOMENTE LEITURA. Nao ha INSERT, UPDATE, DELETE nem DDL.
-- Pode rodar em replica ou no dump restaurado; nao precisa ser o primario.
--
-- Como rodar:  psql "<url-do-banco-legado>" -f consultas-producao.sql
-- ============================================================================

\echo '=== 1) availability_templates — a coluna default_position existe? ==='
-- Nenhuma migration a cria, e mesmo assim tres views e o controller a usam.
-- Se NAO existir, a busca de padroes globais esta quebrada ha anos.
-- Se existir, ha schema fora do versionamento e a DEC-04 precisa ser revisitada.
\d availability_templates


\echo '=== 2) resource_kinds tem uso? (decide 9 IDs) ==='
SELECT count(*) AS resource_kind_em_uso
  FROM receivable_entries
 WHERE resource_kind_id IS NOT NULL;


\echo '=== 3) geolocations tem linhas? (decide 12 IDs) ==='
SELECT count(*) AS geolocations FROM geolocations;


\echo '=== 4) posicao diaria de risco tem dado? (decide a fatia R8 inteira) ==='
SELECT count(*) AS risk_entries FROM risk_entries;


\echo '=== 5) sobrou limite no formato pre-2022, sem tipo? ==='
-- Linha sem tipo SOME de todos os agregados do ai9 — viraria numero errado
-- em silencio, que e o pior tipo de erro num sistema de credito.
SELECT count(*) AS risk_controls_sem_tipo
  FROM risk_controls
 WHERE risk_operation_type_id IS NULL;


\echo '=== 6) alguem entra hoje digitando USERNAME em vez de e-mail? ==='
-- POSSIVEL BLOQUEADOR DE CUTOVER: no ai9 a identificacao e e-mail ou telefone.
-- Se der > 0, essas pessoas ficam sem conseguir entrar no dia da virada.
SELECT count(*) AS so_tem_username
  FROM users
 WHERE username IS NOT NULL
   AND username <> ''
   AND (email IS NULL OR email = '' OR email NOT LIKE '%@%');


\echo '=== 7) quem foi rebaixado a Gerente pela precedencia invertida de 2021? ==='
-- Esta e uma LISTA para revisao humana, nao uma contagem.
-- Promocao automatica nunca: quem volta a ser Admin voce decide na mao.
SELECT id, username, email
  FROM users
 WHERE is_staff = true AND is_superuser = true
 ORDER BY id;


\echo '=== 8) existe remuneracao com taxa fora de 0-100? ==='
-- A taxa multiplica TODO o faturamento e hoje nao tem validacao nenhuma.
SELECT count(*) AS fora_da_faixa,
       min(value)  AS menor,
       max(value)  AS maior
  FROM remunerations
 WHERE value < 0 OR value > 100;

\echo '=== fim ==='
