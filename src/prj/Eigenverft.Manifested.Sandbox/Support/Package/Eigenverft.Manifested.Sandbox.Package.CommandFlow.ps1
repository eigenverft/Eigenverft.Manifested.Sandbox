<#
    Eigenverft.Manifested.Sandbox.Package.CommandFlow
#>

function Get-PackageOutcomeSummary {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $installDirectoryText = if ([string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory)) {
        '<none>'
    }
    else {
        [string]$PackageResult.InstallDirectory
    }
    $packageFileStatusText = if ($PackageResult.PackageFilePreparation -and $PackageResult.PackageFilePreparation.PSObject.Properties['Status']) {
        [string]$PackageResult.PackageFilePreparation.Status
    }
    else {
        '<none>'
    }
    $existingDecisionText = if ($PackageResult.ExistingPackage -and $PackageResult.ExistingPackage.PSObject.Properties['Decision']) {
        [string]$PackageResult.ExistingPackage.Decision
    }
    else {
        '<none>'
    }

    switch -Exact ([string]$PackageResult.InstallOrigin) {
        'PackageReused' {
            return ("[OUTCOME] Reused Package-owned install '{0}' (existingDecision='{1}', packageFileStep='{2}')." -f $installDirectoryText, $existingDecisionText, $packageFileStatusText)
        }
        'AdoptedExternal' {
            return ("[OUTCOME] Adopted external install '{0}' (existingDecision='{1}', packageFileStep='{2}')." -f $installDirectoryText, $existingDecisionText, $packageFileStatusText)
        }
        'PackageInstalled' {
            return ("[OUTCOME] Completed Package-owned install into '{0}' with installStatus='{1}' and packageFileStep='{2}'." -f $installDirectoryText, [string]$PackageResult.Install.Status, $packageFileStatusText)
        }
        'PackageApplied' {
            return ("[OUTCOME] Applied Package prerequisite with installStatus='{0}', packageFileStep='{1}', restartRequired='{2}'." -f [string]$PackageResult.Install.Status, $packageFileStatusText, [string]$PackageResult.Install.Installer.RestartRequired)
        }
        'AlreadySatisfied' {
            return ("[OUTCOME] Package prerequisite already satisfied; installer and package-file acquisition were skipped.")
        }
        default {
            return ("[OUTCOME] Completed Package run with installOrigin='{0}', installStatus='{1}', packageFileStep='{2}', installDirectory='{3}'." -f [string]$PackageResult.InstallOrigin, [string]$PackageResult.Install.Status, $packageFileStatusText, $installDirectoryText)
        }
    }
}

function Get-PackageCommandFailureReason {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentStep
    )

    switch -Exact ($CurrentStep) {
        'ResolvePackage' { return 'PackageSelectionFailed' }
        'ResolveDependencies' { return 'PackageDependencyFailed' }
        'ResolvePaths' { return 'PackagePathResolutionFailed' }
        'ResolvePreInstallSatisfaction' { return 'PreInstallSatisfactionCheckFailed' }
        'BuildAcquisitionPlan' { return 'AcquisitionPlanBuildFailed' }
        'FindExistingPackage' { return 'ExistingPackageDiscoveryFailed' }
        'ClassifyExistingPackage' { return 'ExistingPackageOwnershipClassificationFailed' }
        'ResolveExistingPackageDecision' { return 'ExistingPackageDecisionFailed' }
        'PreparePackageInstallFile' { return 'PackageFilePreparationFailed' }
        'InstallPackage' { return 'PackageInstallFailed' }
        'ValidateInstalledPackage' { return 'InstalledPackageValidationFailed' }
        'RegisterPath' { return 'PathRegistrationFailed' }
        'ResolveEntryPoints' { return 'EntryPointResolutionFailed' }
        'UpdateOwnership' { return 'OwnershipUpdateFailed' }
        'ClearPackageWorkDirectories' { return 'PackageWorkDirectoryCleanupFailed' }
        default { return 'PackageCommandFailed' }
    }
}

function Clear-PackageWorkDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    foreach ($cleanupTarget in @(
            [pscustomobject]@{ Label = 'package file staging'; Path = [string]$PackageResult.PackageFileStagingDirectory }
            [pscustomobject]@{ Label = 'package install stage'; Path = [string]$PackageResult.PackageInstallStageDirectory }
        )) {
        if ([string]::IsNullOrWhiteSpace($cleanupTarget.Path)) {
            Write-PackageExecutionMessage -Message ("[STATE] {0} cleanup skipped because no directory was resolved." -f $cleanupTarget.Label)
            continue
        }

        try {
            $removed = Remove-PathIfExists -Path $cleanupTarget.Path
            if ($removed) {
                Write-PackageExecutionMessage -Message ("[ACTION] Cleaned {0} directory '{1}'." -f $cleanupTarget.Label, $cleanupTarget.Path)
            }
            else {
                Write-PackageExecutionMessage -Message ("[STATE] {0} cleanup skipped because '{1}' does not exist." -f $cleanupTarget.Label, $cleanupTarget.Path)
            }
        }
        catch {
            Write-PackageExecutionMessage -Level 'WRN' -Message ("[WARN] Failed to clean {0} directory '{1}': {2}" -f $cleanupTarget.Label, $cleanupTarget.Path, $_.Exception.Message)
        }
    }

    return $PackageResult
}

function Invoke-PackageDefinitionCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandName,

        [object[]]$DependencyStack = @()
    )

    $packageConfig = Get-PackageConfig -DefinitionId $DefinitionId
    $result = New-PackageResult -CommandName $CommandName -PackageConfig $packageConfig
    $steps = @(
        [pscustomobject]@{ Name = 'ResolvePackage'; Message = '[STEP] Resolving package selection.'; Action = { param($r) Resolve-PackagePackage -PackageResult $r } },
        [pscustomobject]@{ Name = 'ResolveDependencies'; Message = '[STEP] Ensuring package dependencies.'; Action = { param($r) Resolve-PackageDependencies -PackageResult $r -DependencyStack $DependencyStack } },
        [pscustomobject]@{ Name = 'ResolvePaths'; Message = '[STEP] Resolving package paths.'; Action = { param($r) Resolve-PackagePaths -PackageResult $r } },
        [pscustomobject]@{ Name = 'ResolvePreInstallSatisfaction'; Message = '[STEP] Checking pre-install satisfaction.'; Action = { param($r) Resolve-PackagePreInstallSatisfaction -PackageResult $r } },
        [pscustomobject]@{ Name = 'BuildAcquisitionPlan'; Message = '[STEP] Building acquisition plan.'; Action = { param($r) Build-PackageAcquisitionPlan -PackageResult $r } },
        [pscustomobject]@{ Name = 'FindExistingPackage'; Message = '[STEP] Discovering existing installs.'; Action = { param($r) Find-PackageExistingPackage -PackageResult $r } },
        [pscustomobject]@{ Name = 'ClassifyExistingPackage'; Message = '[STEP] Classifying install ownership.'; Action = { param($r) Classify-PackageExistingPackage -PackageResult $r } },
        [pscustomobject]@{ Name = 'ResolveExistingPackageDecision'; Message = '[STEP] Deciding reuse, adoption, or replacement.'; Action = { param($r) Resolve-PackageExistingPackageDecision -PackageResult $r } },
        [pscustomobject]@{ Name = 'PreparePackageInstallFile'; Message = '[STEP] Ensuring package file is available.'; Action = { param($r) Prepare-PackageInstallFile -PackageResult $r } },
        [pscustomobject]@{ Name = 'InstallPackage'; Message = '[STEP] Installing or reusing the package.'; Action = { param($r) Install-PackagePackage -PackageResult $r } },
        [pscustomobject]@{ Name = 'ValidateInstalledPackage'; Message = '[STEP] Validating the installed package.'; Action = { param($r) Test-PackageInstalledPackage -PackageResult $r } },
        [pscustomobject]@{ Name = 'RegisterPath'; Message = '[STEP] Applying PATH registration.'; Action = { param($r) Register-PackagePath -PackageResult $r } },
        [pscustomobject]@{ Name = 'ResolveEntryPoints'; Message = '[STEP] Resolving entry points.'; Action = { param($r) Resolve-PackageEntryPoints -PackageResult $r } },
        [pscustomobject]@{ Name = 'UpdateOwnership'; Message = '[STEP] Updating ownership tracking.'; Action = { param($r) Update-PackageOwnershipRecord -PackageResult $r } },
        [pscustomobject]@{ Name = 'ClearPackageWorkDirectories'; Message = '[STEP] Cleaning package staging directories.'; Action = { param($r) Clear-PackageWorkDirectories -PackageResult $r } }
    )

    try {
        Write-PackageExecutionMessage -Message ("[START] {0}" -f $CommandName)
        foreach ($step in $steps) {
            $result.CurrentStep = $step.Name
            Write-PackageExecutionMessage -Message $step.Message
            $result = & $step.Action $result
        }
        Write-PackageExecutionMessage -Message (Get-PackageOutcomeSummary -PackageResult $result)
        Write-PackageExecutionMessage -Message ("[OK] Package completed with InstallOrigin='{0}' and InstallStatus='{1}'." -f $result.InstallOrigin, $result.Install.Status)
    }
    catch {
        $result.Status = 'Failed'
        $result.ErrorMessage = $_.Exception.Message
        Write-PackageExecutionMessage -Level 'ERR' -Message ("[FAIL] Step '{0}' failed: {1}" -f $result.CurrentStep, $_.Exception.Message)
        $result.FailureReason = Get-PackageCommandFailureReason -CurrentStep ([string]$result.CurrentStep)
    }

    return (Complete-PackageResult -PackageResult $result)
}


