<#
    Eigenverft.Manifested.Sandbox.PackageModel.EntryPoints
#>

function Resolve-PackageModelEntryPoints {
<#
.SYNOPSIS
Resolves the install-relative provided tools for a PackageModel result.

.DESCRIPTION
Maps the definition command and app tool entries into absolute paths beneath
the final install directory and attaches them to the PackageModel result.

.PARAMETER PackageModelResult
The PackageModel result object to enrich.

.EXAMPLE
Resolve-PackageModelEntryPoints -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $definition = $PackageModelResult.PackageModelConfig.Definition
    $commands = @(
        foreach ($entryPoint in @($definition.providedTools.commands)) {
            $path = Join-Path $PackageModelResult.InstallDirectory (([string]$entryPoint.relativePath) -replace '/', '\')
            [pscustomobject]@{
                Name   = $entryPoint.name
                Path   = $path
                Exists = (Test-Path -LiteralPath $path)
            }
        }
    )

    $apps = @(
        foreach ($entryPoint in @($definition.providedTools.apps)) {
            $path = Join-Path $PackageModelResult.InstallDirectory (([string]$entryPoint.relativePath) -replace '/', '\')
            [pscustomobject]@{
                Name   = $entryPoint.name
                Path   = $path
                Exists = (Test-Path -LiteralPath $path)
            }
        }
    )

    $PackageModelResult.EntryPoints = [pscustomobject]@{
        Commands = $commands
        Apps     = $apps
    }

    return $PackageModelResult
}

function Complete-PackageModelResult {
<#
.SYNOPSIS
Finalizes a PackageModel result for output.

.DESCRIPTION
Applies final status and failure details, then removes the internal config
state before returning the user-facing PackageModel result object.

.PARAMETER PackageModelResult
The PackageModel result object to finalize.

.EXAMPLE
Complete-PackageModelResult -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    if (-not [string]::IsNullOrWhiteSpace($PackageModelResult.ErrorMessage)) {
        $PackageModelResult.Status = 'Failed'
    }
    elseif ($PackageModelResult.Validation -and $PackageModelResult.Validation.Accepted) {
        $PackageModelResult.Status = 'Ready'
    }
    else {
        $PackageModelResult.Status = 'Failed'
        if ([string]::IsNullOrWhiteSpace($PackageModelResult.FailureReason)) {
            $PackageModelResult.FailureReason = 'InstalledPackageValidationFailed'
        }
    }

    $null = $PackageModelResult.PSObject.Properties.Remove('PackageModelConfig')
    $null = $PackageModelResult.PSObject.Properties.Remove('CurrentStep')
    $null = $PackageModelResult.PSObject.Properties.Remove('EffectiveRelease')
    $null = $PackageModelResult.PSObject.Properties.Remove('AcquisitionPlan')
    return [pscustomobject]$PackageModelResult
}
