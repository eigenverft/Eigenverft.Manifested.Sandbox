<#
    Eigenverft.Manifested.Sandbox.Package.EntryPoints
#>

function Resolve-PackageEntryPoints {
<#
.SYNOPSIS
Resolves the install-relative provided tools for a Package result.

.DESCRIPTION
Maps the definition command and app tool entries into absolute paths beneath
the final install directory and attaches them to the Package result.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Resolve-PackageEntryPoints -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $definition = $PackageResult.PackageConfig.Definition
    $commands = @(
        foreach ($entryPoint in @($definition.providedTools.commands)) {
            $path = Join-Path $PackageResult.InstallDirectory (([string]$entryPoint.relativePath) -replace '/', '\')
            [pscustomobject]@{
                Name   = $entryPoint.name
                Path   = $path
                Exists = (Test-Path -LiteralPath $path)
            }
        }
    )

    $apps = @(
        foreach ($entryPoint in @($definition.providedTools.apps)) {
            $path = Join-Path $PackageResult.InstallDirectory (([string]$entryPoint.relativePath) -replace '/', '\')
            [pscustomobject]@{
                Name   = $entryPoint.name
                Path   = $path
                Exists = (Test-Path -LiteralPath $path)
            }
        }
    )

    $PackageResult.EntryPoints = [pscustomobject]@{
        Commands = $commands
        Apps     = $apps
    }

    Write-PackageExecutionMessage -Message '[STATE] Resolved entry points:'
    if (@($commands).Count -eq 0) {
        Write-PackageExecutionMessage -Message '[PATH] Command entry points: <none>'
    }
    else {
        foreach ($command in $commands) {
            Write-PackageExecutionMessage -Message ("[PATH] Command {0}: {1} (exists={2})" -f [string]$command.Name, [string]$command.Path, [bool]$command.Exists)
        }
    }

    if (@($apps).Count -eq 0) {
        Write-PackageExecutionMessage -Message '[PATH] App entry points: <none>'
    }
    else {
        foreach ($app in $apps) {
            Write-PackageExecutionMessage -Message ("[PATH] App {0}: {1} (exists={2})" -f [string]$app.Name, [string]$app.Path, [bool]$app.Exists)
        }
    }

    return $PackageResult
}

function Complete-PackageResult {
<#
.SYNOPSIS
Finalizes a Package result for output.

.DESCRIPTION
Applies final status and failure details, then removes the internal config
state before returning the user-facing Package result object.

.PARAMETER PackageResult
The Package result object to finalize.

.EXAMPLE
Complete-PackageResult -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if (-not [string]::IsNullOrWhiteSpace($PackageResult.ErrorMessage)) {
        $PackageResult.Status = 'Failed'
    }
    elseif ($PackageResult.Validation -and $PackageResult.Validation.Accepted) {
        $PackageResult.Status = 'Ready'
    }
    else {
        $PackageResult.Status = 'Failed'
        if ([string]::IsNullOrWhiteSpace($PackageResult.FailureReason)) {
            $PackageResult.FailureReason = 'InstalledPackageValidationFailed'
        }
    }

    $null = $PackageResult.PSObject.Properties.Remove('PackageConfig')
    $null = $PackageResult.PSObject.Properties.Remove('CurrentStep')
    $null = $PackageResult.PSObject.Properties.Remove('EffectiveRelease')
    $null = $PackageResult.PSObject.Properties.Remove('AcquisitionPlan')
    return [pscustomobject]$PackageResult
}

