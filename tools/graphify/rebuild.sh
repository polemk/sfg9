#!/usr/bin/env bash
# Rebuild the ai9 knowledge graph.
#
#   tools/graphify/rebuild.sh              post-process the existing graphify-out/graph.json
#   tools/graphify/rebuild.sh --extract    run graphify's AST extraction first, then post-process
#
# Run from the repo root. See tools/graphify/README.md for why each step exists.
set -euo pipefail

# Match the git hooks exactly, or a manual rebuild produces a different graph:
#   PYTHONHASHSEED - Louvain community ids depend on it (3226/5768 nodes moved without it)
#   PYTHONUTF8     - the extractor reads .md with the locale encoding (cp1252 on Windows),
#                    which turns accented Portuguese headings into corrupt node ids
export PYTHONHASHSEED=0
export PYTHONUTF8=1

cd "$(dirname "$0")/../.."

if [ ! -f graphify-out/.graphify_python ]; then
    echo "graphify-out/.graphify_python not found - resolving interpreter" >&2
    PY="$(command -v graphify >/dev/null 2>&1 && head -1 "$(command -v graphify)" | tr -d '#!' || echo python3)"
    mkdir -p graphify-out
    "$PY" -c "import sys; open('graphify-out/.graphify_python','w',encoding='utf-8').write(sys.executable)"
fi
PYTHON="$(cat graphify-out/.graphify_python)"

if [ "${1:-}" = "--extract" ]; then
    echo "00 extract         : running graphify AST extraction (uses its cache; minutes on a WSL share)"
    graphify extract backend/ frontend/
fi

if [ ! -f graphify-out/graph.json ]; then
    echo "graphify-out/graph.json not found. Run with --extract, or run /graphify first." >&2
    exit 1
fi

cp graphify-out/graph.json graphify-out/graph.prev.json
echo "   (previous graph saved to graphify-out/graph.prev.json)"

"$PYTHON" tools/graphify/steps/01_inject_semantic.py
"$PYTHON" tools/graphify/steps/02_prune.py
"$PYTHON" tools/graphify/steps/03_add_ruby_calls.py
"$PYTHON" tools/graphify/steps/03b_add_ts_imports.py
"$PYTHON" tools/graphify/steps/04_build_directed.py
"$PYTHON" tools/graphify/steps/05_label.py

graphify export html

echo
if "$PYTHON" tools/graphify/verify.py; then
    rm -f graphify-out/graph.prev.json
    echo
    echo "Graph rebuilt. Outputs in graphify-out/ (graph.json, graph.html, GRAPH_REPORT.md)."
else
    echo
    echo "VERIFICATION FAILED - graphify-out/graph.prev.json holds the previous graph." >&2
    exit 1
fi
