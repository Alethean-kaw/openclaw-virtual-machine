[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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

function Get-ExpectedSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChecksumPath,
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    if (-not (Test-Path -LiteralPath $ChecksumPath)) {
        return $null
    }

    $escaped = [regex]::Escape($FileName)
    $line = Select-String -Path $ChecksumPath -Pattern "^[0-9a-fA-F]+\s+\*${escaped}$" | Select-Object -First 1
    if (-not $line) {
        return $null
    }

    return ($line.Line -split '\s+')[0].ToLowerInvariant()
}

function New-FileAudit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [AllowNull()]
        [string]$ChecksumPath
    )

    $fileName = Split-Path -Leaf $FilePath
    $present = Test-Path -LiteralPath $FilePath
    $checksumPresent = $false
    $expected = $null
    $actual = $null
    $verified = $false
    $mismatch = $false

    if ($ChecksumPath) {
        $checksumPresent = Test-Path -LiteralPath $ChecksumPath
    }

    if ($present) {
        $actual = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    if ($checksumPresent) {
        $expected = Get-ExpectedSha256 -ChecksumPath $ChecksumPath -FileName $fileName
    }

    if ($present -and $expected) {
        $verified = $actual -eq $expected
        $mismatch = -not $verified
    }

    return [ordered]@{
        present = $present
        checksum_present = $checksumPresent
        verified = $verified
        mismatch = $mismatch
        sha256 = $actual
        expected_sha256 = $expected
        path = $FilePath
        checksum_path = $ChecksumPath
    }
}

try {
    $scriptRoot = Split-Path -Parent $PSCommandPath
    $skillRoot = Split-Path -Parent $scriptRoot
    $assetRoot = Resolve-AssetRoot -SkillRoot $skillRoot

    $cloudImagePath = Join-Path $assetRoot "ubuntu-24.04-server-cloudimg-amd64.img"
    $cloudChecksumsPath = Join-Path $assetRoot "SHA256SUMS"
    $cloudChecksumsGpgPath = Join-Path $assetRoot "SHA256SUMS.gpg"
    $isoPath = Join-Path $assetRoot "ubuntu-24.04.4-live-server-amd64.iso"
    $releaseChecksumsPath = Join-Path $assetRoot "ubuntu-release-SHA256SUMS"
    $releaseChecksumsGpgPath = Join-Path $assetRoot "ubuntu-release-SHA256SUMS.gpg"

    $cloudImage = New-FileAudit -FilePath $cloudImagePath -ChecksumPath $cloudChecksumsPath
    $serverIso = New-FileAudit -FilePath $isoPath -ChecksumPath $releaseChecksumsPath

    $files = [ordered]@{
        cloud_image = $cloudImage
        cloud_checksums = [ordered]@{
            present = (Test-Path -LiteralPath $cloudChecksumsPath)
            path = $cloudChecksumsPath
        }
        cloud_checksums_gpg = [ordered]@{
            present = (Test-Path -LiteralPath $cloudChecksumsGpgPath)
            path = $cloudChecksumsGpgPath
        }
        server_iso = $serverIso
        release_checksums = [ordered]@{
            present = (Test-Path -LiteralPath $releaseChecksumsPath)
            path = $releaseChecksumsPath
        }
        release_checksums_gpg = [ordered]@{
            present = (Test-Path -LiteralPath $releaseChecksumsGpgPath)
            path = $releaseChecksumsGpgPath
        }
    }

    $missingRequired = New-Object System.Collections.Generic.List[string]
    $recommendedMissing = New-Object System.Collections.Generic.List[string]
    $damaged = New-Object System.Collections.Generic.List[string]
    $guidance = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    if (-not $cloudImage.present) { $missingRequired.Add("cloud_image") }
    if (-not $files.cloud_checksums.present) { $missingRequired.Add("cloud_checksums") }
    if (-not $serverIso.present) { $recommendedMissing.Add("server_iso") }
    if (-not $files.release_checksums.present) { $recommendedMissing.Add("release_checksums") }

    if ($cloudImage.present -and $files.cloud_checksums.present -and -not $cloudImage.expected_sha256) {
        $damaged.Add("cloud_checksums_entry_missing")
    }
    if ($cloudImage.mismatch) { $damaged.Add("cloud_image") }
    if ($serverIso.present -and $files.release_checksums.present -and -not $serverIso.expected_sha256) {
        $damaged.Add("release_checksums_entry_missing")
    }
    if ($serverIso.mismatch) { $damaged.Add("server_iso") }

    if (-not $cloudImage.present) {
        $guidance.Add("Download ubuntu-24.04-server-cloudimg-amd64.img into ubuntu/ at the repository root.")
    }
    if (-not $files.cloud_checksums.present) {
        $guidance.Add("Download the cloud-image SHA256SUMS file into ubuntu/SHA256SUMS.")
    }
    if ($cloudImage.mismatch) {
        $guidance.Add("The cloud image hash does not match SHA256SUMS. Redownload ubuntu-24.04-server-cloudimg-amd64.img.")
    }
    if (-not $serverIso.present) {
        $guidance.Add("Download ubuntu-24.04.4-live-server-amd64.iso into ubuntu/ if you want the ISO fallback path available locally.")
    }
    if (-not $files.release_checksums.present) {
        $guidance.Add("Download the Ubuntu release SHA256SUMS file into ubuntu/ubuntu-release-SHA256SUMS.")
    }
    if ($serverIso.mismatch) {
        $guidance.Add("The server ISO hash does not match ubuntu-release-SHA256SUMS. Redownload ubuntu-24.04.4-live-server-amd64.iso.")
    }

    if (-not $files.cloud_checksums_gpg.present) {
        $warnings.Add("The cloud-image SHA256SUMS.gpg file is missing. Integrity can still be checked locally, but detached signature verification is unavailable.")
    }
    if (-not $files.release_checksums_gpg.present) {
        $warnings.Add("The Ubuntu release SHA256SUMS.gpg file is missing. Integrity can still be checked locally, but detached signature verification is unavailable.")
    }

    $status = "needs_attention"
    if ($missingRequired.Count -eq 0 -and $damaged.Count -eq 0 -and $recommendedMissing.Count -eq 0 -and $serverIso.verified) {
        $status = "complete"
    } elseif ($missingRequired.Count -eq 0 -and $damaged.Count -eq 0 -and $cloudImage.verified) {
        $status = "usable"
    }

    $result = [ordered]@{
        status = $status
        asset_root = $assetRoot
        files = $files
        missing_required = @($missingRequired)
        recommended_missing = @($recommendedMissing)
        damaged = @($damaged)
        guidance = @($guidance)
        warnings = @($warnings)
    }

    $result | ConvertTo-Json -Depth 7
    exit 0
} catch {
    Write-Error $_
    exit 1
}
