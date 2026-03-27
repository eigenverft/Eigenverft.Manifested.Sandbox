function Repair-ManifestedRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [string[]]$CorruptArtifactPaths = @(),

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $pathsToRemove = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($Facts.PartialPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($Facts.InvalidPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($CorruptArtifactPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }

    $removedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($pathsToRemove | Select-Object -Unique)) {
        if (Remove-ManifestedPath -Path $path) {
            $removedPaths.Add($path) | Out-Null
        }
    }

    return [pscustomobject]@{
        Action       = if ($removedPaths.Count -gt 0) { 'Repaired' } else { 'Skipped' }
        RemovedPaths = @($removedPaths)
        LocalRoot    = $LocalRoot
        Layout       = if ($Facts.PSObject.Properties['Layout']) { $Facts.Layout } else { $null }
    }
}

function Invoke-ManifestedRuntimeRepairFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [string[]]$CorruptArtifactPaths = @(),

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Repair-ManifestedRuntime -Facts $Facts -CorruptArtifactPaths $CorruptArtifactPaths -LocalRoot $LocalRoot)
}
