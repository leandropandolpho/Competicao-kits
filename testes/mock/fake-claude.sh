#!/usr/bin/env bash
# Claude simulado (Linux/macOS, só para validação local do harness).
# Sem "exec", para existir um processo pai e um filho, como no .cmd do Windows.
pwsh -NoProfile -File "$(dirname "$0")/fake-claude.ps1" "$@"
exit $?
