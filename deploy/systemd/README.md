# SLIME v0 — systemd deploy (Linux)

This bundle installs two services:

- actuator.service (socket owner): creates /run/slime/egress.sock (0660, actuator:slime-actuator)
- slime.service (client-only): runs SLIME runner and connects to the socket (fail-closed)

Paths:

- /opt/slime/bin/slime-runner
- /opt/slime/bin/actuator-binary
- WorkingDirectory=/opt/slime

Install:

sudo bash deploy/systemd/install.sh

Verify:

systemctl status actuator --no-pager
systemctl status slime --no-pager
sudo stat -c "%U %G %a %n" /run/slime /run/slime/egress.sock

Test (egress):

curl -sS -X POST http://127.0.0.1:8080/action -H "Content-Type: application/json" -d '{"domain":"test","magnitude":10,"payload":""}'
sudo journalctl -u actuator -n 20 --no-pager

