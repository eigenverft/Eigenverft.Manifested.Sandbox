<#
    Eigenverft.Manifested.Sandbox.Package.State
#>

function Get-PackageStateDirectorySummary {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Path
    )

    $exists = $false
    $childCount = 0

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $exists = Test-Path -LiteralPath $Path -PathType Container
        if ($exists) {
            $childCount = @(
                Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            ).Count
        }
    }

    return [pscustomobject]@{
        Path       = $Path
        Exists     = $exists
        ChildCount = $childCount
    }
}

function Test-PackageStateLeafPath {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    return (Test-Path -LiteralPath $Path -PathType Leaf)
}

function Select-PackageStateOwnershipRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Record
    )

    $installDirectory = [string]$Record.installDirectory
    $installDirectoryExists = $false
    if (-not [string]::IsNullOrWhiteSpace($installDirectory)) {
        $installDirectoryExists = Test-Path -LiteralPath $installDirectory -PathType Container
    }

    return [pscustomobject]@{
        InstallSlotId          = $Record.installSlotId
        DefinitionId           = $Record.definitionId
        DefinitionRepositoryId = $Record.definitionRepositoryId
        DefinitionFileName     = $Record.definitionFileName
        DefinitionLocalPath    = $Record.definitionLocalPath
        DefinitionLocalExists  = Test-PackageStateLeafPath -Path ([string]$Record.definitionLocalPath)
        ReleaseTrack           = $Record.releaseTrack
        Flavor                 = $Record.flavor
        CurrentReleaseId       = $Record.currentReleaseId
        CurrentVersion         = $Record.currentVersion
        InstallDirectory       = $installDirectory
        InstallDirectoryExists = $installDirectoryExists
        OwnershipKind          = $Record.ownershipKind
        UpdatedAtUtc           = $Record.updatedAtUtc
    }
}

function Select-PackageStatePackageFileRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Record
    )

    $path = [string]$Record.path
    $exists = $false
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        $exists = Test-Path -LiteralPath $path -PathType Leaf
    }

    return [pscustomobject]@{
        Path         = $path
        Exists       = $exists
        DefinitionId = $Record.definitionId
        ReleaseId    = $Record.releaseId
        ReleaseTrack = $Record.releaseTrack
        Flavor       = $Record.flavor
        Version      = $Record.version
        SourceScope  = $Record.sourceScope
        SourceId     = $Record.sourceId
        UpdatedAtUtc = $Record.updatedAtUtc
    }
}

function Get-PackageModelStateConfig {
    [CmdletBinding()]
    param()

    $globalDocumentInfo = Read-PackageModelJsonDocument -Path (Get-PackageModelGlobalConfigPath)
    Assert-PackageModelGlobalConfigSchema -GlobalDocumentInfo $globalDocumentInfo

    $sourceInventoryInfo = Get-PackageModelSourceInventoryInfo
    $packageModelGlobalConfig = $globalDocumentInfo.Document.packageModel
    $effectiveAcquisitionEnvironment = Resolve-PackageModelEffectiveAcquisitionEnvironment -GlobalConfiguration $packageModelGlobalConfig -SourceInventoryInfo $sourceInventoryInfo

    $preferredTargetInstallDirectory = if ($packageModelGlobalConfig.PSObject.Properties['preferredTargetInstallDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageModelGlobalConfig.preferredTargetInstallDirectory)) {
        Resolve-PackageModelPathValue -PathValue ([string]$packageModelGlobalConfig.preferredTargetInstallDirectory)
    }
    else {
        Get-PackageModelDefaultPreferredTargetInstallDirectory
    }

    $packageStateIndexFilePath = if ($packageModelGlobalConfig.packageState.PSObject.Properties['indexFilePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageModelGlobalConfig.packageState.indexFilePath)) {
        Resolve-PackageModelPathValue -PathValue ([string]$packageModelGlobalConfig.packageState.indexFilePath)
    }
    else {
        Get-PackageModelDefaultPackageStateIndexFilePath
    }

    $localRepositoryRoot = if ($packageModelGlobalConfig.PSObject.Properties['localRepositoryRoot'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageModelGlobalConfig.localRepositoryRoot)) {
        Resolve-PackageModelPathValue -PathValue ([string]$packageModelGlobalConfig.localRepositoryRoot)
    }
    else {
        Get-PackageModelDefaultLocalRepositoryRoot
    }

    return [pscustomobject]@{
        GlobalConfigurationPath             = $globalDocumentInfo.Path
        GlobalConfiguration                 = $packageModelGlobalConfig
        LocalConfigurationPath              = Get-PackageModelLocalGlobalConfigPath
        SourceInventoryPath                 = $effectiveAcquisitionEnvironment.SourceInventoryPath
        SourceInventory                     = $sourceInventoryInfo.Document
        SourceInventoryInfo                 = $sourceInventoryInfo
        EffectiveAcquisitionEnvironment     = $effectiveAcquisitionEnvironment
        InstallWorkspaceRootDirectory       = $effectiveAcquisitionEnvironment.Stores.InstallWorkspaceDirectory
        DefaultPackageDepotDirectory        = $effectiveAcquisitionEnvironment.Stores.DefaultPackageDepotDirectory
        PreferredTargetInstallRootDirectory = $preferredTargetInstallDirectory
        LocalRepositoryRoot                 = $localRepositoryRoot
        PackageFileIndexFilePath            = $effectiveAcquisitionEnvironment.Tracking.PackageFileIndexFilePath
        PackageStateIndexFilePath           = $packageStateIndexFilePath
        EnvironmentSources                  = $effectiveAcquisitionEnvironment.EnvironmentSources
    }
}

function Get-PackageState {
    [CmdletBinding()]
    param(
        [switch]$Raw
    )

    $config = Get-PackageModelStateConfig
    $packageStateIndex = Get-PackageModelPackageStateIndex -PackageModelConfig $config
    $packageFileIndex = Get-PackageModelPackageFileIndex -PackageModelConfig $config
    $sourceInventoryInfo = $config.SourceInventoryInfo

    $directories = [pscustomobject]@{
        Installs            = Get-PackageStateDirectorySummary -Path $config.PreferredTargetInstallRootDirectory
        InstallWorkspace    = Get-PackageStateDirectorySummary -Path $config.InstallWorkspaceRootDirectory
        DefaultPackageDepot = Get-PackageStateDirectorySummary -Path $config.DefaultPackageDepotDirectory
        LocalRepositoryRoot = Get-PackageStateDirectorySummary -Path $config.LocalRepositoryRoot
    }

    if ($Raw.IsPresent) {
        return [pscustomobject]@{
            Config            = $config
            PackageStateIndex = $packageStateIndex
            PackageFileIndex  = $packageFileIndex
            SourceInventory   = $sourceInventoryInfo
            Directories       = $directories
        }
    }

    $localRoot = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$config.PackageStateIndexFilePath)) {
        $localRoot = Split-Path -Parent $config.PackageStateIndexFilePath
    }

    $packageRecords = @($packageStateIndex.Records)
    $packageFileRecords = @($packageFileIndex.Records)

    return [pscustomobject]@{
        LocalRoot                 = $localRoot
        LocalConfigurationPath    = $config.LocalConfigurationPath
        LocalConfigurationExists  = Test-PackageStateLeafPath -Path $config.LocalConfigurationPath
        LocalRepositoryRoot       = $config.LocalRepositoryRoot
        PackageStateIndexPath     = $packageStateIndex.Path
        PackageStateIndexExists   = Test-PackageStateLeafPath -Path $packageStateIndex.Path
        PackageFileIndexPath      = $packageFileIndex.Path
        PackageFileIndexExists    = Test-PackageStateLeafPath -Path $packageFileIndex.Path
        SourceInventoryPath       = $sourceInventoryInfo.Path
        SourceInventoryExists     = [bool]$sourceInventoryInfo.Exists
        PackageRecordCount        = $packageRecords.Count
        PackageFileRecordCount    = $packageFileRecords.Count
        PackageRecords            = @($packageRecords | ForEach-Object { Select-PackageStateOwnershipRecord -Record $_ })
        PackageFiles              = @($packageFileRecords | ForEach-Object { Select-PackageStatePackageFileRecord -Record $_ })
        Directories               = $directories
    }
}
