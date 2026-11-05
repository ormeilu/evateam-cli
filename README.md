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
parent: DEV  Development
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

Сборки есть для macOS на Apple Silicon и для Linux на x86_64 и arm64 (glibc
2.34 и новее). Способов установки несколько, хватит любого.

Скриптом. Он скачивает из GitHub архив релиза под вашу машину, сверяет
sha256, распаковывает в `~/.local/share/eva/<версия>` и ставит ссылку
`~/.local/bin/eva`. Для обновления запустите его ещё раз или выполните
`eva upgrade`; `EVA_VERSION=0.3.0` фиксирует версию:

```bash
curl -fsSL https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh | sh
```

Рантайм-библиотеки Mojo лежат в самом архиве, так что от системы нужен только
Python 3.10 или новее в `PATH`: через него `eva` ходит по HTTPS.

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

По размеру способы сильно различаются. Архив весит меньше мегабайта: бинарник
и три рантайм-библиотеки. PyPI и conda берут библиотеки из пакета
`mojo-compiler` от Modular: из PyPI это около 70 МБ, а окружение pixi
вырастает примерно до 300 МБ, потому что conda-пакет тянет весь компилятор.
При установке из PyPI и conda для HTTPS используется Python, который ставится
вместе с пакетом.

Из исходников, с [pixi](https://pixi.sh):

```bash
git clone https://github.com/ormeilu/evateam-cli
cd evateam-cli
pixi run build          # → build/eva
```

## Настройка

Создайте токен в EvaTeam: «Моя страница» → «Безопасность» → «Сгенерировать
API токен». Потом задайте две переменные: в окружении, в `./.env` или в
`~/.config/eva-cli/env`:

```bash
EVA_URL=https://eva.example.ru
EVA_API_KEY=…
```

`EVA_INSECURE=1` отключает проверку TLS, это для своих серверов с собственным
сертификатом. `eva config` показывает, что и откуда подхватилось; сам токен не
печатается.

## Команды

| Команда | Что делает |
|---|---|
| `eva task get CODE [--fields a,b]` | одна задача: статус, люди, родитель, описание |
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
- `src/eva/client.mojo`: настройки и вызов RPC. В стандартной библиотеке Mojo
  пока нет TLS, поэтому сам HTTPS-запрос уходит через `urllib` из Python
  (через интероп Mojo с Python). Сборка запроса и разбор ответа написаны на
  Mojo.
- `src/eva/pyfind.mojo`: ищет libpython до старта интеропа. Если
  `MOJO_PYTHON_LIBRARY` не задан, берёт первый Python 3.10+ в `PATH`.
- `src/eva/render.mojo`: вывод в терминал и в пайп, HTML в текст, цвета через
  [mist](https://github.com/thatstoasty/mist) из канала
  [modular-community](https://prefix.dev/channels/modular-community).
- `src/eva/commands.mojo`: дерево команд.

JSON-парсер свой: сборка `emberjson` в modular-community скомпилирована под
Mojo 1.1 и под 1.2 не загружается.

## Разработка

```bash
pixi run test     # юнит-тесты: JSON, вывод, разбор аргументов
pixi run e2e      # собирает eva и гоняет её против tests/mock_server.py
```

`tests/mock_server.py` — небольшой JSON-RPC сервер с двумя заготовленными
задачами. Сквозной тест проверяет и то, что `eva` печатает, и то, что она
отправляет.

Сборка пакетов:

- `pixi run wheel macosx_13_0_arm64` упаковывает `build/eva` в wheel в `dist/`;
  rpath указывает на библиотеки `mojo-compiler` в том же site-packages;
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
