<#
    Eigenverft.Manifested.Sandbox.Runtime.Node.Install
#>

function Repair-NodeRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-NodeRuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
    }

    $pathsToRemove = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($State.PartialPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($State.InvalidRuntimeHomes)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($CorruptPackagePaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }

    $removedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in ($pathsToRemove | Select-Object -Unique)) {
        if (Remove-ManifestedPath -Path $path) {
            $removedPaths.Add($path) | Out-Null
        }
    }

    [pscustomobject]@{
        Action       = if ($removedPaths.Count -gt 0) { 'Repaired' } else { 'Skipped' }
        RemovedPaths = @($removedPaths)
        LocalRoot    = $State.LocalRoot
        Layout       = $State.Layout
    }
}

function Install-NodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-NodeFlavor }
    }

    $nodeHome = Get-ManagedNodeRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $currentValidation = Test-NodeRuntime -NodeHome $nodeHome

    if ($currentValidation.Status -ne 'Ready') {
        New-ManifestedDirectory -Path (Split-Path -Parent $nodeHome) | Out-Null

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix 'node'
            if (-not (Test-Path -LiteralPath $stageInfo.ExpandedRoot)) {
                throw 'The Node.js ZIP did not extract as expected.'
            }

            if (Test-Path -LiteralPath $nodeHome) {
                Remove-Item -LiteralPath $nodeHome -Recurse -Force
            }

            New-ManifestedDirectory -Path $nodeHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $nodeHome -Force
            }
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $validation = Test-NodeRuntime -NodeHome $nodeHome
    if ($validation.Status -ne 'Ready') {
        throw "Node runtime validation failed after install at $nodeHome."
    }

    [pscustomobject]@{
        Action     = if ($currentValidation.Status -eq 'Ready') { 'Skipped' } else { 'Installed' }
        Version    = $PackageInfo.Version
        Flavor     = $Flavor
        NodeHome   = $nodeHome
        NodeExe    = $validation.NodeExe
        NpmCmd     = $validation.NpmCmd
        Source     = $PackageInfo.Source
        NpmVersion = $PackageInfo.NpmVersion
    }
}

