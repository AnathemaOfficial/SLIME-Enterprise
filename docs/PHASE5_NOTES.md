# Phase 5 — Hardening + Deployment Readiness (syf-node)

Date: 2026-03-04
Node: syf-node (Ubuntu Server 24.04)

## 1) Fix: no AUTHORIZED without egress (runner noncanon)
Change: `noncanon/implementation_bundle/slime-runner/src/main.rs`
Behavior: if `write_all(egress_frame)` fails, runner exits (fail-closed).
Rationale: prevents "AUTHORIZED phantom" (HTTP OK but no actuation frame).

Commit: f5b95a9 (pushed to main)

## 2) Fix: systemd ordering (boot readiness)
Problem: slime could start before actuator created `/run/slime/egress.sock` (race) → ExecStartPre failure.
Fix: `slime.service` override includes unit ordering:
- After=actuator.service
- Requires=actuator.service

Result: boot ordering HELD; socket present before slime start.

## 3) Proof (commands)

systemctl is-active actuator slime
ls -l /run/slime/egress.sock
curl -sS -m 2 -X POST http://127.0.0.1:8080/action

-H 'Content-Type: application/json'
-d '{"domain":"test","magnitude":1,"payload":"AA=="}'

Expected:
- actuator=active
- slime=active
- egress.sock exists (0660, actuator:slime-actuator)
- response: {"status":"AUTHORIZED"}

## 4) AVP
- T08_backpressure_stall.sh: PASS (no bypass during stall; drain on restart confirmed)
- T07_domain_collision.sh: SKIP (requires sealed domain registry)
- T06_replay_frame.sh: SKIP unless frame logger provides FRAME_HEX capture (future enterprise logger)

## 5) Hotfix (runtime stability)
- Runner reconnects once on egress write failure; if still failing → fail-closed (exit 1).
- Prevents empty-reply crash while preserving 'no AUTHORIZED without egress'.
