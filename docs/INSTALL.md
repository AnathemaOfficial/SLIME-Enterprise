# INSTALL (Enterprise Appliance v0.1)

## Prereqs
- Ubuntu Server 24.04+
- systemd
- sudo access

## Install

```bash
cd enterprise/slime-enterprise
./install.sh
```

## Validate (proof)

```bash
systemctl is-active actuator.service slime.service
ls -ld /run/slime
ls -l /run/slime/egress.sock
```

Expected:

- active / active
- /run/slime owned by actuator:slime-actuator
- egress.sock perms srw-rw---- (0660)

## Reboot proof

```bash
sudo reboot
# reconnect
systemctl is-active actuator.service slime.service
ls -l /run/slime/egress.sock
```

## Uninstall

```bash
cd enterprise/slime-enterprise
./uninstall.sh
```
