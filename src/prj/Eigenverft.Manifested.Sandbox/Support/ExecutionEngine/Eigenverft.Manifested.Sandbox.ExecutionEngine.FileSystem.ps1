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

