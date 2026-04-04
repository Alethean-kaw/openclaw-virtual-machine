# Base Image Bootstrap

## Goal

Create a reusable base image under the skill runtime tree so later VM lifecycle scripts can clone it instead of repeatedly bootstrapping from scratch.

## Current support

Implemented in the current phase:

- host-aware bootstrap entrypoints
- project-relative path resolution
- cloud image to qcow2 conversion
- metadata recording for the base image

Not yet implemented in the current phase:

- unattended installation from the Ubuntu ISO
- cloud-init seeding
- booting and validating the guest

## Source selection

Use these asset roots in this order:

1. `ubuntu/` inside the repository root
2. `../ubuntu/` as a compatibility fallback for nested workspace layouts

Within the resolved asset root, use these source files in this order:

1. `ubuntu-24.04-server-cloudimg-amd64.img`
2. `ubuntu-24.04.4-live-server-amd64.iso`

The cloud image is the supported bootstrap source in this phase.

If only the ISO is present, the script should return a structured `blocked` result with guidance rather than pretending bootstrap succeeded.

## Output paths

Write outputs under the skill directory:

- Base image:
  - `runtime/cache/base-images/ubuntu-24.04-base.qcow2`
- Metadata:
  - `runtime/cache/base-images/ubuntu-24.04-base.json`

## Bootstrap behavior

The bootstrap script should:

1. Run host preflight first.
2. Resolve the preferred asset root.
3. Resolve the preferred source asset.
4. Reuse the existing base image unless forced.
5. Convert the cloud image into qcow2 format with `qemu-img`.
6. Write metadata describing how the base image was created.

## Result contract

The bootstrap scripts return JSON with these result states:

- `blocked`
  - prerequisites or supported source are missing
- `exists`
  - the base image already exists and is reused
- `dry_run`
  - the script resolved all paths and would create the base image, but did not mutate files
- `created`
  - the base image was created in the runtime cache

## Expected guidance rules

- If `qemu-img` is missing, return `blocked` with installation guidance.
- If the cloud image is missing and only the ISO is present, return `blocked` and explain that ISO bootstrap is not yet implemented in this phase.
- If no source material exists, return `blocked` with the expected local download paths.
- If the repository is being hosted on GitHub, do not commit the large assets; instead download them locally by following `references/download-assets.md`.
