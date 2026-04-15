# INSTALL (Enterprise Appliance v0.1)

## Prereqs

- Ubuntu Server 22.04+ or Debian 12+
- systemd
- sudo access

## Install

From the repository root:

```bash
./installer/install.sh
```

## Validate

```bash
systemctl is-active actuator.service slime.service
ls -ld /run/slime
ls -l /run/slime/egress.sock
```

Expected:

- `active / active`
- `/run/slime` owned by the runtime service account
- `egress.sock` permissions compatible with the `slime-actuator` group

If dashboard assets were installed:

```bash
systemctl is-active slime-dashboard.service
curl -fsS http://127.0.0.1:8081/ >/dev/null
```

If the optional AI Analyst surface is enabled, configure its shared token and
local Ollama endpoint in `/etc/slime/dashboard.env`:

```bash
sudo install -d -m 0750 /etc/slime
sudo sh -c 'cat > /etc/slime/dashboard.env <<EOF
ANALYST_SHARED_TOKEN=replace-with-long-random-token
OLLAMA_HOST=http://127.0.0.1:11434
EOF'
sudo chmod 0640 /etc/slime/dashboard.env
sudo systemctl restart slime-dashboard.service
```

Notes:

- `/api/analyst` now fails closed unless `ANALYST_SHARED_TOKEN` is configured.
- `OLLAMA_HOST` must remain localhost-only (`127.0.0.1`, `localhost`, or `::1`).
- Send the shared token in the `X-SLIME-Token` header when calling `/api/analyst`.

## Reboot proof

```bash
sudo reboot
# reconnect
systemctl is-active actuator.service slime.service
ls -l /run/slime/egress.sock
```

## Uninstall

From the repository root:

```bash
./installer/uninstall.sh
```
