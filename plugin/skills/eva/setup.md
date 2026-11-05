# Installing, configuring, permissions

## Getting the binary

The skill is documentation; eva is a separate program. Offer these and let the
user pick:

```bash
curl -fsSL https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh | sh
uv tool install evateam-cli          # or: uvx --from evateam-cli eva --help
pipx install evateam-cli
pixi global install -c https://prefix.dev/ormeilu/ormeilu -c https://conda.modular.com/max -c conda-forge evateam-cli
mise use -g github:ormeilu/evateam-cli
```

Builds exist for macOS 13+ on Apple silicon and Linux x86_64 and arm64 with
glibc 2.34+; nothing else on the machine is needed. The PyPI package is
`evateam-cli`; the command is `eva`. `eva upgrade` updates it the same way it
was installed, and `eva --version` says what is there.

## The address and the token

eva reads two settings, from the environment first, then `./.env`, then
`~/.config/eva-cli/env`, as `KEY=value` lines:

```
EVA_URL=https://eva.company.ru
EVA_API_KEY=...
```

The URL is the one the user opens EvaTeam at; a trailing `/api` is fine. The
token is created by the user in EvaTeam: «Моя страница» → «Безопасность» →
«Сгенерировать API токен». It acts with their permissions.

The token reaches eva through a file the user writes or a variable the user
exports. Ask them to put it in `~/.config/eva-cli/env` themselves; it never goes
through the conversation, into a command line you run, or into a file you
write, since all three leave copies behind. `eva config` then confirms it is
set without printing it.

## Certificates

eva checks the server's certificate against the system's CA bundle. When the
error mentions a certificate and the user's EvaTeam is signed by a corporate
CA, ask them for that CA's PEM file and set `EVA_CA_BUNDLE=/path/to/ca.pem`.
`EVA_INSECURE=1` turns verification off entirely; it is the user's decision,
for a server they know, not a fix to reach for.

## Permission allowlists

eva's commands split cleanly into ones that read and ones that write, so a
static allowlist is safe. For Claude Code, in `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(eva task get:*)",
      "Bash(eva task list:*)",
      "Bash(eva task comments:*)",
      "Bash(eva task links:*)",
      "Bash(eva task statuses:*)",
      "Bash(eva project list:*)",
      "Bash(eva person list:*)",
      "Bash(eva doc list:*)",
      "Bash(eva doc get:*)",
      "Bash(eva config:*)",
      "Bash(eva --help:*)",
      "Bash(eva --version:*)"
    ],
    "ask": [
      "Bash(eva task create:*)",
      "Bash(eva task update:*)",
      "Bash(eva task move:*)",
      "Bash(eva task comment:*)",
      "Bash(eva task log:*)",
      "Bash(eva call:*)",
      "Bash(eva upgrade:*)"
    ]
  }
}
```

`eva call` sits under `ask` because it reaches every API method, writes
included. Commands also answer to aliases (`task show`, `task ls`, `tasks`,
`people`); the list names only the main forms, so an alias falls back to being
asked about. Use the main forms.
