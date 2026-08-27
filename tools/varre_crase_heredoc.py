"""Crase que o bash EXECUTA sem querer, em dois lugares que parecem inofensivos.

Este defeito chegou a producao em 27/08/2026, no meio de um deploy:

    ./install.sh: line 142: required_env.rb: command not found
    ./install.sh: line 142: wss: command not found

Eram COMENTARIOS dentro do heredoc que gera o `.env`. O heredoc tem de ser sem
aspas para expandir ${API_DOMAIN} — e sem aspas o bash tambem executa crase,
inclusive em linha comentada.

Horas depois eu repeti o erro noutra forma: crase dentro de `echo "..."`. Aspas
duplas nao protegem crase. Por isso a varredura olha os DOIS casos.

Nao adianta reler com atencao: nos dois a crase PARECE documentacao. Rodar isto
custa nada:

    python3 tools/varre_crase_heredoc.py

Sai com codigo 1 se achar alguma.
"""
import io
import re
import sys

ABRE_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")

# `echo "... ` ... "` — crase dentro de string de aspas duplas.
ECHO_COM_CRASE = re.compile(r'echo\s+[^\'\n]*"[^"\n]*`')

ARQUIVOS = (
    "install.sh",
    "install_dev.sh",
    "renew_cert.sh",
    "bin/prod",
    "bin/dev",
)

total = 0
for caminho in ARQUIVOS:
    try:
        linhas = io.open(caminho, encoding="utf-8").read().split("\n")
    except FileNotFoundError:
        print(f"{caminho}: nao encontrado (rode na raiz do repositorio)")
        continue

    marcador = None
    protegido = False
    achados = []

    for numero, linha in enumerate(linhas, 1):
        if marcador is None:
            # Fora de heredoc: o risco e crase em `echo "..."`.
            if ECHO_COM_CRASE.search(linha):
                achados.append((numero, "echo com crase", linha.strip()[:60]))

            encontrado = ABRE_HEREDOC.search(linha)
            if encontrado:
                protegido = encontrado.group(1) != ""
                marcador = encontrado.group(2)
            continue

        if linha.strip() == marcador:
            marcador = None
            continue

        if not protegido and "`" in linha:
            achados.append((numero, "heredoc sem aspas", linha.strip()[:60]))

    total += len(achados)
    print(f"{caminho}: {len(achados)} ocorrencia(s)")
    for numero, tipo, texto in achados:
        print(f"    linha {numero} ({tipo}): {texto}")

sys.exit(1 if total else 0)
