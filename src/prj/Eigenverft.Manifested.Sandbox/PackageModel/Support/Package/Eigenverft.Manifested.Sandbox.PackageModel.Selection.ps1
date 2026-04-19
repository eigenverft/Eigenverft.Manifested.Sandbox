<#
    Eigenverft.Manifested.Sandbox.PackageModel.Selection
#>

function ConvertTo-PackageModelVersion {
<#
.SYNOPSIS
Converts a package version string to a sortable version object.

.DESCRIPTION
Normalizes version text so PackageModel release selection can sort exact
version entries by semantic-like version ordering.

.PARAMETER VersionText
The version string to convert.

.EXAMPLE
ConvertTo-PackageModelVersion -VersionText '1.116.0'
#>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return [version]'0.0.0'
    }

    try {
        return [version]$VersionText.Trim()
    }
    catch {
        $match = [regex]::Match($VersionText, '\d+(?:\.\d+){0,3}')
        if ($match.Success) {
            try {
                return [version]$match.Value
            }
            catch {
            }
        }
    }

    return [version]'0.0.0'
}

function Test-PackageModelConstraintSetMatch {
<#
.SYNOPSIS
Checks whether a constraint set matches an actual value.

.DESCRIPTION
Treats empty constraint sets as unrestricted and otherwise performs a
case-insensitive comparison against each configured value.

.PARAMETER Values
The configured constraint values.

.PARAMETER ActualValue
The effective value to test.

.EXAMPLE
Test-PackageModelConstraintSetMatch -Values @('windows') -ActualValue 'windows'
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object[]]$Values,

        [AllowNull()]
        [string]$ActualValue
    )

    if ($null -eq $Values -or $Values.Count -eq 0) {
        return $true
    }

    foreach ($value in $Values) {
        if ([string]::Equals([string]$value, [string]$ActualValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Resolve-PackageModelPackage {
<#
.SYNOPSIS
Attaches the selected release to a PackageModel result.

.DESCRIPTION
Filters the definition releases from the resolved PackageModel config by
platform, architecture, and release track, selects the newest matching release,
applies definition-level release defaults, and attaches the package-facing
data to the result object.

.PARAMETER PackageModelResult
The PackageModel result object to enrich.

.EXAMPLE
Resolve-PackageModelPackage -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $packageModelConfig = $PackageModelResult.PackageModelConfig
    $definition = $packageModelConfig.Definition
    $effectiveReleaseTrack = if ([string]::IsNullOrWhiteSpace($packageModelConfig.ReleaseTrack)) { 'none' } else { [string]$packageModelConfig.ReleaseTrack }

    $matchingPackages = @(
        foreach ($package in @($definition.releases)) {
            $constraints = if ($package.PSObject.Properties['constraints']) { $package.constraints } else { $null }
            $osConstraints = if ($constraints -and $constraints.PSObject.Properties['os']) { @($constraints.os) } else { @() }
            $cpuConstraints = if ($constraints -and $constraints.PSObject.Properties['cpu']) { @($constraints.cpu) } else { @() }
            $packageReleaseTrack = if ($package.PSObject.Properties['releaseTrack'] -and -not [string]::IsNullOrWhiteSpace([string]$package.releaseTrack)) {
                [string]$package.releaseTrack
            }
            else {
                'none'
            }

            if ([string]::Equals($packageReleaseTrack, $effectiveReleaseTrack, [System.StringComparison]::OrdinalIgnoreCase) -and
                (Test-PackageModelConstraintSetMatch -Values $osConstraints -ActualValue $packageModelConfig.Platform) -and
                (Test-PackageModelConstraintSetMatch -Values $cpuConstraints -ActualValue $packageModelConfig.Architecture)) {
                $package
            }
        }
    )

    if (-not $matchingPackages) {
        throw "No PackageModel release matched platform '$($packageModelConfig.Platform)', architecture '$($packageModelConfig.Architecture)', and releaseTrack '$($packageModelConfig.ReleaseTrack)'."
    }

    if (-not [string]::Equals([string]$packageModelConfig.SelectionStrategy, 'latestByVersion', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsupported PackageModel selection strategy '$($packageModelConfig.SelectionStrategy)'."
    }

    $selectedPackage = $matchingPackages |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-PackageModelVersion -VersionText $_.version } } |
        Select-Object -First 1
    $selectedPackage = Resolve-PackageModelEffectiveRelease -Definition $definition -Release $selectedPackage

    $PackageModelResult.Package = $selectedPackage
    $PackageModelResult.EffectiveRelease = $selectedPackage
    $PackageModelResult.PackageId = [string]$selectedPackage.id
    $PackageModelResult.PackageVersion = [string]$selectedPackage.version
    if ($selectedPackage.PSObject.Properties['requirements'] -and
        $selectedPackage.requirements -and
        $selectedPackage.requirements.PSObject.Properties['packages']) {
        $PackageModelResult.Requirements = @($selectedPackage.requirements.packages)
    }

    return $PackageModelResult
}
