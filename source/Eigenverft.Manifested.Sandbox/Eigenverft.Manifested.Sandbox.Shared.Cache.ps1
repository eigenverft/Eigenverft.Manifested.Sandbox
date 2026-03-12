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
