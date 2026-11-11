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

Раз в сутки `eva` проверяет, не вышла ли новая версия. Проверка идёт в фоновом
процессе, команды её не ждут. Запрос уходит на `/releases/latest` в GitHub, тот
же адрес, который читает скрипт установки; ни токена, ни адреса EvaTeam в нём
нет. Если вышла новая версия, команда напишет в stderr одну строку, не чаще раза
в сутки на версию: `eva 0.10.0 is out (you have 0.9.0); update with: eva upgrade`.
`eva --version` и `eva context` показывают эту строку каждый раз, а stdout
остальных команд не меняется. Неудачная проверка ничего не печатает.
`EVA_NO_UPDATE_CHECK=1` выключает проверку, при заданной `CI` она не
запускается, а `EVA_UPDATE_CHECK_HOURS=6` меняет интервал на шесть часов.

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

Сначала создайте API-токен в EvaTeam ([инструкция EvaTeam](https://docs.evateam.ru/docs/DOC-000200)):

1. Откройте «Моя страница», вкладку «Безопасность».
2. Нажмите «Сгенерировать API токен», потом «Создать токен API».
3. Задайте имя и срок действия и создайте токен.
4. Сразу скопируйте токен: EvaTeam показывает его один раз и хранит только хэш.

<details>
<summary>Скриншоты из документации EvaTeam</summary>

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-20230807-161836.png?version=1" alt="«Моя страница»" width="300">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-mce-20260527-115633583.png?version=1" alt="вкладка «Безопасность»" width="700">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-mce-20260527-115842904.png?version=1" alt="«Сгенерировать API токен»" width="700">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-mce-20260527-120135821.png?version=1" alt="«Создать токен API»" width="600">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%253A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-20230317-122341.png" alt="готовый токен" width="600">

<img src="https://docs.evateam.ru/files/obj/CmfDocument/CmfDocument%3A8de/CmfDocument%3A8de0005e-5913-11ed-91cf-cf78a90a1ccb/image-mce-20260527-120731383.png?version=1" alt="панель токенов" width="700">

</details>

Потом войдите (`eva auth login` в терминале сам напомнит эти шаги):

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
- Проверка обновлений обращается только к GitHub, без учётных данных и без
  адреса EvaTeam. Своё состояние она хранит в том же закрытом кэше, что и
  файлы схемы, а из версии, полученной по сети, в терминал попадают только
  цифры, буквы, точки и дефисы.
- Набор тестов проходит под AddressSanitizer, включая работу с Keychain и
  libsecret через FFI.

## Команды

| Команда | Что делает |
|---|---|
| `eva task get CODE [--fields a,b] [--with comments,attachments,links\|all]` | Карточка: статус, люди, планирование, теги, списки и описание |
| `eva task list [-p PROJ] [-a LOGIN\|me] [-s STATUS] [-q TEXT]` | Поиск по названию; фильтры по участникам, архиву, тегам и компонентам |
| `eva task create -p PROJ -t TITLE [-d TEXT\|-F FILE] [--template CODE]` | Создать задачу, в том числе из шаблона |
| `eva task update CODE [-t TITLE] [-d TEXT\|-F FILE] [-a LOGIN\|me] [--set JSON]` | Изменить поля; -s выполняет переход после записи остальных полей |
| `eva task delete CODE [--yes]` | Удалить после подтверждения; без терминала нужен --yes |
| `eva task move CODE STATUS [--path] [--resolution CODE] [--set JSON] [-m TEXT]` | Пройти переходы workflow; при отказе остановиться |
| `eva task statuses CODE` | Доступные переходы из текущего статуса |
| `eva task path CODE STATUS` | Показать путь без смены статуса |
| `eva task comment CODE TEXT\|-F FILE [--reply-to ID] [--attach FILE...]` | Комментарий, ответ в ветке и файлы к нему |
| `eva task comments CODE [--human] [--ids] [-n 20] [--page 1] [--all]` | Последние 20 комментариев по времени; следующая страница содержит более ранние |
| `eva task comment-edit ID TEXT\|-F FILE [--md\|--html]` | Изменить текст комментария |
| `eva task comment-delete ID` | Скрыть комментарий; сервер сохраняет запись об удалении |
| `eva task log CODE 1h30m [-m TEXT] [--date D] [--at HH:MM]` | Списать время сейчас или за выбранный день |
| `eva task history CODE [-n 25] [--page 1]` | История переходов по статусам, начиная с последнего |
| `eva task time CODE [--all] [-n 25] [--page 1]` | Доступные записи журнала задачи; --all добавляет планы и черновики |
| `eva task dev CODE` | Связанные репозитории, ветки, коммиты и запросы на слияние |
| `eva task links CODE` | Входящие и исходящие связи с типами |
| `eva task link CODE OTHER [--type relates\|CODE\|NAME]` | Создать связь выбранного типа; повторный вызов ничего не меняет |
| `eva task unlink CODE OTHER [--type relates\|CODE\|NAME]` | Удалить связи только выбранного типа |
| `eva task checklist CODE [-n 25] [--page 1]` | Чек-листы и страницы их пунктов |
| `eva task check CHLI-1 [--undo]` | Отметить пункт DONE; --undo возвращает OPEN |
| `eva task watch CODE [--login LOGIN]` | Добавить наблюдателя; по умолчанию себя |
| `eva task unwatch CODE [--login LOGIN]` | Убрать наблюдателя; повторный вызов безопасен |
| `eva task attachments CODE` | Файлы задачи |
| `eva task attach CODE FILE [FILE...] [--force]` | Приложить файлы; замена совпавшего имени требует --force |
| `eva task bulk set --filter BQL --set JSON [--yes] [--dry-run]` | Массовое изменение полей; без --yes выводится только предпросмотр |
| `eva task bulk move STATUS --filter BQL [--path] [--set JSON] [--yes]` | Массовые переходы; ошибки отдельных задач не останавливают остальные |
| `eva time list [--from D] [--to D] [-a LOGIN]` | Журнал по дням и рабочая норма; по умолчанию текущая неделя |
| `eva time report --from D --to D [-p PROJ] [-a LOGIN\|me]` | Доступные итоги по проекту и дню начала записи: факт, план и прочее |
| `eva time log CODE 1h30m [--date D] [--at HH:MM]` | То же, что task log |
| `eva time delete TTH-1` | Удалить запись журнала работ |
| `eva attachment get ATT-1` | Сведения о файле и извлечённый текст |
| `eva attachment download ATT-1 [-o PATH\|-] [--force]` | Скачать исходный файл; замена требует --force |
| `eva attachment delete ATT-1 [--yes]` | Удалить после подтверждения; это не гарантия стирания байтов на сервере |
| `eva project list [-q TEXT]` | Коды и названия проектов |
| `eva project get CODE` | Владелец, прямые назначения ролей и списки; группы и наследование не раскрываются |
| `eva person list [-q TEXT]` | Логин, имя и почта |
| `eva doc list [-q TEXT]` | Поиск документов по названию |
| `eva doc get CODE [--version OPAQUE_VERSION]` | Опубликованный текст или версия с точным значением doc_version |
| `eva doc create -t TITLE --parent CODE [-d TEXT\|-F FILE] [--publish]` | Создать черновик; публикация только по явному --publish |
| `eva doc update CODE [-t TITLE] [-d TEXT\|-F FILE] [--publish]` | Изменить черновик |
| `eva doc publish CODE` | Опубликовать черновик и проверить текст |
| `eva doc comment CODE TEXT\|-F FILE [--reply-to ID] [--attach FILE...]` | Комментарий к документу, ответ и файлы |
| `eva doc comment-edit ID TEXT\|-F FILE` | Изменить комментарий к документу |
| `eva doc comments CODE [--human] [--ids] [-n 20] [--page 1] [--all]` | Страницы комментариев по тем же правилам, что у задач |
| `eva doc attachments CODE` | Файлы документа |
| `eva doc attach CODE FILE [FILE...] [--force]` | Приложить файлы с теми же проверками, что у задачи |
| `eva doc download-all CODE [-o DIR] [--force]` | Скачать все вложения в каталог, по одному файлу и без архива на сервере |
| `eva doc children CODE [--depth 1] [-n 25] [--page 1]` | Дочерние документы, со страницами для каждого родителя; глубина до 10 |
| `eva doc history CODE [-n 25] [--page 1]` | Строки версий и идентификаторы истории, начиная с последней |
| `eva doc followers CODE [-n 25] [--page 1]` | Явные подписчики, без читателей и неявных получателей |
| `eva doc watch CODE [--children] [--off] [--dry-run]` | Подписаться на документ от своего имени; `--children` добавляет вложенные страницы, `--off` отписывает |
| `eva sprint list [-p PROJ] [-s open\|closed\|all]` | Найти спринты проекта |
| `eva sprint get CODE [-n 25] [--page 1]` | Сведения о спринте и страница его задач |
| `eva sprint create -p PROJ NAME [--start DATE] [--end DATE] [--text TEXT] [--dry-run]` | Создать спринт в проекте и вывести его код |
| `eva sprint update CODE [--name NAME] [--start DATE\|none] [--end DATE\|none] [--text TEXT] [--dry-run]` | Изменить название, плановые даты или описание; `none` стирает дату |
| `eva sprint rename CODE NAME [--dry-run]` | То же, что `update --name` |
| `eva sprint add CODE TASK [TASK...] [--dry-run]` | Добавить задачи, сохранив их остальные спринты |
| `eva sprint remove CODE TASK [TASK...] [--dry-run]` | Убрать задачи из спринта, сохранив их остальные спринты |
| `eva release list [-p PROJ] [-s open\|closed\|all]` | Найти релизы проекта |
| `eva release get CODE [-n 25] [--page 1]` | Сведения о релизе и страница его задач |
| `eva release create -p PROJ NAME [--start DATE] [--end DATE] [--text TEXT] [--dry-run]` | Создать релиз в проекте и вывести его код |
| `eva release update CODE [--name NAME] [--start DATE\|none] [--end DATE\|none] [--text TEXT] [--dry-run]` | Изменить название, плановые даты или описание; `none` стирает дату |
| `eva release rename CODE NAME [--dry-run]` | То же, что `update --name` |
| `eva release add CODE TASK [TASK...] [--dry-run]` | Добавить задачи, сохранив их остальные релизы |
| `eva release remove CODE TASK [TASK...] [--dry-run]` | Убрать задачи из релиза, сохранив их остальные релизы |
| `eva relation types [-n 25] [--page 1]` | Коды и названия типов связей |
| `eva tag list [-q TEXT]` | Теги; --tag при изменении задачи заменяет весь набор |
| `eva component list [-p PROJ] [-q TEXT]` | Компоненты проекта для фильтра --component |
| `eva filter list [-q TEXT] [-p PROJ]` | Собственные сохранённые фильтры; --filter CODE или NAME выполняет сохранённый JSON BQL |
| `eva notify list [-n 25] [--page 1] [--all]` | Свои непрочитанные уведомления; --all добавляет прочитанные |
| `eva repo list [-q TEXT]` | Код, название и адрес репозитория |
| `eva search TEXT [-t task\|doc\|all] [-p PROJ] [-n 25] [--page 1]` | Поиск подстроки в названии или тексте; лимит отдельный для каждого типа |
| `eva testcase list [-p PROJ] [-q TEXT]` | Тест-кейсы |
| `eva testcase get CODE [-n 25] [--page 1]` | Версия, шаги, секции предусловий и ожидаемые результаты |
| `eva testplan list [-p PROJ] [-q TEXT]` | Тест-планы |
| `eva testplan get CODE [-n 25] [--page 1]` | План и страница входящих в него тест-кейсов |
| `eva ticket get CODE [-n 25] [--page 1]` | Циклы SLA в единицах сервера; принадлежность к очереди не угадывается |
| `eva trash list [-p PROJ] [-n 25] [--page 1]` | Удалённые задачи; дата последнего изменения не обещает срок хранения |
| `eva trash restore CODE [--yes]` | Восстановить задачу после подтверждения |
| `eva field list [-q TEXT]` | Пользовательские поля задач |
| `eva field get NAME` | Значения выбора и мультиселекта |
| `eva resolution list` | Коды и названия резолюций |
| `eva schema CmfTask [-q TEXT] [--relations] [--refresh]` | Схема с локальным фильтром и кешем; --classes перечисляет известные модели |
| `eva context` | Кто вошёл, доступные проекты и недавняя работа |
| `eva cheatsheet` | Короткие примеры без входа в систему |
| `eva call METHOD [--kwargs JSON] [--args JSON] [--flags JSON]` | Любой метод API; слишком большой ответ через пайп сохраняется в закрытый файл |
| `eva auth login [--profile NAME] [--url URL]` | Считать токен без эха или из stdin, сохранить в системную связку ключей |
| `eva auth status` | Учётная запись и профили |
| `eva auth use NAME` | Выбрать профиль по умолчанию |
| `eva auth logout [--profile NAME]` | Удалить профиль |
| `eva config` | Источник настроек, без вывода токена |
| `eva upgrade` | Обновиться тем же способом, каким установлен клиент |
| `eva help [COMMAND [SUB]]` | То же, что `eva COMMAND --help`: справка только по этой команде |
| `eva completion fish\|bash\|zsh` | Скрипт автодополнения команд и подкоманд, например `eva completion fish \| source` |

Списки разбиты на страницы. `task comments` сначала показывает последние 20
комментариев, внутри страницы от старого к новому. `--page 2` ведёт к более
ранним, `--all` запрашивает весь набор с проверкой ограничения по размеру.
`--cols … --format tsv` печатает только строки данных.
`task get/list --fields … --json` оставляет в JSON выбранные поля и вложенные
объекты. Без выбора полей `--json` сохраняет ответ API.

`task create/update` принимают `--priority`, `--story-points`, `--plan-start`,
`--plan-end`, `--alarm`, `--co-assignee`, `--waiting-for` и `--tag`.
`--co-assignee` и `--tag` заменяют набор, `none` его очищает. Повторение флага
задаёт несколько значений. Команды `sprint/release add` и `remove` добавляют
и убирают задачи, не трогая остальные списки.

Плановые даты пишутся в карточку задачи. У диаграммы Ганта своё расписание,
выровненное по рабочему календарю, и `--plan-start` его не двигает. `task get`
показывает его отдельной строкой `gantt schedule`.

`--dry-run` у task create/update/move/log/attach/comment показывает запросы
без записи. Идентификаторы проверяются чтением, но права и правила workflow
сервер при этом не проверяет. Массовые операции без `--yes` показывают только
предпросмотр. В одном наборе допускается до 1 000 задач; ошибки перечисляются
отдельно, успешные изменения не откатываются.

`doc watch` подписывает только вас: на сервере запись подписки создаёт сам
подписчик. Повтор команды ничего не меняет. `doc followers` читает явных
подписчиков, а не всех получателей уведомлений или читателей страницы.
`doc download-all` не вызывает серверный архив: тот сохраняет zip новым
вложением документа. Ограничения и проверки описаны в
[журнале задач](docs/issue-batch.md), [чтении](plugin/skills/eva/reading.md),
[записи](plugin/skills/eva/writing.md) и
[расширенном справочнике](plugin/skills/eva/expanded.md).

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
- `src/main.mojo`: выбор команды и справка.
- `src/eva/common.mojo`, `selection.mojo`: поиск объектов, страницы вывода и
  полные выборки с ограничением размера.
- `task.mojo`, `workflow.mojo`, `collaboration.mojo`, `documents.mojo`,
  `attachments.mojo`: поля задач, переходы, комментарии, документы и файлы.
- `dates.mojo`, `projection.mojo`, `validation.mojo`, `writes.mojo`: общие
  проверки дат, выбор полей, сверка записанных значений и предпросмотр.
  В `commands.mojo` остался только произвольный вызов API.

JSON-парсер свой: сборка `emberjson` в modular-community скомпилирована под
Mojo 1.1 и под 1.2 не загружается.

## Разработка

```bash
pixi run test       # юнит-тесты: 9 наборов, предупреждения компилятора — ошибка
pixi run e2e        # собирает eva и гоняет её против tests/mock_server.py
pixi run asan       # то же под AddressSanitizer
pixi run coverage   # покрытие строк src/ юнит-тестами и e2e
pixi run ci         # test, e2e и asan: то же, что гоняет CI
pixi run fmt-check  # падает, если mojo format что-то поменяет; файлы не трогает
```

Все команды CI и релиза описаны задачами в `pixi.toml`, `pixi task list`
показывает их с описаниями.

`tests/mock_server.py` — небольшой JSON-RPC сервер с заготовленными задачами,
в том числе с «враждебной»: escape-коды в названии и попытка закрыть
`<untrusted>` в описании. Сквозной тест проверяет, что `eva` печатает и что
отправляет, ходит в мок по HTTP, IPv6 и HTTPS с самоподписанным сертификатом и
отдельно проверяет все правила из раздела «Безопасность». Тест настоящей
связки ключей пишет в неё и потому включается только с `EVA_TEST_KEYRING=1`.
`tests/test_update_check.py` через `EVA_UPDATE_URL` подменяет ответ GitHub
о последней версии; во всех остальных тестах задан `EVA_NO_UPDATE_CHECK=1`.

У Mojo нет встроенного покрытия, поэтому `pixi run coverage` идёт через LLVM:
`mojo build -O0 -g --emit llvm`, проход `insert-gcov-profiling`, сборка clang,
затем счётчики всех бинарников сводятся в `coverage/summary.txt` и
`coverage/missed-lines.txt`. Цифра скорее завышена: строку, которую Mojo
переводит без отдельного ветвления, gcov может посчитать выполненной.

Сборка пакетов:

- `pixi run wheel macosx_13_0_arm64` упаковывает `build/eva` в wheel в `dist/`:
  бинарник в `.data/scripts`, библиотеки в `.data/data/lib/evateam-cli`;
- `pixi run archive aarch64-apple-darwin` собирает архив релиза;
- `pixi run -e package conda-package` собирает conda-пакет по
  `recipe/recipe.yaml` в `output/` (окружение `package` содержит только
  rattler-build);
- `check-wheel`, `check-archive` и `pixi run -e package check-conda` ставят
  собранное так же, как пользователь, и гоняют против него сквозной тест;
  релизный workflow вызывает эти же задачи.

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
