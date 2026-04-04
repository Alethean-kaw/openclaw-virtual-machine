# Host Dependencies

## Supported hosts

This skill supports these host operating systems in v1:

- Windows
- Linux

## Required VM commands

Windows:

- `qemu-system-x86_64.exe`
- `qemu-img.exe`
- `ssh.exe`
- `scp.exe`

Linux:

- `qemu-system-x86_64`
- `qemu-img`
- `ssh`
- `scp`

## Required project materials

At least one of these repository-relative assets must exist before VM mode can be considered ready:

- `ubuntu/ubuntu-24.04-server-cloudimg-amd64.img`
- `ubuntu/ubuntu-24.04.4-live-server-amd64.iso`

The cloud image is preferred. The ISO is the fallback.

## Default behavior when QEMU is missing

- Do not treat missing QEMU as a script crash.
- Return successful preflight execution with `status` set to `sandbox_only`.
- Keep sandbox mode available.
- Present host-specific installation guidance.

## Windows installation guidance

Windows guidance is intentionally conservative in v1:

- Do not emit package-manager-specific commands.
- Direct the user to the official QEMU download page:
  - `https://www.qemu.org/download/`
- Tell the user to install the Windows 64-bit binaries or installer.
- Require both of these commands to be callable from `PATH` after installation:
  - `qemu-system-x86_64.exe`
  - `qemu-img.exe`

## Linux installation guidance

Package manager priority:

1. `apt`
2. `dnf`
3. `yum`
4. `pacman`

Default QEMU install commands:

- Debian or Ubuntu:
  - `sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils`
- Fedora:
  - `sudo dnf install -y @virtualization`
- RHEL or CentOS:
  - `sudo yum install -y qemu-kvm`
- Arch:
  - `sudo pacman -S qemu`

If `ssh` or `scp` is also missing, append host-specific OpenSSH client guidance.

## Nested virtualization warning

If the host itself is running inside a VM, return a warning that performance may be reduced because QEMU may not have hardware acceleration. Do not block VM mode when the rest of the requirements are satisfied.
