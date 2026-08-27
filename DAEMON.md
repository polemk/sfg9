# Guia de Deploy como Serviço (Daemon)

Para rodar a aplicação em produção de forma que ela reinicie automaticamente se falhar e persista após o logout do SSH, utilizamos o **Systemd**.

## Pré-requisitos

1.  Ter garantido que as dependências do projeto estão instaladas e o banco migrado (via `bin/prod` uma vez ou manualmente).
2.  Ter o arquivo `bin/prod` funcionando.

## Passo a Passo

### 1. Copiar o arquivo de serviço

Existe um template em `config/ai9.service.example`. Copie-o para o diretório do Systemd:

```bash
sudo cp config/ai9.service.example /etc/systemd/system/ai9.service
```

### 2. Configurar o serviço

**É OBRIGATÓRIO editar o arquivo** para refletir os caminhos reais do seu servidor (o Systemd não aceita caminhos relativos ou variáveis de ambiente de usuário).

```bash
sudo nano /etc/systemd/system/ai9.service
```

Altere as seguintes linhas:

- **User/Group**: Usuário que roda o projeto (ex: `ubuntu`, `deploy`, `vinao`).
- **WorkingDirectory**: Caminho **absoluto** da pasta raiz do projeto.
  - Ex: `/home/ubuntu/apps/ai9`
- **ExecStart**: Caminho **absoluto** para o script `bin/prod`.
  - Ex: `/home/ubuntu/apps/ai9/bin/prod`

### 3. Ativar e Iniciar

Recarregue o Systemd para ler o novo arquivo, habilite o início automático no boot e inicie o serviço:

```bash
sudo systemctl daemon-reload
sudo systemctl enable ai9
sudo systemctl start ai9
```

### 4. Verificar Status e Logs

Para ver se está rodando:

```bash
sudo systemctl status ai9
```

Para ver os logs (Rails, Vite, Sidekiq) em tempo real:

```bash
sudo journalctl -u ai9 -f
```

### Comandos Úteis

- **Reiniciar**: `sudo systemctl restart ai9`
- **Parar**: `sudo systemctl stop ai9`
