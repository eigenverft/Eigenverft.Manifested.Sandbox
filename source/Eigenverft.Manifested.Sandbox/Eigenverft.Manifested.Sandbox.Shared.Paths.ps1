<#
    Eigenverft.Manifested.Sandbox.Shared.Paths
#>

function Get-ManifestedLocalRoot {
    [CmdletBinding()]
    param()

    return (Join-Path $env:LOCALAPPDATA 'Eigenverft.Manifested.Sandbox')
}

function New-ManifestedDirectory {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($PSCmdlet.ShouldProcess($fullPath, 'Create Directory')) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }

    if (Test-Path -LiteralPath $Path) {
        return (Get-Item -LiteralPath $Path).FullName
    }

    return $fullPath
}

function Get-ManifestedLayout {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($LocalRoot)
    $cacheRoot = Join-Path $resolvedRoot 'cache'
    $toolsRoot = Join-Path $resolvedRoot 'tools'

    [pscustomobject]@{
        LocalRoot          = $resolvedRoot
        CacheRoot          = $cacheRoot
        NodeCacheRoot      = (Join-Path $cacheRoot 'node')
        VCRuntimeCacheRoot = (Join-Path $cacheRoot 'vc-runtime')
        ToolsRoot          = $toolsRoot
        NodeToolsRoot      = (Join-Path $toolsRoot 'node')
        StatePath          = (Join-Path $resolvedRoot 'state.json')
    }
}

function New-ManifestedStageDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    New-ManifestedDirectory -Path $RootPath | Out-Null

    $stagePath = Join-Path $RootPath ('_stage_{0}_{1}' -f $Prefix, [Guid]::NewGuid().ToString('N'))
    New-ManifestedDirectory -Path $stagePath | Out-Null

    return $stagePath
}
