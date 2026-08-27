"""Crase dentro de heredoc SEM aspas vira execucao de comando.

Este defeito chegou a producao em 27/08/2026, no meio de um deploy:

    ./install.sh: line 142: required_env.rb: command not found
    ./install.sh: line 142: wss: command not found
    ./install.sh: line 142: ws: command not found

Eram COMENTARIOS dentro do heredoc que gera o `.env`. O heredoc tem de ser sem
aspas para expandir ${API_DOMAIN} — e sem aspas o bash tambem executa crase,
inclusive em linha comentada. As variaveis sairam certas; as palavras entre
crases sumiram, e o erro apareceu na tela de quem estava instalando.

Nao adianta reler o arquivo com atencao: a crase PARECE documentacao. Rodar isto
custa nada:

    python3 tools/varre_crase_heredoc.py

Sai com codigo 1 se achar alguma.
"""
import io
import re
import sys

ABRE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")

ARQUIVOS = (
    "install.sh",
    "install_dev.sh",
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
            encontrado = ABRE.search(linha)
            if encontrado:
                protegido = encontrado.group(1) != ""
                marcador = encontrado.group(2)
            continue

        if linha.strip() == marcador:
            marcador = None
            continue

        if not protegido and "`" in linha:
            achados.append((numero, linha.strip()[:70]))

    total += len(achados)
    print(f"{caminho}: {len(achados)} crase(s) dentro de heredoc sem aspas")
    for numero, texto in achados:
        print(f"    linha {numero}: {texto}")

sys.exit(1 if total else 0)
