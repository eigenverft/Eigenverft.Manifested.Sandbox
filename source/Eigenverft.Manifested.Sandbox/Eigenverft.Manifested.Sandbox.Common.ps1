<#
    Eigenverft.Manifested.Sandbox.Common
#>

function Get-SandboxDefaultLocalRoot {
    [CmdletBinding()]
    param()

    return (Join-Path $env:LOCALAPPDATA 'Eigenverft.Manifested.Sandbox')
}

function ConvertTo-NodeVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, 'v?(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Ensure-SandboxDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    return (Get-Item -LiteralPath $Path).FullName
}

function Get-SandboxLayout {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-SandboxDefaultLocalRoot)
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($LocalRoot)
    $cacheRoot = Join-Path $resolvedRoot 'cache'
    $toolsRoot = Join-Path $resolvedRoot 'tools'

    [pscustomobject]@{
        LocalRoot         = $resolvedRoot
        CacheRoot         = $cacheRoot
        NodeCacheRoot     = (Join-Path $cacheRoot 'node')
        VCRuntimeCacheRoot = (Join-Path $cacheRoot 'vc-runtime')
        ToolsRoot         = $toolsRoot
        NodeToolsRoot     = (Join-Path $toolsRoot 'node')
    }
}
