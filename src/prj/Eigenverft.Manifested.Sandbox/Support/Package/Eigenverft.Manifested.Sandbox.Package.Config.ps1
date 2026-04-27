<#
    Eigenverft.Manifested.Sandbox.Package.Config
#>

function Read-PackageJsonDocument {
<#
.SYNOPSIS
Reads a Package JSON document from disk.

.DESCRIPTION
Resolves a JSON file path, validates that it contains content, parses it, and
returns the resolved path together with the parsed document object.

.PARAMETER Path
Path to the JSON file that should be loaded.

.EXAMPLE
Read-PackageJsonDocument -Path .\Configuration\Internal\Config.json
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $rawContent = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($rawContent)) {
        throw "Package JSON file '$resolvedPath' is empty."
    }

    try {
        $document = $rawContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Package JSON file '$resolvedPath' could not be parsed. $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        Path     = $resolvedPath
        Document = $document
    }
}

function Resolve-PackagePathValue {
<#
.SYNOPSIS
Expands and normalizes a filesystem path value.

.DESCRIPTION
Expands environment variables, normalizes path separators, and returns a full
filesystem path for relative, local, or UNC paths.

.PARAMETER PathValue
The raw path value that should be normalized.

.EXAMPLE
Resolve-PackagePathValue -PathValue '%USERPROFILE%/Downloads/Test'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    $expandedPath = [Environment]::ExpandEnvironmentVariables($PathValue).Trim()
    if ([string]::IsNullOrWhiteSpace($expandedPath)) {
        throw 'Package path values must not be empty.'
    }

    $normalizedPath = $expandedPath -replace '/', '\'
    if ([System.IO.Path]::IsPathRooted($normalizedPath)) {
        return [System.IO.Path]::GetFullPath($normalizedPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $normalizedPath))
}

function Get-PackageRuntimeContext {
<#
.SYNOPSIS
Resolves the current Package runtime context.

.DESCRIPTION
Detects the effective platform and architecture used for package matching.

.EXAMPLE
Get-PackageRuntimeContext
#>
    [CmdletBinding()]
    param()

    $platform = switch ([Environment]::OSVersion.Platform) {
        ([System.PlatformID]::Win32NT) { 'windows'; break }
        ([System.PlatformID]::Unix) { 'linux'; break }
        ([System.PlatformID]::MacOSX) { 'macos'; break }
        default { [Environment]::OSVersion.Platform.ToString().ToLowerInvariant() }
    }

    $architecture = 'x86'
    foreach ($candidate in @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $normalizedCandidate = $candidate.ToUpperInvariant()
        if ($normalizedCandidate -like '*ARM64*') {
            $architecture = 'arm64'
            break
        }
        if ($normalizedCandidate -like '*64*') {
            $architecture = 'x64'
            break
        }
    }

    return [pscustomobject]@{
        Platform     = $platform
        Architecture = $architecture
        OSVersion    = [Environment]::OSVersion.Version.ToString()
    }
}

function Get-PackageDefaultPackageFileStagingDirectory {
<#
.SYNOPSIS
Returns the default Package package-file staging root.

.DESCRIPTION
Builds the fallback local staging root for raw package files
when the shipped or external config does not define one explicitly.

.EXAMPLE
Get-PackageDefaultPackageFileStagingDirectory
#>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path (Get-PackageLocalRoot) 'PackageFileStaging'))
}

function Get-PackageDefaultPackageInstallStageDirectory {
<#
.SYNOPSIS
Returns the default Package install-stage root.

.DESCRIPTION
Builds the fallback local stage root for package extraction and installer
execution when the shipped or external config does not define one explicitly.

.EXAMPLE
Get-PackageDefaultPackageInstallStageDirectory
#>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path (Get-PackageLocalRoot) 'PackageInstallStage'))
}

function Get-PackageDefaultPreferredTargetInstallDirectory {
<#
.SYNOPSIS
Returns the default Package preferred target-install root.

.DESCRIPTION
Builds the fallback local application-data root for Package preferred
target installs when the global document does not define one explicitly.

.EXAMPLE
Get-PackageDefaultPreferredTargetInstallDirectory
#>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path (Get-PackageLocalRoot) 'Installed'))
}

function Get-PackageDefaultPackageFileIndexFilePath {
<#
.SYNOPSIS
Returns the default Package package-file index path.

.DESCRIPTION
Builds the fallback local package-file index file path when the Package
acquisition environment does not define one explicitly.

.EXAMPLE
Get-PackageDefaultPackageFileIndexFilePath
#>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path (Join-Path (Get-PackageLocalRoot) 'State') 'package-file-index.json'))
}

function Get-PackageDefaultPackageStateIndexFilePath {
<#
.SYNOPSIS
Returns the default Package package-state index path.

.DESCRIPTION
Builds the fallback local package-state index file path when the Package
global document does not define one explicitly.

.EXAMPLE
Get-PackageDefaultPackageStateIndexFilePath
#>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path (Join-Path (Get-PackageLocalRoot) 'State') 'package-state-index.json'))
}

function Get-PackageDefaultLocalRepositoryRoot {
<#
.SYNOPSIS
Returns the default Package local repository root.

.DESCRIPTION
Builds the fallback local repository-copy root for package definitions that
have been used successfully.

.EXAMPLE
Get-PackageDefaultLocalRepositoryRoot
#>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path (Get-PackageLocalRoot) 'PackageRepositories'))
}

function Get-PackageDefaultSourceInventoryPath {
<#
.SYNOPSIS
Returns the default external Package source-inventory path.

.DESCRIPTION
Builds the fallback local source-inventory path that can hold environment and
site acquisition sources outside the shipped module JSON.

.EXAMPLE
Get-PackageDefaultSourceInventoryPath
#>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path (Join-Path (Get-PackageLocalRoot) 'Configuration\External') 'SourceInventory.json'))
}

function Get-PackageDefaultLogRootDirectory {
<#
.SYNOPSIS
Returns the default Package log root.

.DESCRIPTION
Builds the fallback local application-data root for package installer logs.

.EXAMPLE
Get-PackageDefaultLogRootDirectory
#>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path (Get-PackageLocalRoot) 'Logs'))
}

function Get-PackageRootFromStateIndexPath {
<#
.SYNOPSIS
Returns the Package local root from a package-state index path.

.DESCRIPTION
The current layout stores indexes under State. Older or custom test layouts may
place the state index directly under the package root, so this helper accepts
both shapes.

.EXAMPLE
Get-PackageRootFromStateIndexPath -PackageStateIndexFilePath $path
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageStateIndexFilePath
    )

    $indexDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($PackageStateIndexFilePath))
    if ([string]::Equals((Split-Path -Leaf $indexDirectory), 'State', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [System.IO.Path]::GetFullPath((Split-Path -Parent $indexDirectory))
    }

    return [System.IO.Path]::GetFullPath($indexDirectory)
}

function Resolve-PackageTemplateText {
<#
.SYNOPSIS
Resolves simple Package template tokens in text.

.DESCRIPTION
Replaces package-aware tokens such as `{releaseTrack}`, `{version}`, and
`{flavor}` with the current values from the resolved Package config and
selected release.

.PARAMETER Text
The text that contains optional Package tokens.

.PARAMETER PackageConfig
The resolved Package config object.

.PARAMETER Package
The selected release object.

.PARAMETER ExtraTokens
Optional extra tokens to merge into the standard replacement map.

.EXAMPLE
Resolve-PackageTemplateText -Text '{releaseTrack}\{version}\{flavor}' -PackageConfig $config -Package $package
#>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [AllowNull()]
        [psobject]$PackageConfig,

        [AllowNull()]
        [psobject]$Package,

        [hashtable]$ExtraTokens = @{}
    )

    if ($null -eq $Text) {
        return $null
    }

    $tokens = [ordered]@{}
    if ($PackageConfig) {
        $tokens['definitionId'] = $PackageConfig.DefinitionId
        $tokens['platform'] = $PackageConfig.Platform
        $tokens['architecture'] = $PackageConfig.Architecture
        $tokens['releaseTrack'] = $PackageConfig.ReleaseTrack
        if ($PackageConfig.PSObject.Properties['PreferredTargetInstallRootDirectory']) {
            $tokens['preferredTargetInstallDirectory'] = $PackageConfig.PreferredTargetInstallRootDirectory
        }
        if ($PackageConfig.PSObject.Properties['PackageFileStagingRootDirectory']) {
            $tokens['packageFileStagingDirectory'] = $PackageConfig.PackageFileStagingRootDirectory
        }
        if ($PackageConfig.PSObject.Properties['PackageInstallStageRootDirectory']) {
            $tokens['packageInstallStageDirectory'] = $PackageConfig.PackageInstallStageRootDirectory
        }
        if ($PackageConfig.PSObject.Properties['DefaultPackageDepotDirectory']) {
            $tokens['defaultPackageDepotDirectory'] = $PackageConfig.DefaultPackageDepotDirectory
        }
    }
    if ($Package) {
        $tokens['packageId'] = if ($Package.PSObject.Properties['id']) { [string]$Package.id } else { $null }
        $tokens['releaseId'] = if ($Package.PSObject.Properties['id']) { [string]$Package.id } else { $null }
        $tokens['releaseTrack'] = if ($Package.PSObject.Properties['releaseTrack']) { [string]$Package.releaseTrack } else { $tokens['releaseTrack'] }
        $tokens['version'] = if ($Package.PSObject.Properties['version']) { [string]$Package.version } else { $null }
        $tokens['flavor'] = if ($Package.PSObject.Properties['flavor']) { [string]$Package.flavor } else { $null }
    }
    foreach ($key in @($ExtraTokens.Keys)) {
        $tokens[$key] = $ExtraTokens[$key]
    }

    $resolvedText = [string]$Text
    foreach ($key in @($tokens.Keys)) {
        if ($null -eq $tokens[$key]) {
            continue
        }

        $resolvedText = $resolvedText.Replace(('{' + [string]$key + '}'), [string]$tokens[$key])
    }

    return $resolvedText
}

function Get-PackagePackageFileRelativeDirectory {
<#
.SYNOPSIS
Builds the relative package-file directory for depot and workspace storage.

.DESCRIPTION
Derives the shared relative directory used below package depots and the
package file staging from the definition id and selected release identity.

.PARAMETER PackageConfig
The resolved Package config object.

.PARAMETER Package
The selected release object.

.EXAMPLE
Get-PackagePackageFileRelativeDirectory -PackageConfig $config -Package $package
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageConfig,

        [Parameter(Mandatory = $true)]
        [psobject]$Package
    )

    $definitionId = [string]$PackageConfig.DefinitionId
    $releaseTrack = if ($Package.PSObject.Properties['releaseTrack']) { [string]$Package.releaseTrack } else { [string]$PackageConfig.ReleaseTrack }
    $version = if ($Package.PSObject.Properties['version']) { [string]$Package.version } else { $null }
    $flavor = if ($Package.PSObject.Properties['flavor']) { [string]$Package.flavor } else { $null }

    foreach ($requiredValue in @($definitionId, $releaseTrack, $version, $flavor)) {
        if ([string]::IsNullOrWhiteSpace($requiredValue)) {
            throw 'Package package-file directory derivation requires definition id, releaseTrack, version, and flavor.'
        }
    }

    $pathSegments = @('packages', $definitionId, $releaseTrack, $version, $flavor) | ForEach-Object {
        $segmentText = ([string]$_).Trim() -replace '[\\/:\*\?"<>\|]', '-'
        if ([string]::IsNullOrWhiteSpace($segmentText)) {
            throw 'Package package-file directory derivation produced an empty path segment.'
        }
        $segmentText
    }

    return (($pathSegments -join '\') -replace '/', '\')
}

function ConvertTo-PackageMergeValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [string] -or
        $InputObject -is [ValueType] -or
        $InputObject -is [datetime] -or
        $InputObject -is [guid]) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($InputObject.Keys)) {
            $result[[string]$key] = ConvertTo-PackageMergeValue -InputObject $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0)) {
        return @($InputObject | ForEach-Object { ConvertTo-PackageMergeValue -InputObject $_ })
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        return @($InputObject | ForEach-Object { ConvertTo-PackageMergeValue -InputObject $_ })
    }

    if ($InputObject.PSObject.Properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($property in @($InputObject.PSObject.Properties)) {
            $result[$property.Name] = ConvertTo-PackageMergeValue -InputObject $property.Value
        }
        return $result
    }

    return $InputObject
}

function Merge-PackageValues {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$BaseValue,

        [AllowNull()]
        [object]$OverlayValue
    )

    if ($null -eq $BaseValue) {
        return (ConvertTo-PackageMergeValue -InputObject $OverlayValue)
    }
    if ($null -eq $OverlayValue) {
        return (ConvertTo-PackageMergeValue -InputObject $BaseValue)
    }

    $baseIsObject = ($BaseValue -is [System.Collections.IDictionary])
    $overlayIsObject = ($OverlayValue -is [System.Collections.IDictionary])
    if ($baseIsObject -and $overlayIsObject) {
        $merged = [ordered]@{}
        foreach ($key in @($BaseValue.Keys)) {
            $merged[[string]$key] = ConvertTo-PackageMergeValue -InputObject $BaseValue[$key]
        }
        foreach ($key in @($OverlayValue.Keys)) {
            $keyText = [string]$key
            if ($merged.Contains($keyText)) {
                $merged[$keyText] = Merge-PackageValues -BaseValue $merged[$keyText] -OverlayValue $OverlayValue[$key]
            }
            else {
                $merged[$keyText] = ConvertTo-PackageMergeValue -InputObject $OverlayValue[$key]
            }
        }
        return $merged
    }

    if (($BaseValue -is [System.Collections.IEnumerable] -and -not ($BaseValue -is [string])) -and
        ($OverlayValue -is [System.Collections.IEnumerable] -and -not ($OverlayValue -is [string]))) {
        return @(ConvertTo-PackageMergeValue -InputObject $OverlayValue)
    }

    return (ConvertTo-PackageMergeValue -InputObject $OverlayValue)
}

function ConvertTo-PackageObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [string] -or
        $InputObject -is [ValueType] -or
        $InputObject -is [datetime] -or
        $InputObject -is [guid]) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($InputObject.Keys)) {
            $result[[string]$key] = ConvertTo-PackageObject -InputObject $InputObject[$key]
        }
        return [pscustomobject]$result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and
        -not ($InputObject -is [string]) -and
        -not ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0)) {
        return @($InputObject | ForEach-Object { ConvertTo-PackageObject -InputObject $_ })
    }

    if ($InputObject.PSObject.Properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($property in @($InputObject.PSObject.Properties)) {
            $result[$property.Name] = ConvertTo-PackageObject -InputObject $property.Value
        }
        return [pscustomobject]$result
    }

    return $InputObject
}

function Get-PackageSourceInventoryPath {
<#
.SYNOPSIS
Returns the effective external Package source-inventory path.

.DESCRIPTION
Resolves the environment-variable override first, then falls back to the
well-known local inventory path.

.EXAMPLE
Get-PackageSourceInventoryPath
#>
    [CmdletBinding()]
    param()

    $environmentVariableName = Get-PackageSourceInventoryPathEnvironmentVariableName
    $configuredPath = [Environment]::GetEnvironmentVariable($environmentVariableName)
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        return (Resolve-PackagePathValue -PathValue $configuredPath)
    }

    return (Get-PackageDefaultSourceInventoryPath)
}

function Get-PackageSiteCode {
<#
.SYNOPSIS
Returns the effective Package site code.

.DESCRIPTION
Reads the optional site-code environment variable and normalizes its value.

.EXAMPLE
Get-PackageSiteCode
#>
    [CmdletBinding()]
    param()

    $environmentVariableName = Get-PackageSiteCodeEnvironmentVariableName
    $siteCode = [Environment]::GetEnvironmentVariable($environmentVariableName)
    if ([string]::IsNullOrWhiteSpace($siteCode)) {
        return $null
    }

    return $siteCode.Trim()
}

function Get-PackageActiveSiteCodes {
<#
.SYNOPSIS
Returns the effective Package site-code list.

.DESCRIPTION
Reads the optional site-code environment variable as a semicolon-separated
list, trims empty entries, and de-duplicates while preserving order.

.EXAMPLE
Get-PackageActiveSiteCodes
#>
    [CmdletBinding()]
    param()

    $environmentVariableName = Get-PackageSiteCodeEnvironmentVariableName
    $siteCodeText = [Environment]::GetEnvironmentVariable($environmentVariableName)
    if ([string]::IsNullOrWhiteSpace($siteCodeText)) {
        return @()
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $siteCodes = New-Object System.Collections.Generic.List[string]
    foreach ($siteCode in @($siteCodeText -split ';')) {
        $normalizedSiteCode = ([string]$siteCode).Trim()
        if ([string]::IsNullOrWhiteSpace($normalizedSiteCode)) {
            continue
        }
        if ($seen.Add($normalizedSiteCode)) {
            $siteCodes.Add($normalizedSiteCode) | Out-Null
        }
    }

    return @($siteCodes.ToArray())
}

function Assert-PackageDepotInventorySchema {
<#
.SYNOPSIS
Validates the Package depot-inventory schema.

.DESCRIPTION
Checks that the internal depot inventory document uses the current shape with
inventoryVersion and acquisitionEnvironment.

.PARAMETER DepotInventoryDocumentInfo
The loaded depot-inventory document info.

.EXAMPLE
Assert-PackageDepotInventorySchema -DepotInventoryDocumentInfo $inventoryInfo
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$DepotInventoryDocumentInfo
    )

    $document = $DepotInventoryDocumentInfo.Document
    if (-not $document.PSObject.Properties['inventoryVersion']) {
        throw "Package depot inventory '$($DepotInventoryDocumentInfo.Path)' is missing inventoryVersion."
    }
    if (-not $document.PSObject.Properties['acquisitionEnvironment'] -or $null -eq $document.acquisitionEnvironment) {
        throw "Package depot inventory '$($DepotInventoryDocumentInfo.Path)' is missing acquisitionEnvironment."
    }
    if ($document.acquisitionEnvironment.PSObject.Properties['environmentSources']) {
        foreach ($sourceProperty in @($document.acquisitionEnvironment.environmentSources.PSObject.Properties)) {
            if ($sourceProperty.Value -and $sourceProperty.Value.PSObject.Properties['priority']) {
                throw "Package depot inventory '$($DepotInventoryDocumentInfo.Path)' source '$($sourceProperty.Name)' still uses retired property 'priority'. Use 'searchOrder'."
            }
            if ($sourceProperty.Value -and -not $sourceProperty.Value.PSObject.Properties['searchOrder']) {
                throw "Package depot inventory '$($DepotInventoryDocumentInfo.Path)' source '$($sourceProperty.Name)' is missing searchOrder."
            }
            Assert-PackageEnvironmentSourceCapabilities -SourceId $sourceProperty.Name -SourceValue $sourceProperty.Value -DocumentPath $DepotInventoryDocumentInfo.Path
        }
    }
}

function Assert-PackageEnvironmentSourceCapabilities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [psobject]$SourceValue,

        [Parameter(Mandatory = $true)]
        [string]$DocumentPath
    )

    if (-not [string]::Equals([string]$SourceValue.kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    foreach ($capabilityName in @('readable', 'writable', 'mirrorTarget', 'ensureExists')) {
        if (-not $SourceValue.PSObject.Properties[$capabilityName]) {
            throw "Package environment source '$SourceId' in '$DocumentPath' is missing capability '$capabilityName'."
        }
    }

    $writable = [bool]$SourceValue.writable
    if ([bool]$SourceValue.mirrorTarget -and -not $writable) {
        throw "Package environment source '$SourceId' in '$DocumentPath' cannot use mirrorTarget=true with writable=false."
    }
    if ([bool]$SourceValue.ensureExists -and -not $writable) {
        throw "Package environment source '$SourceId' in '$DocumentPath' cannot use ensureExists=true with writable=false."
    }
}

function Get-PackageDepotInventoryInfo {
<#
.SYNOPSIS
Loads the internal Package depot inventory.

.DESCRIPTION
Loads the effective local depot-inventory document, creating it from the
shipped module defaults when missing.

.EXAMPLE
Get-PackageDepotInventoryInfo
#>
    [CmdletBinding()]
    param()

    $inventoryPath = Get-PackageDepotInventoryPath
    $documentInfo = Read-PackageJsonDocument -Path $inventoryPath
    Assert-PackageDepotInventorySchema -DepotInventoryDocumentInfo $documentInfo
    return [pscustomobject]@{
        Path     = $documentInfo.Path
        Document = $documentInfo.Document
        Exists   = $true
    }
}

function Assert-PackageSourceInventorySchema {
<#
.SYNOPSIS
Validates the Package source-inventory schema.

.DESCRIPTION
Checks that the external inventory document uses the current shape with
inventoryVersion, global, and optional site overlays.

.PARAMETER SourceInventoryDocumentInfo
The loaded source-inventory document info.

.EXAMPLE
Assert-PackageSourceInventorySchema -SourceInventoryDocumentInfo $inventoryInfo
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SourceInventoryDocumentInfo
    )

    $document = $SourceInventoryDocumentInfo.Document
    if (-not $document.PSObject.Properties['inventoryVersion']) {
        throw "Package source inventory '$($SourceInventoryDocumentInfo.Path)' is missing inventoryVersion."
    }
    if (-not $document.PSObject.Properties['global']) {
        $document | Add-Member -MemberType NoteProperty -Name global -Value ([pscustomobject]@{})
    }
    if (-not $document.PSObject.Properties['sites']) {
        $document | Add-Member -MemberType NoteProperty -Name sites -Value ([pscustomobject]@{})
    }
}

function Get-PackageSourceInventoryInfo {
<#
.SYNOPSIS
Loads the optional external Package source inventory.

.DESCRIPTION
Resolves the effective inventory path, loads it when present, validates the
schema, and otherwise returns a null document marker.

.EXAMPLE
Get-PackageSourceInventoryInfo
#>
    [CmdletBinding()]
    param()

    $inventoryPath = Get-PackageSourceInventoryPath
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        return [pscustomobject]@{
            Path     = $inventoryPath
            Document = $null
            Exists   = $false
        }
    }

    $documentInfo = Read-PackageJsonDocument -Path $inventoryPath
    Assert-PackageSourceInventorySchema -SourceInventoryDocumentInfo $documentInfo
    return [pscustomobject]@{
        Path     = $documentInfo.Path
        Document = $documentInfo.Document
        Exists   = $true
    }
}

function Assert-PackageGlobalConfigSchema {
<#
.SYNOPSIS
Validates the Package global config schema.

.DESCRIPTION
Rejects retired global field names and requires the current Package
preferred-install and acquisition-environment fields.

.PARAMETER GlobalDocumentInfo
The loaded Package global config document info.

.EXAMPLE
Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalInfo
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$GlobalDocumentInfo
    )

    if (-not $GlobalDocumentInfo.Document.PSObject.Properties['package'] -or $null -eq $GlobalDocumentInfo.Document.package) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' does not contain a 'package' object."
    }

    $package = $GlobalDocumentInfo.Document.package
    foreach ($retiredProperty in @('managedStorageRoots', 'acquisitionDefaults', 'sourceBindings', 'downloadRootDirectory', 'installRootDirectory', 'allowSourceFallback', 'packageSelection', 'ownershipTracking')) {
        if ($package.PSObject.Properties[$retiredProperty]) {
            throw "Package global config '$($GlobalDocumentInfo.Path)' still uses retired property '$retiredProperty'."
        }
    }

    foreach ($requiredProperty in @('preferredTargetInstallDirectory', 'repositorySources', 'localRepositoryRoot', 'acquisitionEnvironment', 'packageState', 'selectionDefaults')) {
        if (-not $package.PSObject.Properties[$requiredProperty]) {
            throw "Package global config '$($GlobalDocumentInfo.Path)' is missing required property '$requiredProperty'."
        }
    }

    if ($package.selectionDefaults.PSObject.Properties['channel']) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' still uses retired property 'selectionDefaults.channel'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$package.preferredTargetInstallDirectory)) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' is missing preferredTargetInstallDirectory."
    }

    foreach ($requiredAcquisitionProperty in @('stores', 'defaults', 'tracking')) {
        if (-not $package.acquisitionEnvironment.PSObject.Properties[$requiredAcquisitionProperty]) {
            throw "Package global config '$($GlobalDocumentInfo.Path)' is missing acquisitionEnvironment.$requiredAcquisitionProperty."
        }
    }

    if ($package.acquisitionEnvironment.stores.PSObject.Properties['defaultPackageDepotDirectory']) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' still uses retired property 'acquisitionEnvironment.stores.defaultPackageDepotDirectory'. Use Configuration/Internal/DepotInventory.json environmentSources.defaultPackageDepot.basePath."
    }
    if ($package.acquisitionEnvironment.stores.PSObject.Properties['installWorkspaceDirectory']) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' still uses retired property 'acquisitionEnvironment.stores.installWorkspaceDirectory'. Use 'acquisitionEnvironment.stores.packageFileStagingDirectory'."
    }
    if ($package.acquisitionEnvironment.stores.PSObject.Properties['installPreparationDirectory']) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' still uses retired property 'acquisitionEnvironment.stores.installPreparationDirectory'. Use 'acquisitionEnvironment.stores.packageFileStagingDirectory' and 'acquisitionEnvironment.stores.packageInstallStageDirectory'."
    }

    foreach ($requiredStoreProperty in @('packageFileStagingDirectory', 'packageInstallStageDirectory')) {
        if (-not $package.acquisitionEnvironment.stores.PSObject.Properties[$requiredStoreProperty]) {
            throw "Package global config '$($GlobalDocumentInfo.Path)' is missing acquisitionEnvironment.stores.$requiredStoreProperty."
        }
    }

    foreach ($requiredDefaultProperty in @('allowFallback', 'mirrorDownloadedArtifactsToDefaultPackageDepot')) {
        if (-not $package.acquisitionEnvironment.defaults.PSObject.Properties[$requiredDefaultProperty]) {
            throw "Package global config '$($GlobalDocumentInfo.Path)' is missing acquisitionEnvironment.defaults.$requiredDefaultProperty."
        }
    }

    if ($package.acquisitionEnvironment.tracking.PSObject.Properties['artifactIndexFilePath']) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' still uses retired property 'acquisitionEnvironment.tracking.artifactIndexFilePath'. Use 'acquisitionEnvironment.tracking.packageFileIndexFilePath'."
    }
    if (-not $package.acquisitionEnvironment.tracking.PSObject.Properties['packageFileIndexFilePath']) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' is missing acquisitionEnvironment.tracking.packageFileIndexFilePath."
    }
    if (-not $package.packageState.PSObject.Properties['indexFilePath']) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' is missing packageState.indexFilePath."
    }
    if (-not $package.selectionDefaults.PSObject.Properties['releaseTrack']) {
        throw "Package global config '$($GlobalDocumentInfo.Path)' is missing selectionDefaults.releaseTrack."
    }

    foreach ($repositoryProperty in @($package.repositorySources.PSObject.Properties)) {
        $repositorySource = $repositoryProperty.Value
        if (-not $repositorySource.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$repositorySource.kind)) {
            throw "Package global config '$($GlobalDocumentInfo.Path)' repositorySources.$($repositoryProperty.Name) is missing kind."
        }
        if (-not $repositorySource.PSObject.Properties['definitionRoot'] -or [string]::IsNullOrWhiteSpace([string]$repositorySource.definitionRoot)) {
            throw "Package global config '$($GlobalDocumentInfo.Path)' repositorySources.$($repositoryProperty.Name) is missing definitionRoot."
        }
    }

    if ($package.acquisitionEnvironment.PSObject.Properties['environmentSources'] -and $null -ne $package.acquisitionEnvironment.environmentSources) {
        foreach ($retiredEnvironmentSourceId in @('localPackageDepot', 'remotePackageDepot', 'corpPackageDepot', 'sitePackageDepot', 'vsCodeUpdateService')) {
            if ($package.acquisitionEnvironment.environmentSources.PSObject.Properties[$retiredEnvironmentSourceId]) {
                throw "Package global config '$($GlobalDocumentInfo.Path)' must not define acquisitionEnvironment.environmentSources.$retiredEnvironmentSourceId in the shipped global config."
            }
        }
    }
}

function Resolve-PackageEnvironmentSources {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$EnvironmentSources,

        [AllowNull()]
        [string[]]$ActiveSiteCodes = @()
    )

    $resolvedSources = [ordered]@{}

    if ($EnvironmentSources) {
        foreach ($property in @($EnvironmentSources.PSObject.Properties)) {
            $sourceValue = $property.Value
            $enabled = $true
            if ($sourceValue.PSObject.Properties['enabled']) {
                $enabled = [bool]$sourceValue.enabled
            }
            if (-not $enabled) {
                continue
            }
            if ($sourceValue.PSObject.Properties['priority']) {
                throw "Package environment source '$($property.Name)' still uses retired property 'priority'. Use 'searchOrder'."
            }
            if (-not $sourceValue.PSObject.Properties['searchOrder']) {
                throw "Package environment source '$($property.Name)' is missing searchOrder."
            }
            Assert-PackageEnvironmentSourceCapabilities -SourceId $property.Name -SourceValue $sourceValue -DocumentPath 'effective acquisition environment'

            $sourceSiteCodes = @()
            if ($sourceValue.PSObject.Properties['siteCodes'] -and $null -ne $sourceValue.siteCodes) {
                $sourceSiteCodes = @($sourceValue.siteCodes | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
            if ($sourceSiteCodes.Count -gt 0) {
                $matchesActiveSiteCode = $false
                foreach ($sourceSiteCode in $sourceSiteCodes) {
                    foreach ($activeSiteCode in @($ActiveSiteCodes)) {
                        if ([string]::Equals([string]$sourceSiteCode, [string]$activeSiteCode, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $matchesActiveSiteCode = $true
                            break
                        }
                    }
                    if ($matchesActiveSiteCode) {
                        break
                    }
                }
                if (-not $matchesActiveSiteCode) {
                    continue
                }
            }

            $resolvedSource = [ordered]@{
                id       = $property.Name
                kind     = if ($sourceValue.PSObject.Properties['kind']) { [string]$sourceValue.kind } else { $null }
                enabled  = $true
                searchOrder = if ($sourceValue.PSObject.Properties['searchOrder']) { [int]$sourceValue.searchOrder } else { 1000 }
                readable = if ($sourceValue.PSObject.Properties['readable']) { [bool]$sourceValue.readable } else { $true }
                writable = if ($sourceValue.PSObject.Properties['writable']) { [bool]$sourceValue.writable } else { $false }
                mirrorTarget = if ($sourceValue.PSObject.Properties['mirrorTarget']) { [bool]$sourceValue.mirrorTarget } else { $false }
                ensureExists = if ($sourceValue.PSObject.Properties['ensureExists']) { [bool]$sourceValue.ensureExists } else { $false }
            }

            if ($sourceValue.PSObject.Properties['baseUri'] -and -not [string]::IsNullOrWhiteSpace([string]$sourceValue.baseUri)) {
                $resolvedSource.baseUri = [string]$sourceValue.baseUri
            }
            if ($sourceValue.PSObject.Properties['basePath'] -and -not [string]::IsNullOrWhiteSpace([string]$sourceValue.basePath)) {
                $resolvedSource.basePath = Resolve-PackagePathValue -PathValue ([string]$sourceValue.basePath)
            }
            if ($sourceSiteCodes.Count -gt 0) {
                $resolvedSource.siteCodes = @($sourceSiteCodes)
            }

            $resolvedSources[$property.Name] = $resolvedSource
        }
    }

    return (ConvertTo-PackageObject -InputObject $resolvedSources)
}

function Resolve-PackageEffectiveAcquisitionEnvironment {
<#
.SYNOPSIS
Materializes the effective Package acquisition environment.

.DESCRIPTION
Starts from the shipped acquisition-environment config, applies optional
inventory global and site overlays, resolves concrete store paths, and returns
the internal effective environment model used by later source planning.

.PARAMETER GlobalConfiguration
The shipped Package global config object.

.PARAMETER SourceInventoryInfo
The optional external source-inventory document info.

.PARAMETER DepotInventoryInfo
The internal depot-inventory document info.

.EXAMPLE
Resolve-PackageEffectiveAcquisitionEnvironment -GlobalConfiguration $global -SourceInventoryInfo $inventory -DepotInventoryInfo $depotInventory
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$GlobalConfiguration,

        [Parameter(Mandatory = $true)]
        [psobject]$SourceInventoryInfo,

        [Parameter(Mandatory = $true)]
        [psobject]$DepotInventoryInfo
    )

    $mergedAcquisitionEnvironment = ConvertTo-PackageMergeValue -InputObject $GlobalConfiguration.acquisitionEnvironment
    $activeSiteCodes = @(Get-PackageActiveSiteCodes)

    if ($DepotInventoryInfo -and $DepotInventoryInfo.Document) {
        $depotOverlay = Get-PackageInventoryAcquisitionOverlay -InventoryNode $DepotInventoryInfo.Document
        if ($depotOverlay) {
            $mergedAcquisitionEnvironment = Merge-PackageValues -BaseValue $mergedAcquisitionEnvironment -OverlayValue (ConvertTo-PackageMergeValue -InputObject $depotOverlay)
        }
    }

    if ($SourceInventoryInfo -and $SourceInventoryInfo.Exists -and $SourceInventoryInfo.Document) {
        $inventoryGlobal = if ($SourceInventoryInfo.Document.PSObject.Properties['global']) { $SourceInventoryInfo.Document.global } else { $null }
        if ($inventoryGlobal) {
            $inventoryGlobalOverlay = Get-PackageInventoryAcquisitionOverlay -InventoryNode $inventoryGlobal
            if ($inventoryGlobalOverlay) {
                $mergedAcquisitionEnvironment = Merge-PackageValues -BaseValue $mergedAcquisitionEnvironment -OverlayValue (ConvertTo-PackageMergeValue -InputObject $inventoryGlobalOverlay)
            }
        }

        if ($activeSiteCodes.Count -gt 0 -and $SourceInventoryInfo.Document.PSObject.Properties['sites']) {
            foreach ($activeSiteCode in @($activeSiteCodes)) {
                foreach ($siteProperty in @($SourceInventoryInfo.Document.sites.PSObject.Properties)) {
                    if ([string]::Equals([string]$siteProperty.Name, [string]$activeSiteCode, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $siteOverlay = Get-PackageInventoryAcquisitionOverlay -InventoryNode $siteProperty.Value
                        if ($siteOverlay) {
                            $mergedAcquisitionEnvironment = Merge-PackageValues -BaseValue $mergedAcquisitionEnvironment -OverlayValue (ConvertTo-PackageMergeValue -InputObject $siteOverlay)
                        }
                        break
                    }
                }
            }
        }
    }

    $acquisitionEnvironment = ConvertTo-PackageObject -InputObject $mergedAcquisitionEnvironment

    $packageFileStagingDirectory = if ($acquisitionEnvironment.stores.PSObject.Properties['packageFileStagingDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$acquisitionEnvironment.stores.packageFileStagingDirectory)) {
        Resolve-PackagePathValue -PathValue ([string]$acquisitionEnvironment.stores.packageFileStagingDirectory)
    }
    else {
        Get-PackageDefaultPackageFileStagingDirectory
    }

    $packageInstallStageDirectory = if ($acquisitionEnvironment.stores.PSObject.Properties['packageInstallStageDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$acquisitionEnvironment.stores.packageInstallStageDirectory)) {
        Resolve-PackagePathValue -PathValue ([string]$acquisitionEnvironment.stores.packageInstallStageDirectory)
    }
    else {
        Get-PackageDefaultPackageInstallStageDirectory
    }

    $packageFileIndexFilePath = if ($acquisitionEnvironment.tracking.PSObject.Properties['packageFileIndexFilePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$acquisitionEnvironment.tracking.packageFileIndexFilePath)) {
        Resolve-PackagePathValue -PathValue ([string]$acquisitionEnvironment.tracking.packageFileIndexFilePath)
    }
    else {
        Get-PackageDefaultPackageFileIndexFilePath
    }

    $allowFallback = $true
    if ($acquisitionEnvironment.defaults.PSObject.Properties['allowFallback']) {
        $allowFallback = [bool]$acquisitionEnvironment.defaults.allowFallback
    }

    $mirrorDownloadedArtifacts = $true
    if ($acquisitionEnvironment.defaults.PSObject.Properties['mirrorDownloadedArtifactsToDefaultPackageDepot']) {
        $mirrorDownloadedArtifacts = [bool]$acquisitionEnvironment.defaults.mirrorDownloadedArtifactsToDefaultPackageDepot
    }

    $configuredEnvironmentSources = $null
    if ($acquisitionEnvironment.PSObject.Properties['environmentSources']) {
        $configuredEnvironmentSources = $acquisitionEnvironment.environmentSources
    }

    $environmentSources = Resolve-PackageEnvironmentSources -EnvironmentSources $configuredEnvironmentSources -ActiveSiteCodes $activeSiteCodes
    $defaultPackageDepotDirectory = $null
    if ($environmentSources -and $environmentSources.PSObject.Properties['defaultPackageDepot']) {
        $defaultPackageDepot = $environmentSources.defaultPackageDepot
        if ([string]::Equals([string]$defaultPackageDepot.kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase) -and
            $defaultPackageDepot.PSObject.Properties['basePath'] -and
            -not [string]::IsNullOrWhiteSpace([string]$defaultPackageDepot.basePath)) {
            $defaultPackageDepotDirectory = [string]$defaultPackageDepot.basePath
        }
    }

    return [pscustomobject]@{
        SourceInventoryPath = $SourceInventoryInfo.Path
        DepotInventoryPath  = $DepotInventoryInfo.Path
        SiteCode            = (@($activeSiteCodes) -join ';')
        SiteCodes           = @($activeSiteCodes)
        Stores              = [pscustomobject]@{
            PackageFileStagingDirectory  = $packageFileStagingDirectory
            PackageInstallStageDirectory = $packageInstallStageDirectory
            DefaultPackageDepotDirectory = $defaultPackageDepotDirectory
        }
        Defaults            = [pscustomobject]@{
            AllowFallback = $allowFallback
            MirrorDownloadedArtifactsToDefaultPackageDepot = $mirrorDownloadedArtifacts
        }
        EnvironmentSources  = $environmentSources
        Tracking            = [pscustomobject]@{
            PackageFileIndexFilePath = $packageFileIndexFilePath
        }
    }
}

function Get-PackageInventoryAcquisitionOverlay {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$InventoryNode
    )

    if (-not $InventoryNode) {
        return $null
    }

    if ($InventoryNode.PSObject.Properties['acquisitionEnvironment'] -and $null -ne $InventoryNode.acquisitionEnvironment) {
        return $InventoryNode.acquisitionEnvironment
    }

    return $InventoryNode
}

function Assert-PackageDefinitionSchema {
<#
.SYNOPSIS
Validates the Package definition schema for this package pass.

.DESCRIPTION
Checks that the definition uses the current package-definition and
acquisition-source model and rejects the earlier experimental schema names.

.PARAMETER DefinitionDocumentInfo
The loaded Package definition document info.

.PARAMETER DefinitionId
The expected definition id.

.EXAMPLE
Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId VSCodeRuntime
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$DefinitionDocumentInfo,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId
    )

    $definition = $DefinitionDocumentInfo.Document
    foreach ($retiredProperty in @('classification', 'target', 'origins', 'interfaces', 'packageType', 'paths', 'sources', 'packages', 'entryPoints', 'packageFamily', 'managedPaths')) {
        if ($definition.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' still uses retired property '$retiredProperty'."
        }
    }

    foreach ($requiredProperty in @('schemaVersion', 'id', 'display', 'upstreamSources', 'providedTools', 'releaseDefaults', 'releases')) {
        if (-not $definition.PSObject.Properties[$requiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' is missing required property '$requiredProperty'."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$definition.schemaVersion)) {
        throw "Package definition '$($DefinitionDocumentInfo.Path)' defines schemaVersion, but it is empty."
    }
    if (-not [string]::Equals([string]$definition.schemaVersion, '1.0', [System.StringComparison]::Ordinal)) {
        throw "Package definition '$($DefinitionDocumentInfo.Path)' uses unsupported schemaVersion '$($definition.schemaVersion)'. Supported schemaVersion is '1.0'."
    }

    if (-not [string]::Equals([string]$definition.id, [string]$DefinitionId, [System.StringComparison]::Ordinal)) {
        throw "Package definition id '$($definition.id)' does not match requested definition id '$DefinitionId'."
    }

    if ($definition.PSObject.Properties['dependencies']) {
        foreach ($dependency in @($definition.dependencies)) {
            if (-not $dependency.PSObject.Properties['definitionId'] -or [string]::IsNullOrWhiteSpace([string]$dependency.definitionId)) {
                throw "Package definition '$($definition.id)' has dependency without definitionId."
            }
            if ([string]::Equals([string]$dependency.definitionId, [string]$definition.id, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Package definition '$($definition.id)' cannot depend on itself."
            }
        }
    }

    foreach ($upstreamSourceProperty in @($definition.upstreamSources.PSObject.Properties)) {
        $upstreamSource = $upstreamSourceProperty.Value
        if (-not $upstreamSource.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$upstreamSource.kind)) {
            throw "Package definition '$($definition.id)' has upstream source '$($upstreamSourceProperty.Name)' without kind."
        }

        switch -Exact ([string]$upstreamSource.kind) {
            'download' {
                if (-not $upstreamSource.PSObject.Properties['baseUri'] -or [string]::IsNullOrWhiteSpace([string]$upstreamSource.baseUri)) {
                    throw "Package definition '$($definition.id)' has download upstream source '$($upstreamSourceProperty.Name)' without baseUri."
                }
            }
            'githubRelease' {
                if (-not $upstreamSource.PSObject.Properties['repositoryOwner'] -or [string]::IsNullOrWhiteSpace([string]$upstreamSource.repositoryOwner)) {
                    throw "Package definition '$($definition.id)' has GitHub release upstream source '$($upstreamSourceProperty.Name)' without repositoryOwner."
                }
                if (-not $upstreamSource.PSObject.Properties['repositoryName'] -or [string]::IsNullOrWhiteSpace([string]$upstreamSource.repositoryName)) {
                    throw "Package definition '$($definition.id)' has GitHub release upstream source '$($upstreamSourceProperty.Name)' without repositoryName."
                }
            }
            default {
                throw "Package definition '$($definition.id)' uses unsupported upstream source kind '$($upstreamSource.kind)' for '$($upstreamSourceProperty.Name)'."
            }
        }
    }

    if ($definition.releaseDefaults.PSObject.Properties['requirements']) {
        throw "Package definition '$($definition.id)' still uses retired property 'releaseDefaults.requirements'. Use 'releaseDefaults.compatibility.checks'."
    }

    foreach ($requiredDefaultProperty in @('compatibility', 'install', 'validation', 'existingInstallDiscovery', 'existingInstallPolicy')) {
        if (-not $definition.releaseDefaults.PSObject.Properties[$requiredDefaultProperty]) {
            throw "Package definition '$($definition.id)' is missing releaseDefaults.$requiredDefaultProperty."
        }
    }
    foreach ($retiredDefaultProperty in @('existingInstall')) {
        if ($definition.releaseDefaults.PSObject.Properties[$retiredDefaultProperty]) {
            throw "Package definition '$($definition.id)' still uses retired property 'releaseDefaults.$retiredDefaultProperty'."
        }
    }

    foreach ($release in @($definition.releases)) {
        foreach ($retiredProperty in @('artifact', 'acquisitions', 'sourceOptions', 'reuse', 'channel')) {
            if ($release.PSObject.Properties[$retiredProperty]) {
                throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property '$retiredProperty'."
            }
        }
        if ($release.PSObject.Properties['requirements']) {
            throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'requirements'. Use 'compatibility.checks'."
        }
        foreach ($retiredReleaseProperty in @('existingInstall')) {
            if ($release.PSObject.Properties[$retiredReleaseProperty]) {
                throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property '$retiredReleaseProperty'."
            }
        }

        foreach ($requiredProperty in @('id', 'version', 'releaseTrack', 'flavor', 'constraints')) {
            if (-not $release.PSObject.Properties[$requiredProperty]) {
                throw "Package release '$($release.id)' in '$($definition.id)' is missing required property '$requiredProperty'."
            }
        }

        $effectiveRelease = Resolve-PackageEffectiveRelease -Definition $definition -Release $release
        foreach ($requiredEffectiveProperty in @('install', 'validation', 'compatibility', 'existingInstallDiscovery', 'existingInstallPolicy')) {
            if (-not $effectiveRelease.PSObject.Properties[$requiredEffectiveProperty]) {
                throw "Package release '$($release.id)' in '$($definition.id)' is missing required effective property '$requiredEffectiveProperty'."
            }
        }
        if ($effectiveRelease.compatibility.PSObject.Properties['packages']) {
            throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'compatibility.packages'. Use 'compatibility.checks'."
        }
        if (-not $effectiveRelease.compatibility.PSObject.Properties['checks']) {
            throw "Package release '$($release.id)' in '$($definition.id)' is missing compatibility.checks."
        }
        foreach ($compatibilityCheck in @($effectiveRelease.compatibility.checks)) {
            if ($null -eq $compatibilityCheck) {
                continue
            }
            if (-not $compatibilityCheck.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.kind)) {
                throw "Package release '$($release.id)' in '$($definition.id)' has a compatibility check without kind."
            }
            $onFail = 'fail'
            if ($compatibilityCheck.PSObject.Properties['onFail'] -and -not [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.onFail)) {
                $onFail = ([string]$compatibilityCheck.onFail).ToLowerInvariant()
            }
            if ($onFail -notin @('fail', 'warn')) {
                throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported compatibility onFail '$($compatibilityCheck.onFail)'."
            }

            switch -Exact ([string]$compatibilityCheck.kind) {
                'osFamily' {
                    $hasAllowed = $compatibilityCheck.PSObject.Properties['allowed'] -and @($compatibilityCheck.allowed).Count -gt 0
                    $hasBlocked = $compatibilityCheck.PSObject.Properties['blocked'] -and @($compatibilityCheck.blocked).Count -gt 0
                    if (-not $hasAllowed -and -not $hasBlocked) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has an osFamily compatibility check without allowed or blocked values."
                    }
                }
                'cpuArchitecture' {
                    $hasAllowed = $compatibilityCheck.PSObject.Properties['allowed'] -and @($compatibilityCheck.allowed).Count -gt 0
                    $hasBlocked = $compatibilityCheck.PSObject.Properties['blocked'] -and @($compatibilityCheck.blocked).Count -gt 0
                    if (-not $hasAllowed -and -not $hasBlocked) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a cpuArchitecture compatibility check without allowed or blocked values."
                    }
                }
                'osVersion' {
                    if (-not $compatibilityCheck.PSObject.Properties['operator'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.operator)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has an osVersion compatibility check without operator."
                    }
                    if (-not $compatibilityCheck.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.value)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has an osVersion compatibility check without value."
                    }
                }
                'physicalMemoryGiB' {
                    if (-not $compatibilityCheck.PSObject.Properties['operator'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.operator)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a physicalMemoryGiB compatibility check without operator."
                    }
                    if (-not $compatibilityCheck.PSObject.Properties['value']) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a physicalMemoryGiB compatibility check without value."
                    }
                    $parsedValue = 0.0
                    if (-not [double]::TryParse(([string]$compatibilityCheck.value), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a physicalMemoryGiB compatibility check with non-numeric value '$($compatibilityCheck.value)'."
                    }
                }
                'videoMemoryGiB' {
                    if (-not $compatibilityCheck.PSObject.Properties['operator'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.operator)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a videoMemoryGiB compatibility check without operator."
                    }
                    if (-not $compatibilityCheck.PSObject.Properties['value']) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a videoMemoryGiB compatibility check without value."
                    }
                    $parsedValue = 0.0
                    if (-not [double]::TryParse(([string]$compatibilityCheck.value), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a videoMemoryGiB compatibility check with non-numeric value '$($compatibilityCheck.value)'."
                    }
                }
                'physicalOrVideoMemoryGiB' {
                    if (-not $compatibilityCheck.PSObject.Properties['operator'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.operator)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a physicalOrVideoMemoryGiB compatibility check without operator."
                    }
                    if (-not $compatibilityCheck.PSObject.Properties['value']) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a physicalOrVideoMemoryGiB compatibility check without value."
                    }
                    $parsedValue = 0.0
                    if (-not [double]::TryParse(([string]$compatibilityCheck.value), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a physicalOrVideoMemoryGiB compatibility check with non-numeric value '$($compatibilityCheck.value)'."
                    }
                }
                default {
                    throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported compatibility kind '$($compatibilityCheck.kind)'."
                }
            }
        }
        if ($effectiveRelease.existingInstallPolicy -and $effectiveRelease.existingInstallPolicy.PSObject.Properties['requireManagedOwnership']) {
            throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'requireManagedOwnership'. Use 'requirePackageOwnership'."
        }

        $installKind = if ($effectiveRelease.install -and $effectiveRelease.install.PSObject.Properties['kind']) {
            [string]$effectiveRelease.install.kind
        }
        else {
            $null
        }

        if ([string]::IsNullOrWhiteSpace($installKind)) {
            throw "Package release '$($release.id)' in '$($definition.id)' is missing install.kind."
        }

        if ($installKind -notin @('expandArchive', 'placePackageFile', 'runInstaller', 'npmGlobalPackage', 'reuseExisting')) {
            throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.kind '$installKind'."
        }

        foreach ($retiredInstallProperty in @('managerKind', 'managerDependency')) {
            if ($effectiveRelease.install.PSObject.Properties[$retiredInstallProperty]) {
                throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'install.$retiredInstallProperty'. Use install.kind 'npmGlobalPackage' with install.installerCommand."
            }
        }

        if ($effectiveRelease.install.PSObject.Properties['targetKind'] -and
            -not [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.targetKind) -and
            ([string]$effectiveRelease.install.targetKind) -notin @('directory', 'machinePrerequisite')) {
            throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.targetKind '$($effectiveRelease.install.targetKind)'."
        }

        if ($effectiveRelease.install.PSObject.Properties['elevation'] -and
            -not [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.elevation) -and
            ([string]$effectiveRelease.install.elevation) -notin @('none', 'required', 'auto')) {
            throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.elevation '$($effectiveRelease.install.elevation)'."
        }

        if ([string]::Equals($installKind, 'npmGlobalPackage', [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not $effectiveRelease.install.PSObject.Properties['packageSpec'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.packageSpec)) {
                throw "Package release '$($release.id)' in '$($definition.id)' uses install.kind 'npmGlobalPackage' without install.packageSpec."
            }
            if (-not $effectiveRelease.install.PSObject.Properties['installerCommand'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.installerCommand)) {
                throw "Package release '$($release.id)' in '$($definition.id)' uses install.kind 'npmGlobalPackage' without install.installerCommand."
            }
        }

        if ($effectiveRelease.install -and $effectiveRelease.install.PSObject.Properties['pathRegistration'] -and $null -ne $effectiveRelease.install.pathRegistration) {
            $pathRegistration = $effectiveRelease.install.pathRegistration
            if (-not $pathRegistration.PSObject.Properties['mode'] -or [string]::IsNullOrWhiteSpace([string]$pathRegistration.mode)) {
                throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration without mode."
            }

            $pathRegistrationMode = ([string]$pathRegistration.mode).ToLowerInvariant()
            if ($pathRegistrationMode -notin @('none', 'user', 'machine')) {
                throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.pathRegistration.mode '$($pathRegistration.mode)'."
            }

            if ($pathRegistrationMode -ne 'none') {
                if (-not $pathRegistration.PSObject.Properties['source'] -or $null -eq $pathRegistration.source) {
                    throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration.mode '$($pathRegistration.mode)' without source."
                }
                if (-not $pathRegistration.source.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$pathRegistration.source.kind)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration without source.kind."
                }
                if (-not $pathRegistration.source.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$pathRegistration.source.value)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration without source.value."
                }

                switch -Exact ([string]$pathRegistration.source.kind) {
                    'commandEntryPoint' { }
                    'appEntryPoint' { }
                    'installRelativeDirectory' { }
                    'shim' { }
                    default {
                        throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.pathRegistration.source.kind '$($pathRegistration.source.kind)'."
                    }
                }
            }
        }

        $requiresPackageFile = $false
        $requiresAcquisitionCandidates = $false
        switch -Exact ($installKind) {
            'expandArchive' {
                $requiresPackageFile = $true
                $requiresAcquisitionCandidates = $true
            }
            'placePackageFile' {
                $requiresPackageFile = $true
                $requiresAcquisitionCandidates = $true
                if ($effectiveRelease.install.PSObject.Properties['targetRelativePath'] -and
                    [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.targetRelativePath)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' defines install.targetRelativePath without a value."
                }
            }
            'runInstaller' {
                if (-not $effectiveRelease.install.PSObject.Properties['commandPath'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.commandPath)) {
                    $requiresPackageFile = $true
                    $requiresAcquisitionCandidates = $true
                }
            }
        }

        if ($requiresPackageFile) {
            if (-not $effectiveRelease.PSObject.Properties['packageFile'] -or $null -eq $effectiveRelease.packageFile) {
                throw "Package release '$($release.id)' in '$($definition.id)' is missing required property 'packageFile'."
            }
            if (-not $effectiveRelease.packageFile.PSObject.Properties['fileName'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.packageFile.fileName)) {
                throw "Package release '$($release.id)' in '$($definition.id)' is missing packageFile.fileName."
            }
        }

        if ($effectiveRelease.PSObject.Properties['packageFile'] -and $effectiveRelease.packageFile -and
            (-not $effectiveRelease.packageFile.PSObject.Properties['fileName'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.packageFile.fileName))) {
            throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile without packageFile.fileName."
        }
        if ($effectiveRelease.PSObject.Properties['packageFile'] -and
            $effectiveRelease.packageFile -and
            $effectiveRelease.packageFile.PSObject.Properties['integrity'] -and
            $null -ne $effectiveRelease.packageFile.integrity) {
            $integrity = $effectiveRelease.packageFile.integrity
            if (-not $integrity.PSObject.Properties['algorithm'] -or [string]::IsNullOrWhiteSpace([string]$integrity.algorithm)) {
                throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile.integrity without algorithm."
            }
            if (-not $integrity.PSObject.Properties['sha256'] -or [string]::IsNullOrWhiteSpace([string]$integrity.sha256)) {
                throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile.integrity without sha256."
            }
            if (-not [string]::Equals([string]$integrity.algorithm, 'sha256', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported packageFile.integrity.algorithm '$($integrity.algorithm)'."
            }
        }

        if ($effectiveRelease.PSObject.Properties['packageFile'] -and
            $effectiveRelease.packageFile -and
            $effectiveRelease.packageFile.PSObject.Properties['authenticode'] -and
            $null -ne $effectiveRelease.packageFile.authenticode) {
            $authenticode = $effectiveRelease.packageFile.authenticode
            if ($authenticode.PSObject.Properties['requireValid'] -and
                $null -eq $authenticode.requireValid) {
                throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile.authenticode.requireValid without a value."
            }
            if ($authenticode.PSObject.Properties['subjectContains'] -and
                [string]::IsNullOrWhiteSpace([string]$authenticode.subjectContains)) {
                throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile.authenticode.subjectContains without a value."
            }
        }

        if ($requiresAcquisitionCandidates) {
            if (-not $effectiveRelease.PSObject.Properties['acquisitionCandidates'] -or @($effectiveRelease.acquisitionCandidates).Count -eq 0) {
                throw "Package release '$($release.id)' in '$($definition.id)' is missing required property 'acquisitionCandidates'."
            }
        }

        if ($effectiveRelease.PSObject.Properties['acquisitionCandidates']) {
            foreach ($candidate in @($effectiveRelease.acquisitionCandidates)) {
                if ($null -eq $candidate) {
                    continue
                }
                if ($candidate.PSObject.Properties['sourceBindingId']) {
                    throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'sourceBindingId'."
                }
                if ($candidate.PSObject.Properties['sourceRef']) {
                    throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'sourceRef'."
                }
                if ($candidate.PSObject.Properties['priority']) {
                    throw "Package release '$($release.id)' in '$($definition.id)' acquisition candidate still uses retired property 'priority'. Use 'searchOrder'."
                }
                if (-not $candidate.PSObject.Properties['searchOrder']) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has an acquisition candidate without searchOrder."
                }
                if (-not $candidate.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$candidate.kind)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has an acquisition candidate without kind."
                }
                switch -Exact ([string]$candidate.kind) {
                    'packageDepot' { }
                    'download' {
                        if (-not $candidate.PSObject.Properties['sourceId'] -or [string]::IsNullOrWhiteSpace([string]$candidate.sourceId)) {
                            throw "Package release '$($release.id)' in '$($definition.id)' has a download acquisition candidate without sourceId."
                        }

                        $downloadSource = $null
                        foreach ($upstreamSourceProperty in @($definition.upstreamSources.PSObject.Properties)) {
                            if ([string]::Equals([string]$upstreamSourceProperty.Name, [string]$candidate.sourceId, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $downloadSource = $upstreamSourceProperty.Value
                                break
                            }
                        }
                        if (-not $downloadSource) {
                            throw "Package release '$($release.id)' in '$($definition.id)' references unknown download sourceId '$($candidate.sourceId)'."
                        }

                        $downloadSourceKind = if ($downloadSource.PSObject.Properties['kind']) { [string]$downloadSource.kind } else { $null }
                        switch -Exact ($downloadSourceKind) {
                            'download' {
                                if (-not $candidate.PSObject.Properties['sourcePath'] -or [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                                    throw "Package release '$($release.id)' in '$($definition.id)' has a download acquisition candidate without sourcePath."
                                }
                            }
                            'githubRelease' {
                                if ($candidate.PSObject.Properties['sourcePath'] -and -not [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                                    throw "Package release '$($release.id)' in '$($definition.id)' must not define sourcePath for GitHub release source '$($candidate.sourceId)'."
                                }
                                if (-not $effectiveRelease.PSObject.Properties['releaseTag'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.releaseTag)) {
                                    throw "Package release '$($release.id)' in '$($definition.id)' requires releaseTag when download source '$($candidate.sourceId)' is a GitHub release source."
                                }
                                if (-not $effectiveRelease.PSObject.Properties['packageFile'] -or
                                    $null -eq $effectiveRelease.packageFile -or
                                    -not $effectiveRelease.packageFile.PSObject.Properties['fileName'] -or
                                    [string]::IsNullOrWhiteSpace([string]$effectiveRelease.packageFile.fileName)) {
                                    throw "Package release '$($release.id)' in '$($definition.id)' requires packageFile.fileName when download source '$($candidate.sourceId)' is a GitHub release source."
                                }
                            }
                            default {
                                throw "Package release '$($release.id)' in '$($definition.id)' references unsupported download source kind '$downloadSourceKind' for sourceId '$($candidate.sourceId)'."
                            }
                        }
                    }
                    'filesystem' {
                        if (-not $candidate.PSObject.Properties['sourcePath'] -or [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                            throw "Package release '$($release.id)' in '$($definition.id)' has a filesystem acquisition candidate without sourcePath."
                        }
                    }
                    default {
                        throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported acquisition kind '$($candidate.kind)'."
                    }
                }
            }
        }

        $existingInstallDiscovery = $effectiveRelease.existingInstallDiscovery
        if ($existingInstallDiscovery.PSObject.Properties['enableDetection'] -and [bool]$existingInstallDiscovery.enableDetection) {
            if (-not $existingInstallDiscovery.PSObject.Properties['searchLocations']) {
                throw "Package release '$($release.id)' in '$($definition.id)' is missing existingInstallDiscovery.searchLocations."
            }
            if (-not $existingInstallDiscovery.PSObject.Properties['installRootRules']) {
                throw "Package release '$($release.id)' in '$($definition.id)' is missing existingInstallDiscovery.installRootRules."
            }
            foreach ($rule in @($existingInstallDiscovery.installRootRules)) {
                if ($null -eq $rule) {
                    continue
                }
                if ($rule.PSObject.Properties['fileName'] -or $rule.PSObject.Properties['homePath']) {
                    throw "Package release '$($release.id)' in '$($definition.id)' still uses retired installRootRules fields from installHomeRules."
                }
                if (-not $rule.PSObject.Properties['match'] -or $null -eq $rule.match) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has an installRootRule without match."
                }
                if (-not $rule.match.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$rule.match.kind)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has an installRootRule without match.kind."
                }
                if (-not $rule.match.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$rule.match.value)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has an installRootRule without match.value."
                }
                if (-not $rule.PSObject.Properties['installRootRelativePath']) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has an installRootRule without installRootRelativePath."
                }
            }
        }
    }
}

function Resolve-PackageEffectiveRelease {
<#
.SYNOPSIS
Builds the effective Package release by applying definition defaults.

.DESCRIPTION
Applies whole-block fallback from the definition releaseDefaults block to a
single release entry. When a release defines one of the known release blocks,
that block fully replaces the default block.

.PARAMETER Definition
The Package definition object.

.PARAMETER Release
The raw release object from the definition.

.EXAMPLE
Resolve-PackageEffectiveRelease -Definition $definition -Release $release
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [psobject]$Release
    )

    $effectiveRelease = ConvertTo-PackageObject -InputObject $Release
    foreach ($propertyName in @('compatibility', 'install', 'validation', 'existingInstallDiscovery', 'existingInstallPolicy')) {
        if (-not $effectiveRelease.PSObject.Properties[$propertyName] -and $Definition.releaseDefaults.PSObject.Properties[$propertyName]) {
            $effectiveRelease | Add-Member -MemberType NoteProperty -Name $propertyName -Value (ConvertTo-PackageObject -InputObject $Definition.releaseDefaults.$propertyName)
        }
    }

    return $effectiveRelease
}

function Get-PackageConfig {
<#
.SYNOPSIS
Loads the effective Package config for a definition id.

.DESCRIPTION
Loads the shipped Package global document, applies the optional external
source inventory, loads one shipped Package definition, validates the
current schema, resolves runtime context and Package roots, and returns the
combined config object for command orchestration.

.PARAMETER DefinitionId
The Package definition id. The shipped JSON filename stem must match this
value.

.EXAMPLE
Get-PackageConfig -DefinitionId VSCodeRuntime
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId
    )

    $globalDocumentInfo = Read-PackageJsonDocument -Path (Get-PackageGlobalConfigPath)
    Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalDocumentInfo

    $depotInventoryInfo = Get-PackageDepotInventoryInfo
    $sourceInventoryInfo = Get-PackageSourceInventoryInfo

    $definitionDocumentInfo = Read-PackageJsonDocument -Path (Get-PackageDefinitionPath -DefinitionId $DefinitionId)
    Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionDocumentInfo -DefinitionId $DefinitionId

    $packageGlobalConfig = $globalDocumentInfo.Document.package
    $runtimeContext = Get-PackageRuntimeContext
    $definition = $definitionDocumentInfo.Document
    $effectiveAcquisitionEnvironment = Resolve-PackageEffectiveAcquisitionEnvironment -GlobalConfiguration $packageGlobalConfig -SourceInventoryInfo $sourceInventoryInfo -DepotInventoryInfo $depotInventoryInfo

    $selectionReleaseTrack = 'none'
    if ($packageGlobalConfig.selectionDefaults.PSObject.Properties['releaseTrack'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.selectionDefaults.releaseTrack)) {
        $selectionReleaseTrack = [string]$packageGlobalConfig.selectionDefaults.releaseTrack
    }

    $selectionStrategy = 'latestByVersion'
    if ($packageGlobalConfig.selectionDefaults.PSObject.Properties['strategy'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.selectionDefaults.strategy)) {
        $selectionStrategy = [string]$packageGlobalConfig.selectionDefaults.strategy
    }

    $preferredTargetInstallDirectory = if ($packageGlobalConfig.PSObject.Properties['preferredTargetInstallDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.preferredTargetInstallDirectory)) {
        Resolve-PackagePathValue -PathValue ([string]$packageGlobalConfig.preferredTargetInstallDirectory)
    }
    else {
        Get-PackageDefaultPreferredTargetInstallDirectory
    }

    $packageStateIndexFilePath = if ($packageGlobalConfig.packageState.PSObject.Properties['indexFilePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.packageState.indexFilePath)) {
        Resolve-PackagePathValue -PathValue ([string]$packageGlobalConfig.packageState.indexFilePath)
    }
    else {
        Get-PackageDefaultPackageStateIndexFilePath
    }

    $localRepositoryRoot = if ($packageGlobalConfig.PSObject.Properties['localRepositoryRoot'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.localRepositoryRoot)) {
        Resolve-PackagePathValue -PathValue ([string]$packageGlobalConfig.localRepositoryRoot)
    }
    else {
        Get-PackageDefaultLocalRepositoryRoot
    }

    $definitionRepositoryId = Get-PackageDefaultRepositoryId
    $definitionFileName = Split-Path -Leaf $definitionDocumentInfo.Path

    $display = if ($definition.display -and $definition.display.PSObject.Properties['default'] -and $null -ne $definition.display.default) {
        $definition.display.default
    }
    else {
        [pscustomobject]@{}
    }

    return [pscustomobject]@{
        GlobalConfigurationPath            = $globalDocumentInfo.Path
        GlobalConfiguration                = $packageGlobalConfig
        SourceInventoryPath                = $effectiveAcquisitionEnvironment.SourceInventoryPath
        SourceInventory                    = $sourceInventoryInfo.Document
        DepotInventoryPath                 = $effectiveAcquisitionEnvironment.DepotInventoryPath
        DepotInventory                     = $depotInventoryInfo.Document
        EffectiveAcquisitionEnvironment    = $effectiveAcquisitionEnvironment
        DefinitionPath                     = $definitionDocumentInfo.Path
        Definition                         = $definition
        DefinitionId                       = [string]$definition.id
        DefinitionRepositoryId             = $definitionRepositoryId
        DefinitionFileName                 = $definitionFileName
        DefinitionUpstreamSources          = $definition.upstreamSources
        Display                            = $display
        SchemaVersion                      = [string]$definition.schemaVersion
        Platform                           = $runtimeContext.Platform
        Architecture                       = $runtimeContext.Architecture
        OSVersion                          = $runtimeContext.OSVersion
        ReleaseTrack                       = $selectionReleaseTrack
        SelectionStrategy                  = $selectionStrategy
        PackageFileStagingRootDirectory      = $effectiveAcquisitionEnvironment.Stores.PackageFileStagingDirectory
        PackageInstallStageRootDirectory     = $effectiveAcquisitionEnvironment.Stores.PackageInstallStageDirectory
        DefaultPackageDepotDirectory       = $effectiveAcquisitionEnvironment.Stores.DefaultPackageDepotDirectory
        PreferredTargetInstallRootDirectory = $preferredTargetInstallDirectory
        LocalRepositoryRoot                = $localRepositoryRoot
        PackageFileIndexFilePath           = $effectiveAcquisitionEnvironment.Tracking.PackageFileIndexFilePath
        PackageStateIndexFilePath          = $packageStateIndexFilePath
        AllowAcquisitionFallback           = $effectiveAcquisitionEnvironment.Defaults.AllowFallback
        MirrorDownloadedArtifactsToDefaultPackageDepot = $effectiveAcquisitionEnvironment.Defaults.MirrorDownloadedArtifactsToDefaultPackageDepot
        EnvironmentSources                 = $effectiveAcquisitionEnvironment.EnvironmentSources
    }
}

function Resolve-PackagePaths {
<#
.SYNOPSIS
Resolves the concrete package-file workspace/depot and install paths for a selected release.

.DESCRIPTION
Builds the shared relative package-file directory for depot and workspace
storage from the selected release identity, resolves the effective install
directory template, and attaches the resolved directories to the Package
result object.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Resolve-PackagePaths -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $packageConfig = $PackageResult.PackageConfig
    $definition = $packageConfig.Definition
    $package = $PackageResult.Package
    if (-not $package) {
        throw 'Resolve-PackagePaths requires a selected release.'
    }
    $installKind = if ($package.PSObject.Properties['install'] -and $package.install -and $package.install.PSObject.Properties['kind']) {
        [string]$package.install.kind
    }
    else {
        $null
    }
    $installTargetKind = if ($package.PSObject.Properties['install'] -and $package.install -and $package.install.PSObject.Properties['targetKind'] -and
        -not [string]::IsNullOrWhiteSpace([string]$package.install.targetKind)) {
        [string]$package.install.targetKind
    }
    else {
        'directory'
    }

    $packageFileRelativeDirectory = Get-PackagePackageFileRelativeDirectory -PackageConfig $packageConfig -Package $package
    $installDirectoryTemplate = $null
    if ($package.PSObject.Properties['install'] -and $package.install -and
        $package.install.PSObject.Properties['installDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$package.install.installDirectory)) {
        $installDirectoryTemplate = Resolve-PackageTemplateText -Text ([string]$package.install.installDirectory) -PackageConfig $packageConfig -Package $package
    }
    elseif (-not [string]::Equals($installKind, 'reuseExisting', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($installTargetKind, 'machinePrerequisite', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package definition '$($definition.id)' does not define an install target path. Use install.installDirectory."
    }

    $normalizedPackageFileRelativeDirectory = $packageFileRelativeDirectory.Trim() -replace '/', '\'
    if ([System.IO.Path]::IsPathRooted($normalizedPackageFileRelativeDirectory)) {
        throw "Package definition '$($definition.id)' must use a relative package-file directory."
    }

    $packageFileStagingDirectory = [System.IO.Path]::GetFullPath((Join-Path $packageConfig.PackageFileStagingRootDirectory $normalizedPackageFileRelativeDirectory))
    $packageInstallStageDirectory = [System.IO.Path]::GetFullPath((Join-Path $packageConfig.PackageInstallStageRootDirectory $normalizedPackageFileRelativeDirectory))

    $installDirectory = $null
    if (-not [string]::IsNullOrWhiteSpace($installDirectoryTemplate)) {
        $expandedInstallDirectoryTemplate = [Environment]::ExpandEnvironmentVariables(([string]$installDirectoryTemplate).Trim()) -replace '/', '\'
        $installDirectory = if ([System.IO.Path]::IsPathRooted($expandedInstallDirectoryTemplate)) {
            [System.IO.Path]::GetFullPath($expandedInstallDirectoryTemplate)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $packageConfig.PreferredTargetInstallRootDirectory $expandedInstallDirectoryTemplate))
        }
    }

    $packageFilePath = $null
    $defaultPackageDepotFilePath = $null
    if ($package.PSObject.Properties['packageFile'] -and
        $package.packageFile -and
        $package.packageFile.PSObject.Properties['fileName'] -and
        -not [string]::IsNullOrWhiteSpace([string]$package.packageFile.fileName)) {
        $packageFilePath = Join-Path $packageFileStagingDirectory ([string]$package.packageFile.fileName)
        if (-not [string]::IsNullOrWhiteSpace([string]$packageConfig.DefaultPackageDepotDirectory)) {
            $defaultPackageDepotDirectory = [System.IO.Path]::GetFullPath((Join-Path $packageConfig.DefaultPackageDepotDirectory $normalizedPackageFileRelativeDirectory))
            $defaultPackageDepotFilePath = Join-Path $defaultPackageDepotDirectory ([string]$package.packageFile.fileName)
        }
    }

    $PackageResult.PackageFileStagingDirectory = $packageFileStagingDirectory
    $PackageResult.PackageInstallStageDirectory = $packageInstallStageDirectory
    $PackageResult.InstallDirectory = $installDirectory
    $PackageResult.PackageFileRelativeDirectory = $normalizedPackageFileRelativeDirectory
    $PackageResult.PackageFilePath = $packageFilePath
    $PackageResult.DefaultPackageDepotFilePath = $defaultPackageDepotFilePath

    $resolvedInstallDirectoryText = if ([string]::IsNullOrWhiteSpace([string]$installDirectory)) { '<none>' } else { $installDirectory }
    $resolvedPackageFilePathText = if ([string]::IsNullOrWhiteSpace([string]$packageFilePath)) { '<none>' } else { $packageFilePath }
    $resolvedDefaultDepotFilePathText = if ([string]::IsNullOrWhiteSpace([string]$defaultPackageDepotFilePath)) { '<none>' } else { $defaultPackageDepotFilePath }
    Write-PackageExecutionMessage -Message '[STATE] Resolved paths:'
    Write-PackageExecutionMessage -Message ("[PATH] Package file staging: {0}" -f $packageFileStagingDirectory)
    Write-PackageExecutionMessage -Message ("[PATH] Package install stage: {0}" -f $packageInstallStageDirectory)
    Write-PackageExecutionMessage -Message ("[PATH] Target install directory: {0}" -f $resolvedInstallDirectoryText)
    Write-PackageExecutionMessage -Message ("[PATH] Package file: {0}" -f $resolvedPackageFilePathText)
    Write-PackageExecutionMessage -Message ("[PATH] Default package depot file: {0}" -f $resolvedDefaultDepotFilePathText)

    return $PackageResult
}

function New-PackageResult {
<#
.SYNOPSIS
Creates the initial Package result object.

.DESCRIPTION
Creates the result object that later Package stage helpers enrich with
release selection, package file, install, ownership, validation, and entry-point data.

.PARAMETER CommandName
The command that owns the result.

.PARAMETER PackageConfig
The resolved Package config object for the command.

.EXAMPLE
New-PackageResult -CommandName Invoke-VSCodeRuntime -PackageConfig $config
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [psobject]$PackageConfig
    )

    return [pscustomobject]@{
        CommandName                      = $CommandName
        Status                           = 'Pending'
        FailureReason                    = $null
        ErrorMessage                     = $null
        CurrentStep                      = 'Pending'
        DefinitionId                     = $PackageConfig.DefinitionId
        DefinitionRepositoryId           = $PackageConfig.DefinitionRepositoryId
        DefinitionFileName               = $PackageConfig.DefinitionFileName
        Display                          = $PackageConfig.Display
        Platform                         = $PackageConfig.Platform
        Architecture                     = $PackageConfig.Architecture
        OSVersion                        = $PackageConfig.OSVersion
        ReleaseTrack                     = $PackageConfig.ReleaseTrack
        SourceInventoryPath              = $PackageConfig.SourceInventoryPath
        DepotInventoryPath               = $PackageConfig.DepotInventoryPath
        PackageFileStagingRootDirectory    = $PackageConfig.PackageFileStagingRootDirectory
        PackageInstallStageRootDirectory   = $PackageConfig.PackageInstallStageRootDirectory
        DefaultPackageDepotDirectory     = $PackageConfig.DefaultPackageDepotDirectory
        PreferredTargetInstallRootDirectory = $PackageConfig.PreferredTargetInstallRootDirectory
        LocalRepositoryRoot              = $PackageConfig.LocalRepositoryRoot
        PackageFileIndexFilePath         = $PackageConfig.PackageFileIndexFilePath
        PackageStateIndexFilePath        = $PackageConfig.PackageStateIndexFilePath
        Package                          = $null
        EffectiveRelease                 = $null
        PackageId                        = $null
        PackageVersion                   = $null
        Compatibility                    = @()
        PackageFileStagingDirectory        = $null
        PackageInstallStageDirectory       = $null
        InstallDirectory                 = $null
        PackageFileRelativeDirectory     = $null
        PackageFilePath                  = $null
        DefaultPackageDepotFilePath      = $null
        AcquisitionPlan                  = $null
        ExistingPackage                  = $null
        Ownership                        = $null
        InstallOrigin                    = $null
        PackageFilePreparation                  = $null
        Dependencies                     = @()
        Install                          = $null
        Validation                       = $null
        EntryPoints                      = $null
        PathRegistration                 = $null
        PackageConfig               = $PackageConfig
    }
}


