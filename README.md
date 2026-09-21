# mcp-secrets-tools

Keep the secrets your MCP servers need — API tokens, session cookies, OAuth key
files — in the **iCloud keychain** instead of in plain text in `~/.bash_profile`
or `~/.claude.json`.

Items are created with the `kSecAttrSynchronizable` attribute, so they show up on
every Mac signed into the same Apple ID with iCloud Keychain enabled. No manual
copying of secrets between machines.

macOS only.

## How it works

| Component | Role |
|---|---|
| `bin/keychain-icloud` | access to synchronized keychain items: `set` / `get` / `has` / `delete` / `list` / `classes` / `dump` |
| `bin/mcp-secrets` | task-shaped wrapper: list known secrets, `exec` launcher for MCP servers, `export` for the shell, file secrets, migrations |
| `bin/claude` | shim that checks the secrets are readable before a Claude Code run (values stay out of its environment) |
| `config/vars.example` | names of environment-variable secrets (names only, never values) |
| `config/files.example` | names of file secrets (names only, never values) |

Secrets do **not** end up in the environment of ordinary shells, nor in the
environment of Claude Code itself. They appear:

- inside an MCP server — via `mcp-secrets exec`, which replaces `${VAR}` in the
  server's arguments and environment with values from the keychain right before
  `exec`. Each server gets only the secrets its own config names;
- in the current shell on demand — via the `mcp-secrets load` shell function.

Why not load everything into the Claude Code process: every shell command the
agent runs inherits that environment, so one stray `env`, `set` or bare
`export` prints every secret into the transcript. That did happen, hence the
guards: `mcp-secrets export` refuses to write to a terminal or to run inside an
agent session (`CLAUDECODE` / `CODEX_*` set; `MCP_SECRETS_ALLOW_EXPORT=1`
overrides), and `keychain-icloud dump` writes only to a regular file.
`mcp-secrets get NAME` still works — one named secret, asked for on purpose.

In `~/.claude.json` a secret only ever appears as `"${VAR_NAME}"` in `env` (or in
`headers` for http servers).

## Why python and not a binary

`/usr/bin/security` only talks to the file-based `login.keychain`, which is **not**
synchronized through iCloud — the CLI has no synchronization flags at all.
Synchronized items live in the data-protection keychain and require `SecItem*`
calls with `kSecAttrSynchronizable = true`.

Reaching that store requires an entitlement:

- a self-built binary (Swift or otherwise) gets `-34018 errSecMissingEntitlement`;
- ad-hoc signing with `keychain-access-groups` does not help — AMFI kills the
  process (SIGKILL, exit 137);
- Apple-signed `/usr/bin/python3` gets the calls through.

So `keychain-icloud` is a python script with a `#!/usr/bin/python3` shebang that
goes through `ctypes`. Rewriting it in a compiled language, or "simplifying" it
down to `security`, will break it.

## Install

```sh
git clone https://github.com/OAPrilepa/mcp-secrets-tools.git
cd mcp-secrets-tools
./install.sh
```

`install.sh` symlinks `bin/*` into `~/bin`, seeds `~/.config/mcp-secrets/` from
the `.example` lists (existing files are left alone) and prints a shell snippet.
Paste that snippet into `~/.bash_profile` / `~/.zshrc` yourself — it defines the
`mcp-secrets` function, and without it only `mcp-secrets load` stops working; the
`claude` shim does not need it.

Requirements: `~/bin` **before** `/opt/homebrew/bin` in `PATH` (otherwise the
`claude` shim never intercepts the run), Command Line Tools (for
`/usr/bin/python3`), and iCloud Keychain enabled.

Then store the secrets you need — `set` adds the name to
`~/.config/mcp-secrets/vars` on its own — and check:

```sh
mcp-secrets set MY_API_TOKEN
mcp-secrets check
```

Finally, reference them from your MCP config and start the server through
`mcp-secrets exec`. A secret only reaches a server if its config asks for it:

```jsonc
// ~/.claude.json
"my-server": {
  "command": "/Users/you/bin/mcp-secrets",
  "args": ["exec", "/path/to/my-mcp-server", "--flag"],
  "env": { "MY_API_TOKEN": "${MY_API_TOKEN}" }
}
```

Claude Code leaves an unset `${VAR}` as is, so the placeholder reaches
`mcp-secrets exec` untouched; a secret missing from the keychain stops the
server with an explicit error instead of a quiet 401. The same entry works for
Claude Desktop, which does not expand `${VAR}` at all. An http server with a
secret header goes through a stdio bridge such as `mcp-remote` under
`mcp-secrets exec` (`--header "Authorization:Bearer ${TOKEN}"`).

The `claude` shim only verifies before each run that every listed secret is
readable (`mcp-secrets verify`) and warns on stderr otherwise. Ordinary shells
stay clean on purpose; `mcp-secrets load` pulls the values into the current
shell when you actually want them there.

On a second Mac the values arrive with the keychain on their own — only
`./install.sh` is needed there.

## Commands

```sh
mcp-secrets list                      # what is configured, without values
mcp-secrets check                     # everything readable and AfterFirstUnlock?
mcp-secrets verify                    # quick readability check, prints no values
mcp-secrets exec CMD [ARGS...]        # launch an MCP server with ${VAR}s filled in
mcp-secrets set VAR                   # write/update, input hidden
mcp-secrets get NAME                  # print a value
mcp-secrets delete NAME
mcp-secrets export                    # export lines for eval (not on a tty, not in an agent)
mcp-secrets load                      # shell function: load into the current shell

mcp-secrets set-file NAME FILE         # store a file (json key, OAuth token)
mcp-secrets get-file NAME [OUTFILE]    # read it back (into a 0600 file)

mcp-secrets migrate-from-login         # one-off move from the file login.keychain
mcp-secrets migrate-accessible         # re-create items as AfterFirstUnlock
```

`mcp-secrets set VAR_NAME` adds the name to your `vars` list automatically; after
that put `"${VAR_NAME}"` into `~/.claude.json`.

## Notes

- Values are passed on stdin, never as an argument — they do not show up in `ps`.
- `mcp-secrets export` reads the whole keychain in one call (`keychain-icloud
  dump`): ~40 ms for a full set. If even one item of the service is in the
  WhenUnlocked class (`ak`), macOS fails the entire request with `-25308` while
  the screen is locked; `export` then falls back to reading items one by one and
  names the offenders on stderr. Check the class of every item with
  `keychain-icloud classes` (`ck` is the good one), fix it with
  `mcp-secrets migrate-accessible` — `mcp-secrets check` marks such items FAIL.
- Secrets do travel to iCloud. That is the deliberate trade-off for having them
  synchronized across machines.

## License

MIT — see [LICENSE](LICENSE).
