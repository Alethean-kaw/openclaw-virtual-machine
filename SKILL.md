---
name: openclaw-vm
description: Run tasks in either the normal sandbox or a headless CLI virtual machine with all important state kept under stable project-relative paths. Use when Codex or OpenClaw needs host preflight checks, QEMU dependency validation, sandbox fallback when VM dependencies are missing, or a controlled path toward isolated Linux VM execution.
---

# OpenClaw VM

Use this skill to decide whether a task should stay in the sandbox or can proceed into a headless VM workflow.

## Current scope

This v1 skill implements:

- host preflight and dependency guidance
- base image bootstrap from the project cloud image

It does not yet boot, connect to, or manage VM sessions.

## Required workflow

1. Resolve the skill root from the current file location.
2. Treat the repository root as the parent of the skill root.
3. Before any VM action, run the host preflight script for the current host:
   - Windows host: `openclaw-vm/scripts/ensure-host.ps1`
   - Linux host: `openclaw-vm/scripts/ensure-host.sh`
4. Parse the JSON output and treat it as the single source of truth for host readiness.
5. If you need a reusable base image, run the bootstrap script for the current host:
   - Windows host: `openclaw-vm/scripts/bootstrap-base-image.ps1`
   - Linux host: `openclaw-vm/scripts/bootstrap-base-image.sh`
6. If preflight returns `status` as `sandbox_only`, do not attempt VM session lifecycle work. Continue with sandbox-safe work and show the user the `guidance` entries from the preflight result.
7. Base image bootstrap may still report a structured `blocked` result instead of crashing. Surface its `guidance` to the user.

## Fixed behavior

- `sandbox_available` is always true.
- Missing QEMU is not a fatal error for the skill.
- Missing QEMU forces a sandbox-only downgrade and installation guidance.
- Running inside a VM only produces a warning. It does not block VM mode by itself.
- Base image bootstrap currently supports the cloud image path first.
- The ISO path is recognized but unattended ISO bootstrap is not implemented yet.
- VM materials are expected at repository-relative paths:
  - `ubuntu/ubuntu-24.04-server-cloudimg-amd64.img`
  - `ubuntu/ubuntu-24.04.4-live-server-amd64.iso`

## References

- Read `references/host-dependencies.md` for the supported host matrix, required commands, install guidance, and downgrade rules.
- Read `references/base-image-bootstrap.md` for the base image output paths, source selection rules, and bootstrap result contract.
