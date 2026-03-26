<#
    Eigenverft.Manifested.Sandbox.Runtime.Python.Install
#>

function Repair-PythonRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-PythonRuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
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

function Install-PythonRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot),
        [switch]$ForceInstall
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-PythonFlavor }
    }

    $pythonHome = Get-ManagedPythonRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $currentValidation = Test-PythonRuntime -PythonHome $pythonHome -LocalRoot $LocalRoot

    if ($ForceInstall -or $currentValidation.Status -ne 'Ready') {
        New-ManifestedDirectory -Path (Split-Path -Parent $pythonHome) | Out-Null

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix 'python'
            if (-not (Test-Path -LiteralPath $stageInfo.ExpandedRoot)) {
                throw 'The Python embeddable ZIP did not extract as expected.'
            }

            if (Test-Path -LiteralPath $pythonHome) {
                Remove-Item -LiteralPath $pythonHome -Recurse -Force
            }

            New-ManifestedDirectory -Path $pythonHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $pythonHome -Force
            }

            $siteState = Enable-PythonSiteImports -PythonHome $pythonHome
            if (-not $siteState.IsReady) {
                throw "Python site import enablement failed for $pythonHome."
            }
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $pythonExe = Join-Path $pythonHome 'python.exe'
    $versionProbe = Get-PythonReportedVersionProbe -PythonExe $pythonExe -LocalRoot $LocalRoot
    $reportedVersion = $versionProbe.ReportedVersion
    $reportedVersionObject = ConvertTo-PythonVersion -VersionText $reportedVersion
    $expectedVersionObject = ConvertTo-PythonVersion -VersionText $PackageInfo.Version
    if (-not $reportedVersionObject -or -not $expectedVersionObject -or $reportedVersionObject -ne $expectedVersionObject) {
        throw (New-PythonRuntimeValidationFailureMessage -Operation 'post-install version check' -PythonHome $pythonHome -ExpectedVersion $PackageInfo.Version -ReportedVersion $reportedVersion -CommandResult $versionProbe.CommandResult -SiteImportsState $siteState -LocalRoot $LocalRoot)
    }

    $pipResult = Ensure-PythonPip -PythonExe $pythonExe -PythonHome $pythonHome -LocalRoot $LocalRoot
    $validation = Test-PythonRuntime -PythonHome $pythonHome -LocalRoot $LocalRoot
    if ($validation.Status -ne 'Ready') {
        $validationCommandResult = if ([string]::IsNullOrWhiteSpace($validation.ReportedVersion)) {
            $validation.VersionCommandResult
        }
        elseif ([string]::IsNullOrWhiteSpace($validation.PipVersion)) {
            $validation.PipCommandResult
        }
        else {
            $validation.VersionCommandResult
        }

        throw (New-PythonRuntimeValidationFailureMessage -Operation 'post-pip validation' -PythonHome $pythonHome -ExpectedVersion $PackageInfo.Version -ReportedVersion $validation.ReportedVersion -CommandResult $validationCommandResult -SiteImportsState $validation.SiteImports -LocalRoot $LocalRoot)
    }

    [pscustomobject]@{
        Action                = if ($ForceInstall -or $currentValidation.Status -ne 'Ready') { 'Installed' } else { 'Skipped' }
        Version               = $PackageInfo.Version
        Flavor                = $Flavor
        PythonHome            = $pythonHome
        PythonExe             = $validation.PythonExe
        PipCmd                = $validation.PipCmd
        Pip3Cmd               = $validation.Pip3Cmd
        PthPath               = $validation.PthPath
        PipVersion            = $validation.PipVersion
        PipResult             = $pipResult
        Source                = $PackageInfo.Source
    }
}

