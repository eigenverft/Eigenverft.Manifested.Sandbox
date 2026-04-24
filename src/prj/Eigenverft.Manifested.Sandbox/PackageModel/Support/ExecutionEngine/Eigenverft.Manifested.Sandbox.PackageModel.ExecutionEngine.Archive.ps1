<#
    Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.Archive
#>

function Expand-ArchiveToDirectory {
<#
.SYNOPSIS
Expands an archive into a destination directory.

.DESCRIPTION
Ensures the destination directory exists, then extracts the archive into that
directory. Overwrite behavior is controlled through the Overwrite switch so the
archive backend can be replaced later without touching PackageModel flows.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDirectory,

        [switch]$Overwrite
    )

    if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
        throw 'An archive path is required.'
    }

    if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
        throw 'A destination directory is required.'
    }

    $resolvedArchivePath = [System.IO.Path]::GetFullPath($ArchivePath)
    if (-not (Test-Path -LiteralPath $resolvedArchivePath -PathType Leaf)) {
        throw "Archive '$resolvedArchivePath' was not found."
    }

    $resolvedDestinationDirectory = [System.IO.Path]::GetFullPath($DestinationDirectory)
    $null = New-Item -ItemType Directory -Path $resolvedDestinationDirectory -Force

    if ($Overwrite) {
        Expand-Archive -LiteralPath $resolvedArchivePath -DestinationPath $resolvedDestinationDirectory -Force
    }
    else {
        Expand-Archive -LiteralPath $resolvedArchivePath -DestinationPath $resolvedDestinationDirectory
    }

    return $resolvedDestinationDirectory
}

function New-TemporaryStageDirectory {
<#
.SYNOPSIS
Creates a short temporary stage directory for execution-time work.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        throw 'A stage prefix is required.'
    }

    $stageRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'evf', 'stg', $Prefix))
    $null = New-Item -ItemType Directory -Path $stageRoot -Force

    do {
        $stagePath = Join-Path $stageRoot ([Guid]::NewGuid().ToString('N').Substring(0, 12))
    }
    while (Test-Path -LiteralPath $stagePath)

    $null = New-Item -ItemType Directory -Path $stagePath -Force
    return ([System.IO.Path]::GetFullPath($stagePath))
}

function Get-ExpandedArchiveRoot {
<#
.SYNOPSIS
Resolves the effective expanded root inside a stage directory.

.DESCRIPTION
If the archive expands under one top-level directory and no files are written
directly to the stage root, the child directory is returned. Otherwise the
stage root itself is returned.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StagePath
    )

    if ([string]::IsNullOrWhiteSpace($StagePath)) {
        throw 'A stage path is required.'
    }

    $resolvedStagePath = [System.IO.Path]::GetFullPath($StagePath)
    if (-not (Test-Path -LiteralPath $resolvedStagePath -PathType Container)) {
        throw "Stage path '$resolvedStagePath' was not found."
    }

    $directories = @(Get-ChildItem -LiteralPath $resolvedStagePath -Directory -Force -ErrorAction SilentlyContinue)
    $files = @(Get-ChildItem -LiteralPath $resolvedStagePath -File -Force -ErrorAction SilentlyContinue)

    if ($directories.Count -eq 1 -and $files.Count -eq 0) {
        return $directories[0].FullName
    }

    return $resolvedStagePath
}

function Expand-ArchiveToStage {
<#
.SYNOPSIS
Expands an archive into a new temporary stage directory.

.DESCRIPTION
Creates a temporary stage directory, expands the archive into it, and returns
both the stage path and the effective expanded root.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    $stagePath = New-TemporaryStageDirectory -Prefix $Prefix
    Expand-ArchiveToDirectory -ArchivePath $ArchivePath -DestinationDirectory $stagePath -Overwrite | Out-Null

    return [pscustomobject]@{
        StagePath    = $stagePath
        ExpandedRoot = (Get-ExpandedArchiveRoot -StagePath $stagePath)
    }
}
