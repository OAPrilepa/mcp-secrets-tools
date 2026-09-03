#!/bin/bash
# Installs the tools on this machine: symlinks in ~/bin and lists in
# ~/.config/mcp-secrets. Symlinks rather than copies, so `git pull` takes effect
# right away.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/bin"
CONF="$HOME/.config/mcp-secrets"

mkdir -p "$BIN" "$CONF"

for f in "$REPO"/bin/*; do
  name=$(basename "$f")
  target="$BIN/$name"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "install: $target is a regular file, leaving it alone (remove it by hand if needed)" >&2
    continue
  fi
  ln -sfn "$f" "$target"
  echo "install: $target -> $f"
done

for name in vars files; do
  if [ -f "$CONF/$name" ]; then
    echo "install: $CONF/$name already exists, keeping it"
  else
    install -m 600 "$REPO/config/$name.example" "$CONF/$name"
    echo "install: $CONF/$name created"
  fi
done

# the claude shim only works if ~/bin comes before the real claude in PATH
case ":$PATH:" in
  *":$BIN:"*)
    first=$(command -v claude 2>/dev/null || true)
    if [ -n "$first" ] && [ "$first" != "$BIN/claude" ]; then
      echo "WARNING: $first comes first in PATH, not $BIN/claude — move ~/bin up" >&2
    fi
    ;;
  *) echo "WARNING: $BIN is not in PATH — the claude shim will not intercept the run" >&2 ;;
esac

cat <<'EOF'

Done. Add this to ~/.bash_profile and ~/.zshrc (if it is not there yet):

  # MCP server secrets live in the iCloud keychain.
  # `mcp-secrets load` pulls them into the current shell; when Claude Code starts
  # the ~/bin/claude shim does it automatically.
  mcp-secrets() {
    if [ "${1:-}" = "load" ]; then
      eval "$("$HOME/bin/mcp-secrets" export)"
    else
      command "$HOME/bin/mcp-secrets" "$@"
    fi
  }

And make sure ~/bin comes before /opt/homebrew/bin in PATH.
To verify the installation: mcp-secrets check
EOF
