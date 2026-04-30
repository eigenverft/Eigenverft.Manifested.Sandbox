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

function Get-PackageStateConfig {
    [CmdletBinding()]
    param()

    $globalDocumentInfo = Read-PackageJsonDocument -Path (Get-PackageGlobalConfigPath)
    Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalDocumentInfo

    $packageGlobalConfig = $globalDocumentInfo.Document.package
    $applicationRootDirectory = Resolve-PackageApplicationRootDirectory -GlobalConfiguration $packageGlobalConfig
    $depotInventoryInfo = Get-PackageDepotInventoryInfo
    $sourceInventoryInfo = Get-PackageSourceInventoryInfo -ApplicationRootDirectory $applicationRootDirectory
    $effectiveAcquisitionEnvironment = Resolve-PackageEffectiveAcquisitionEnvironment -GlobalConfiguration $packageGlobalConfig -SourceInventoryInfo $sourceInventoryInfo -DepotInventoryInfo $depotInventoryInfo

    $preferredTargetInstallDirectory = if ($packageGlobalConfig.PSObject.Properties['preferredTargetInstallDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.preferredTargetInstallDirectory)) {
        Resolve-PackageConfiguredPath -PathValue ([string]$packageGlobalConfig.preferredTargetInstallDirectory) -ApplicationRootDirectory $applicationRootDirectory
    }
    else {
        Resolve-PackageConfiguredPath -PathValue 'Installed' -ApplicationRootDirectory $applicationRootDirectory
    }

    $packageStateIndexFilePath = if ($packageGlobalConfig.packageState.PSObject.Properties['indexFilePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.packageState.indexFilePath)) {
        Resolve-PackageConfiguredPath -PathValue ([string]$packageGlobalConfig.packageState.indexFilePath) -ApplicationRootDirectory $applicationRootDirectory
    }
    else {
        Resolve-PackageConfiguredPath -PathValue 'State\package-state-index.json' -ApplicationRootDirectory $applicationRootDirectory
    }

    $localRepositoryRoot = if ($packageGlobalConfig.PSObject.Properties['localRepositoryRoot'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.localRepositoryRoot)) {
        Resolve-PackageConfiguredPath -PathValue ([string]$packageGlobalConfig.localRepositoryRoot) -ApplicationRootDirectory $applicationRootDirectory
    }
    else {
        Resolve-PackageConfiguredPath -PathValue 'PackageRepositories' -ApplicationRootDirectory $applicationRootDirectory
    }

    return [pscustomobject]@{
        GlobalConfigurationPath             = $globalDocumentInfo.Path
        GlobalConfiguration                 = $packageGlobalConfig
        ApplicationRootDirectory            = $applicationRootDirectory
        LocalConfigurationPath              = Get-PackageLocalGlobalConfigPath
        LocalDepotInventoryPath             = Get-PackageLocalDepotInventoryPath
        DepotInventoryPath                  = $effectiveAcquisitionEnvironment.DepotInventoryPath
        DepotInventory                      = $depotInventoryInfo.Document
        DepotInventoryInfo                  = $depotInventoryInfo
        SourceInventoryPath                 = $effectiveAcquisitionEnvironment.SourceInventoryPath
        SourceInventory                     = $sourceInventoryInfo.Document
        SourceInventoryInfo                 = $sourceInventoryInfo
        EffectiveAcquisitionEnvironment     = $effectiveAcquisitionEnvironment
        PackageFileStagingRootDirectory       = $effectiveAcquisitionEnvironment.Stores.PackageFileStagingDirectory
        PackageInstallStageRootDirectory      = $effectiveAcquisitionEnvironment.Stores.PackageInstallStageDirectory
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

    $config = Get-PackageStateConfig
    $packageStateIndex = Get-PackagePackageStateIndex -PackageConfig $config
    $packageFileIndex = Get-PackagePackageFileIndex -PackageConfig $config
    $sourceInventoryInfo = $config.SourceInventoryInfo
    $depotInventoryInfo = $config.DepotInventoryInfo

    $directories = [pscustomobject]@{
        Installed           = Get-PackageStateDirectorySummary -Path $config.PreferredTargetInstallRootDirectory
        PackageFileStaging    = Get-PackageStateDirectorySummary -Path $config.PackageFileStagingRootDirectory
        PackageInstallStage   = Get-PackageStateDirectorySummary -Path $config.PackageInstallStageRootDirectory
        DefaultPackageDepot = Get-PackageStateDirectorySummary -Path $config.DefaultPackageDepotDirectory
        LocalRepositoryRoot = Get-PackageStateDirectorySummary -Path $config.LocalRepositoryRoot
    }

    if ($Raw.IsPresent) {
        return [pscustomobject]@{
            Config            = $config
            PackageStateIndex = $packageStateIndex
            PackageFileIndex  = $packageFileIndex
            DepotInventory    = $depotInventoryInfo
            SourceInventory   = $sourceInventoryInfo
            Directories       = $directories
        }
    }

    $localRoot = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$config.PackageStateIndexFilePath)) {
        $localRoot = Get-PackageRootFromStateIndexPath -PackageStateIndexFilePath $config.PackageStateIndexFilePath
    }

    $packageRecords = @($packageStateIndex.Records)
    $packageFileRecords = @($packageFileIndex.Records)

    return [pscustomobject]@{
        LocalRoot                 = $localRoot
        ApplicationRootDirectory  = $config.ApplicationRootDirectory
        LocalConfigurationPath    = $config.LocalConfigurationPath
        LocalConfigurationExists  = Test-PackageStateLeafPath -Path $config.LocalConfigurationPath
        LocalDepotInventoryPath   = $config.LocalDepotInventoryPath
        LocalDepotInventoryExists = Test-PackageStateLeafPath -Path $config.LocalDepotInventoryPath
        DepotInventoryPath        = $depotInventoryInfo.Path
        DepotInventoryExists      = [bool]$depotInventoryInfo.Exists
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

