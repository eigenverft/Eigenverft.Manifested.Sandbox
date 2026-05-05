<#
    Eigenverft.Manifested.Sandbox.Package.EntryPoints
#>

function Get-PackageProvidedToolEntryPoint {
<#
.SYNOPSIS
Finds one provided command or app entry point by name.

.DESCRIPTION
Looks up an entry in definition.providedTools.commands or
definition.providedTools.apps using the same case-insensitive matching used by
Package path registration. Returns $null when the collection or entry is not
present.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('commands', 'apps')]
        [string]$ToolKind,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $Definition.PSObject.Properties['providedTools'] -or
        -not $Definition.providedTools.PSObject.Properties[$ToolKind]) {
        return $null
    }

    foreach ($entryPoint in @($Definition.providedTools.$ToolKind)) {
        if ([string]::Equals([string]$entryPoint.name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entryPoint
        }
    }

    return $null
}

function Resolve-PackageProvidedToolEntryPointPath {
<#
.SYNOPSIS
Resolves one provided-tool entry point under an install directory.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EntryPoint,

        [Parameter(Mandatory = $true)]
        [string]$InstallDirectory
    )

    return (Join-Path $InstallDirectory (([string]$EntryPoint.relativePath) -replace '/', '\'))
}

function Resolve-PackageProvidedToolPath {
<#
.SYNOPSIS
Resolves one named provided command or app path under an install directory.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('commands', 'apps')]
        [string]$ToolKind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$InstallDirectory
    )

    $entryPoint = Get-PackageProvidedToolEntryPoint -Definition $Definition -ToolKind $ToolKind -Name $Name
    if (-not $entryPoint) {
        return $null
    }

    return (Resolve-PackageProvidedToolEntryPointPath -EntryPoint $entryPoint -InstallDirectory $InstallDirectory)
}

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
            $path = Resolve-PackageProvidedToolEntryPointPath -EntryPoint $entryPoint -InstallDirectory $PackageResult.InstallDirectory
            [pscustomobject]@{
                Name   = $entryPoint.name
                Path   = $path
                Exists = (Test-Path -LiteralPath $path)
            }
        }
    )

    $apps = @(
        foreach ($entryPoint in @($definition.providedTools.apps)) {
            $path = Resolve-PackageProvidedToolEntryPointPath -EntryPoint $entryPoint -InstallDirectory $PackageResult.InstallDirectory
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

