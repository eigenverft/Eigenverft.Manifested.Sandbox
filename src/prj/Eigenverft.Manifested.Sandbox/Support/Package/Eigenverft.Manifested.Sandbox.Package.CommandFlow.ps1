<#
    Eigenverft.Manifested.Sandbox.Package.CommandFlow
#>

function Get-PackageModelOutcomeSummary {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $installDirectoryText = if ([string]::IsNullOrWhiteSpace([string]$PackageModelResult.InstallDirectory)) {
        '<none>'
    }
    else {
        [string]$PackageModelResult.InstallDirectory
    }
    $packageFileStatusText = if ($PackageModelResult.PackageFileSave -and $PackageModelResult.PackageFileSave.PSObject.Properties['Status']) {
        [string]$PackageModelResult.PackageFileSave.Status
    }
    else {
        '<none>'
    }
    $existingDecisionText = if ($PackageModelResult.ExistingPackage -and $PackageModelResult.ExistingPackage.PSObject.Properties['Decision']) {
        [string]$PackageModelResult.ExistingPackage.Decision
    }
    else {
        '<none>'
    }

    switch -Exact ([string]$PackageModelResult.InstallOrigin) {
        'PackageModelReused' {
            return ("[OUTCOME] Reused PackageModel-owned install '{0}' (existingDecision='{1}', packageFileStep='{2}')." -f $installDirectoryText, $existingDecisionText, $packageFileStatusText)
        }
        'AdoptedExternal' {
            return ("[OUTCOME] Adopted external install '{0}' (existingDecision='{1}', packageFileStep='{2}')." -f $installDirectoryText, $existingDecisionText, $packageFileStatusText)
        }
        'PackageModelInstalled' {
            return ("[OUTCOME] Completed PackageModel-owned install into '{0}' with installStatus='{1}' and packageFileStep='{2}'." -f $installDirectoryText, [string]$PackageModelResult.Install.Status, $packageFileStatusText)
        }
        'PackageModelApplied' {
            return ("[OUTCOME] Applied PackageModel prerequisite with installStatus='{0}', packageFileStep='{1}', restartRequired='{2}'." -f [string]$PackageModelResult.Install.Status, $packageFileStatusText, [string]$PackageModelResult.Install.Installer.RestartRequired)
        }
        'AlreadySatisfied' {
            return ("[OUTCOME] Package prerequisite already satisfied; installer and package-file acquisition were skipped.")
        }
        default {
            return ("[OUTCOME] Completed PackageModel run with installOrigin='{0}', installStatus='{1}', packageFileStep='{2}', installDirectory='{3}'." -f [string]$PackageModelResult.InstallOrigin, [string]$PackageModelResult.Install.Status, $packageFileStatusText, $installDirectoryText)
        }
    }
}

function Get-PackageModelCommandFailureReason {
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
        'SavePackageFile' { return 'PackageFileSaveFailed' }
        'InstallPackage' { return 'PackageInstallFailed' }
        'ValidateInstalledPackage' { return 'InstalledPackageValidationFailed' }
        'RegisterPath' { return 'PathRegistrationFailed' }
        'ResolveEntryPoints' { return 'EntryPointResolutionFailed' }
        'UpdateOwnership' { return 'OwnershipUpdateFailed' }
        default { return 'PackageModelCommandFailed' }
    }
}

function Invoke-PackageModelDefinitionCommand {
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

    $packageModelConfig = Get-PackageModelConfig -DefinitionId $DefinitionId
    $result = New-PackageModelResult -CommandName $CommandName -PackageModelConfig $packageModelConfig
    $steps = @(
        [pscustomobject]@{ Name = 'ResolvePackage'; Message = '[STEP] Resolving package selection.'; Action = { param($r) Resolve-PackageModelPackage -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'ResolveDependencies'; Message = '[STEP] Ensuring package dependencies.'; Action = { param($r) Resolve-PackageModelDependencies -PackageModelResult $r -DependencyStack $DependencyStack } },
        [pscustomobject]@{ Name = 'ResolvePaths'; Message = '[STEP] Resolving package paths.'; Action = { param($r) Resolve-PackageModelPaths -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'ResolvePreInstallSatisfaction'; Message = '[STEP] Checking pre-install satisfaction.'; Action = { param($r) Resolve-PackageModelPreInstallSatisfaction -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'BuildAcquisitionPlan'; Message = '[STEP] Building acquisition plan.'; Action = { param($r) Build-PackageModelAcquisitionPlan -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'FindExistingPackage'; Message = '[STEP] Discovering existing installs.'; Action = { param($r) Find-PackageModelExistingPackage -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'ClassifyExistingPackage'; Message = '[STEP] Classifying install ownership.'; Action = { param($r) Classify-PackageModelExistingPackage -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'ResolveExistingPackageDecision'; Message = '[STEP] Deciding reuse, adoption, or replacement.'; Action = { param($r) Resolve-PackageModelExistingPackageDecision -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'SavePackageFile'; Message = '[STEP] Ensuring package file is available.'; Action = { param($r) Save-PackageModelPackageFile -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'InstallPackage'; Message = '[STEP] Installing or reusing the package.'; Action = { param($r) Install-PackageModelPackage -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'ValidateInstalledPackage'; Message = '[STEP] Validating the installed package.'; Action = { param($r) Test-PackageModelInstalledPackage -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'RegisterPath'; Message = '[STEP] Applying PATH registration.'; Action = { param($r) Register-PackageModelPath -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'ResolveEntryPoints'; Message = '[STEP] Resolving entry points.'; Action = { param($r) Resolve-PackageModelEntryPoints -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'UpdateOwnership'; Message = '[STEP] Updating ownership tracking.'; Action = { param($r) Update-PackageModelOwnershipRecord -PackageModelResult $r } }
    )

    try {
        Write-PackageModelExecutionMessage -Message ("[START] {0}" -f $CommandName)
        foreach ($step in $steps) {
            $result.CurrentStep = $step.Name
            Write-PackageModelExecutionMessage -Message $step.Message
            $result = & $step.Action $result
        }
        Write-PackageModelExecutionMessage -Message (Get-PackageModelOutcomeSummary -PackageModelResult $result)
        Write-PackageModelExecutionMessage -Message ("[OK] PackageModel completed with InstallOrigin='{0}' and InstallStatus='{1}'." -f $result.InstallOrigin, $result.Install.Status)
    }
    catch {
        $result.Status = 'Failed'
        $result.ErrorMessage = $_.Exception.Message
        Write-PackageModelExecutionMessage -Level 'ERR' -Message ("[FAIL] Step '{0}' failed: {1}" -f $result.CurrentStep, $_.Exception.Message)
        $result.FailureReason = Get-PackageModelCommandFailureReason -CurrentStep ([string]$result.CurrentStep)
    }

    return (Complete-PackageModelResult -PackageModelResult $result)
}

