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

Once a day eva checks GitHub for a newer release in the background. When one
is out, a command adds a line on stderr, at most once a day per version, and
`eva --version` and `eva context` show it every time:
`eva 0.10.0 is out (you have 0.9.0); update with: eva upgrade`. The check sends
no token and no EvaTeam address. `EVA_NO_UPDATE_CHECK=1` turns it off; it is
off when `CI` is set.

## Signing in

The user creates a token in EvaTeam («Моя страница» → «Безопасность» →
«Сгенерировать API токен» → «Создать токен API»; EvaTeam's guide with
screenshots: https://docs.evateam.ru/docs/DOC-000200) and runs, in their own terminal:

```bash
eva auth login                       # asks for the address and, without echo, the token
eva auth login --profile sandbox --url https://eva-test.company.ru
```

eva checks the token against the server, then stores the address and token in
the OS keychain under a profile (`default` unless named). Suggest the command;
the user types the token. It never goes into the conversation, a command line
you run, or a file you write: each of those keeps a copy.

```bash
eva auth status                      # profiles, the account each signs in as
eva auth use sandbox                 # change the default profile
eva --profile sandbox task get X     # one command against another profile
eva auth logout --profile sandbox    # remove it from the keychain
```

On a Mac, macOS asks once whether a newly installed or upgraded eva may read
its keychain item: each build is a new program to the keychain. In a terminal
that is a dialog to answer with Always Allow. Run through an agent, eva cannot
show it and stops with "macOS wants to ask first"; ask the user to run
`eva auth status` in their own terminal and choose Always Allow, then retry.

A Linux machine without a Secret Service (a server, a container) has no
keychain. There `auth login` says so, and the user sets `EVA_URL` and
`EVA_API_KEY` in the environment, or in `~/.config/eva-cli/env` with
`chmod 600`. CI does the same with its secret store.

## Errors that are protections

eva refuses some setups on purpose. Read the message; it says what to change.

- `… sets EVA_URL but not EVA_API_KEY`: the address and the token must come
  from the same place, so a `.env` in some repository cannot redirect the
  user's saved token. Ask the user which EvaTeam they meant.
- `… is plain http, which would send the token unencrypted`: use the https
  address.
- `… redirects … eva does not follow it with your token`: the address moved;
  the user signs in to the new one.
- `warning: … other users can read it`: a token file with loose permissions;
  suggest `chmod 600` or moving to `eva auth login`.

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
      "Bash(eva task path:*)",
      "Bash(eva task history:*)",
      "Bash(eva task time:*)",
      "Bash(eva task dev:*)",
      "Bash(eva task checklist:*)",
      "Bash(eva task attachments:*)",
      "Bash(eva time list:*)",
      "Bash(eva time report:*)",
      "Bash(eva field list:*)",
      "Bash(eva field get:*)",
      "Bash(eva attachment get:*)",
      "Bash(eva attachment download:*)",
      "Bash(eva project list:*)",
      "Bash(eva project get:*)",
      "Bash(eva resolution list:*)",
      "Bash(eva person list:*)",
      "Bash(eva doc list:*)",
      "Bash(eva doc get:*)",
      "Bash(eva doc comments:*)",
      "Bash(eva doc attachments:*)",
      "Bash(eva doc children:*)",
      "Bash(eva doc history:*)",
      "Bash(eva doc followers:*)",
      "Bash(eva doc download-all:*)",
      "Bash(eva sprint list:*)",
      "Bash(eva sprint get:*)",
      "Bash(eva release list:*)",
      "Bash(eva release get:*)",
      "Bash(eva relation types:*)",
      "Bash(eva tag list:*)",
      "Bash(eva component list:*)",
      "Bash(eva filter list:*)",
      "Bash(eva notify list:*)",
      "Bash(eva repo list:*)",
      "Bash(eva search:*)",
      "Bash(eva testcase list:*)",
      "Bash(eva testcase get:*)",
      "Bash(eva testplan list:*)",
      "Bash(eva testplan get:*)",
      "Bash(eva ticket get:*)",
      "Bash(eva trash list:*)",
      "Bash(eva schema:*)",
      "Bash(eva context:*)",
      "Bash(eva cheatsheet:*)",
      "Bash(eva config:*)",
      "Bash(eva help:*)",
      "Bash(eva completion:*)",
      "Bash(eva auth status:*)",
      "Bash(eva --help:*)",
      "Bash(eva --version:*)"
    ],
    "ask": [
      "Bash(eva task create:*)",
      "Bash(eva task update:*)",
      "Bash(eva task delete:*)",
      "Bash(eva task attach:*)",
      "Bash(eva task move:*)",
      "Bash(eva task comment:*)",
      "Bash(eva task comment-edit:*)",
      "Bash(eva task comment-delete:*)",
      "Bash(eva task log:*)",
      "Bash(eva task watch:*)",
      "Bash(eva task unwatch:*)",
      "Bash(eva task link:*)",
      "Bash(eva task unlink:*)",
      "Bash(eva task check:*)",
      "Bash(eva task bulk:*)",
      "Bash(eva time log:*)",
      "Bash(eva time delete:*)",
      "Bash(eva attachment delete:*)",
      "Bash(eva doc create:*)",
      "Bash(eva doc update:*)",
      "Bash(eva doc publish:*)",
      "Bash(eva doc comment:*)",
      "Bash(eva doc comment-edit:*)",
      "Bash(eva doc attach:*)",
      "Bash(eva doc watch:*)",
      "Bash(eva sprint add:*)",
      "Bash(eva release add:*)",
      "Bash(eva trash restore:*)",
      "Bash(eva call:*)",
      "Bash(eva upgrade:*)",
      "Bash(eva auth login:*)",
      "Bash(eva auth use:*)",
      "Bash(eva auth logout:*)"
    ]
  }
}
```

`eva call` sits under `ask` because it reaches every API method, writes
included. Commands also answer to aliases (`task show`, `task ls`, `tasks`,
`people`); the list names only the main forms, so an alias falls back to being
asked about. Use the main forms.
