<#
    Eigenverft.Manifested.Sandbox.Package.Selection
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

function Test-PackageModelCompatibilityAllowedBlockedMatch {
<#
.SYNOPSIS
Checks allowed/blocked compatibility lists against one actual value.

.DESCRIPTION
Treats empty allowed/blocked lists as unrestricted and otherwise enforces
case-insensitive allow and block matching for one actual value.

.PARAMETER Allowed
The optional allowed values.

.PARAMETER Blocked
The optional blocked values.

.PARAMETER ActualValue
The value to test.
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object[]]$Allowed,

        [AllowNull()]
        [object[]]$Blocked,

        [AllowNull()]
        [string]$ActualValue
    )

    if ($Blocked -and $Blocked.Count -gt 0) {
        foreach ($value in @($Blocked)) {
            if ([string]::Equals([string]$value, [string]$ActualValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
        }
    }

    if ($Allowed -and $Allowed.Count -gt 0) {
        foreach ($value in @($Allowed)) {
            if ([string]::Equals([string]$value, [string]$ActualValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    }

    return $true
}

function Test-PackageModelCompatibilityChecks {
<#
.SYNOPSIS
Evaluates typed PackageModel compatibility checks for one selected release.

.DESCRIPTION
Runs the current compatibility kinds against the resolved runtime context and
returns the normalized compatibility results and acceptance state.

.PARAMETER PackageModelConfig
The resolved PackageModel config object.

.PARAMETER Compatibility
The effective release compatibility object.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelConfig,

        [AllowNull()]
        [psobject]$Compatibility
    )

    $results = New-Object System.Collections.Generic.List[object]
    $allAccepted = $true
    $blockingAccepted = $true
    $checks = if ($Compatibility -and $Compatibility.PSObject.Properties['checks']) { @($Compatibility.checks) } else { @() }

    foreach ($check in @($checks)) {
        if ($null -eq $check) {
            continue
        }

        $kind = [string]$check.kind
        $onFail = if ($check.PSObject.Properties['onFail'] -and -not [string]::IsNullOrWhiteSpace([string]$check.onFail)) {
            ([string]$check.onFail).ToLowerInvariant()
        }
        else {
            'fail'
        }
        $accepted = $false
        $actualValue = $null
        $expectedSummary = $null
        $testNumericValue = {
            param(
                [AllowNull()]
                [object]$ActualNumericValue,

                [Parameter(Mandatory = $true)]
                [string]$Operator,

                [Parameter(Mandatory = $true)]
                [double]$ExpectedNumericValue
            )

            if ($null -eq $ActualNumericValue) {
                return $false
            }

            $actualNumericComparisonValue = [double]$ActualNumericValue

            switch -Exact ($Operator) {
                '=' { return $actualNumericComparisonValue -eq $ExpectedNumericValue }
                '==' { return $actualNumericComparisonValue -eq $ExpectedNumericValue }
                '!=' { return $actualNumericComparisonValue -ne $ExpectedNumericValue }
                '>' { return $actualNumericComparisonValue -gt $ExpectedNumericValue }
                '>=' { return $actualNumericComparisonValue -ge $ExpectedNumericValue }
                '<' { return $actualNumericComparisonValue -lt $ExpectedNumericValue }
                '<=' { return $actualNumericComparisonValue -le $ExpectedNumericValue }
                default { throw "Unsupported numeric compatibility operator '$Operator'." }
            }
        }
        $formatMemoryValue = {
            param([AllowNull()][object]$MemoryGiB)

            if ($null -eq $MemoryGiB) {
                return 'unknown'
            }

            return ('{0:N2} GiB' -f ([double]$MemoryGiB))
        }

        switch -Exact ($kind) {
            'osFamily' {
                $actualValue = [string]$PackageModelConfig.Platform
                $allowedValues = if ($check.PSObject.Properties['allowed']) { @($check.allowed) } else { @() }
                $blockedValues = if ($check.PSObject.Properties['blocked']) { @($check.blocked) } else { @() }
                $accepted = Test-PackageModelCompatibilityAllowedBlockedMatch -Allowed $allowedValues -Blocked $blockedValues -ActualValue $actualValue
                $expectedSummary = @(
                    if ($allowedValues.Count -gt 0) { 'allowed=' + (($allowedValues | ForEach-Object { [string]$_ }) -join ',') }
                    if ($blockedValues.Count -gt 0) { 'blocked=' + (($blockedValues | ForEach-Object { [string]$_ }) -join ',') }
                ) -join '; '
            }
            'cpuArchitecture' {
                $actualValue = [string]$PackageModelConfig.Architecture
                $allowedValues = if ($check.PSObject.Properties['allowed']) { @($check.allowed) } else { @() }
                $blockedValues = if ($check.PSObject.Properties['blocked']) { @($check.blocked) } else { @() }
                $accepted = Test-PackageModelCompatibilityAllowedBlockedMatch -Allowed $allowedValues -Blocked $blockedValues -ActualValue $actualValue
                $expectedSummary = @(
                    if ($allowedValues.Count -gt 0) { 'allowed=' + (($allowedValues | ForEach-Object { [string]$_ }) -join ',') }
                    if ($blockedValues.Count -gt 0) { 'blocked=' + (($blockedValues | ForEach-Object { [string]$_ }) -join ',') }
                ) -join '; '
            }
            'osVersion' {
                $actualValue = [string]$PackageModelConfig.OSVersion
                $expectedVersion = ConvertTo-PackageModelVersion -VersionText ([string]$check.value)
                $actualVersion = ConvertTo-PackageModelVersion -VersionText $actualValue
                $operator = [string]$check.operator
                $accepted = switch -Exact ($operator) {
                    '=' { $actualVersion -eq $expectedVersion }
                    '==' { $actualVersion -eq $expectedVersion }
                    '!=' { $actualVersion -ne $expectedVersion }
                    '>' { $actualVersion -gt $expectedVersion }
                    '>=' { $actualVersion -ge $expectedVersion }
                    '<' { $actualVersion -lt $expectedVersion }
                    '<=' { $actualVersion -le $expectedVersion }
                    default { throw "Unsupported PackageModel osVersion compatibility operator '$operator'." }
                }
                $expectedSummary = '{0} {1}' -f $operator, [string]$check.value
            }
            'physicalMemoryGiB' {
                $operator = [string]$check.operator
                $expectedNumericValue = [double]([string]$check.value)
                $observedMemoryGiB = Get-PhysicalMemoryGiB
                $accepted = & $testNumericValue -ActualNumericValue $observedMemoryGiB -Operator $operator -ExpectedNumericValue $expectedNumericValue
                $actualValue = & $formatMemoryValue $observedMemoryGiB
                $expectedSummary = '{0} {1} GiB' -f $operator, [string]$check.value
            }
            'videoMemoryGiB' {
                $operator = [string]$check.operator
                $expectedNumericValue = [double]([string]$check.value)
                $observedMemoryGiB = Get-VideoMemoryGiB
                $accepted = & $testNumericValue -ActualNumericValue $observedMemoryGiB -Operator $operator -ExpectedNumericValue $expectedNumericValue
                $actualValue = & $formatMemoryValue $observedMemoryGiB
                $expectedSummary = '{0} {1} GiB' -f $operator, [string]$check.value
            }
            'physicalOrVideoMemoryGiB' {
                $operator = [string]$check.operator
                $expectedNumericValue = [double]([string]$check.value)
                $memoryRequirementResult = Test-PhysicalOrVideoMemoryRequirement -Operator $operator -ValueGiB $expectedNumericValue
                $accepted = [bool]$memoryRequirementResult.Accepted
                $actualValue = 'physical={0}; video={1}' -f (& $formatMemoryValue $memoryRequirementResult.PhysicalMemoryGiB), (& $formatMemoryValue $memoryRequirementResult.VideoMemoryGiB)
                $expectedSummary = '{0} {1} GiB' -f $operator, [string]$check.value
            }
            default {
                throw "Unsupported PackageModel compatibility kind '$kind'."
            }
        }

        if (-not $accepted) {
            $allAccepted = $false
            if ([string]::Equals($onFail, 'fail', [System.StringComparison]::OrdinalIgnoreCase)) {
                $blockingAccepted = $false
            }
        }

        $results.Add([pscustomobject]@{
            Kind     = $kind
            OnFail   = $onFail
            Accepted = $accepted
            Actual   = $actualValue
            Expected = $expectedSummary
        }) | Out-Null
    }

    return [pscustomobject]@{
        Accepted         = $allAccepted
        BlockingAccepted = $blockingAccepted
        Checks           = @($results.ToArray())
    }
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
    $compatibilityEvaluation = Test-PackageModelCompatibilityChecks -PackageModelConfig $packageModelConfig -Compatibility $selectedPackage.compatibility
    $PackageModelResult.Compatibility = @($compatibilityEvaluation.Checks)
    if (-not $compatibilityEvaluation.BlockingAccepted) {
        $failedCompatibilityText = @(
            foreach ($checkResult in @($compatibilityEvaluation.Checks)) {
                if (-not $checkResult.Accepted -and [string]::Equals([string]$checkResult.OnFail, 'fail', [System.StringComparison]::OrdinalIgnoreCase)) {
                    "{0} actual='{1}' expected='{2}' onFail='{3}'" -f $checkResult.Kind, [string]$checkResult.Actual, [string]$checkResult.Expected, [string]$checkResult.OnFail
                }
            }
        ) -join '; '
        throw "PackageModel release '$($selectedPackage.id)' does not satisfy compatibility.checks. $failedCompatibilityText"
    }

    $selectedFlavor = if ($selectedPackage.PSObject.Properties['flavor']) { [string]$selectedPackage.flavor } else { 'default' }
    Write-PackageModelExecutionMessage -Message ("[STATE] Selected release '{0}' version '{1}' for platform '{2}', architecture '{3}', releaseTrack '{4}', flavor '{5}'." -f $PackageModelResult.PackageId, $PackageModelResult.PackageVersion, $packageModelConfig.Platform, $packageModelConfig.Architecture, $effectiveReleaseTrack, $selectedFlavor)
    if (@($compatibilityEvaluation.Checks).Count -gt 0) {
        $compatibilitySummary = @(
            foreach ($checkResult in @($compatibilityEvaluation.Checks)) {
                "{0}={1}({2})" -f $checkResult.Kind, $(if ($checkResult.Accepted) { 'accepted' } else { 'rejected' }), [string]$checkResult.OnFail
            }
        ) -join ', '
        Write-PackageModelExecutionMessage -Message ("[STATE] Compatibility checks: {0}." -f $compatibilitySummary)
    }

    $compatibilityWarnings = @(
        foreach ($checkResult in @($compatibilityEvaluation.Checks)) {
            if (-not $checkResult.Accepted -and [string]::Equals([string]$checkResult.OnFail, 'warn', [System.StringComparison]::OrdinalIgnoreCase)) {
                "{0} actual='{1}' expected='{2}'" -f $checkResult.Kind, [string]$checkResult.Actual, [string]$checkResult.Expected
            }
        }
    )
    if ($compatibilityWarnings.Count -gt 0) {
        Write-PackageModelExecutionMessage -Message ("[WARN] Compatibility warnings: {0}." -f ($compatibilityWarnings -join '; '))
    }

    return $PackageModelResult
}

