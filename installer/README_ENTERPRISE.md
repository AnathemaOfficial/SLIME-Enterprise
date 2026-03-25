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

Properties:

- fail-closed: `slime.service` requires `actuator.service`
- `actuator-min` owns `/run/slime/egress.sock`
- dashboard is optional and read-only

Install:

```bash
./installer/install.sh
```

Uninstall:

```bash
./installer/uninstall.sh
```
