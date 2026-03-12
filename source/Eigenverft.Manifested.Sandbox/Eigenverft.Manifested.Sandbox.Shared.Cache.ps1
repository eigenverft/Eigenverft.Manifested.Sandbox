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

function Get-ManifestedStageDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return @()
    }

    $pattern = '_stage_{0}_*' -f $Prefix
    return @(Get-ChildItem -LiteralPath $RootPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern })
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
    return $true
}
