# mtproxy-logs

Альфа-версия.

`mtproxy-logs` — это runtime-часть стека:

- пропатченный `MTProxy`
- managed-запуск с несколькими `secret`
- хостовые шаблоны сервисов
- формат логов, который использует панель

Этот репозиторий предполагается использовать вместе с `mtproxy-logs-panel`.

## Статус

Это публичная альфа-версия.

- проект уже можно использовать
- структура ещё может меняться
- процесс установки ещё упрощается
- перед использованием в production всё нужно перепроверять

## Что внутри

- `scripts/build-patched-mtproxy.sh`
  Сборка `MTProxy` с текущим патчем на количество secret-слотов и события логирования.
- `scripts/mtproxy-managed-run.sh`
  Запуск `MTProxy` через `/etc/mtproxy/mtproxy.env` и `/etc/mtproxy/managed_secrets.list`.
- `templates/mtproxy.service`
  Пример `systemd`-сервиса.
- `templates/mtproxy.env.example`
  Пример runtime-конфига.
- `scripts/bootstrap-all-in-one.sh`
  Старый bootstrap-скрипт из первой внутренней установки. Сейчас это reference, не финальный installer.

## Ожидаемая раскладка на хосте

- исходники `MTProxy`: `/opt/MTProxy`
- runtime env: `/etc/mtproxy/mtproxy.env`
- список secret: `/etc/mtproxy/managed_secrets.list`
- лог-файл: `/var/log/mtproxy/mtproxy.log`
- runner-скрипт: `/usr/local/bin/mtproxy-managed-run.sh`

## Установка на чистый Ubuntu-сервер

Минимальный сценарий:

```bash
git clone https://github.com/ski28dev/mtproxy-logs.git
cd mtproxy-logs
sudo chmod +x scripts/*.sh
sudo ./scripts/install-runtime.sh
```

Что делает installer:

- ставит build-зависимости
- клонирует или обновляет `MTProxy` в `/opt/MTProxy`
- накладывает патч логирования и multi-secret
- собирает бинарь
- ставит runner и fetch-скрипты в `/usr/local/bin`
- создаёт `/etc/mtproxy/mtproxy.env`
- создаёт `/etc/mtproxy/managed_secrets.list`
- подтягивает `proxy-secret` и `proxy-multi.conf` с `core.telegram.org`
- ставит и запускает `mtproxy.service`

После установки можно отредактировать:

- `/etc/mtproxy/mtproxy.env`
- `/etc/mtproxy/managed_secrets.list`

И затем перечитать сервис:

```bash
sudo systemctl restart mtproxy.service
```

## Полезные скрипты

- `scripts/install-runtime.sh`
  Установка runtime на fresh server.
- `scripts/build-patched-mtproxy.sh`
  Ручная пересборка патченного `MTProxy`.
- `scripts/mtproxy-fetch-config.sh`
  Обновление `proxy-secret` и `proxy-multi.conf`.
- `scripts/generate-client-secret.sh`
  Генерация `ee...` client secret из raw secret и fake host.

## Замечания

- в текущей схеме `MTProxy` слушает `TCP 443`
- панель опирается на строки логов `MTP_EVENT handshake_ok` и `MTP_EVENT disconnect`
- если менять формат логов, нужно обновлять и импортёр панели

## Связка с панелью

Использовать вместе с:

- `mtproxy-logs-panel`

Панель управляет:

- `secret`
- группами
- историей слотов
- импортом логов
- runtime-статистикой
