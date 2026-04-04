# Download Assets

## Why this file exists

The Ubuntu cloud image and ISO are too large to store comfortably in a normal GitHub repository. This skill expects those assets to exist locally, but not to be committed.

## Default local layout

If `openclaw-vm` is your repository root, download the files into:

- `ubuntu/ubuntu-24.04-server-cloudimg-amd64.img`
- `ubuntu/ubuntu-24.04.4-live-server-amd64.iso`
- `ubuntu/SHA256SUMS`
- `ubuntu/SHA256SUMS.gpg`
- `ubuntu/ubuntu-release-SHA256SUMS`
- `ubuntu/ubuntu-release-SHA256SUMS.gpg`

The scripts also accept `../ubuntu/` as a compatibility fallback when the skill is nested inside a larger workspace, but the repository-local `ubuntu/` directory is the preferred layout for GitHub use.

## Official download sources

Cloud image source:

- `https://cloud-images.ubuntu.com/releases/noble/release/`

Ubuntu release source:

- `https://releases.ubuntu.com/noble/`

## PowerShell commands

```powershell
New-Item -ItemType Directory -Force .\ubuntu | Out-Null

Invoke-WebRequest -Uri "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img" -OutFile ".\ubuntu\ubuntu-24.04-server-cloudimg-amd64.img"
Invoke-WebRequest -Uri "https://cloud-images.ubuntu.com/releases/noble/release/SHA256SUMS" -OutFile ".\ubuntu\SHA256SUMS"
Invoke-WebRequest -Uri "https://cloud-images.ubuntu.com/releases/noble/release/SHA256SUMS.gpg" -OutFile ".\ubuntu\SHA256SUMS.gpg"

Invoke-WebRequest -Uri "https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso" -OutFile ".\ubuntu\ubuntu-24.04.4-live-server-amd64.iso"
Invoke-WebRequest -Uri "https://releases.ubuntu.com/noble/SHA256SUMS" -OutFile ".\ubuntu\ubuntu-release-SHA256SUMS"
Invoke-WebRequest -Uri "https://releases.ubuntu.com/noble/SHA256SUMS.gpg" -OutFile ".\ubuntu\ubuntu-release-SHA256SUMS.gpg"
```

## Linux commands

```bash
mkdir -p ./ubuntu

curl -L "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img" -o "./ubuntu/ubuntu-24.04-server-cloudimg-amd64.img"
curl -L "https://cloud-images.ubuntu.com/releases/noble/release/SHA256SUMS" -o "./ubuntu/SHA256SUMS"
curl -L "https://cloud-images.ubuntu.com/releases/noble/release/SHA256SUMS.gpg" -o "./ubuntu/SHA256SUMS.gpg"

curl -L "https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso" -o "./ubuntu/ubuntu-24.04.4-live-server-amd64.iso"
curl -L "https://releases.ubuntu.com/noble/SHA256SUMS" -o "./ubuntu/ubuntu-release-SHA256SUMS"
curl -L "https://releases.ubuntu.com/noble/SHA256SUMS.gpg" -o "./ubuntu/ubuntu-release-SHA256SUMS.gpg"
```

## Verification

PowerShell:

```powershell
Get-FileHash ".\ubuntu\ubuntu-24.04-server-cloudimg-amd64.img" -Algorithm SHA256
Get-FileHash ".\ubuntu\ubuntu-24.04.4-live-server-amd64.iso" -Algorithm SHA256
Get-Content ".\ubuntu\SHA256SUMS"
Get-Content ".\ubuntu\ubuntu-release-SHA256SUMS"
```

Linux:

```bash
sha256sum ./ubuntu/ubuntu-24.04-server-cloudimg-amd64.img
sha256sum ./ubuntu/ubuntu-24.04.4-live-server-amd64.iso
grep 'ubuntu-24.04-server-cloudimg-amd64.img' ./ubuntu/SHA256SUMS
grep 'ubuntu-24.04.4-live-server-amd64.iso' ./ubuntu/ubuntu-release-SHA256SUMS
```

## Local audit scripts

After downloading, run the local audit script from the repository root:

Windows:

```powershell
.\scripts\check-assets.ps1
```

Linux:

```bash
bash ./scripts/check-assets.sh
```

The audit result tells you whether the repository is:

- `complete`
  - cloud image and ISO are both present and hash-verified
- `usable`
  - the cloud image is present and verified, so the current bootstrap flow can proceed
- `needs_attention`
  - one or more required files are missing, or a checksum mismatch was detected

## Optional note

If you also want the Ubuntu desktop ISO for manual experiments, it is available from the same Ubuntu releases page, but it is not required by the current skill workflow.
