#!/usr/bin/env bash
# Make the graphify git hooks run OUR pipeline, not just graphify's raw rebuild.
#
# The hooks installed by `graphify hook install` rebuild graphify-out/graph.json from the
# extractor alone on every commit and branch switch. That is the naive graph: ~31% Ruby call
# recall, false cross-language edges, undirected, unnamed communities. Left alone, the hook
# silently reverts the curated artifact every time someone commits.
#
# This patches the hooks so the curated pipeline runs immediately after the raw rebuild,
# inside the same detached process. Re-run this after `graphify hook install` ever runs again.
#
#   tools/graphify/install-hook.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

python3 - <<'PATCH'
import sys
from pathlib import Path

# post-commit and post-checkout call _rebuild_code with different signatures
ANCHORS = [
    "    _rebuild_code(_root, changed_paths=changed, force=_force)\n",
    "    _rebuild_code(_root, force=_force)\n",
]
MARKER = "# ai9-curated-pipeline"

INSERT = """
    # ai9-curated-pipeline: graphify's raw rebuild has ~31% Ruby call recall and emits
    # false cross-language edges. Re-apply the verified pipeline on top of it, or the
    # hook reverts the curated graph on every commit. See tools/graphify/README.md.
    try:
        import subprocess as _sp
        _pipe = _root / 'tools' / 'graphify'
        # Runs unconditionally: the trigger is that the raw rebuild ran, not that code
        # changed. Skipping on a docs-only commit still leaves the raw graph in place,
        # which is the exact regression this block exists to prevent.
        if (_pipe / 'verify.py').is_file():
            for _step in ('01_inject_semantic.py', '02_prune.py', '03_add_ruby_calls.py', '03b_add_ts_imports.py',
                          '04_build_directed.py', '05_label.py'):
                _sp.run([sys.executable, str(_pipe / 'steps' / _step)],
                        cwd=str(_root), check=True)
            _sp.run([sys.executable, str(_pipe / 'verify.py')], cwd=str(_root), check=True)
            # graphify's watch path skips graph.html above 5000 nodes and leaves it
            # deleted; the exporter aggregates by community instead, so ask for it.
            try:
                _sp.run(['graphify', 'export', 'html'], cwd=str(_root), check=False)
            except Exception:
                pass
            print('[graphify hook] curated pipeline applied and verified', flush=True)
        else:
            print('[graphify hook] tools/graphify not found - left the raw graph in place', flush=True)
    except Exception as _exc:
        print('[graphify hook] CURATED PIPELINE FAILED: %s' % _exc, flush=True)
"""

# The block is spliced into a Python string that itself sits inside a shell
# DOUBLE-QUOTED argument. A backtick or a double quote in there - even inside a Python
# comment - is interpreted by the shell, which truncates the script and breaks the hook
# at runtime while still passing `sh -n`. Both have bitten this file already.
FORBIDDEN = {chr(96): 'backtick (shell command substitution)',
             chr(34): 'double quote (closes the shell string)',
             chr(36): 'dollar (shell expansion)',
             chr(92): 'backslash (shell escape)'}
_bad = sorted(reason for ch, reason in FORBIDDEN.items() if ch in INSERT)
if _bad:
    sys.exit('INSERT block contains characters the shell will eat: ' + '; '.join(_bad))

# graphify's own hook template exports PYTHONHASHSEED but not PYTHONUTF8. Without UTF-8
# mode the extractor reads .md with the locale encoding and accented Portuguese headings
# become mojibake node ids, so every hook rebuild churns the graph. Add it if missing.
ENV_ANCHOR = "export PYTHONHASHSEED=0

# ai9: a reconstrucao roda em segundo plano DENTRO do repositorio e os comandos
# git que ela faz pegam o lock do indice oportunisticamente (o refresh de
# `git status`/`git diff`). Medido: o `.git/index.lock` aparece ~55s depois do
# commit e some sozinho — mas um `git add` que caia nessa janela falha com
# "Another git process seems to be running", e um lock de 0 byte fica para tras
# se o processo morre ali dentro. Aconteceu tres vezes em uma manha.
#
# `GIT_OPTIONAL_LOCKS=0` e a variavel do proprio git para isto: o comando le o
# indice sem tentar reescreve-lo. Nao desliga nada de que a reconstrucao precise
# — ela so LE o repositorio.
export GIT_OPTIONAL_LOCKS=0
"
ENV_ADD = ("export PYTHONHASHSEED=0

"
           "# ai9: force UTF-8 so accented markdown headings do not become corrupt node ids.
"
           "export PYTHONUTF8=1
")

patched, skipped, missing = [], [], []
for name in ('post-commit', 'post-checkout'):
    hook = Path('.git/hooks') / name
    if not hook.is_file():
        missing.append(name)
        continue
    text = hook.read_text(encoding='utf-8')
    if MARKER in text:
        skipped.append(name)
        continue
    anchor = next((a for a in ANCHORS if a in text), None)
    if anchor is None:
        print('  ! %s: anchor not found - graphify may have changed the hook template' % name)
        print('    patch it by hand, or the curated graph will be reverted on every commit')
        continue
    text = text.replace(anchor, anchor + INSERT, 1)
    if 'PYTHONUTF8' not in text and ENV_ANCHOR in text:
        text = text.replace(ENV_ANCHOR, ENV_ADD, 1)
    hook.write_text(text, encoding='utf-8')
    patched.append(name)

for name in patched:
    print('  patched  .git/hooks/%s' % name)
for name in skipped:
    print('  already  .git/hooks/%s' % name)
for name in missing:
    print('  absent   .git/hooks/%s (nothing to patch)' % name)
if not patched and not skipped:
    sys.exit(1)
PATCH

echo
echo "Hooks now run tools/graphify/rebuild.sh's steps after graphify's raw rebuild."
echo "To skip a rebuild for one command:  GRAPHIFY_SKIP_HOOK=1 git commit ..."
