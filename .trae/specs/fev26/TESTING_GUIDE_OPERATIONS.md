# Guia de Testes: Operations, Knowledge & Assets

Este guia ajuda a validar a implementacao completa do sistema de Operations com Knowledge Base e Assets.

---

## Pre-requisitos

1. Backend rodando: `cd backend && rails s`
2. Frontend rodando: `cd frontend && npm run dev`
3. Estar logado como usuario OG (admin)

---

## Teste 1: Acesso ao Menu

**Objetivo:** Verificar se Operations aparece no menu lateral

**Passos:**
1. Acesse http://localhost:5173
2. Faca login como admin
3. Clique no icone de menu (hamburger) no canto superior esquerdo
4. Procure pelo icone de predio (Building2) com tooltip "Operacoes"

**Resultado Esperado:**
- O icone de Operations deve aparecer no menu
- Ao clicar, deve redirecionar para /operations

---

## Teste 2: Listagem de Operations

**Objetivo:** Verificar listagem e criacao de operacoes

**Passos:**
1. Acesse http://localhost:5173/operations
2. Clique em "CADASTRAR"
3. Preencha:
   - Titulo: `Condominio Solar das Palmeiras`
   - Chave: `cond_solar_palmeiras`
   - Descricao: `Operacao para atendimento do condominio`
4. Adicione keywords: `palmeiras`, `solar`, `condominio`
5. Marque "Ativo"
6. Clique no botao de check (salvar)

**Resultado Esperado:**
- Operacao criada com sucesso
- Aparece na lista com status verde (ativo)
- Keywords aparecem como badges

---

## Teste 3: Simulador de Validacao

**Objetivo:** Testar a deteccao semantica de operacoes

**Passos:**
1. Na pagina /operations, use o "Simulador de Validacao"
2. Digite: `Quero saber sobre o condominio palmeiras`
3. Pressione Enter

**Resultado Esperado:**
- Toast de sucesso: "MATCH! Operacao: Condominio Solar das Palmeiras"

---

## Teste 4: Gerenciar Base de Conhecimento

**Objetivo:** Adicionar conhecimento para a IA

**Passos:**
1. Na operacao criada, clique em "Gerenciar IA"
2. Na aba "Base de Conhecimento", cole o texto:

```
O Condominio Solar das Palmeiras e um empreendimento de alto padrao localizado na Zona Sul.

INFORMACOES:
- Endereco: Rua das Palmeiras, 1000
- Apartamentos: 2 e 3 quartos
- Valores: a partir de R$ 450.000
- Portaria 24h
- Piscina, academia, salao de festas

CONTATO:
- Telefone: (11) 99999-9999
- WhatsApp: (11) 98888-8888

HORARIOS:
- Plantao de vendas: Seg a Sex 9h-18h, Sabados 9h-13h
```

3. Clique em "Salvar Conhecimento"

**Resultado Esperado:**
- Toast: "Base de conhecimento salva! Indexando na IA..."
- O texto e preservado no campo

---

## Teste 5: Adicionar Assets (Midias)

**Objetivo:** Cadastrar imagens/videos para uso nos chats

**Passos:**
1. No painel de gerenciamento, clique na aba "Midias & Assets"
2. Adicione um asset:
   - URL: `https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?w=400`
   - Titulo: `Foto da Fachada`
   - Tipo: Imagem (PNG)
   - Descricao: `Vista frontal do condominio`
3. Clique "Adicionar Asset"

**Resultado Esperado:**
- Asset aparece na lista com preview da imagem
- Shortcode visivel (ex: `[asset:ABCD123456]`)
- Botao de copiar funciona

---

## Teste 6: Usar Shortcode no Chat

**Objetivo:** Verificar que o asset e exibido corretamente no chat

**Passos:**
1. Copie o shortcode do asset criado
2. Em uma conversa de teste (ou via API), simule uma resposta do agente contendo:
   ```
   Olá! Aqui está a fachada do condomínio: [asset:ABCD123456]
   ```

**Resultado Esperado:**
- O shortcode e substituido pela imagem
- A imagem aparece com preview clicavel
- Clicar abre em lightbox

---

## Teste 7: Protecao contra Shortcodes de Usuario

**Objetivo:** Garantir que usuarios nao podem "injetar" assets

**Passos:**
1. No chat, digite como usuario: `Quero ver [asset:ABCD123456]`

**Resultado Esperado:**
- O texto aparece como string literal `[asset:ABCD123456]`
- NAO e convertido em imagem (apenas respostas do agente sao processadas)

---

## Teste 8: API Endpoints (via curl ou Postman)

### Listar Assets
```bash
curl -H "Authorization: Bearer SEU_TOKEN" \
  http://localhost:3000/api/v1/operations/cond_solar_palmeiras/assets
```

### Criar Asset
```bash
curl -X POST \
  -H "Authorization: Bearer SEU_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"media_url":"https://example.com/img.jpg","mime_type":"image/jpeg","title":"Teste"}' \
  http://localhost:3000/api/v1/operations/cond_solar_palmeiras/assets
```

### Salvar Knowledge
```bash
curl -X POST \
  -H "Authorization: Bearer SEU_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content":"Texto de conhecimento da operacao"}' \
  http://localhost:3000/api/v1/operations/cond_solar_palmeiras/knowledge
```

---

## Checklist Final

- [ ] Menu lateral mostra Operations
- [ ] CRUD de operacoes funciona
- [ ] Simulador de validacao detecta operacoes
- [ ] Base de conhecimento salva e indexa
- [ ] Assets sao cadastrados com shortcode
- [ ] Shortcodes funcionam no chat (apenas agente)
- [ ] Usuario nao consegue injetar shortcodes

---

## Troubleshooting

### Erro 401 Unauthorized
- Verifique se esta logado
- Verifique se e usuario OG/admin

### Assets nao aparecem no chat
- Verifique se o shortcode esta correto
- Verifique se a mensagem e do agente (role: 'agent')

### Knowledge nao indexa
- Verifique os logs do Sidekiq
- Verifique se a API da OpenAI esta configurada

---

*Ultima atualizacao: Marco 2026*
