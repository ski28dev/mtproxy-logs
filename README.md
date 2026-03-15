# mtproxy-logs

Alpha release.

`mtproxy-logs` is the runtime side of the stack:

- patched `MTProxy`
- managed multi-secret startup
- host-level service templates
- log format used by the panel

This repository is meant to be paired with `mtproxy-logs-panel`.

## Status

This is a public alpha build.

- the project is usable
- the layout may still change
- install flow is still being simplified
- review everything before using it in production

## What is inside

- `scripts/build-patched-mtproxy.sh`
  Builds `MTProxy` with the current secret-slot and log-event patch.
- `scripts/mtproxy-managed-run.sh`
  Starts `MTProxy` using `/etc/mtproxy/mtproxy.env` and `/etc/mtproxy/managed_secrets.list`.
- `templates/mtproxy.service`
  Example systemd unit.
- `templates/mtproxy.env.example`
  Example runtime env file.
- `scripts/bootstrap-all-in-one.sh`
  Legacy bootstrap script from the first internal install. Keep it as reference only.

## Expected host layout

- `MTProxy` source: `/opt/MTProxy`
- runtime env: `/etc/mtproxy/mtproxy.env`
- secret list: `/etc/mtproxy/managed_secrets.list`
- log file: `/var/log/mtproxy/mtproxy.log`
- runner script: `/usr/local/bin/mtproxy-managed-run.sh`

## Quick start

1. Install build dependencies and `MTProxy` source.
2. Build the patched binary:

```bash
chmod +x scripts/build-patched-mtproxy.sh
./scripts/build-patched-mtproxy.sh /opt/MTProxy
```

3. Copy runtime files:

```bash
sudo install -m 755 scripts/mtproxy-managed-run.sh /usr/local/bin/mtproxy-managed-run.sh
sudo install -m 644 templates/mtproxy.service /etc/systemd/system/mtproxy.service
sudo mkdir -p /etc/mtproxy /var/log/mtproxy
sudo cp templates/mtproxy.env.example /etc/mtproxy/mtproxy.env
```

4. Edit `/etc/mtproxy/mtproxy.env`.
5. Create `/etc/mtproxy/managed_secrets.list`.
6. Start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mtproxy.service
```

## Notes

- `MTProxy` listens on `TCP 443` in the current layout.
- the panel relies on `MTP_EVENT handshake_ok` and `MTP_EVENT disconnect` log lines
- if you change the log format, the panel importer must be updated too

## Pairing with the panel

Use this together with:

- `mtproxy-logs-panel`

The panel manages:

- secrets
- groups
- slot history
- log import
- runtime statistics

