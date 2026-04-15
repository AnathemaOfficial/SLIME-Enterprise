# SLIME Enterprise - systemd deploy bundle

This bundle installs the minimal enterprise runtime:

- `actuator.service` - runs `actuator-min`, owns `/run/slime/egress.sock`, and is guarded by FirePlank at boot
- `slime.service` - runs the runner, waits for the actuator socket, and fails closed if the membrane is unavailable

Paths:

- `/usr/local/bin/slime-runner`
- `/usr/local/bin/actuator-min`
- `/usr/local/bin/fireplank-guard-boot.sh`
- `/usr/local/bin/generate-seal.sh`
- `/usr/lib/slime/fireplank.seal`
- `/var/log/slime-actuator/events.log`

Install:

```bash
sudo bash deploy/systemd/install.sh
```

Notes:

- The installer auto-imports legacy binaries from `/opt/slime/bin` if needed.
- The deploy bundle installs the FP-4 hardening drop-ins.
- This bundle does not install the optional dashboard; use the main appliance installer for that.

Verify:

```bash
systemctl status actuator.service --no-pager
systemctl status slime.service --no-pager
sudo stat -c "%U %G %a %n" /run/slime /run/slime/egress.sock
sudo cat /usr/lib/slime/fireplank.seal
```

Test (egress):

```bash
curl -sS -X POST http://127.0.0.1:8080/action -H "Content-Type: application/json" -d '{"domain":"test","magnitude":10,"payload":""}'
sudo journalctl -u actuator.service -n 20 --no-pager
```
