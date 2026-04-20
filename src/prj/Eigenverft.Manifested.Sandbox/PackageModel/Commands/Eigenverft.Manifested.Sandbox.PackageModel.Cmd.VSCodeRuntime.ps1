<#
    Eigenverft.Manifested.Sandbox.PackageModel.Cmd.VSCodeRuntime
#>

function Invoke-PackageModel-VSCodeRuntime {
<#
.SYNOPSIS
Ensures the configured VS Code package is available through PackageModel.

.DESCRIPTION
Loads the shipped PackageModel JSON documents through the neutral PackageModel
config loader, resolves the effective VS Code release for the current runtime
context, evaluates existing-install ownership and policy, saves the package
file when needed, installs or reuses the package, validates the installed
package, updates the ownership index, and returns the resolved entry points.

.EXAMPLE
Invoke-PackageModel-VSCodeRuntime
#>
    [CmdletBinding()]
    param()

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
            default {
                return ("[OUTCOME] Completed PackageModel run with installOrigin='{0}', installStatus='{1}', packageFileStep='{2}', installDirectory='{3}'." -f [string]$PackageModelResult.InstallOrigin, [string]$PackageModelResult.Install.Status, $packageFileStatusText, $installDirectoryText)
            }
        }
    }

    $packageModelConfig = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
    $result = New-PackageModelResult -CommandName 'Invoke-PackageModel-VSCodeRuntime' -PackageModelConfig $packageModelConfig
    $steps = @(
        [pscustomobject]@{ Name = 'ResolvePackage'; Message = '[STEP] Resolving package selection.'; Action = { param($r) Resolve-PackageModelPackage -PackageModelResult $r } },
        [pscustomobject]@{ Name = 'ResolvePaths'; Message = '[STEP] Resolving package paths.'; Action = { param($r) Resolve-PackageModelPaths -PackageModelResult $r } },
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
        Write-PackageModelExecutionMessage -Message '[START] Invoke-PackageModel-VSCodeRuntime'
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
        switch -Exact ([string]$result.CurrentStep) {
            'ResolvePackage' { $result.FailureReason = 'PackageSelectionFailed' }
            'ResolvePaths' { $result.FailureReason = 'PackagePathResolutionFailed' }
            'BuildAcquisitionPlan' { $result.FailureReason = 'AcquisitionPlanBuildFailed' }
            'FindExistingPackage' { $result.FailureReason = 'ExistingPackageDiscoveryFailed' }
            'ClassifyExistingPackage' { $result.FailureReason = 'ExistingPackageOwnershipClassificationFailed' }
            'ResolveExistingPackageDecision' { $result.FailureReason = 'ExistingPackageDecisionFailed' }
            'SavePackageFile' { $result.FailureReason = 'PackageFileSaveFailed' }
            'InstallPackage' { $result.FailureReason = 'PackageInstallFailed' }
            'ValidateInstalledPackage' { $result.FailureReason = 'InstalledPackageValidationFailed' }
            'RegisterPath' { $result.FailureReason = 'PathRegistrationFailed' }
            'ResolveEntryPoints' { $result.FailureReason = 'EntryPointResolutionFailed' }
            'UpdateOwnership' { $result.FailureReason = 'OwnershipUpdateFailed' }
            default { $result.FailureReason = 'PackageModelCommandFailed' }
        }
    }

    return (Complete-PackageModelResult -PackageModelResult $result)
}
