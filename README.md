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

## Быстрый старт

1. Установить зависимости для сборки и исходники `MTProxy`.
2. Собрать пропатченный бинарь:

```bash
chmod +x scripts/build-patched-mtproxy.sh
./scripts/build-patched-mtproxy.sh /opt/MTProxy
```

3. Установить runtime-файлы:

```bash
sudo install -m 755 scripts/mtproxy-managed-run.sh /usr/local/bin/mtproxy-managed-run.sh
sudo install -m 644 templates/mtproxy.service /etc/systemd/system/mtproxy.service
sudo mkdir -p /etc/mtproxy /var/log/mtproxy
sudo cp templates/mtproxy.env.example /etc/mtproxy/mtproxy.env
```

4. Отредактировать `/etc/mtproxy/mtproxy.env`.
5. Создать `/etc/mtproxy/managed_secrets.list`.
6. Запустить сервис:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mtproxy.service
```

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
