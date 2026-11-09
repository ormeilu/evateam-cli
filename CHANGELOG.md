# Changelog

## [0.11.0](https://github.com/ormeilu/evateam-cli/compare/v0.10.3...v0.11.0) (2026-11-09)


### Features

* command table with per-command help, typo suggestions and shell completion ([b9ef259](https://github.com/ormeilu/evateam-cli/commit/b9ef25949797d23cb7bb049897b9086dcaa71366))

## [0.10.3](https://github.com/ormeilu/evateam-cli/compare/v0.10.2...v0.10.3) (2026-11-08)


### Bug Fixes

* conda package tests run eva without the background update check ([cb0d668](https://github.com/ormeilu/evateam-cli/commit/cb0d668c31acb86d0beb2e03e5fc7754d311436b))

## [0.10.2](https://github.com/ormeilu/evateam-cli/compare/v0.10.1...v0.10.2) (2026-11-08)


### Bug Fixes

* workflow transitions with an empty status_from run from any status ([6946d39](https://github.com/ormeilu/evateam-cli/commit/6946d39c83cb0104dbd7d82007161e674b20a126))

## [0.10.1](https://github.com/ormeilu/evateam-cli/compare/v0.10.0...v0.10.1) (2026-11-07)


### Bug Fixes

* the update check verifies GitHub with the system CA bundle ([a61cdc8](https://github.com/ormeilu/evateam-cli/commit/a61cdc81910fa23de01f3bb94add994bc6102a77))

## [0.10.0](https://github.com/ormeilu/evateam-cli/compare/v0.9.1...v0.10.0) (2026-11-07)


### Features

* periodic update check with a once-a-day notice ([1938254](https://github.com/ormeilu/evateam-cli/commit/1938254e61ef39fc0975046d66fd5dea8bfac297))

## [0.9.1](https://github.com/ormeilu/evateam-cli/compare/v0.9.0...v0.9.1) (2026-11-07)


### Bug Fixes

* release suite runs where no Mojo toolchain is installed ([bfe3a45](https://github.com/ormeilu/evateam-cli/commit/bfe3a45729d3e99c846cd8b25201bd398f38c39e))

## [0.9.0](https://github.com/ormeilu/evateam-cli/compare/v0.8.1...v0.9.0) (2026-11-07)


### ⚠ BREAKING CHANGES

* task comments shows the newest 20 by default (--all for everything); --fields with --json drops implicit id/class_name; a move to the current status is a no-op; unknown doc subcommands are errors; piped eva call replies over 64 KiB are previewed and spilled to a private file; task update -m needs -s; option values starting with -- need --opt=VALUE.

### Features

* add task, wiki and agent workflows across the open backlog ([c9065fb](https://github.com/ormeilu/evateam-cli/commit/c9065fb5a4bee50b51cc4fdf5edc97ab904a624a))
* doc download-all, doc watch and the Gantt schedule in task get ([6b2f081](https://github.com/ormeilu/evateam-cli/commit/6b2f081d561f0d7609c610acc032b5d225416d16))

## [0.8.1](https://github.com/ormeilu/evateam-cli/compare/v0.8.0...v0.8.1) (2026-11-06)


### Bug Fixes

* task attach works against the real server and cannot clobber a file ([f4954db](https://github.com/ormeilu/evateam-cli/commit/f4954db01b223380492314a7256e1e5a5dac274b))

## [0.8.0](https://github.com/ormeilu/evateam-cli/compare/v0.7.0...v0.8.0) (2026-11-06)


### Features

* task attach uploads files to a task ([b691e68](https://github.com/ormeilu/evateam-cli/commit/b691e686b60d3815fe339607d3c2ac2b5bbad1b3)), closes [#31](https://github.com/ormeilu/evateam-cli/issues/31)

## [0.7.0](https://github.com/ormeilu/evateam-cli/compare/v0.6.1...v0.7.0) (2026-11-06)


### Features

* field list and field get, and multi-select values by name in --set ([8be0037](https://github.com/ormeilu/evateam-cli/commit/8be003750bcb1fd5441ccbaa0e1075c59e87cd9e)), closes [#27](https://github.com/ormeilu/evateam-cli/issues/27)
* task delete, with a confirmation ([547403e](https://github.com/ormeilu/evateam-cli/commit/547403e4ee788aa708ec81b56fda74d89bb2625b))
* work log with time list, task log --date/--at and time delete ([26be39d](https://github.com/ormeilu/evateam-cli/commit/26be39dc0a68660bfe5f4107179ea2e9867537d8))


### Bug Fixes

* task get shows filled multi-select custom fields ([8520397](https://github.com/ormeilu/evateam-cli/commit/8520397db1eb8cda42f8034548021c4eac2cf5aa)), closes [#28](https://github.com/ormeilu/evateam-cli/issues/28)

## [0.6.1](https://github.com/ormeilu/evateam-cli/compare/v0.6.0...v0.6.1) (2026-11-06)


### Bug Fixes

* task create --parent and --type send the field names EvaTeam accepts ([db7c844](https://github.com/ormeilu/evateam-cli/commit/db7c844e8a041b3695bca8550c20e4a79e6ffa3e))

## [0.6.0](https://github.com/ormeilu/evateam-cli/compare/v0.5.1...v0.6.0) (2026-11-06)


### Features

* auth login and the READMEs explain where to get an API token ([3736d17](https://github.com/ormeilu/evateam-cli/commit/3736d17e4b6664277fdcaaef2767d9cefbbb887c))
* task create --parent, --type and --set ([751d27c](https://github.com/ormeilu/evateam-cli/commit/751d27c6481341f9c766ac5b4604dcc02affdd4a))
* task create --parent, --type and --set; notes when the server changes more ([751d27c](https://github.com/ormeilu/evateam-cli/commit/751d27c6481341f9c766ac5b4604dcc02affdd4a))


### Bug Fixes

* task list hides rows without access instead of printing them empty ([751d27c](https://github.com/ormeilu/evateam-cli/commit/751d27c6481341f9c766ac5b4604dcc02affdd4a))
* task update says when EvaTeam also changed a field it was not asked to ([751d27c](https://github.com/ormeilu/evateam-cli/commit/751d27c6481341f9c766ac5b4604dcc02affdd4a))

## [0.5.1](https://github.com/ormeilu/evateam-cli/compare/v0.5.0...v0.5.1) (2026-11-06)


### Bug Fixes

* eva hangs on a hidden keychain dialog after an upgrade on macOS ([6c205d0](https://github.com/ormeilu/evateam-cli/commit/6c205d087fe1209207ee5c2b857d3e6635796708))

## [0.5.0](https://github.com/ormeilu/evateam-cli/compare/v0.4.0...v0.5.0) (2026-11-06)


### Features

* --md and --html formatting for comments and descriptions ([b20b7d5](https://github.com/ormeilu/evateam-cli/commit/b20b7d5f46c96472fed6597fd33e4593bb986777))
* attachments, and walking a workflow path with task move --path ([fb00c9b](https://github.com/ormeilu/evateam-cli/commit/fb00c9b283f0e555530cb35873344e02373a27d6))
* comment and description text from a file or stdin with -F ([b20b7d5](https://github.com/ormeilu/evateam-cli/commit/b20b7d5f46c96472fed6597fd33e4593bb986777))
* comments from a file or stdin, Markdown, --human and comment-delete ([b20b7d5](https://github.com/ormeilu/evateam-cli/commit/b20b7d5f46c96472fed6597fd33e4593bb986777))
* resolution on task move and update, and resolution list ([f1b89bc](https://github.com/ormeilu/evateam-cli/commit/f1b89bc856b014428284b1226ddaa922f23fabed)), closes [#10](https://github.com/ormeilu/evateam-cli/issues/10)
* task attachments, attachment get and attachment download ([fb00c9b](https://github.com/ormeilu/evateam-cli/commit/fb00c9b283f0e555530cb35873344e02373a27d6))
* task comment-delete, and comment ids with task comments --ids ([b20b7d5](https://github.com/ormeilu/evateam-cli/commit/b20b7d5f46c96472fed6597fd33e4593bb986777))
* task comments --human hides workflow and system entries ([b20b7d5](https://github.com/ormeilu/evateam-cli/commit/b20b7d5f46c96472fed6597fd33e4593bb986777))
* task path and task move --path walk a multi-step workflow ([fb00c9b](https://github.com/ormeilu/evateam-cli/commit/fb00c9b283f0e555530cb35873344e02373a27d6))


### Bug Fixes

* task comments misses comments posted from the web UI ([b20b7d5](https://github.com/ormeilu/evateam-cli/commit/b20b7d5f46c96472fed6597fd33e4593bb986777))

## [0.4.0](https://github.com/ormeilu/evateam-cli/compare/v0.3.0...v0.4.0) (2026-11-05)


### Features

* agent skill and Claude Code plugin ([21fe0e6](https://github.com/ormeilu/evateam-cli/commit/21fe0e6f28ebfd8168c24e43baf9975fd9056c80))
* drop Python: HTTPS in Mojo with a bundled OpenSSL ([38dfa79](https://github.com/ormeilu/evateam-cli/commit/38dfa7924e79197f3ff9d61a6f748eff6a56a581))
* eva auth login with the OS keychain, and setups that leak a token refused ([ac6db0b](https://github.com/ormeilu/evateam-cli/commit/ac6db0b47926c355bb54982b0037bf397c1b1895))
* show the parent task and subtasks in task get ([3deabd3](https://github.com/ormeilu/evateam-cli/commit/3deabd3234fd1310ae49839db4f8793e744ba2d8))


### Bug Fixes

* case-insensitive -q and --fields that prints only what was asked ([1e73ced](https://github.com/ormeilu/evateam-cli/commit/1e73cedd05ce063965f4b5e826d6f2e3bde7dfde))
* IPv6 sockaddr layout and credentials on redirects in the HTTP client ([05f9848](https://github.com/ormeilu/evateam-cli/commit/05f984846f642ea07b5b5f2f2818ef187985894d))
* keyring reads hanging on Linux after a write ([a3138d3](https://github.com/ormeilu/evateam-cli/commit/a3138d346d1958f6eb6f62e71ad93c9e152df1bc))
* pin release builds to Mojo's CPU floor and ship libstdc++ on Linux ([84fe58f](https://github.com/ormeilu/evateam-cli/commit/84fe58f11b242ae3267071ad3f45db9250364ddc))
* resolve hostnames on Linux ([d55d1ec](https://github.com/ormeilu/evateam-cli/commit/d55d1ec52cbdd36d00732ed100f6d4528502cba1))
* trim whitespace around task and document names in headers ([fee369f](https://github.com/ormeilu/evateam-cli/commit/fee369f3538f11f02eba395882acabc31df1a066))

## [0.3.0](https://github.com/ormeilu/evateam-cli/compare/v0.2.0...v0.3.0) (2026-11-05)


### Features

* install.sh installs the release binary directly ([ac99d2a](https://github.com/ormeilu/evateam-cli/commit/ac99d2a7762988e10d7828f0e419a2d29f110d42))


### Bug Fixes

* fetch Modular's licence files when the package cache lacks them ([e387075](https://github.com/ormeilu/evateam-cli/commit/e38707542d636a9e802f6045d7dd7475431c89ee))
* run the release builds when release-please is skipped ([ac0ab2b](https://github.com/ormeilu/evateam-cli/commit/ac0ab2bd9228205cb1e0c47e977c351b8d79d35b))

## [0.2.0](https://github.com/ormeilu/evateam-cli/compare/v0.1.0...v0.2.0) (2026-11-05)


### Features

* release archives for three platforms, cut by release-please ([0f572fb](https://github.com/ormeilu/evateam-cli/commit/0f572fba5d5644c101c283ac98358ecf6d2f7f8d))


### Bug Fixes

* accept the unquoted recipe version release-please writes ([3aa29f4](https://github.com/ormeilu/evateam-cli/commit/3aa29f4445811c669ce2f68406369fd0120526d4))
* attach only the archives to GitHub releases ([b8c7f39](https://github.com/ormeilu/evateam-cli/commit/b8c7f39abe83ee97df19a93be25591d60ae2ad8c))
* publish conda packages to the namespaced channel ormeilu/ormeilu ([35d3387](https://github.com/ormeilu/evateam-cli/commit/35d3387cee9cbb1c506d6f72ff6de013adb9d19f))
