<#
    Eigenverft.Manifested.Sandbox.Shared.Paths
#>

function Get-ManifestedLocalRoot {
    [CmdletBinding()]
    param()

    $pinnedLocalRoot = [System.Environment]::GetEnvironmentVariable('EIGENVERFT_MANIFESTED_LOCALROOT', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($pinnedLocalRoot)) {
        return [System.IO.Path]::GetFullPath($pinnedLocalRoot)
    }

    return (Join-Path $env:LOCALAPPDATA 'Eigenverft.Manifested.Sandbox')
}

function Get-ManifestedFullPath {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Test-ManifestedPathIsUnderRoot {
    [CmdletBinding()]
    param(
        [string]$Path,

        [string]$RootPath
    )

    $fullPath = Get-ManifestedFullPath -Path $Path
    $fullRoot = Get-ManifestedFullPath -Path $RootPath
    if ([string]::IsNullOrWhiteSpace($fullPath) -or [string]::IsNullOrWhiteSpace($fullRoot)) {
        return $false
    }

    $normalizedPath = $fullPath.TrimEnd('\')
    $normalizedRoot = $fullRoot.TrimEnd('\')
    if ($normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $normalizedPath.StartsWith(($normalizedRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ManifestedApplicationPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string[]]$ExcludedRoots = @(),

        [string[]]$AdditionalPaths = @()
    )

    $candidatePaths = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @(Get-Command -Name $CommandName -CommandType Application -All -ErrorAction SilentlyContinue)) {
        $candidatePath = $null
        if ($candidate.PSObject.Properties['Path'] -and $candidate.Path) {
            $candidatePath = $candidate.Path
        }
        elseif ($candidate.PSObject.Properties['Source'] -and $candidate.Source) {
            $candidatePath = $candidate.Source
        }

        if (-not [string]::IsNullOrWhiteSpace($candidatePath)) {
            $candidatePaths.Add($candidatePath) | Out-Null
        }
    }

    foreach ($candidatePath in @($AdditionalPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($candidatePath)) {
            $candidatePaths.Add($candidatePath) | Out-Null
        }
    }

    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $fullCandidatePath = Get-ManifestedFullPath -Path $candidatePath
        if ([string]::IsNullOrWhiteSpace($fullCandidatePath) -or -not (Test-Path -LiteralPath $fullCandidatePath)) {
            continue
        }

        $isExcluded = $false
        foreach ($excludedRoot in @($ExcludedRoots)) {
            if (Test-ManifestedPathIsUnderRoot -Path $fullCandidatePath -RootPath $excludedRoot) {
                $isExcluded = $true
                break
            }
        }

        if (-not $isExcluded) {
            return $fullCandidatePath
        }
    }

    return $null
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
    $reportsRoot = Join-Path $resolvedRoot 'reports'
    $toolsRoot = Join-Path $resolvedRoot 'tools'

    [pscustomobject]@{
        LocalRoot          = $resolvedRoot
        CacheRoot          = $cacheRoot
        ReportsRoot        = $reportsRoot
        Ps7CacheRoot       = (Join-Path $cacheRoot 'powershell')
        PythonCacheRoot    = (Join-Path $cacheRoot 'python')
        NodeCacheRoot      = (Join-Path $cacheRoot 'node')
        OpenCodeCacheRoot  = (Join-Path $cacheRoot 'opencode')
        GeminiCacheRoot    = (Join-Path $cacheRoot 'gemini')
        QwenCacheRoot      = (Join-Path $cacheRoot 'qwen')
        CodexCacheRoot     = (Join-Path $cacheRoot 'codex')
        GHCliCacheRoot     = (Join-Path $cacheRoot 'ghcli')
        GitCacheRoot       = (Join-Path $cacheRoot 'git')
        VsCodeCacheRoot    = (Join-Path $cacheRoot 'vscode')
        VCRuntimeCacheRoot = (Join-Path $cacheRoot 'vc-runtime')
        ToolsRoot          = $toolsRoot
        Ps7ToolsRoot       = (Join-Path $toolsRoot 'powershell')
        PythonToolsRoot    = (Join-Path $toolsRoot 'python')
        NodeToolsRoot      = (Join-Path $toolsRoot 'node')
        OpenCodeToolsRoot  = (Join-Path $toolsRoot 'opencode')
        GeminiToolsRoot    = (Join-Path $toolsRoot 'gemini')
        QwenToolsRoot      = (Join-Path $toolsRoot 'qwen')
        CodexToolsRoot     = (Join-Path $toolsRoot 'codex')
        GHCliToolsRoot     = (Join-Path $toolsRoot 'ghcli')
        GitToolsRoot       = (Join-Path $toolsRoot 'git')
        VsCodeToolsRoot    = (Join-Path $toolsRoot 'vscode')
    }
}

function Get-ManifestedTemporaryRoot {
    [CmdletBinding()]
    param()

    return ([System.IO.Path]::GetFullPath([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'evf', 'stg')))
}
