# eva — EvaTeam из командной строки, на Mojo

[English version](README.en.md)

`eva` — консольный клиент для [EvaTeam](https://www.evateam.ru/), российского
таск-трекера и вики. Он родственник
[ytcli](https://github.com/ormeilu/yandex-tracker-cli), который делает то же
для Яндекс Трекера, и написан на [Mojo](https://www.modular.com/mojo) ради
интереса.

Как и у ytcli, у `eva` два читателя: человек в терминале и ИИ-агент, который
читает вывод через пайп. В терминале будут цвета и описания целиком. В пайп
идёт обычный текст, описание обрезается, а в конце написано, сколько строк
осталось за кадром.

```console
$ eva task get DEV-1
DEV-1  Вложения теряются при переносе задачи
status: В работе   stage: IN_PROGRESS
assignee: ilya@example.ru   author: rep@example.ru
project: DEV  Development
parent task: DEV-100  Storage rework
created: 2026-11-01T10:00:00+03:00   updated: 2026-11-02T10:00:00+03:00
<untrusted src="DEV-1/text">
Шаги:

- Приложить файл
- Перенести
</untrusted>

$ eva task list -p DEV -s open -n 2
DEV-2        Открыто        -                  Retry uploads on 5xx
DEV-7        Открыто        ilya@example.ru    Flaky upload test
shown 2 of 14 — next: --page 2
```

Описания задач и комментарии пишут другие люди, поэтому `eva` их огораживает:
в терминале полем `▏` слева, в пайпе тегом `<untrusted src="…">`. Агент видит,
где данные трекера, а где инструкции.

## Установка

Сборки есть для macOS 13 и новее на Apple Silicon и для Linux на x86_64 и
arm64 с glibc 2.34 и новее: проверены Ubuntu 22.04, Debian 12 и Rocky Linux 9.
Процессор нужен не старее, чем требует сам Mojo: x86-64-v3 (Haswell и новее) или
ARM Neoverse N1 (Graviton2 и новее). Python для работы не нужен. Способов установки несколько, хватит любого.

Скриптом. Он скачивает из GitHub архив релиза под вашу машину, сверяет
sha256, распаковывает в `~/.local/share/eva/<версия>` и ставит ссылку
`~/.local/bin/eva`. Для обновления запустите его ещё раз или выполните
`eva upgrade`; `EVA_VERSION=0.3.0` фиксирует версию:

```bash
curl -fsSL https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh | sh
```

Рантайм-библиотеки Mojo и OpenSSL лежат в самом архиве, от системы нужен
только набор корневых сертификатов, который есть везде.

Через pixi, из conda-канала
[`prefix.dev/ormeilu/ormeilu`](https://prefix.dev/channels/@ormeilu/ormeilu):

```bash
pixi global install -c https://prefix.dev/ormeilu/ormeilu -c https://conda.modular.com/max -c conda-forge evateam-cli
```

Из PyPI, если привычнее uv или pipx:

```bash
uvx --from evateam-cli eva --help     # запустить без установки
uv tool install evateam-cli           # или поставить eva в PATH
pipx install evateam-cli
```

Архивы релизов (`eva-vX.Y.Z-<target>.tar.gz` для `aarch64-apple-darwin`,
`x86_64-unknown-linux-gnu` и `aarch64-unknown-linux-gnu`) лежат в каждом
[релизе](https://github.com/ormeilu/evateam-cli/releases), их можно
распаковать и вручную. Внутри `bin/eva`, библиотеки в `lib/` и лицензии.

Через [mise](https://mise.jdx.dev), из тех же архивов или из PyPI:

```bash
mise use -g github:ormeilu/evateam-cli
mise use -g pypi:evateam-cli
```

Свежие версии mise прячут релизы моложе суток (`minimum_release_age`). Для
`github:` хватит указать версию явно, например
`github:ormeilu/evateam-cli@0.3.0`. Для `pypi:` mise передаёт тот же срок в uv,
так что новую версию оттуда получится поставить только через сутки. Бэкенд
`conda:` не подойдёт: он берёт пакет и все зависимости из одного канала, а
`mojo-compiler` лежит в канале Modular.

`eva upgrade` обновляет `eva` тем же способом, каким её поставили.

Архив и wheel весят около 3,5 МБ: бинарник, три рантайм-библиотеки Mojo и
OpenSSL. Из wheel бинарник ставится прямо в `bin/` окружения, Python-обёртки
нет. Conda-пакет берёт библиотеки из пакета `mojo-compiler` от Modular, и
окружение pixi вырастает примерно до 300 МБ: этот пакет тянет за собой весь
компилятор и Python.

Из исходников, с [pixi](https://pixi.sh):

```bash
git clone https://github.com/ormeilu/evateam-cli
cd evateam-cli
pixi run build          # → build/eva
```

## Скилл для агентов

Скилл учит агента пользоваться `eva`: что запускать первым, какие команды только
читают, как менять статус через воркфлоу и почему текст из задач — данные, а не
инструкции. Ставится отдельно от бинарника:

```bash
npx skills add ormeilu/evateam-cli                 # для любого агента через skills CLI
```

В Claude Code:

```
/plugin install eva --marketplace ormeilu/evateam-cli
```

Скилл лежит в `plugin/skills/eva/`. В `setup.md` там же есть allowlist
разрешений для Claude Code: читающие команды разрешены, пишущие спрашивают.

## Настройка

Создайте токен в EvaTeam: «Моя страница» → «Безопасность» → «Сгенерировать
API токен». Потом войдите:

```bash
eva auth login
```

`eva` спросит адрес и токен. Токен вводится без эха, перед сохранением
проверяется запросом к серверу, а потом адрес и токен попадают в системную
связку ключей: Keychain на macOS, Secret Service (GNOME Keyring, KWallet) на
Linux. В файлах на диске их нет.

```bash
eva auth status                  # профили, кто вошёл, работают ли
eva auth login --profile sandbox --url https://eva-test.example.ru
eva auth use sandbox             # профиль по умолчанию
eva --profile sandbox task get X # один раз другим профилем
eva auth logout --profile sandbox
```

Для скриптов и CI токен можно передать на stdin
(`printf '%s\n' "$TOKEN" | eva auth login --url …`) или задать переменными
окружения `EVA_URL` и `EVA_API_KEY`: они главнее профилей. Ещё `eva` читает
`./.env` и `~/.config/eva-cli/env`. Кто откуда, показывает `eva config`.

Сертификаты сервера `eva` проверяет по системному набору (`/etc/ssl/cert.pem`,
`/etc/ssl/certs/ca-certificates.crt` и т. п.). Если EvaTeam подписан
корпоративным центром сертификации, укажите его PEM-файл в `EVA_CA_BUNDLE`.
`EVA_INSECURE=1` отключает проверку TLS совсем.

## Безопасность

- Токен не бывает аргументом командной строки: аргументы видны в `ps` и
  остаются в истории shell. Он вводится без эха или читается из stdin.
- Адрес и токен берутся из одного места. Если `.env` в чужом репозитории задаёт
  только `EVA_URL`, `eva` откажется работать, а не отправит туда токен из
  связки ключей.
- Токен уходит только по HTTPS. Обычный `http://` разрешён лишь для
  `localhost` или с явным `EVA_INSECURE=1`.
- За редиректами API `eva` не идёт, а клиент `requests` при смене хоста,
  порта или схемы выбрасывает `Authorization` и cookie.
- Описания, комментарии и документы помечены как чужой текст, и закрыть
  `<untrusted>` изнутри нельзя. Из всего, что пришло с сервера, вырезаются
  управляющие символы, так что название задачи не может нести escape-коды в
  терминал.
- Если файл с токеном доступен группе или всем, `eva` об этом предупредит.
- Набор тестов проходит под AddressSanitizer, включая работу с Keychain и
  libsecret через FFI.

## Команды

| Команда | Что делает |
|---|---|
| `eva task get CODE [--fields a,b]` | одна задача: статус, люди, проект, родительская задача, подзадачи, описание |
| `eva task list [-p PROJ] [-a LOGIN] [-s STATUS] [-q TEXT]` | поиск; `-s` принимает `open`, `closed`, `in_progress`, `in_review`, `all` или код статуса |
| `eva task create -p PROJ -t TITLE [-d TEXT] [-a LOGIN] [--sprint SPR-1]` | новая задача |
| `eva task update CODE [-t] [-d] [-a] [--set JSON]` | изменить поля; `--set` передаёт любое поле как есть |
| `eva task statuses CODE` | в какие статусы воркфлоу пускает задачу из текущего |
| `eva task move CODE STATUS [-m TEXT] [--set JSON]` | сменить статус через переход воркфлоу; `--set` заполняет поля, которых требует переход |
| `eva task comment CODE TEXT` / `eva task comments CODE` | написать или прочитать комментарии |
| `eva task log CODE 1h30m [-m TEXT]` | списать время |
| `eva task links CODE` | входящие и исходящие связи |
| `eva project list`, `eva person list`, `eva doc list` | списки, `-q` ищет по названию |
| `eva doc get CODE` | документ вики текстом |
| `eva call METHOD --kwargs JSON` | любой метод API, ответ как есть |

Все списки понимают `-n/--limit` и `--page` и заканчиваются строкой
`shown N of M`, чтобы страницу не приняли за весь ответ. `--json` печатает
JSON самого API, `--full` отключает обрезку в пайпе, `-v` выводит каждый запрос
и ответ в stderr.

`--filter` у `task list` добавляет условие на BQL как есть, для всего, чего нет
среди флагов:

```bash
eva task list --filter '["cmf_created_at", ">=", "2026-10-01"]'
```

## Как устроено

EvaTeam работает по JSON-RPC 2.2: каждый вызов — это `POST /api/` с именем
метода вроде `CmfTask.list` и именованными аргументами. Из чего состоит `eva`:

- `src/eva/json.mojo`: разбор и запись JSON. Узлы хранятся в одном массиве и
  ссылаются на детей по индексу, так обходится без рекурсивного типа. Числа
  сохраняют исходный текст, поэтому идентификаторы и даты проходят без
  изменений.
- `src/eva/client.mojo`: настройки и вызов RPC, выбор набора сертификатов.
- `src/requests/`: HTTP-клиент на Mojo из
  [mojo-requests-poc](https://github.com/ormeilu/mojo-requests-poc) (Apache-2.0,
  лицензия лежит рядом), перенесённый на Mojo 1.2. Сокеты и DNS через libc,
  TLS через OpenSSL, который подгружается `dlopen`: сначала из `lib/` рядом с
  бинарником, потом из системы. Python-интеропа в `eva` нет.
- `src/eva/render.mojo`: вывод в терминал и в пайп, HTML в текст, цвета через
  [mist](https://github.com/thatstoasty/mist) из канала
  [modular-community](https://prefix.dev/channels/modular-community).
- `src/eva/commands.mojo`: дерево команд.

JSON-парсер свой: сборка `emberjson` в modular-community скомпилирована под
Mojo 1.1 и под 1.2 не загружается.

## Разработка

```bash
pixi run test       # юнит-тесты: 9 наборов, предупреждения компилятора — ошибка
pixi run e2e        # собирает eva и гоняет её против tests/mock_server.py
pixi run asan       # то же под AddressSanitizer
pixi run coverage   # покрытие строк src/ юнит-тестами и e2e
```

`tests/mock_server.py` — небольшой JSON-RPC сервер с заготовленными задачами,
в том числе с «враждебной»: escape-коды в названии и попытка закрыть
`<untrusted>` в описании. Сквозной тест проверяет, что `eva` печатает и что
отправляет, ходит в мок по HTTP, IPv6 и HTTPS с самоподписанным сертификатом и
отдельно проверяет все правила из раздела «Безопасность». Тест настоящей
связки ключей пишет в неё и потому включается только с `EVA_TEST_KEYRING=1`.

У Mojo нет встроенного покрытия, поэтому `pixi run coverage` идёт через LLVM:
`mojo build -O0 -g --emit llvm`, проход `insert-gcov-profiling`, сборка clang,
затем счётчики всех бинарников сводятся в `coverage/summary.txt` и
`coverage/missed-lines.txt`. Цифра скорее завышена: строку, которую Mojo
переводит без отдельного ветвления, gcov может посчитать выполненной.

Сборка пакетов:

- `pixi run wheel macosx_13_0_arm64` упаковывает `build/eva` в wheel в `dist/`:
  бинарник в `.data/scripts`, библиотеки в `.data/data/lib/evateam-cli`;
- `pixi run archive aarch64-apple-darwin` собирает архив релиза;
- `pixi run conda-package` собирает conda-пакет по `recipe/recipe.yaml` в
  `output/`.

Версии выпускает [release-please](https://github.com/googleapis/release-please)
по [conventional commits](https://www.conventionalcommits.org/): `fix:`
поднимает патч-версию, `feat:` минорную (пока версия ниже 1.0), а `feat!:` или
футер `BREAKING CHANGE:` мажорную. Каждый пуш в main обновляет релизный PR:
в нём changelog и версия в `pixi.toml`, `src/main.mojo` и `recipe/recipe.yaml`.
После мержа PR появляется тег, и тот же `.github/workflows/release.yml`
собирает wheel'ы, архивы и conda-пакеты под три платформы, гоняет сквозной
тест на каждом из них, установленном так же, как его поставит пользователь, и
публикует всё на PyPI, prefix.dev и в GitHub-релиз.

## Состояние

Проверено на живом инстансе EvaTeam, и чтение, и запись: все команды из
таблицы, страницы и подсчёт, тестовая задача от создания до Done.

Так нашлись две вещи, о которых документация молчит:

- Обычный `CmfTask.update` с новым статусом сервер принимает и молча
  игнорирует. Статус меняется только переходом воркфлоу
  (`CmfTask.task_transition_run`), это и делает `task move`: читает воркфлоу
  задачи, находит переход из текущего статуса, а если нужного нет, перечисляет
  доступные.
- Отказ приходит как HTTP 200 с сообщением в `abort` («Необходимо заполнить
  Вид услуги») и без `error`. `eva` считает такой ответ ошибкой.

## Лицензия

MIT
