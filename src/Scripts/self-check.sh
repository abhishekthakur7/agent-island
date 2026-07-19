#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
cd "$ROOT"

# Headless evidence capture: negotiates, delivers, and validates every
# AB-118 required-evidence scenario through the real ApplicationRuntime and
# SessionStore, without opening a window. See Evidence/README.md.
swift run AgentIslandApp --self-check
