# Configuração do GA4 Server-Side (Measurement Protocol)

Para que a integração via backend funcione (Enviando eventos do Ruby direto para o Google), você precisa de duas chaves: **Measurement ID** e **API Secret**.

Diferente do tracking tradicional (apenas colocar o ID no HTML), o Server-Side exige uma "senha" (API Secret) para autorizar que nosso servidor mande dados em nome dos usuários.

## Passo a Passo

1.  Acesse o [Google Analytics](https://analytics.google.com/).
2.  Vá em **Admin** (ícone da engrenagem no canto inferior esquerdo).
3.  Na coluna **Data collection and modification**, clique em **Data streams** (Fluxos de dados).
4.  Clique no fluxo do seu site (Web).

### 1. Pegando o Measurement ID
Ao abrir os detalhes do fluxo, você verá no topo à direita:
*   **Measurement ID**: `G-XXXXXXXXXX`
*   👉 Copie este valor para a variável `GA4_MEASUREMENT_ID`.

### 2. Criando o API Secret
Na mesma tela de detalhes do fluxo, role para baixo até encontrar a seção **Additional Settings** (Configurações adicionais) ou **Events** (dependendo da versão).
1.  Clique em **Measurement Protocol API secrets**.
2.  Clique no botão **Create** (Criar).
3.  Dê um apelido (ex: "Rails API Backend").
4.  O Google vai gerar uma chave secreta (ex: `a1b2c3d4...`).
*   👉 Copie este valor para a variável `GA4_API_SECRET`.

## Onde Salvar
No arquivo `.env` do backend (ou nas variáveis de produção do Render/Heroku):

```bash
GA4_MEASUREMENT_ID=G-SEU_ID_AQUI
GA4_API_SECRET=SUA_SECRET_AQUI
```

## Como Testar
Após configurar, acesse o site e navegue.
No GA4, vá em **Reports > Realtime**. Você deverá ver os eventos chegando (pode haver um delay de alguns segundos a minutos no server-side, mas no Realtime costuma ser rápido).
