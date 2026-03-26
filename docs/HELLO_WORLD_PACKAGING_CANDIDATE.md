---
status: candidate
version: 0.1
last_updated: 2026-03-25
scope: slime-enterprise
---

# SLIME-Enterprise Hello World Packaging Candidate

## Purpose

Define the smallest appliance bundle that can honestly be called a
`ready-to-ship candidate` for `SLIME-Enterprise`.

This package is not a business demo.
It is a proof that the appliance chain is installable, fail-closed,
observable, and reproducible on a clean Linux host.

Real field validation remains pending.

## Appliance Role

`SLIME-Enterprise` is the hardened execution appliance above the public
`SLIME` canon.

Its job is to:

- package the execution surface
- boot safely under systemd
- expose a bounded actuator path
- preserve observation without turning the appliance into a product UI

## Hello World Goal

A clean Linux host must be able to:

1. install the appliance
2. boot `slime.service` and `actuator.service`
3. validate the egress socket and service health
4. submit one minimal authorized test action
5. observe one actuator event
6. reboot and recover cleanly
7. uninstall without residue beyond expected logs or state

## Minimal Scenario

### Action

- domain: `test`
- magnitude: `1`

### Expected Result

- the runner returns `AUTHORIZED`
- one 32-byte frame is emitted on the bounded egress path
- `actuator-min` records one observable event
- if the optional dashboard is installed, it shows the event as read-only
  observation

### Non-goals

- no agent layer
- no product semantics
- no dynamic plugin system
- no broad domain registry
- no bidirectional control channel

## Candidate Package Contents

Required:

- `slime-runner`
- `actuator-min`
- `deploy/fireplank-guard-boot.sh`
- `deploy/generate-seal.sh`
- `installer/install.sh`
- `installer/uninstall.sh`
- `installer/systemd/slime.service`
- `installer/systemd/actuator.service`
- `installer/systemd/fp4-hardening-slime.conf`
- `installer/systemd/fp4-hardening-actuator.conf`
- `releases/SHA256SUMS`

Optional:

- dashboard assets
- `installer/systemd/slime-dashboard.service`

Planned candidate artifact:

- `releases/slime-appliance-v0.2.1-hello-world-candidate.tar.gz`

Manifest reference:

- `releases/HELLO_WORLD_CANDIDATE_MANIFEST.txt`

## Install Contract

Inputs:

- Linux host
- systemd
- sudo
- bundle or repo checkout that contains the packaged binaries

Outputs:

- binaries under `/usr/local/bin`
- unit files under `/etc/systemd/system`
- runtime directory under `/run/slime`
- egress socket at `/run/slime/egress.sock`
- boot seal under `/usr/lib/slime/fireplank.seal`

## Validation Contract

Minimum validation sequence:

```bash
systemctl is-active actuator.service slime.service
ls -ld /run/slime
ls -l /run/slime/egress.sock
curl -sS -X POST http://127.0.0.1:8080/action \
  -H "Content-Type: application/json" \
  -d '{"domain":"test","magnitude":1}'
tail -n 5 /var/log/slime-actuator/events.log
```

Expected:

- both services active
- socket present
- action returns `AUTHORIZED`
- one new actuator event appears

If dashboard assets are present:

```bash
systemctl is-active slime-dashboard.service
curl -fsS http://127.0.0.1:8081/ >/dev/null
```

## Reboot Proof

The package is not accepted until this also works after reboot:

```bash
systemctl is-active actuator.service slime.service
ls -l /run/slime/egress.sock
```

Expected:

- services recover automatically
- socket is recreated correctly
- if the socket is missing, the appliance remains fail-closed

## Release Acceptance Criteria

`SLIME-Enterprise Hello World Candidate` is accepted only if:

1. install works from a fresh supported Linux host
2. validation commands match the real package paths
3. reboot proof passes
4. uninstall works cleanly
5. release checksum is published with the bundle
6. the package does not require a separate public `SLIME` checkout at install
   time
7. the package is described as a `ready-to-ship candidate`, not as fully field
   validated production hardware or enterprise deployment

## Remaining Gaps Before True Ship Readiness

This candidate still leaves later work:

- regenerate the release tarball so it matches the current repo state
- add end-to-end Linux install validation in CI
- define release signing and provenance beyond plain checksums
- validate upgrade and rollback paths

## Relationship to SAFA

`SLIME-Enterprise` is the execution appliance.

Later packaging should allow the clean chain:

`SCLAPY -> SAFA -> SLIME-Enterprise -> actuator -> system effect`

`SAFA` is not part of this package.
It is the adjacent adapter layer that will rely on this appliance for a
ready-to-ship execution path.
