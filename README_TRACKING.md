# Guia de Rastreamento & Utm_Params - Plataforma Goat (AI9)

Bem-vindo(a) ao guia explicativo para o rastreamento avançado da AI9.

## O que é o parâmetro `?lead_id=`?

Nossa plataforma possui uma inteligência de captura de dados. Sempre que você envia um link pelo seu WhatsApp (ou via automações como Manychat e ActiveCampaign), você pode adicionar o parâmetro `?lead_id=ID_DO_LEAD` ao final da URL.

Por exemplo:
`https://goat.polemk.com/tracking-guide?lead_id=12345`

Quando o usuário clica nesse link e acessa nosso site, ele será automaticamente vinculado ao registro do Lead com o ID `12345`. Isso permite que a AI9 saiba exatamente quem é a pessoa que está visitando, suas interações no site, os botões que clicou, e até o tempo de leitura de cada seção.

### Como usar no Manychat
Se você usa o Manychat, pode criar um botão e inserir o link da seguinte forma:
`https://goat.polemk.com/tracking-guide?lead_id={{id_do_contato_personalizado}}`
> Lembre-se de usar a variável que guarda o ID interno do seu Lead no seu sistema.

### Como usar no ActiveCampaign
No ActiveCampaign, o e-mail de campanha pode conter a tag de personalização:
`https://goat.polemk.com/tracking-guide?lead_id=%SUBSCRIBERID%`

## Script de Rastreamento da AI9

O Script de rastreamento avançado da AI9 opera automaticamente nas páginas do seu site (desde que integrado). Ele captura cliques e rolagens, associando-os ao visitante atual.

Sempre que a visitação ocorre com um `lead_id` na URL, nosso backend armazena as interações na base de dados, montando um "Score" ou histórico para aquele Lead, permitindo ações de retargeting super precisas.

## Dúvidas? Fale com o "Homem dos Dados"

O agente "Homem dos Dados" é um Chatbot configurado nativamente na página `/tracking-guide` para tirar dúvidas em tempo real de forma técnica, mas compreensível, para profissionais de marketing e growth!
