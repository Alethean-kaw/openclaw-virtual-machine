[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Find-ApplicationPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command.Source
        }
    }

    return $null
}

function Get-HostOs {
    if ($IsWindows) {
        return "windows"
    }

    if ($IsLinux) {
        return "linux"
    }

    throw "Unsupported host operating system for ensure-host.ps1."
}

function Test-RunningInsideVm {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostOs
    )

    if ($HostOs -eq "windows") {
        try {
            $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
            $signals = @(
                $computerSystem.Manufacturer
                $computerSystem.Model
                $bios.Manufacturer
                $bios.SMBIOSBIOSVersion
            ) -join " "

            $haystack = $signals.ToLowerInvariant()
            $markers = @(
                "virtualbox",
                "vmware",
                "kvm",
                "qemu",
                "xen",
                "hyper-v",
                "virtual machine",
                "microsoft corporation virtual",
                "parallels",
                "bhyve"
            )

            foreach ($marker in $markers) {
                if ($haystack.Contains($marker)) {
                    return $true
                }
            }
        } catch {
            return $false
        }

        return $false
    }

    try {
        $virt = Find-ApplicationPath -Candidates @("systemd-detect-virt")
        if ($virt) {
            & $virt --quiet
            if ($LASTEXITCODE -eq 0) {
                return $true
            }
        }

        foreach ($path in @("/sys/class/dmi/id/product_name", "/sys/class/dmi/id/sys_vendor")) {
            if (Test-Path -LiteralPath $path) {
                $content = (Get-Content -LiteralPath $path -Raw).ToLowerInvariant()
                foreach ($marker in @("virtualbox", "vmware", "kvm", "qemu", "xen", "hyper-v", "parallels", "bhyve")) {
                    if ($content.Contains($marker)) {
                        return $true
                    }
                }
            }
        }
    } catch {
        return $false
    }

    return $false
}

function Get-PackageManager {
    foreach ($candidate in @("apt", "dnf", "yum", "pacman")) {
        if (Find-ApplicationPath -Candidates @($candidate)) {
            return $candidate
        }
    }

    return $null
}

function Test-AssetRootHasMaterials {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetRoot
    )

    foreach ($name in @(
        "ubuntu-24.04-server-cloudimg-amd64.img",
        "ubuntu-24.04.4-live-server-amd64.iso",
        "SHA256SUMS",
        "ubuntu-release-SHA256SUMS"
    )) {
        if (Test-Path -LiteralPath (Join-Path $AssetRoot $name)) {
            return $true
        }
    }

    return $false
}

function Resolve-AssetRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SkillRoot
    )

    $parentRoot = Split-Path -Parent $SkillRoot
    $localAssetRoot = Join-Path $SkillRoot "ubuntu"
    $fallbackAssetRoot = Join-Path $parentRoot "ubuntu"

    if (Test-AssetRootHasMaterials -AssetRoot $localAssetRoot) {
        return $localAssetRoot
    }

    if (Test-AssetRootHasMaterials -AssetRoot $fallbackAssetRoot) {
        return $fallbackAssetRoot
    }

    return $localAssetRoot
}

function New-ToolStatus {
    param(
        [AllowNull()]
        $Path
    )

    return [ordered]@{
        found = [bool]$Path
        path  = $Path
    }
}

try {
    $hostOs = Get-HostOs
    $runningInsideVm = Test-RunningInsideVm -HostOs $hostOs

    $scriptRoot = Split-Path -Parent $PSCommandPath
    $skillRoot = Split-Path -Parent $scriptRoot
    $assetRoot = Resolve-AssetRoot -SkillRoot $skillRoot

    $cloudImagePath = Join-Path $assetRoot "ubuntu-24.04-server-cloudimg-amd64.img"
    $isoPath = Join-Path $assetRoot "ubuntu-24.04.4-live-server-amd64.iso"

    if ($hostOs -eq "windows") {
        $qemuSystemPath = Find-ApplicationPath -Candidates @("qemu-system-x86_64.exe", "qemu-system-x86_64")
        $qemuImgPath = Find-ApplicationPath -Candidates @("qemu-img.exe", "qemu-img")
        $sshPath = Find-ApplicationPath -Candidates @("ssh.exe", "ssh")
        $scpPath = Find-ApplicationPath -Candidates @("scp.exe", "scp")
    } else {
        $qemuSystemPath = Find-ApplicationPath -Candidates @("qemu-system-x86_64")
        $qemuImgPath = Find-ApplicationPath -Candidates @("qemu-img")
        $sshPath = Find-ApplicationPath -Candidates @("ssh")
        $scpPath = Find-ApplicationPath -Candidates @("scp")
    }

    $cloudImageFound = Test-Path -LiteralPath $cloudImagePath
    $isoFound = Test-Path -LiteralPath $isoPath

    $missingRequired = New-Object System.Collections.Generic.List[string]
    if (-not $qemuSystemPath) { $missingRequired.Add("qemu_system") }
    if (-not $qemuImgPath) { $missingRequired.Add("qemu_img") }
    if (-not $sshPath) { $missingRequired.Add("ssh") }
    if (-not $scpPath) { $missingRequired.Add("scp") }
    if (-not ($cloudImageFound -or $isoFound)) { $missingRequired.Add("ubuntu_base_asset") }

    $warnings = New-Object System.Collections.Generic.List[string]
    if ($runningInsideVm) {
        $warnings.Add("The host is running inside a virtual machine; QEMU may not have hardware acceleration and performance may be reduced.")
    }

    $guidance = New-Object System.Collections.Generic.List[string]
    $qemuMissing = (-not $qemuSystemPath) -or (-not $qemuImgPath)
    $sshMissing = (-not $sshPath) -or (-not $scpPath)

    if ($qemuMissing) {
        $guidance.Add("QEMU was not detected. VM mode is unavailable and the skill will fall back to sandbox mode.")

        if ($hostOs -eq "windows") {
            $guidance.Add("Install QEMU from the official download page and choose the Windows 64-bit binaries or installer: https://www.qemu.org/download/")
            $guidance.Add("After installation, confirm qemu-system-x86_64.exe and qemu-img.exe are available on PATH, then rerun host validation.")
        } else {
            $packageManager = Get-PackageManager
            switch ($packageManager) {
                "apt" { $guidance.Add("Install QEMU with: sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils") }
                "dnf" { $guidance.Add("Install QEMU with: sudo dnf install -y @virtualization") }
                "yum" { $guidance.Add("Install QEMU with: sudo yum install -y qemu-kvm") }
                "pacman" { $guidance.Add("Install QEMU with: sudo pacman -S qemu") }
                default { $guidance.Add("Install QEMU with your Linux package manager, then rerun host validation.") }
            }
        }
    }

    if ($sshMissing) {
        if ($hostOs -eq "windows") {
            $guidance.Add("OpenSSH client support is required for VM mode. Ensure ssh.exe and scp.exe are available, then rerun host validation.")
        } else {
            $packageManager = Get-PackageManager
            switch ($packageManager) {
                "apt" { $guidance.Add("Install the OpenSSH client with: sudo apt update && sudo apt install -y openssh-client") }
                "dnf" { $guidance.Add("Install the OpenSSH client with: sudo dnf install -y openssh-clients") }
                "yum" { $guidance.Add("Install the OpenSSH client with: sudo yum install -y openssh-clients") }
                "pacman" { $guidance.Add("Install the OpenSSH client with: sudo pacman -S openssh") }
                default { $guidance.Add("Install the OpenSSH client so that ssh and scp are available, then rerun host validation.") }
            }
        }
    }

    if (-not ($cloudImageFound -or $isoFound)) {
        $guidance.Add("Ubuntu VM materials were not found. Download them into ubuntu/ at the repository root. A parent ../ubuntu directory is also accepted as a compatibility fallback.")
    }

    $vmAvailable = $missingRequired.Count -eq 0
    $status = if ($vmAvailable) { "vm_ready" } else { "sandbox_only" }

    $result = [ordered]@{
        host_os = $hostOs
        running_inside_vm = $runningInsideVm
        sandbox_available = $true
        vm_available = $vmAvailable
        status = $status
        tools = [ordered]@{
            qemu_system = New-ToolStatus -Path $qemuSystemPath
            qemu_img = New-ToolStatus -Path $qemuImgPath
            ssh = New-ToolStatus -Path $sshPath
            scp = New-ToolStatus -Path $scpPath
        }
        assets = [ordered]@{
            asset_root = $assetRoot
            cloud_image_found = $cloudImageFound
            iso_found = $isoFound
        }
        missing_required = @($missingRequired)
        guidance = @($guidance)
        warnings = @($warnings)
    }

    $result | ConvertTo-Json -Depth 6
    exit 0
} catch {
    Write-Error $_
    exit 1
}
