[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function New-StringList {
    return New-Object System.Collections.Generic.List[string]
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

function Get-PreflightResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnsureHostPath
    )

    $json = & $EnsureHostPath | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Host preflight failed."
    }

    return $json | ConvertFrom-Json
}

function Write-MetadataFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Metadata
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $Metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path
}

try {
    $scriptRoot = Split-Path -Parent $PSCommandPath
    $skillRoot = Split-Path -Parent $scriptRoot
    $assetRoot = Resolve-AssetRoot -SkillRoot $skillRoot
    $ensureHostPath = Join-Path $scriptRoot "ensure-host.ps1"

    $cloudImagePath = Join-Path $assetRoot "ubuntu-24.04-server-cloudimg-amd64.img"
    $isoPath = Join-Path $assetRoot "ubuntu-24.04.4-live-server-amd64.iso"
    $baseImageDir = Join-Path $skillRoot "runtime\cache\base-images"
    $baseImagePath = Join-Path $baseImageDir "ubuntu-24.04-base.qcow2"
    $metadataPath = Join-Path $baseImageDir "ubuntu-24.04-base.json"

    $preflight = Get-PreflightResult -EnsureHostPath $ensureHostPath

    $guidance = New-StringList
    $warnings = New-StringList

    foreach ($item in @($preflight.warnings)) {
        if ($null -ne $item -and $item -ne "") {
            $warnings.Add([string]$item)
        }
    }

    $sourceType = $null
    $sourcePath = $null
    $cloudImageFound = Test-Path -LiteralPath $cloudImagePath
    $isoFound = Test-Path -LiteralPath $isoPath

    if ($cloudImageFound) {
        $sourceType = "cloud_image"
        $sourcePath = $cloudImagePath
    } elseif ($isoFound) {
        $sourceType = "iso"
        $sourcePath = $isoPath
    }

    $qemuImgPath = $preflight.tools.qemu_img.path
    $baseImageFound = Test-Path -LiteralPath $baseImagePath
    $status = "blocked"
    $created = $false
    $reusedExisting = $false

    if ($baseImageFound -and -not $Force) {
        $status = "exists"
        $reusedExisting = $true
    } else {
        if (-not $qemuImgPath) {
            $guidance.Add("qemu-img is required to build the base image.")
            foreach ($item in @($preflight.guidance)) {
                if ($null -ne $item -and $item -ne "") {
                    $guidance.Add([string]$item)
                }
            }
        }

        if (-not $sourceType) {
            $guidance.Add("No Ubuntu bootstrap source was found. Download the files into ubuntu/ at the repository root. A parent ../ubuntu directory is also accepted as a compatibility fallback.")
        } elseif ($sourceType -eq "iso") {
            $guidance.Add("ISO bootstrap was detected, but unattended ISO installation is not implemented yet in this phase.")
            $guidance.Add("Keep the ISO as project material, but use the cloud image to create the first reusable base image.")
        }

        if ($qemuImgPath -and $sourceType -eq "cloud_image") {
            if ($DryRun) {
                $status = "dry_run"
                $guidance.Add("Dry run complete. The cloud image is available and qemu-img can create the base image when you rerun without -DryRun.")
            } else {
                if (-not (Test-Path -LiteralPath $baseImageDir)) {
                    New-Item -ItemType Directory -Path $baseImageDir -Force | Out-Null
                }

                $tempBaseImagePath = "$baseImagePath.tmp"
                if (Test-Path -LiteralPath $tempBaseImagePath) {
                    Remove-Item -LiteralPath $tempBaseImagePath -Force
                }

                & $qemuImgPath "convert" "-p" "-O" "qcow2" $sourcePath $tempBaseImagePath
                if ($LASTEXITCODE -ne 0) {
                    throw "qemu-img convert failed with exit code $LASTEXITCODE."
                }

                Move-Item -LiteralPath $tempBaseImagePath -Destination $baseImagePath -Force
                $status = "created"
                $created = $true
                $baseImageFound = $true
            }
        }
    }

    if (($status -eq "created" -or $status -eq "exists") -and -not $DryRun) {
        $metadata = [ordered]@{
            asset_root = $assetRoot
            base_image_path = $baseImagePath
            source_type = $sourceType
            source_path = $sourcePath
            created_with = if ($created) { "bootstrap-base-image.ps1" } else { "existing-base-image" }
            created_at = (Get-Date).ToString("o")
            host_os = [string]$preflight.host_os
            preflight_status = [string]$preflight.status
            force = [bool]$Force
        }

        Write-MetadataFile -Path $metadataPath -Metadata $metadata
    }

    $result = [ordered]@{
        status = $status
        host_os = [string]$preflight.host_os
        preflight_status = [string]$preflight.status
        asset_root = $assetRoot
        source_type = $sourceType
        source_path = $sourcePath
        base_image_path = $baseImagePath
        metadata_path = $metadataPath
        base_image_found = $baseImageFound
        created = $created
        reused_existing = $reusedExisting
        force = [bool]$Force
        dry_run = [bool]$DryRun
        guidance = @($guidance)
        warnings = @($warnings)
    }

    $result | ConvertTo-Json -Depth 6
    exit 0
} catch {
    Write-Error $_
    exit 1
}
