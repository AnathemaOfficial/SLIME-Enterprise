<img width="1199" height="349" alt="SLIME logo ENTERPRISE" src="https://github.com/user-attachments/assets/3cfdde9c-0052-48a9-9b68-0ebc85182c01" />

# SLIME Enterprise

**Sealed law-layer execution appliance**

Open-source enterprise appliance by SYFCORP.

## Contents

| Directory | Description |
|---|---|
| `actuator-min/` | hardened reference actuator source (Rust, Unix socket bridge) |
| `dashboard/` | optional read-only observation server |
| `deploy/` | FirePlank boot integrity and seal generation scripts |
| `adversarial/` | adversarial validation suite |
| `installer/` | install/uninstall scripts, systemd units, bundled binaries |
| `docs/` | architecture, TCB, ABI, install, FAQ |
| `releases/` | distributable appliance bundles and checksums |

## Packaging Candidate

The current repo-level packaging target is documented in:

- `docs/HELLO_WORLD_PACKAGING_CANDIDATE.md`

## Relationship to SLIME (Public)

This repository is the **enterprise appliance layer** around the public
`SLIME` canon.

The public `SLIME` repository provides:

- canonical specs
- formal core
- bounded public runner surface

This repository adds the appliance layer:

- bundled runner binary for the appliance
- bundled reference actuator
- systemd packaging and hardening
- FirePlank boot integrity scripts
- optional read-only dashboard
- adversarial validation material

It should not describe the public `SLIME` checkout as if the public repo itself
contained the private enterprise wiring.

## Requirements

For installation from this repository or its release bundle:

- Linux server (Ubuntu 22.04+ / Debian 12+)
- systemd
- `sudo`
- bundled binaries from `installer/bin/` or a release tarball

The public `SLIME` repo remains the law/spec surface.
This appliance ships its own packaging surface.

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

If dashboard assets are installed:

```bash
systemctl is-active slime-dashboard.service
curl -fsS http://127.0.0.1:8081/ >/dev/null
```
