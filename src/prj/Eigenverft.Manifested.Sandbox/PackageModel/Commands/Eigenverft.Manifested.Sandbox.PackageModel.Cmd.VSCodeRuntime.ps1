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

    $packageModelConfig = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
    $result = New-PackageModelResult -CommandName 'Invoke-PackageModel-VSCodeRuntime' -PackageModelConfig $packageModelConfig

    try {
        $result.CurrentStep = 'ResolvePackage'
        $result = Resolve-PackageModelPackage -PackageModelResult $result

        $result.CurrentStep = 'ResolvePaths'
        $result = Resolve-PackageModelPaths -PackageModelResult $result

        $result.CurrentStep = 'BuildAcquisitionPlan'
        $result = Build-PackageModelAcquisitionPlan -PackageModelResult $result

        $result.CurrentStep = 'FindExistingPackage'
        $result = Find-PackageModelExistingPackage -PackageModelResult $result

        $result.CurrentStep = 'ClassifyExistingPackage'
        $result = Classify-PackageModelExistingPackage -PackageModelResult $result

        $result.CurrentStep = 'ResolveExistingPackageDecision'
        $result = Resolve-PackageModelExistingPackageDecision -PackageModelResult $result

        $result.CurrentStep = 'SavePackageFile'
        $result = Save-PackageModelPackageFile -PackageModelResult $result

        $result.CurrentStep = 'InstallPackage'
        $result = Install-PackageModelPackage -PackageModelResult $result

        $result.CurrentStep = 'ValidateInstalledPackage'
        $result = Test-PackageModelInstalledPackage -PackageModelResult $result

        $result.CurrentStep = 'ResolveEntryPoints'
        $result = Resolve-PackageModelEntryPoints -PackageModelResult $result

        $result.CurrentStep = 'UpdateOwnership'
        $result = Update-PackageModelOwnershipRecord -PackageModelResult $result
    }
    catch {
        $result.Status = 'Failed'
        $result.ErrorMessage = $_.Exception.Message
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
            'ResolveEntryPoints' { $result.FailureReason = 'EntryPointResolutionFailed' }
            'UpdateOwnership' { $result.FailureReason = 'OwnershipUpdateFailed' }
            default { $result.FailureReason = 'PackageModelCommandFailed' }
        }
    }

    return (Complete-PackageModelResult -PackageModelResult $result)
}
