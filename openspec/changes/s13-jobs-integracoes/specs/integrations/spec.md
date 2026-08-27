## ADDED Requirements

### Requirement: SFG-S13-02 — Portão de decisão da família de geolocalização
O ai9 **MUST NOT** implementar nenhum dos 12 IDs da família de geolocalização (DB-592,
DB-431, DB-480, OPS-481, OPS-482, FE-483, BE-435, BE-436, BE-437, BE-438, BE-439, BE-440)
antes de a contagem de linhas da tabela `geolocations` na origem ter sido **medida e
registrada** em `.migration-ai9/decisions.md`.

Motivo: os 12 estão marcados `build?` em `.migration-ai9/map/data-infra.md` §2.4 e §2.7
porque **nenhum model do legado declara `has_one/has_many :geolocation`** e não há referência
a `geolocatable` fora do próprio model (pergunta **Q-04** do mapa). Construir a família
inteira sobre uma tabela vazia é trabalho perdido; descartá-la sem medir é perda de feature.

Contagem **0** → os 12 **MUST** ser registrados como `dropped` no `parity-ledger.md` com a
contagem como evidência. Contagem **> 0** → os 12 entram, e obrigatoriamente com as três
correções da §2.4: geocoding **fora do `before_save`**, `timeout` expresso em **segundos**
(o legado usa 12000 s ≈ 3h20) e `street_number` como **string** (inteiro perde "123-A" e
"S/N").

OPS-483 (catálogo de estados e cidades do Brasil) **MUST NOT** ser bloqueado por este portão:
o select encadeado País→Estado→Cidade é útil com ou sem geocoding.

#### Scenario: a tabela de origem está vazia
- **GIVEN** que a contagem medida em `geolocations` é 0
- **WHEN** a fatia S13 é executada
- **THEN** nenhum código de geolocalização é escrito e os 12 IDs aparecem como `dropped` no ledger, cada um citando a contagem medida

#### Scenario: a tabela de origem tem dados
- **GIVEN** que a contagem medida em `geolocations` é maior que zero
- **WHEN** a família é implementada
- **THEN** o geocoding roda como job fora do ciclo de save, o timeout é de poucos segundos e `street_number` é string

#### Scenario: o catálogo brasileiro não depende do portão
- **GIVEN** que a decisão de Q-04 ainda não foi tomada
- **WHEN** OPS-483 é implementado
- **THEN** o endpoint de UF e cidades funciona normalmente, sem depender de geocoding
