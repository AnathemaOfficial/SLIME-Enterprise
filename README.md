
<img width="1199" height="349" alt="SLIME logo 2" src="https://github.com/user-attachments/assets/93edba17-2061-406a-8081-d19288c77816" />

# SLIME Enterprise

**Sealed Law-layer Execution Environment — Enterprise Appliance**

Private commercial distribution by SYFCORP.

## Contents

| Directory | Description |
|---|---|
| `actuator-min/` | Hardened actuator source (Rust, egress socket bridge) |
| `dashboard/` | Read-only observation server (Python + HTML) |
| `deploy/` | FP-1 boot integrity, FP-4 systemd hardening, seal generation |
| `adversarial/` | Phase 4 security test suite (8 attack vectors + 5 structural tests) |
| `installer/` | 12-step install/uninstall scripts + prebuilt binaries |
| `docs/` | Architecture docs (TCB, double membrane, ABI, FAQ) |
| `releases/` | Distributable `.tar.gz` appliance packages |

## Relationship to SLIME (Public)

This repo contains the **commercial enterprise layer** built on top of the
open-source [SLIME](https://github.com/AnathemaOfficial/SLIME) framework.

SLIME (public) provides the canonical specs, formal core, and a reference
runner with a stub resolver. This repo adds:

- Real actuator implementation (egress bridge)
- Production systemd packaging with security hardening
- Boot-time binary integrity verification (FirePlank)
- Web dashboard for operational monitoring
- Adversarial validation test suite
- One-command installer for Linux servers

## Requirements

- Linux server (Ubuntu 22.04+ / Debian 12+)
- SLIME runner binary (compiled from public repo with `real_ab` feature)
- Anathema-Breaker engine (private dependency)
