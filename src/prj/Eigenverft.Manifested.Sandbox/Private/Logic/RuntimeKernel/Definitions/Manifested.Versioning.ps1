function ConvertTo-ManifestedComparableVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, 'v?(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function ConvertTo-ManifestedSemanticVersionText {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, 'v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?)')
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value
}

function ConvertTo-ManifestedSemanticVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    $normalizedVersion = ConvertTo-ManifestedSemanticVersionText -VersionText $VersionText
    if ([string]::IsNullOrWhiteSpace($normalizedVersion)) {
        return $null
    }

    $match = [regex]::Match($normalizedVersion, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Expand-ManifestedDefinitionTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,

        [string]$Version,

        [string]$TagName,

        [string]$Flavor
    )

    return ($Template.
        Replace('{version}', $(if ($null -ne $Version) { [string]$Version } else { '' })).
        Replace('{tagName}', $(if ($null -ne $TagName) { [string]$TagName } else { '' })).
        Replace('{flavor}', $(if ($null -ne $Flavor) { [string]$Flavor } else { '' })))
}

function Get-ManifestedHostArchitectureKey {
    [CmdletBinding()]
    param()

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return $null
    }

    $archHints = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) -join ';'
    if ($archHints -match 'ARM64') {
        return 'arm64'
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return 'x64'
    }

    return $null
}

function Get-ManifestedDefinitionPortableFactsBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    foreach ($blockName in @('portableRuntime', 'pythonEmbeddableRuntime')) {
        $factsBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName $blockName
        if ($factsBlock) {
            return $factsBlock
        }
    }

    return $null
}

function Get-ManifestedDefinitionRuntimeVersionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    $factsBlock = Get-ManifestedDefinitionPortableFactsBlock -Definition $Definition
    if (-not $factsBlock) {
        return $null
    }

    if ($factsBlock.PSObject.Properties.Match('versionRule').Count -gt 0 -and $factsBlock.versionRule) {
        return $factsBlock.versionRule
    }

    if ($factsBlock.PSObject.Properties.Match('versionProbe').Count -gt 0 -and $factsBlock.versionProbe) {
        return $factsBlock.versionProbe
    }

    return $null
}

function Get-ManifestedDefinitionReleaseVersionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    foreach ($blockName in @('githubRelease', 'nodeDist', 'vsCodeUpdate', 'pythonEmbed', 'directDownload')) {
        $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName $blockName
        if (-not $supplyBlock) {
            continue
        }

        if ($supplyBlock.PSObject.Properties.Match('releaseVersionRule').Count -gt 0 -and $supplyBlock.releaseVersionRule) {
            return $supplyBlock.releaseVersionRule
        }
    }

    return (Get-ManifestedDefinitionRuntimeVersionRule -Definition $Definition)
}

function Get-ManifestedDefinitionVersionPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    $factsBlock = Get-ManifestedDefinitionPortableFactsBlock -Definition $Definition
    if (-not $factsBlock) {
        return $null
    }

    if ($factsBlock.PSObject.Properties.Match('versionPolicy').Count -gt 0 -and $factsBlock.versionPolicy) {
        return $factsBlock.versionPolicy
    }

    return $null
}

function ConvertTo-ManifestedVersionTextFromRule {
    [CmdletBinding()]
    param(
        [string]$VersionText,

        [pscustomobject]$Rule
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    if (-not $Rule) {
        return (ConvertTo-ManifestedSemanticVersionText -VersionText $VersionText)
    }

    $pattern = if ($Rule.PSObject.Properties.Match('regex').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Rule.regex)) {
        [string]$Rule.regex
    }
    else {
        'v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?)'
    }

    $match = [regex]::Match($VersionText, $pattern)
    if (-not $match.Success) {
        return $null
    }

    $normalizedVersion = if ($match.Groups.Count -gt 1) { $match.Groups[1].Value } else { $match.Value }
    if ($Rule.PSObject.Properties.Match('normalizeRegex').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Rule.normalizeRegex)) {
        $replacement = if ($Rule.PSObject.Properties.Match('normalizeReplacement').Count -gt 0) { [string]$Rule.normalizeReplacement } else { '$1' }
        $normalizedVersion = ($normalizedVersion -replace [string]$Rule.normalizeRegex, $replacement)
    }

    if ($Rule.PSObject.Properties.Match('prefix').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Rule.prefix) -and -not $normalizedVersion.StartsWith([string]$Rule.prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedVersion = ([string]$Rule.prefix + $normalizedVersion)
    }

    return $normalizedVersion
}

function ConvertTo-ManifestedVersionObjectFromRule {
    [CmdletBinding()]
    param(
        [string]$VersionText,

        [pscustomobject]$Rule
    )

    $normalizedVersion = ConvertTo-ManifestedVersionTextFromRule -VersionText $VersionText -Rule $Rule
    if ([string]::IsNullOrWhiteSpace($normalizedVersion)) {
        return $null
    }

    $match = [regex]::Match($normalizedVersion, '(\d+(?:\.\d+){1,3})')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-ManifestedDefinitionFlavor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    foreach ($blockName in @('portableRuntime', 'pythonEmbeddableRuntime', 'machinePrerequisite', 'npmCli')) {
        $factsBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName $blockName
        if (-not $factsBlock) {
            continue
        }

        if ($factsBlock.PSObject.Properties.Match('hostFlavorMap').Count -gt 0 -and $factsBlock.hostFlavorMap) {
            $archKey = Get-ManifestedHostArchitectureKey
            if ([string]::IsNullOrWhiteSpace($archKey)) {
                return $null
            }

            if ($factsBlock.hostFlavorMap.PSObject.Properties.Match($archKey).Count -gt 0) {
                return $factsBlock.hostFlavorMap.$archKey
            }
        }
    }

    return $null
}

function Get-ManifestedVersionSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    return [pscustomobject]@{
        RuntimeVersionRule = Get-ManifestedDefinitionRuntimeVersionRule -Definition $Definition
        ReleaseVersionRule = Get-ManifestedDefinitionReleaseVersionRule -Definition $Definition
        VersionPolicy      = Get-ManifestedDefinitionVersionPolicy -Definition $Definition
    }
}

function Test-ManifestedManagedVersion {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [version]$Version,

        $VersionPolicy,

        $Rule
    )

    if (-not $VersionPolicy) {
        return $true
    }

    if ($VersionPolicy.PSObject.Properties.Match('managedMinimumVersion').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($VersionPolicy.managedMinimumVersion)) {
        $minimumVersion = ConvertTo-ManifestedVersionObjectFromRule -VersionText ([string]$VersionPolicy.managedMinimumVersion) -Rule $Rule
        if ($minimumVersion -and ($Version -lt $minimumVersion)) {
            return $false
        }
    }

    if ($VersionPolicy.PSObject.Properties.Match('managedVersionFamily').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($VersionPolicy.managedVersionFamily)) {
        $currentFamily = '{0}.{1}' -f $Version.Major, $Version.Minor
        if ($currentFamily -ne [string]$VersionPolicy.managedVersionFamily) {
            return $false
        }
    }

    return $true
}

function Test-ManifestedExternalVersion {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [version]$Version,

        $VersionPolicy,

        $Rule
    )

    if (-not $VersionPolicy) {
        return $true
    }

    if ($VersionPolicy.PSObject.Properties.Match('externalMinimumVersion').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($VersionPolicy.externalMinimumVersion)) {
        $minimumVersion = ConvertTo-ManifestedVersionObjectFromRule -VersionText ([string]$VersionPolicy.externalMinimumVersion) -Rule $Rule
        if ($minimumVersion -and ($Version -lt $minimumVersion)) {
            return $false
        }
    }

    return $true
}

function Get-ManifestedFlavorMappedValue {
    [CmdletBinding()]
    param(
        $Map,

        [Parameter(Mandatory = $true)]
        [string]$Flavor
    )

    if ($null -eq $Map) {
        return $null
    }

    if ($Map.PSObject.Properties.Match($Flavor).Count -gt 0) {
        return [string]$Map.$Flavor
    }

    return $null
}


