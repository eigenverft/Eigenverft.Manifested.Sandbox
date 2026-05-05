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
        'InitializeLocalEnvironment' { return 'LocalEnvironmentInitializationFailed' }
        'ResolveDesiredState' { return 'PackageDesiredStateNotImplemented' }
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
        'UpdateInventory' { return 'PackageInventoryUpdateFailed' }
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

function Invoke-PackageAssignedFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [object[]]$DependencyStack = @()
    )

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
        [pscustomobject]@{ Name = 'UpdateInventory'; Message = '[STEP] Updating package inventory.'; Action = { param($r) Update-PackageInventoryRecord -PackageResult $r } },
        [pscustomobject]@{ Name = 'ClearPackageWorkDirectories'; Message = '[STEP] Cleaning package staging directories.'; Action = { param($r) Clear-PackageWorkDirectories -PackageResult $r } }
    )

    try {
        Write-PackageExecutionMessage -Message ("[START] Invoke-PackageDefinitionCommand repository='{0}' definition='{1}' desiredState='{2}'." -f $PackageResult.RepositoryId, $PackageResult.DefinitionId, $PackageResult.DesiredState)
        $PackageResult.CurrentStep = 'InitializeLocalEnvironment'
        Write-PackageExecutionMessage -Message '[STEP] Initializing local package environment.'
        $PackageResult.LocalEnvironment = Initialize-PackageLocalEnvironment -PackageConfig $PackageResult.PackageConfig
        if ($PackageResult.LocalEnvironment.InitializedNow) {
            Write-PackageExecutionMessage -Message ("[STATE] Local package environment initialized: created={0}, existing={1}, skippedSources={2}." -f @($PackageResult.LocalEnvironment.CreatedDirectories).Count, @($PackageResult.LocalEnvironment.ExistingDirectories).Count, @($PackageResult.LocalEnvironment.SkippedSources).Count)
        }
        else {
            Write-PackageExecutionMessage -Message '[STATE] Local package environment already initialized.'
        }

        foreach ($step in $steps) {
            $PackageResult.CurrentStep = $step.Name
            Write-PackageExecutionMessage -Message $step.Message
            $PackageResult = & $step.Action $PackageResult
            if ($step.Name -eq 'ValidateInstalledPackage' -and (-not $PackageResult.Validation -or -not $PackageResult.Validation.Accepted)) {
                $failedCount = if ($PackageResult.Validation -and $PackageResult.Validation.PSObject.Properties['FailedChecks']) { @($PackageResult.Validation.FailedChecks).Count } else { 0 }
                throw ("Package validation failed for '{0}' with {1} failed check(s)." -f $PackageResult.PackageId, $failedCount)
            }
        }
        Write-PackageExecutionMessage -Message (Get-PackageOutcomeSummary -PackageResult $PackageResult)
        Write-PackageExecutionMessage -Message ("[OK] Package completed with InstallOrigin='{0}' and InstallStatus='{1}'." -f $PackageResult.InstallOrigin, $PackageResult.Install.Status)
    }
    catch {
        $PackageResult.Status = 'Failed'
        $PackageResult.ErrorMessage = $_.Exception.Message
        Write-PackageExecutionMessage -Level 'ERR' -Message ("[FAIL] Step '{0}' failed: {1}" -f $PackageResult.CurrentStep, $_.Exception.Message)
        $PackageResult.FailureReason = Get-PackageCommandFailureReason -CurrentStep ([string]$PackageResult.CurrentStep)
    }

    return $PackageResult
}

function Invoke-PackageDefinitionCommandCore {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RepositoryId = (Get-PackageDefaultRepositoryId),

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionId,

        [ValidateSet('Assigned', 'Removed')]
        [string]$DesiredState = 'Assigned',

        [object[]]$DependencyStack = @()
    )

    $packageConfig = Get-PackageConfig -RepositoryId $RepositoryId -DefinitionId $DefinitionId
    $result = New-PackageResult -DesiredState $DesiredState -PackageConfig $packageConfig

    if ([string]::Equals($DesiredState, 'Removed', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-PackageExecutionMessage -Message ("[START] Invoke-PackageDefinitionCommand repository='{0}' definition='{1}' desiredState='{2}'." -f $result.RepositoryId, $result.DefinitionId, $result.DesiredState)
        $result.CurrentStep = 'ResolveDesiredState'
        $result.Status = 'Failed'
        $result.FailureReason = 'PackageDesiredStateNotImplemented'
        $result.ErrorMessage = "DesiredState 'Removed' is not implemented yet for package definition '$DefinitionId'."
        Write-PackageExecutionMessage -Level 'ERR' -Message ("[FAIL] DesiredState 'Removed' is not implemented yet for package definition '{0}'." -f $DefinitionId)
        $completedResult = Complete-PackageResult -PackageResult $result
        Add-PackageOperationHistoryRecord -PackageConfig $packageConfig -PackageResult $completedResult -FailedStep 'ResolveDesiredState'
        return $completedResult
    }

    $result = Invoke-PackageAssignedFlow -PackageResult $result -DependencyStack $DependencyStack
    $failedStep = if ([string]::Equals([string]$result.Status, 'Failed', [System.StringComparison]::OrdinalIgnoreCase)) { [string]$result.CurrentStep } else { $null }
    $completedResult = Complete-PackageResult -PackageResult $result
    if ([string]::Equals([string]$completedResult.Status, 'Failed', [System.StringComparison]::OrdinalIgnoreCase) -and [string]::IsNullOrWhiteSpace($failedStep)) {
        $failedStep = [string]$result.CurrentStep
    }
    Add-PackageOperationHistoryRecord -PackageConfig $packageConfig -PackageResult $completedResult -FailedStep $failedStep
    return $completedResult
}

function Invoke-PackageDefinitionCommand {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RepositoryId = (Get-PackageDefaultRepositoryId),

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$DefinitionId,

        [ValidateSet('Assigned', 'Removed')]
        [string]$DesiredState = 'Assigned'
    )

    foreach ($definition in $DefinitionId) {
        $result = Invoke-PackageDefinitionCommandCore -RepositoryId $RepositoryId -DefinitionId $definition -DesiredState $DesiredState
        $result
        if ($result -and -not [string]::Equals([string]$result.Status, 'Ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
    }
}

function Invoke-Package {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$DefinitionId,

        [ValidateSet('Assigned', 'Removed')]
        [string]$DesiredState = 'Assigned'
    )

    Invoke-PackageDefinitionCommand -DefinitionId $DefinitionId -DesiredState $DesiredState
}
