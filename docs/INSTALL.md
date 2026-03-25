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
