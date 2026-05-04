<#
    Eigenverft.Manifested.Sandbox.ExecutionEngine.FileSystem
#>

function Remove-PathIfExists {
<#
.SYNOPSIS
Removes a file or directory when it exists.

.DESCRIPTION
Returns `$false` when the path is already missing. Otherwise removes the path
recursively and forcefully, then returns `$true`.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $Path) {
        throw "Could not remove path '$Path'."
    }

    return $true
}

function Copy-FileToPath {
<#
.SYNOPSIS
Copies one file to a target path.

.DESCRIPTION
Provides a thin execution seam over `Copy-Item` so callers do not depend on a
specific file-copy backend.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [switch]$Overwrite
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        throw 'A source file path is required.'
    }

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        throw 'A target file path is required.'
    }

    if ($Overwrite) {
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    }
    else {
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath
    }

    return (Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop).Path
}

function New-CommandShim {
<#
.SYNOPSIS
Creates a small command shim script.

.DESCRIPTION
Writes a `.cmd` shim that forwards all arguments to a concrete target command.
The helper is intentionally generic so the Package layer can decide ownership,
name collision, and lifecycle policy.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShimPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [string[]]$HeaderLines = @(),

        [switch]$Overwrite
    )

    if ([string]::IsNullOrWhiteSpace($ShimPath)) {
        throw 'A shim path is required.'
    }

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        throw 'A shim target path is required.'
    }

    $resolvedShimPath = [System.IO.Path]::GetFullPath($ShimPath)
    $resolvedTargetPath = [System.IO.Path]::GetFullPath($TargetPath)
    $shimDirectory = Split-Path -Parent $resolvedShimPath
    if (-not [string]::IsNullOrWhiteSpace($shimDirectory) -and -not (Test-Path -LiteralPath $shimDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $shimDirectory -Force
    }

    if ((Test-Path -LiteralPath $resolvedShimPath -PathType Leaf) -and -not $Overwrite.IsPresent) {
        throw "Command shim '$resolvedShimPath' already exists."
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@echo off') | Out-Null
    foreach ($headerLine in @($HeaderLines)) {
        if (-not [string]::IsNullOrWhiteSpace($headerLine)) {
            $lines.Add(("rem {0}" -f [string]$headerLine)) | Out-Null
        }
    }
    $lines.Add(('call "{0}" %*' -f $resolvedTargetPath)) | Out-Null
    $lines.Add('exit /b %ERRORLEVEL%') | Out-Null

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($resolvedShimPath, (@($lines.ToArray()) -join "`r`n") + "`r`n", $encoding)

    return $resolvedShimPath
}

