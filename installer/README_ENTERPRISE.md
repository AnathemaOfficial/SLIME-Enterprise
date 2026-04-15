# SLIME Enterprise Appliance (v0.1)

This bundle installs:

- `/usr/local/bin/slime-runner`
- `/usr/local/bin/actuator-min`
- `/usr/local/bin/fireplank-guard-boot.sh`
- `/usr/local/bin/generate-seal.sh`
- systemd units: `actuator.service`, `slime.service`

If dashboard assets are present, it also installs:

- `/opt/slime/dashboard/*`
- `slime-dashboard.service`
- optional `/etc/slime/dashboard.env` operator config for AI Analyst auth

Properties:

- fail-closed: `slime.service` requires `actuator.service`
- `actuator-min` owns `/run/slime/egress.sock`
- dashboard is optional and read-only

Install:

```bash
./installer/install.sh
```

If you enable the dashboard AI Analyst later, configure `/etc/slime/dashboard.env`
with `ANALYST_SHARED_TOKEN` and a localhost-only `OLLAMA_HOST`, then restart
`slime-dashboard.service`.

Uninstall:

```bash
./installer/uninstall.sh
```
