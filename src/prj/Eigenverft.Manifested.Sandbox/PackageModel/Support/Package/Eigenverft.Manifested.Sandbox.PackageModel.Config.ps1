<#
    Eigenverft.Manifested.Sandbox.PackageModel.Config
#>

function Read-PackageModelJsonDocument {
<#
.SYNOPSIS
Reads a PackageModel JSON document from disk.

.DESCRIPTION
Resolves a JSON file path, validates that it contains content, parses it, and
returns the resolved path together with the parsed document object.

.PARAMETER Path
Path to the JSON file that should be loaded.

.EXAMPLE
Read-PackageModelJsonDocument -Path .\PackageModel.Global.json
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $rawContent = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($rawContent)) {
        throw "PackageModel JSON file '$resolvedPath' is empty."
    }

    try {
        $document = $rawContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "PackageModel JSON file '$resolvedPath' could not be parsed. $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        Path     = $resolvedPath
        Document = $document
    }
}

function Resolve-PackageModelPathValue {
<#
.SYNOPSIS
Expands and normalizes a filesystem path value.

.DESCRIPTION
Expands environment variables, normalizes path separators, and returns a full
filesystem path for relative, local, or UNC paths.

.PARAMETER PathValue
The raw path value that should be normalized.

.EXAMPLE
Resolve-PackageModelPathValue -PathValue '%USERPROFILE%/Downloads/Test'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    $expandedPath = [Environment]::ExpandEnvironmentVariables($PathValue).Trim()
    if ([string]::IsNullOrWhiteSpace($expandedPath)) {
        throw 'PackageModel path values must not be empty.'
    }

    $normalizedPath = $expandedPath -replace '/', '\'
    if ([System.IO.Path]::IsPathRooted($normalizedPath)) {
        return [System.IO.Path]::GetFullPath($normalizedPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $normalizedPath))
}

function Get-PackageModelRuntimeContext {
<#
.SYNOPSIS
Resolves the current PackageModel runtime context.

.DESCRIPTION
Detects the effective platform and architecture used for package matching.

.EXAMPLE
Get-PackageModelRuntimeContext
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
    }
}

function Get-PackageModelDefaultInstallWorkspaceDirectory {
<#
.SYNOPSIS
Returns the default PackageModel install-workspace root.

.DESCRIPTION
Builds the fallback local workspace root for PackageModel working artifacts
when the shipped or external config does not define one explicitly.

.EXAMPLE
Get-PackageModelDefaultInstallWorkspaceDirectory
#>
    [CmdletBinding()]
    param()

    $localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        $localApplicationData = $env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        throw 'Could not resolve the LocalApplicationData directory for the PackageModel install workspace.'
    }

    return [System.IO.Path]::GetFullPath((Join-Path $localApplicationData 'Eigenverft.Manifested.Sandbox\PackageModel\InstallWorkspace'))
}

function Get-PackageModelDefaultPreferredTargetInstallDirectory {
<#
.SYNOPSIS
Returns the default PackageModel preferred target-install root.

.DESCRIPTION
Builds the fallback local application-data root for PackageModel preferred
target installs when the global document does not define one explicitly.

.EXAMPLE
Get-PackageModelDefaultPreferredTargetInstallDirectory
#>
    [CmdletBinding()]
    param()

    $localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        $localApplicationData = $env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        throw 'Could not resolve the LocalApplicationData directory for the PackageModel preferred target-install root.'
    }

    return [System.IO.Path]::GetFullPath((Join-Path $localApplicationData 'Eigenverft.Manifested.Sandbox\PackageModel\Installs'))
}

function Get-PackageModelDefaultPackageDepotDirectory {
<#
.SYNOPSIS
Returns the default PackageModel default package-depot root.

.DESCRIPTION
Builds the fallback persistent default depot directory that can mirror
verified downloaded artifacts for later reuse.

.EXAMPLE
Get-PackageModelDefaultPackageDepotDirectory
#>
    [CmdletBinding()]
    param()

    $localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        $localApplicationData = $env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        throw 'Could not resolve the LocalApplicationData directory for the PackageModel default package depot.'
    }

    return [System.IO.Path]::GetFullPath((Join-Path $localApplicationData 'Eigenverft.Manifested.Sandbox\PackageModel\DefaultPackageDepot'))
}

function Get-PackageModelDefaultArtifactIndexFilePath {
<#
.SYNOPSIS
Returns the default PackageModel artifact-index path.

.DESCRIPTION
Builds the fallback local artifact index file path when the PackageModel
acquisition environment does not define one explicitly.

.EXAMPLE
Get-PackageModelDefaultArtifactIndexFilePath
#>
    [CmdletBinding()]
    param()

    $localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        $localApplicationData = $env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        throw 'Could not resolve the LocalApplicationData directory for the PackageModel artifact index.'
    }

    return [System.IO.Path]::GetFullPath((Join-Path $localApplicationData 'Eigenverft.Manifested.Sandbox\PackageModel\artifact-index.json'))
}

function Get-PackageModelDefaultOwnershipIndexFilePath {
<#
.SYNOPSIS
Returns the default PackageModel ownership index path.

.DESCRIPTION
Builds the fallback local ownership index file path when the PackageModel
global document does not define one explicitly.

.EXAMPLE
Get-PackageModelDefaultOwnershipIndexFilePath
#>
    [CmdletBinding()]
    param()

    $localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        $localApplicationData = $env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        throw 'Could not resolve the LocalApplicationData directory for the PackageModel ownership index.'
    }

    return [System.IO.Path]::GetFullPath((Join-Path $localApplicationData 'Eigenverft.Manifested.Sandbox\PackageModel\ownership-index.json'))
}

function Get-PackageModelDefaultSourceInventoryPath {
<#
.SYNOPSIS
Returns the default external PackageModel source-inventory path.

.DESCRIPTION
Builds the fallback local source-inventory path that can hold environment and
site acquisition sources outside the shipped module JSON.

.EXAMPLE
Get-PackageModelDefaultSourceInventoryPath
#>
    [CmdletBinding()]
    param()

    $localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        $localApplicationData = $env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        throw 'Could not resolve the LocalApplicationData directory for the PackageModel source inventory.'
    }

    return [System.IO.Path]::GetFullPath((Join-Path $localApplicationData 'Eigenverft.Manifested.Sandbox\PackageModel\SourceInventory.json'))
}

function Resolve-PackageModelTemplateText {
<#
.SYNOPSIS
Resolves simple PackageModel template tokens in text.

.DESCRIPTION
Replaces package-aware tokens such as `{releaseTrack}`, `{version}`, and
`{flavor}` with the current values from the resolved PackageModel config and
selected release.

.PARAMETER Text
The text that contains optional PackageModel tokens.

.PARAMETER PackageModelConfig
The resolved PackageModel config object.

.PARAMETER Package
The selected release object.

.PARAMETER ExtraTokens
Optional extra tokens to merge into the standard replacement map.

.EXAMPLE
Resolve-PackageModelTemplateText -Text '{releaseTrack}\{version}\{flavor}' -PackageModelConfig $config -Package $package
#>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [AllowNull()]
        [psobject]$PackageModelConfig,

        [AllowNull()]
        [psobject]$Package,

        [hashtable]$ExtraTokens = @{}
    )

    if ($null -eq $Text) {
        return $null
    }

    $tokens = [ordered]@{}
    if ($PackageModelConfig) {
        $tokens['definitionId'] = $PackageModelConfig.DefinitionId
        $tokens['platform'] = $PackageModelConfig.Platform
        $tokens['architecture'] = $PackageModelConfig.Architecture
        $tokens['releaseTrack'] = $PackageModelConfig.ReleaseTrack
        if ($PackageModelConfig.PSObject.Properties['PreferredTargetInstallRootDirectory']) {
            $tokens['preferredTargetInstallDirectory'] = $PackageModelConfig.PreferredTargetInstallRootDirectory
        }
        if ($PackageModelConfig.PSObject.Properties['InstallWorkspaceRootDirectory']) {
            $tokens['installWorkspaceDirectory'] = $PackageModelConfig.InstallWorkspaceRootDirectory
        }
        if ($PackageModelConfig.PSObject.Properties['DefaultPackageDepotDirectory']) {
            $tokens['defaultPackageDepotDirectory'] = $PackageModelConfig.DefaultPackageDepotDirectory
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

function Get-PackageModelPackageFileRelativeDirectory {
<#
.SYNOPSIS
Builds the relative package-file directory for depot and workspace storage.

.DESCRIPTION
Derives the shared relative directory used below package depots and the
install workspace from the definition id and selected release identity.

.PARAMETER PackageModelConfig
The resolved PackageModel config object.

.PARAMETER Package
The selected release object.

.EXAMPLE
Get-PackageModelPackageFileRelativeDirectory -PackageModelConfig $config -Package $package
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelConfig,

        [Parameter(Mandatory = $true)]
        [psobject]$Package
    )

    $definitionId = [string]$PackageModelConfig.DefinitionId
    $releaseTrack = if ($Package.PSObject.Properties['releaseTrack']) { [string]$Package.releaseTrack } else { [string]$PackageModelConfig.ReleaseTrack }
    $version = if ($Package.PSObject.Properties['version']) { [string]$Package.version } else { $null }
    $flavor = if ($Package.PSObject.Properties['flavor']) { [string]$Package.flavor } else { $null }

    foreach ($requiredValue in @($definitionId, $releaseTrack, $version, $flavor)) {
        if ([string]::IsNullOrWhiteSpace($requiredValue)) {
            throw 'PackageModel package-file directory derivation requires definition id, releaseTrack, version, and flavor.'
        }
    }

    $pathSegments = @('packages', $definitionId, $releaseTrack, $version, $flavor) | ForEach-Object {
        $segmentText = ([string]$_).Trim() -replace '[\\/:\*\?"<>\|]', '-'
        if ([string]::IsNullOrWhiteSpace($segmentText)) {
            throw 'PackageModel package-file directory derivation produced an empty path segment.'
        }
        $segmentText
    }

    return (($pathSegments -join '\') -replace '/', '\')
}

function ConvertTo-PackageModelMergeValue {
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
            $result[[string]$key] = ConvertTo-PackageModelMergeValue -InputObject $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0)) {
        return @($InputObject | ForEach-Object { ConvertTo-PackageModelMergeValue -InputObject $_ })
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        return @($InputObject | ForEach-Object { ConvertTo-PackageModelMergeValue -InputObject $_ })
    }

    if ($InputObject.PSObject.Properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($property in @($InputObject.PSObject.Properties)) {
            $result[$property.Name] = ConvertTo-PackageModelMergeValue -InputObject $property.Value
        }
        return $result
    }

    return $InputObject
}

function Merge-PackageModelValues {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$BaseValue,

        [AllowNull()]
        [object]$OverlayValue
    )

    if ($null -eq $BaseValue) {
        return (ConvertTo-PackageModelMergeValue -InputObject $OverlayValue)
    }
    if ($null -eq $OverlayValue) {
        return (ConvertTo-PackageModelMergeValue -InputObject $BaseValue)
    }

    $baseIsObject = ($BaseValue -is [System.Collections.IDictionary])
    $overlayIsObject = ($OverlayValue -is [System.Collections.IDictionary])
    if ($baseIsObject -and $overlayIsObject) {
        $merged = [ordered]@{}
        foreach ($key in @($BaseValue.Keys)) {
            $merged[[string]$key] = ConvertTo-PackageModelMergeValue -InputObject $BaseValue[$key]
        }
        foreach ($key in @($OverlayValue.Keys)) {
            $keyText = [string]$key
            if ($merged.Contains($keyText)) {
                $merged[$keyText] = Merge-PackageModelValues -BaseValue $merged[$keyText] -OverlayValue $OverlayValue[$key]
            }
            else {
                $merged[$keyText] = ConvertTo-PackageModelMergeValue -InputObject $OverlayValue[$key]
            }
        }
        return $merged
    }

    if (($BaseValue -is [System.Collections.IEnumerable] -and -not ($BaseValue -is [string])) -and
        ($OverlayValue -is [System.Collections.IEnumerable] -and -not ($OverlayValue -is [string]))) {
        return @(ConvertTo-PackageModelMergeValue -InputObject $OverlayValue)
    }

    return (ConvertTo-PackageModelMergeValue -InputObject $OverlayValue)
}

function ConvertTo-PackageModelObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    return ((ConvertTo-PackageModelMergeValue -InputObject $InputObject | ConvertTo-Json -Depth 60) | ConvertFrom-Json)
}

function Get-PackageModelSourceInventoryPath {
<#
.SYNOPSIS
Returns the effective external PackageModel source-inventory path.

.DESCRIPTION
Resolves the environment-variable override first, then falls back to the
well-known local inventory path.

.EXAMPLE
Get-PackageModelSourceInventoryPath
#>
    [CmdletBinding()]
    param()

    $environmentVariableName = Get-PackageModelSourceInventoryPathEnvironmentVariableName
    $configuredPath = [Environment]::GetEnvironmentVariable($environmentVariableName)
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        return (Resolve-PackageModelPathValue -PathValue $configuredPath)
    }

    return (Get-PackageModelDefaultSourceInventoryPath)
}

function Get-PackageModelSiteCode {
<#
.SYNOPSIS
Returns the effective PackageModel site code.

.DESCRIPTION
Reads the optional site-code environment variable and normalizes its value.

.EXAMPLE
Get-PackageModelSiteCode
#>
    [CmdletBinding()]
    param()

    $environmentVariableName = Get-PackageModelSiteCodeEnvironmentVariableName
    $siteCode = [Environment]::GetEnvironmentVariable($environmentVariableName)
    if ([string]::IsNullOrWhiteSpace($siteCode)) {
        return $null
    }

    return $siteCode.Trim()
}

function Assert-PackageModelSourceInventorySchema {
<#
.SYNOPSIS
Validates the PackageModel source-inventory schema.

.DESCRIPTION
Checks that the external inventory document uses the current shape with
inventoryVersion, global, and optional site overlays.

.PARAMETER SourceInventoryDocumentInfo
The loaded source-inventory document info.

.EXAMPLE
Assert-PackageModelSourceInventorySchema -SourceInventoryDocumentInfo $inventoryInfo
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SourceInventoryDocumentInfo
    )

    $document = $SourceInventoryDocumentInfo.Document
    if (-not $document.PSObject.Properties['inventoryVersion']) {
        throw "PackageModel source inventory '$($SourceInventoryDocumentInfo.Path)' is missing inventoryVersion."
    }
    if (-not $document.PSObject.Properties['global']) {
        $document | Add-Member -MemberType NoteProperty -Name global -Value ([pscustomobject]@{})
    }
    if (-not $document.PSObject.Properties['sites']) {
        $document | Add-Member -MemberType NoteProperty -Name sites -Value ([pscustomobject]@{})
    }
}

function Get-PackageModelSourceInventoryInfo {
<#
.SYNOPSIS
Loads the optional external PackageModel source inventory.

.DESCRIPTION
Resolves the effective inventory path, loads it when present, validates the
schema, and otherwise returns a null document marker.

.EXAMPLE
Get-PackageModelSourceInventoryInfo
#>
    [CmdletBinding()]
    param()

    $inventoryPath = Get-PackageModelSourceInventoryPath
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        return [pscustomobject]@{
            Path     = $inventoryPath
            Document = $null
            Exists   = $false
        }
    }

    $documentInfo = Read-PackageModelJsonDocument -Path $inventoryPath
    Assert-PackageModelSourceInventorySchema -SourceInventoryDocumentInfo $documentInfo
    return [pscustomobject]@{
        Path     = $documentInfo.Path
        Document = $documentInfo.Document
        Exists   = $true
    }
}

function Assert-PackageModelGlobalConfigSchema {
<#
.SYNOPSIS
Validates the PackageModel global config schema.

.DESCRIPTION
Rejects retired global field names and requires the current PackageModel
preferred-install and acquisition-environment fields.

.PARAMETER GlobalDocumentInfo
The loaded PackageModel global config document info.

.EXAMPLE
Assert-PackageModelGlobalConfigSchema -GlobalDocumentInfo $globalInfo
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$GlobalDocumentInfo
    )

    if (-not $GlobalDocumentInfo.Document.PSObject.Properties['packageModel'] -or $null -eq $GlobalDocumentInfo.Document.packageModel) {
        throw "PackageModel global config '$($GlobalDocumentInfo.Path)' does not contain a 'packageModel' object."
    }

    $packageModel = $GlobalDocumentInfo.Document.packageModel
    foreach ($retiredProperty in @('managedStorageRoots', 'acquisitionDefaults', 'sourceBindings', 'downloadRootDirectory', 'installRootDirectory', 'allowSourceFallback', 'packageSelection')) {
        if ($packageModel.PSObject.Properties[$retiredProperty]) {
            throw "PackageModel global config '$($GlobalDocumentInfo.Path)' still uses retired property '$retiredProperty'."
        }
    }

    foreach ($requiredProperty in @('preferredTargetInstallDirectory', 'acquisitionEnvironment', 'ownershipTracking', 'selectionDefaults')) {
        if (-not $packageModel.PSObject.Properties[$requiredProperty]) {
            throw "PackageModel global config '$($GlobalDocumentInfo.Path)' is missing required property '$requiredProperty'."
        }
    }

    if ($packageModel.selectionDefaults.PSObject.Properties['channel']) {
        throw "PackageModel global config '$($GlobalDocumentInfo.Path)' still uses retired property 'selectionDefaults.channel'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$packageModel.preferredTargetInstallDirectory)) {
        throw "PackageModel global config '$($GlobalDocumentInfo.Path)' is missing preferredTargetInstallDirectory."
    }

    foreach ($requiredAcquisitionProperty in @('stores', 'defaults', 'tracking')) {
        if (-not $packageModel.acquisitionEnvironment.PSObject.Properties[$requiredAcquisitionProperty]) {
            throw "PackageModel global config '$($GlobalDocumentInfo.Path)' is missing acquisitionEnvironment.$requiredAcquisitionProperty."
        }
    }

    foreach ($requiredStoreProperty in @('installWorkspaceDirectory', 'defaultPackageDepotDirectory')) {
        if (-not $packageModel.acquisitionEnvironment.stores.PSObject.Properties[$requiredStoreProperty]) {
            throw "PackageModel global config '$($GlobalDocumentInfo.Path)' is missing acquisitionEnvironment.stores.$requiredStoreProperty."
        }
    }

    foreach ($requiredDefaultProperty in @('allowFallback', 'mirrorDownloadedArtifactsToDefaultPackageDepot')) {
        if (-not $packageModel.acquisitionEnvironment.defaults.PSObject.Properties[$requiredDefaultProperty]) {
            throw "PackageModel global config '$($GlobalDocumentInfo.Path)' is missing acquisitionEnvironment.defaults.$requiredDefaultProperty."
        }
    }

    if (-not $packageModel.acquisitionEnvironment.tracking.PSObject.Properties['artifactIndexFilePath']) {
        throw "PackageModel global config '$($GlobalDocumentInfo.Path)' is missing acquisitionEnvironment.tracking.artifactIndexFilePath."
    }
    if (-not $packageModel.ownershipTracking.PSObject.Properties['indexFilePath']) {
        throw "PackageModel global config '$($GlobalDocumentInfo.Path)' is missing ownershipTracking.indexFilePath."
    }
    if (-not $packageModel.selectionDefaults.PSObject.Properties['releaseTrack']) {
        throw "PackageModel global config '$($GlobalDocumentInfo.Path)' is missing selectionDefaults.releaseTrack."
    }

    if ($packageModel.acquisitionEnvironment.PSObject.Properties['environmentSources'] -and $null -ne $packageModel.acquisitionEnvironment.environmentSources) {
        foreach ($retiredEnvironmentSourceId in @('localPackageDepot', 'remotePackageDepot', 'corpPackageDepot', 'sitePackageDepot', 'vsCodeUpdateService')) {
            if ($packageModel.acquisitionEnvironment.environmentSources.PSObject.Properties[$retiredEnvironmentSourceId]) {
                throw "PackageModel global config '$($GlobalDocumentInfo.Path)' must not define acquisitionEnvironment.environmentSources.$retiredEnvironmentSourceId in the shipped global config."
            }
        }
    }
}

function Resolve-PackageModelEnvironmentSources {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$EnvironmentSources,

        [AllowNull()]
        [string]$DefaultPackageDepotDirectory
    )

    $resolvedSources = [ordered]@{}

    if (-not [string]::IsNullOrWhiteSpace($DefaultPackageDepotDirectory)) {
        $resolvedSources['defaultPackageDepot'] = [ordered]@{
            id       = 'defaultPackageDepot'
            kind     = 'filesystem'
            basePath = $DefaultPackageDepotDirectory
        }
    }

    if ($EnvironmentSources) {
        foreach ($property in @($EnvironmentSources.PSObject.Properties)) {
            $sourceValue = $property.Value
            $resolvedSource = [ordered]@{
                id   = $property.Name
                kind = if ($sourceValue.PSObject.Properties['kind']) { [string]$sourceValue.kind } else { $null }
            }

            if ($sourceValue.PSObject.Properties['baseUri'] -and -not [string]::IsNullOrWhiteSpace([string]$sourceValue.baseUri)) {
                $resolvedSource.baseUri = [string]$sourceValue.baseUri
            }
            if ($sourceValue.PSObject.Properties['basePath'] -and -not [string]::IsNullOrWhiteSpace([string]$sourceValue.basePath)) {
                $resolvedSource.basePath = Resolve-PackageModelPathValue -PathValue ([string]$sourceValue.basePath)
            }

            $resolvedSources[$property.Name] = $resolvedSource
        }
    }

    return (ConvertTo-PackageModelObject -InputObject $resolvedSources)
}

function Resolve-PackageModelEffectiveAcquisitionEnvironment {
<#
.SYNOPSIS
Materializes the effective PackageModel acquisition environment.

.DESCRIPTION
Starts from the shipped acquisition-environment config, applies optional
inventory global and site overlays, resolves concrete store paths, and returns
the internal effective environment model used by later source planning.

.PARAMETER GlobalConfiguration
The shipped PackageModel global config object.

.PARAMETER SourceInventoryInfo
The optional external source-inventory document info.

.EXAMPLE
Resolve-PackageModelEffectiveAcquisitionEnvironment -GlobalConfiguration $global -SourceInventoryInfo $inventory
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$GlobalConfiguration,

        [Parameter(Mandatory = $true)]
        [psobject]$SourceInventoryInfo
    )

    $mergedAcquisitionEnvironment = ConvertTo-PackageModelMergeValue -InputObject $GlobalConfiguration.acquisitionEnvironment
    $siteCode = Get-PackageModelSiteCode

    if ($SourceInventoryInfo -and $SourceInventoryInfo.Exists -and $SourceInventoryInfo.Document) {
        $inventoryGlobal = if ($SourceInventoryInfo.Document.PSObject.Properties['global']) { $SourceInventoryInfo.Document.global } else { $null }
        if ($inventoryGlobal) {
            $mergedAcquisitionEnvironment = Merge-PackageModelValues -BaseValue $mergedAcquisitionEnvironment -OverlayValue (ConvertTo-PackageModelMergeValue -InputObject $inventoryGlobal)
        }

        if (-not [string]::IsNullOrWhiteSpace($siteCode) -and $SourceInventoryInfo.Document.PSObject.Properties['sites']) {
            foreach ($siteProperty in @($SourceInventoryInfo.Document.sites.PSObject.Properties)) {
                if ([string]::Equals([string]$siteProperty.Name, [string]$siteCode, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $mergedAcquisitionEnvironment = Merge-PackageModelValues -BaseValue $mergedAcquisitionEnvironment -OverlayValue (ConvertTo-PackageModelMergeValue -InputObject $siteProperty.Value)
                    break
                }
            }
        }
    }

    $acquisitionEnvironment = ConvertTo-PackageModelObject -InputObject $mergedAcquisitionEnvironment

    $installWorkspaceDirectory = if ($acquisitionEnvironment.stores.PSObject.Properties['installWorkspaceDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$acquisitionEnvironment.stores.installWorkspaceDirectory)) {
        Resolve-PackageModelPathValue -PathValue ([string]$acquisitionEnvironment.stores.installWorkspaceDirectory)
    }
    else {
        Get-PackageModelDefaultInstallWorkspaceDirectory
    }

    $defaultPackageDepotDirectory = if ($acquisitionEnvironment.stores.PSObject.Properties['defaultPackageDepotDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$acquisitionEnvironment.stores.defaultPackageDepotDirectory)) {
        Resolve-PackageModelPathValue -PathValue ([string]$acquisitionEnvironment.stores.defaultPackageDepotDirectory)
    }
    else {
        Get-PackageModelDefaultPackageDepotDirectory
    }

    $artifactIndexFilePath = if ($acquisitionEnvironment.tracking.PSObject.Properties['artifactIndexFilePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$acquisitionEnvironment.tracking.artifactIndexFilePath)) {
        Resolve-PackageModelPathValue -PathValue ([string]$acquisitionEnvironment.tracking.artifactIndexFilePath)
    }
    else {
        Get-PackageModelDefaultArtifactIndexFilePath
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

    $environmentSources = Resolve-PackageModelEnvironmentSources -EnvironmentSources $configuredEnvironmentSources -DefaultPackageDepotDirectory $defaultPackageDepotDirectory

    return [pscustomobject]@{
        SourceInventoryPath = $SourceInventoryInfo.Path
        SiteCode            = $siteCode
        Stores              = [pscustomobject]@{
            InstallWorkspaceDirectory = $installWorkspaceDirectory
            DefaultPackageDepotDirectory = $defaultPackageDepotDirectory
        }
        Defaults            = [pscustomobject]@{
            AllowFallback = $allowFallback
            MirrorDownloadedArtifactsToDefaultPackageDepot = $mirrorDownloadedArtifacts
        }
        EnvironmentSources  = $environmentSources
        Tracking            = [pscustomobject]@{
            ArtifactIndexFilePath = $artifactIndexFilePath
        }
    }
}

function Assert-PackageModelDefinitionSchema {
<#
.SYNOPSIS
Validates the PackageModel definition schema for this package pass.

.DESCRIPTION
Checks that the definition uses the current package-definition and
acquisition-source model and rejects the earlier experimental schema names.

.PARAMETER DefinitionDocumentInfo
The loaded PackageModel definition document info.

.PARAMETER DefinitionId
The expected definition id.

.EXAMPLE
Assert-PackageModelDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId VSCodeRuntime
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
            throw "PackageModel definition '$($DefinitionDocumentInfo.Path)' still uses retired property '$retiredProperty'."
        }
    }

    foreach ($requiredProperty in @('id', 'display', 'upstreamSources', 'providedTools', 'releaseDefaults', 'releases')) {
        if (-not $definition.PSObject.Properties[$requiredProperty]) {
            throw "PackageModel definition '$($DefinitionDocumentInfo.Path)' is missing required property '$requiredProperty'."
        }
    }

    if (-not [string]::Equals([string]$definition.id, [string]$DefinitionId, [System.StringComparison]::Ordinal)) {
        throw "PackageModel definition id '$($definition.id)' does not match requested definition id '$DefinitionId'."
    }

    foreach ($requiredDefaultProperty in @('requirements', 'install', 'validation', 'existingInstallDiscovery', 'existingInstallPolicy')) {
        if (-not $definition.releaseDefaults.PSObject.Properties[$requiredDefaultProperty]) {
            throw "PackageModel definition '$($definition.id)' is missing releaseDefaults.$requiredDefaultProperty."
        }
    }
    foreach ($retiredDefaultProperty in @('existingInstall')) {
        if ($definition.releaseDefaults.PSObject.Properties[$retiredDefaultProperty]) {
            throw "PackageModel definition '$($definition.id)' still uses retired property 'releaseDefaults.$retiredDefaultProperty'."
        }
    }

    foreach ($release in @($definition.releases)) {
        foreach ($retiredProperty in @('artifact', 'acquisitions', 'dependencies', 'sourceOptions', 'reuse', 'channel')) {
            if ($release.PSObject.Properties[$retiredProperty]) {
                throw "PackageModel release '$($release.id)' in '$($definition.id)' still uses retired property '$retiredProperty'."
            }
        }
        foreach ($retiredReleaseProperty in @('existingInstall')) {
            if ($release.PSObject.Properties[$retiredReleaseProperty]) {
                throw "PackageModel release '$($release.id)' in '$($definition.id)' still uses retired property '$retiredReleaseProperty'."
            }
        }

        foreach ($requiredProperty in @('id', 'version', 'releaseTrack', 'flavor', 'constraints')) {
            if (-not $release.PSObject.Properties[$requiredProperty]) {
                throw "PackageModel release '$($release.id)' in '$($definition.id)' is missing required property '$requiredProperty'."
            }
        }

        $effectiveRelease = Resolve-PackageModelEffectiveRelease -Definition $definition -Release $release
        foreach ($requiredEffectiveProperty in @('install', 'validation', 'requirements', 'existingInstallDiscovery', 'existingInstallPolicy')) {
            if (-not $effectiveRelease.PSObject.Properties[$requiredEffectiveProperty]) {
                throw "PackageModel release '$($release.id)' in '$($definition.id)' is missing required effective property '$requiredEffectiveProperty'."
            }
        }

        $installKind = if ($effectiveRelease.install -and $effectiveRelease.install.PSObject.Properties['kind']) {
            [string]$effectiveRelease.install.kind
        }
        else {
            $null
        }

        $requiresPackageFile = $false
        $requiresAcquisitionCandidates = $false
        switch -Exact ($installKind) {
            'expandArchive' {
                $requiresPackageFile = $true
                $requiresAcquisitionCandidates = $true
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
                throw "PackageModel release '$($release.id)' in '$($definition.id)' is missing required property 'packageFile'."
            }
            if (-not $effectiveRelease.packageFile.PSObject.Properties['fileName'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.packageFile.fileName)) {
                throw "PackageModel release '$($release.id)' in '$($definition.id)' is missing packageFile.fileName."
            }
        }

        if ($effectiveRelease.PSObject.Properties['packageFile'] -and $effectiveRelease.packageFile -and
            (-not $effectiveRelease.packageFile.PSObject.Properties['fileName'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.packageFile.fileName))) {
            throw "PackageModel release '$($release.id)' in '$($definition.id)' defines packageFile without packageFile.fileName."
        }

        if ($requiresAcquisitionCandidates) {
            if (-not $effectiveRelease.PSObject.Properties['acquisitionCandidates'] -or @($effectiveRelease.acquisitionCandidates).Count -eq 0) {
                throw "PackageModel release '$($release.id)' in '$($definition.id)' is missing required property 'acquisitionCandidates'."
            }
        }

        if ($effectiveRelease.PSObject.Properties['acquisitionCandidates']) {
            foreach ($candidate in @($effectiveRelease.acquisitionCandidates)) {
                if ($null -eq $candidate) {
                    continue
                }
                if ($candidate.PSObject.Properties['sourceBindingId']) {
                    throw "PackageModel release '$($release.id)' in '$($definition.id)' still uses retired property 'sourceBindingId'."
                }
                if ($candidate.PSObject.Properties['sourceRef']) {
                    throw "PackageModel release '$($release.id)' in '$($definition.id)' still uses retired property 'sourceRef'."
                }
                if (-not $candidate.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$candidate.kind)) {
                    throw "PackageModel release '$($release.id)' in '$($definition.id)' has an acquisition candidate without kind."
                }
                switch -Exact ([string]$candidate.kind) {
                    'packageDepot' { }
                    'download' {
                        if (-not $candidate.PSObject.Properties['sourcePath'] -or [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                            throw "PackageModel release '$($release.id)' in '$($definition.id)' has a download acquisition candidate without sourcePath."
                        }
                        if (-not $candidate.PSObject.Properties['sourceId'] -or [string]::IsNullOrWhiteSpace([string]$candidate.sourceId)) {
                            throw "PackageModel release '$($release.id)' in '$($definition.id)' has a download acquisition candidate without sourceId."
                        }
                    }
                    'filesystem' {
                        if (-not $candidate.PSObject.Properties['sourcePath'] -or [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                            throw "PackageModel release '$($release.id)' in '$($definition.id)' has a filesystem acquisition candidate without sourcePath."
                        }
                    }
                    default {
                        throw "PackageModel release '$($release.id)' in '$($definition.id)' uses unsupported acquisition kind '$($candidate.kind)'."
                    }
                }
            }
        }

        $existingInstallDiscovery = $effectiveRelease.existingInstallDiscovery
        if ($existingInstallDiscovery.PSObject.Properties['enableDetection'] -and [bool]$existingInstallDiscovery.enableDetection) {
            if (-not $existingInstallDiscovery.PSObject.Properties['searchLocations']) {
                throw "PackageModel release '$($release.id)' in '$($definition.id)' is missing existingInstallDiscovery.searchLocations."
            }
            if (-not $existingInstallDiscovery.PSObject.Properties['installRootRules']) {
                throw "PackageModel release '$($release.id)' in '$($definition.id)' is missing existingInstallDiscovery.installRootRules."
            }
            foreach ($rule in @($existingInstallDiscovery.installRootRules)) {
                if ($null -eq $rule) {
                    continue
                }
                if ($rule.PSObject.Properties['fileName'] -or $rule.PSObject.Properties['homePath']) {
                    throw "PackageModel release '$($release.id)' in '$($definition.id)' still uses retired installRootRules fields from installHomeRules."
                }
                if (-not $rule.PSObject.Properties['match'] -or $null -eq $rule.match) {
                    throw "PackageModel release '$($release.id)' in '$($definition.id)' has an installRootRule without match."
                }
                if (-not $rule.match.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$rule.match.kind)) {
                    throw "PackageModel release '$($release.id)' in '$($definition.id)' has an installRootRule without match.kind."
                }
                if (-not $rule.match.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$rule.match.value)) {
                    throw "PackageModel release '$($release.id)' in '$($definition.id)' has an installRootRule without match.value."
                }
                if (-not $rule.PSObject.Properties['installRootRelativePath']) {
                    throw "PackageModel release '$($release.id)' in '$($definition.id)' has an installRootRule without installRootRelativePath."
                }
            }
        }
    }
}

function Resolve-PackageModelEffectiveRelease {
<#
.SYNOPSIS
Builds the effective PackageModel release by applying definition defaults.

.DESCRIPTION
Applies whole-block fallback from the definition releaseDefaults block to a
single release entry. When a release defines one of the known release blocks,
that block fully replaces the default block.

.PARAMETER Definition
The PackageModel definition object.

.PARAMETER Release
The raw release object from the definition.

.EXAMPLE
Resolve-PackageModelEffectiveRelease -Definition $definition -Release $release
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [psobject]$Release
    )

    $effectiveRelease = ConvertTo-PackageModelObject -InputObject $Release
    foreach ($propertyName in @('requirements', 'install', 'validation', 'existingInstallDiscovery', 'existingInstallPolicy')) {
        if (-not $effectiveRelease.PSObject.Properties[$propertyName] -and $Definition.releaseDefaults.PSObject.Properties[$propertyName]) {
            $effectiveRelease | Add-Member -MemberType NoteProperty -Name $propertyName -Value (ConvertTo-PackageModelObject -InputObject $Definition.releaseDefaults.$propertyName)
        }
    }

    return $effectiveRelease
}

function Get-PackageModelConfig {
<#
.SYNOPSIS
Loads the effective PackageModel config for a definition id.

.DESCRIPTION
Loads the shipped PackageModel global document, applies the optional external
source inventory, loads one shipped PackageModel definition, validates the
current schema, resolves runtime context and managed roots, and returns the
combined config object for command orchestration.

.PARAMETER DefinitionId
The PackageModel definition id. The shipped JSON filename stem must match this
value.

.EXAMPLE
Get-PackageModelConfig -DefinitionId VSCodeRuntime
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId
    )

    $globalDocumentInfo = Read-PackageModelJsonDocument -Path (Get-PackageModelGlobalConfigPath)
    Assert-PackageModelGlobalConfigSchema -GlobalDocumentInfo $globalDocumentInfo

    $sourceInventoryInfo = Get-PackageModelSourceInventoryInfo

    $definitionDocumentInfo = Read-PackageModelJsonDocument -Path (Get-PackageModelDefinitionPath -DefinitionId $DefinitionId)
    Assert-PackageModelDefinitionSchema -DefinitionDocumentInfo $definitionDocumentInfo -DefinitionId $DefinitionId

    $packageModelGlobalConfig = $globalDocumentInfo.Document.packageModel
    $runtimeContext = Get-PackageModelRuntimeContext
    $definition = $definitionDocumentInfo.Document
    $effectiveAcquisitionEnvironment = Resolve-PackageModelEffectiveAcquisitionEnvironment -GlobalConfiguration $packageModelGlobalConfig -SourceInventoryInfo $sourceInventoryInfo

    $selectionReleaseTrack = 'none'
    if ($packageModelGlobalConfig.selectionDefaults.PSObject.Properties['releaseTrack'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageModelGlobalConfig.selectionDefaults.releaseTrack)) {
        $selectionReleaseTrack = [string]$packageModelGlobalConfig.selectionDefaults.releaseTrack
    }

    $selectionStrategy = 'latestByVersion'
    if ($packageModelGlobalConfig.selectionDefaults.PSObject.Properties['strategy'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageModelGlobalConfig.selectionDefaults.strategy)) {
        $selectionStrategy = [string]$packageModelGlobalConfig.selectionDefaults.strategy
    }

    $preferredTargetInstallDirectory = if ($packageModelGlobalConfig.PSObject.Properties['preferredTargetInstallDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageModelGlobalConfig.preferredTargetInstallDirectory)) {
        Resolve-PackageModelPathValue -PathValue ([string]$packageModelGlobalConfig.preferredTargetInstallDirectory)
    }
    else {
        Get-PackageModelDefaultPreferredTargetInstallDirectory
    }

    $ownershipIndexFilePath = if ($packageModelGlobalConfig.ownershipTracking.PSObject.Properties['indexFilePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageModelGlobalConfig.ownershipTracking.indexFilePath)) {
        Resolve-PackageModelPathValue -PathValue ([string]$packageModelGlobalConfig.ownershipTracking.indexFilePath)
    }
    else {
        Get-PackageModelDefaultOwnershipIndexFilePath
    }

    $display = if ($definition.display -and $definition.display.PSObject.Properties['default'] -and $null -ne $definition.display.default) {
        $definition.display.default
    }
    else {
        [pscustomobject]@{}
    }

    return [pscustomobject]@{
        GlobalConfigurationPath            = $globalDocumentInfo.Path
        GlobalConfiguration                = $packageModelGlobalConfig
        SourceInventoryPath                = $effectiveAcquisitionEnvironment.SourceInventoryPath
        SourceInventory                    = $sourceInventoryInfo.Document
        EffectiveAcquisitionEnvironment    = $effectiveAcquisitionEnvironment
        DefinitionPath                     = $definitionDocumentInfo.Path
        Definition                         = $definition
        DefinitionId                       = [string]$definition.id
        DefinitionUpstreamSources          = $definition.upstreamSources
        Display                            = $display
        Platform                           = $runtimeContext.Platform
        Architecture                       = $runtimeContext.Architecture
        ReleaseTrack                       = $selectionReleaseTrack
        SelectionStrategy                  = $selectionStrategy
        InstallWorkspaceRootDirectory      = $effectiveAcquisitionEnvironment.Stores.InstallWorkspaceDirectory
        DefaultPackageDepotDirectory       = $effectiveAcquisitionEnvironment.Stores.DefaultPackageDepotDirectory
        PreferredTargetInstallRootDirectory = $preferredTargetInstallDirectory
        ArtifactIndexFilePath              = $effectiveAcquisitionEnvironment.Tracking.ArtifactIndexFilePath
        OwnershipIndexFilePath             = $ownershipIndexFilePath
        AllowAcquisitionFallback           = $effectiveAcquisitionEnvironment.Defaults.AllowFallback
        MirrorDownloadedArtifactsToDefaultPackageDepot = $effectiveAcquisitionEnvironment.Defaults.MirrorDownloadedArtifactsToDefaultPackageDepot
        EnvironmentSources                 = $effectiveAcquisitionEnvironment.EnvironmentSources
    }
}

function Resolve-PackageModelPaths {
<#
.SYNOPSIS
Resolves the concrete package-file workspace/depot and install paths for a selected release.

.DESCRIPTION
Builds the shared relative package-file directory for depot and workspace
storage from the selected release identity, resolves the effective install
directory template, and attaches the resolved directories to the PackageModel
result object.

.PARAMETER PackageModelResult
The PackageModel result object to enrich.

.EXAMPLE
Resolve-PackageModelPaths -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $packageModelConfig = $PackageModelResult.PackageModelConfig
    $definition = $packageModelConfig.Definition
    $package = $PackageModelResult.Package
    if (-not $package) {
        throw 'Resolve-PackageModelPaths requires a selected release.'
    }
    $installKind = if ($package.PSObject.Properties['install'] -and $package.install -and $package.install.PSObject.Properties['kind']) {
        [string]$package.install.kind
    }
    else {
        $null
    }

    $packageFileRelativeDirectory = Get-PackageModelPackageFileRelativeDirectory -PackageModelConfig $packageModelConfig -Package $package
    $installDirectoryTemplate = $null
    if ($package.PSObject.Properties['install'] -and $package.install -and
        $package.install.PSObject.Properties['installDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$package.install.installDirectory)) {
        $installDirectoryTemplate = Resolve-PackageModelTemplateText -Text ([string]$package.install.installDirectory) -PackageModelConfig $packageModelConfig -Package $package
    }
    elseif (-not [string]::Equals($installKind, 'reuseExisting', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "PackageModel definition '$($definition.id)' does not define an install target path. Use install.installDirectory."
    }

    $normalizedPackageFileRelativeDirectory = $packageFileRelativeDirectory.Trim() -replace '/', '\'
    if ([System.IO.Path]::IsPathRooted($normalizedPackageFileRelativeDirectory)) {
        throw "PackageModel definition '$($definition.id)' must use a relative package-file directory."
    }

    $installWorkspaceDirectory = [System.IO.Path]::GetFullPath((Join-Path $packageModelConfig.InstallWorkspaceRootDirectory $normalizedPackageFileRelativeDirectory))

    $installDirectory = $null
    if (-not [string]::IsNullOrWhiteSpace($installDirectoryTemplate)) {
        $expandedInstallDirectoryTemplate = [Environment]::ExpandEnvironmentVariables(([string]$installDirectoryTemplate).Trim()) -replace '/', '\'
        $installDirectory = if ([System.IO.Path]::IsPathRooted($expandedInstallDirectoryTemplate)) {
            [System.IO.Path]::GetFullPath($expandedInstallDirectoryTemplate)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $packageModelConfig.PreferredTargetInstallRootDirectory $expandedInstallDirectoryTemplate))
        }
    }

    $packageFilePath = $null
    $defaultPackageDepotFilePath = $null
    if ($package.PSObject.Properties['packageFile'] -and
        $package.packageFile -and
        $package.packageFile.PSObject.Properties['fileName'] -and
        -not [string]::IsNullOrWhiteSpace([string]$package.packageFile.fileName)) {
        $packageFilePath = Join-Path $installWorkspaceDirectory ([string]$package.packageFile.fileName)
        $defaultPackageDepotDirectory = [System.IO.Path]::GetFullPath((Join-Path $packageModelConfig.DefaultPackageDepotDirectory $normalizedPackageFileRelativeDirectory))
        $defaultPackageDepotFilePath = Join-Path $defaultPackageDepotDirectory ([string]$package.packageFile.fileName)
    }

    $PackageModelResult.InstallWorkspaceDirectory = $installWorkspaceDirectory
    $PackageModelResult.InstallDirectory = $installDirectory
    $PackageModelResult.PackageFileRelativeDirectory = $normalizedPackageFileRelativeDirectory
    $PackageModelResult.PackageFilePath = $packageFilePath
    $PackageModelResult.DefaultPackageDepotFilePath = $defaultPackageDepotFilePath

    return $PackageModelResult
}

function New-PackageModelResult {
<#
.SYNOPSIS
Creates the initial PackageModel result object.

.DESCRIPTION
Creates the result object that later PackageModel stage helpers enrich with
release selection, package file, install, ownership, validation, and entry-point data.

.PARAMETER CommandName
The command that owns the result.

.PARAMETER PackageModelConfig
The resolved PackageModel config object for the command.

.EXAMPLE
New-PackageModelResult -CommandName Invoke-PackageModel-VSCodeRuntime -PackageModelConfig $config
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelConfig
    )

    return [pscustomobject]@{
        CommandName                      = $CommandName
        Status                           = 'Pending'
        FailureReason                    = $null
        ErrorMessage                     = $null
        CurrentStep                      = 'Pending'
        DefinitionId                     = $PackageModelConfig.DefinitionId
        Display                          = $PackageModelConfig.Display
        Platform                         = $PackageModelConfig.Platform
        Architecture                     = $PackageModelConfig.Architecture
        ReleaseTrack                     = $PackageModelConfig.ReleaseTrack
        SourceInventoryPath              = $PackageModelConfig.SourceInventoryPath
        InstallWorkspaceRootDirectory    = $PackageModelConfig.InstallWorkspaceRootDirectory
        DefaultPackageDepotDirectory     = $PackageModelConfig.DefaultPackageDepotDirectory
        PreferredTargetInstallRootDirectory = $PackageModelConfig.PreferredTargetInstallRootDirectory
        ArtifactIndexFilePath            = $PackageModelConfig.ArtifactIndexFilePath
        OwnershipIndexFilePath           = $PackageModelConfig.OwnershipIndexFilePath
        Package                          = $null
        EffectiveRelease                 = $null
        PackageId                        = $null
        PackageVersion                   = $null
        Requirements                     = @()
        InstallWorkspaceDirectory        = $null
        InstallDirectory                 = $null
        PackageFileRelativeDirectory     = $null
        PackageFilePath                  = $null
        DefaultPackageDepotFilePath      = $null
        AcquisitionPlan                  = $null
        ExistingPackage                  = $null
        Ownership                        = $null
        InstallOrigin                    = $null
        PackageFileSave                  = $null
        Install                          = $null
        Validation                       = $null
        EntryPoints                      = $null
        PackageModelConfig               = $PackageModelConfig
    }
}
