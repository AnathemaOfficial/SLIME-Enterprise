# SLIME Enterprise Appliance (v0.1)

This bundle installs:
- /usr/local/bin/slime-runner
- /usr/local/bin/actuator-min (reference actuator owning /run/slime/egress.sock)
- systemd units: actuator.service, slime.service

Properties:
- fail-closed: SLIME requires actuator.service (socket owner).
- actuator-min listens on /run/slime/egress.sock and logs 32-byte events.

Install:
  cd enterprise/slime-enterprise
  ./install.sh

Uninstall:
  cd enterprise/slime-enterprise
  ./uninstall.sh
