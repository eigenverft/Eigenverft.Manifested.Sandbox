<#
    Eigenverft.Manifested.Sandbox.Shared.Cache
#>

function Get-ManifestedDownloadPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    return ($TargetPath + '.download')
}

function Get-ManifestedExpandedArchiveRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StagePath
    )

    $directories = @(Get-ChildItem -LiteralPath $StagePath -Directory -Force -ErrorAction SilentlyContinue)
    $files = @(Get-ChildItem -LiteralPath $StagePath -File -Force -ErrorAction SilentlyContinue)

    if ($directories.Count -eq 1 -and $files.Count -eq 0) {
        return $directories[0].FullName
    }

    return $StagePath
}

function Get-ManifestedArtifactMetadataPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArtifactPath
    )

    return ($ArtifactPath + '.metadata.json')
}

function Get-ManifestedArtifactMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArtifactPath
    )

    $metadataPath = Get-ManifestedArtifactMetadataPath -ArtifactPath $ArtifactPath
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        return $null
    }

    try {
        return ((Get-Content -LiteralPath $metadataPath -Raw -ErrorAction Stop) | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Save-ManifestedArtifactMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArtifactPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Metadata
    )

    $metadataPath = Get-ManifestedArtifactMetadataPath -ArtifactPath $ArtifactPath
    $metadataDirectory = Split-Path -Parent $metadataPath
    if (-not [string]::IsNullOrWhiteSpace($metadataDirectory)) {
        New-ManifestedDirectory -Path $metadataDirectory | Out-Null
    }

    ([pscustomobject]$Metadata | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $metadataPath -Encoding UTF8
    return $metadataPath
}

function Remove-ManifestedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    $metadataPath = Get-ManifestedArtifactMetadataPath -ArtifactPath $Path
    if (Test-Path -LiteralPath $metadataPath) {
        Remove-Item -LiteralPath $metadataPath -Force -ErrorAction SilentlyContinue
    }
    return $true
}
