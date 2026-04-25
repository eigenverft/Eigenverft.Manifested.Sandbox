<#
    Eigenverft.Manifested.Sandbox.Package.EntryPoints
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

    Write-PackageModelExecutionMessage -Message '[STATE] Resolved entry points:'
    if (@($commands).Count -eq 0) {
        Write-PackageModelExecutionMessage -Message '[PATH] Command entry points: <none>'
    }
    else {
        foreach ($command in $commands) {
            Write-PackageModelExecutionMessage -Message ("[PATH] Command {0}: {1} (exists={2})" -f [string]$command.Name, [string]$command.Path, [bool]$command.Exists)
        }
    }

    if (@($apps).Count -eq 0) {
        Write-PackageModelExecutionMessage -Message '[PATH] App entry points: <none>'
    }
    else {
        foreach ($app in $apps) {
            Write-PackageModelExecutionMessage -Message ("[PATH] App {0}: {1} (exists={2})" -f [string]$app.Name, [string]$app.Path, [bool]$app.Exists)
        }
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

