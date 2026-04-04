# OpenClaw VM

`openclaw-vm` is an OpenClaw skill for choosing between sandbox execution and a headless CLI virtual machine workflow.

## Current status

The current implementation covers:

- host preflight for Windows and Linux
- QEMU dependency detection
- sandbox fallback when VM dependencies are missing
- base image bootstrap planning and cloud-image-based bootstrap entrypoints

The current implementation does not yet include full VM session lifecycle management.

## Why large images are not in Git

Ubuntu cloud images and ISO files are too large for a normal GitHub workflow, so they are intentionally excluded from version control.

Download them locally into:

- `ubuntu/ubuntu-24.04-server-cloudimg-amd64.img`
- `ubuntu/ubuntu-24.04.4-live-server-amd64.iso`

See `references/download-assets.md` for official download URLs, commands, and verification steps.

## Quick start

Windows:

```powershell
.\scripts\ensure-host.ps1
.\scripts\bootstrap-base-image.ps1
```

Linux:

```bash
bash ./scripts/ensure-host.sh
bash ./scripts/bootstrap-base-image.sh
```

## Key files

- `SKILL.md`
  - runtime behavior for OpenClaw
- `references/host-dependencies.md`
  - host requirements and dependency policy
- `references/base-image-bootstrap.md`
  - base image bootstrap behavior and result contract
- `references/download-assets.md`
  - local asset download and verification guide

## Asset path policy

Preferred layout:

- `ubuntu/` inside this repository root

Compatibility fallback:

- `../ubuntu/` when this skill is nested inside a larger workspace

The scripts automatically prefer the first location that actually contains VM materials.
