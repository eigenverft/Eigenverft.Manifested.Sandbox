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

    $pathRegistration = $null
    if ($Record.PSObject.Properties['pathRegistration'] -and $null -ne $Record.pathRegistration) {
        $sourcePath = [string]$Record.pathRegistration.sourcePath
        $registeredPath = [string]$Record.pathRegistration.registeredPath
        $registeredPathExists = $false
        if (-not [string]::IsNullOrWhiteSpace($registeredPath)) {
            $registeredPathExists = Test-Path -LiteralPath $registeredPath -PathType Container
        }

        $pathRegistration = [pscustomobject]@{
            Mode                 = $Record.pathRegistration.mode
            SourceKind           = $Record.pathRegistration.sourceKind
            SourceValue          = $Record.pathRegistration.sourceValue
            SourceValues         = @($Record.pathRegistration.sourceValues)
            SourcePath           = $sourcePath
            SourcePathExists     = Test-PackageStateLeafPath -Path $sourcePath
            RegisteredPath       = $registeredPath
            RegisteredPathExists = $registeredPathExists
            Status               = $Record.pathRegistration.status
        }
    }

    $dependencyInstallSlotIds = if ($Record.PSObject.Properties['dependencyInstallSlotIds'] -and $null -ne $Record.dependencyInstallSlotIds) {
        @($Record.dependencyInstallSlotIds | ForEach-Object { [string]$_ })
    }
    else {
        @()
    }

    return [pscustomobject]@{
        InstallSlotId          = $Record.installSlotId
        DefinitionId           = $Record.definitionId
        DefinitionRepositoryId = $Record.definitionRepositoryId
        DefinitionFileName     = $Record.definitionFileName
        DefinitionLocalPath    = $Record.definitionLocalPath
        DefinitionLocalExists  = Test-PackageStateLeafPath -Path ([string]$Record.definitionLocalPath)
        ReleaseTrack           = $Record.releaseTrack
        ArtifactDistributionVariant = $Record.artifactDistributionVariant
        CurrentReleaseId       = $Record.currentReleaseId
        CurrentVersion         = $Record.currentVersion
        InstallDirectory       = $installDirectory
        InstallDirectoryExists = $installDirectoryExists
        OwnershipKind          = $Record.ownershipKind
        PathRegistration       = $pathRegistration
        DependencyInstallSlotIds = @($dependencyInstallSlotIds)
        UpdatedAtUtc           = $Record.updatedAtUtc
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

    $packageInventoryFilePath = if ($packageGlobalConfig.packageState.PSObject.Properties['inventoryFilePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.packageState.inventoryFilePath)) {
        Resolve-PackageConfiguredPath -PathValue ([string]$packageGlobalConfig.packageState.inventoryFilePath) -ApplicationRootDirectory $applicationRootDirectory
    }
    else {
        Resolve-PackageConfiguredPath -PathValue 'State\package-inventory.json' -ApplicationRootDirectory $applicationRootDirectory
    }

    $packageOperationHistoryFilePath = if ($packageGlobalConfig.packageState.PSObject.Properties['operationHistoryFilePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.packageState.operationHistoryFilePath)) {
        Resolve-PackageConfiguredPath -PathValue ([string]$packageGlobalConfig.packageState.operationHistoryFilePath) -ApplicationRootDirectory $applicationRootDirectory
    }
    else {
        Resolve-PackageConfiguredPath -PathValue 'State\package-operation-history.json' -ApplicationRootDirectory $applicationRootDirectory
    }

    $localRepositoryRoot = if ($packageGlobalConfig.PSObject.Properties['localRepositoryRoot'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.localRepositoryRoot)) {
        Resolve-PackageConfiguredPath -PathValue ([string]$packageGlobalConfig.localRepositoryRoot) -ApplicationRootDirectory $applicationRootDirectory
    }
    else {
        Resolve-PackageConfiguredPath -PathValue 'PackageRepositories' -ApplicationRootDirectory $applicationRootDirectory
    }

    $shimDirectory = if ($packageGlobalConfig.PSObject.Properties['shimDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$packageGlobalConfig.shimDirectory)) {
        Resolve-PackageConfiguredPath -PathValue ([string]$packageGlobalConfig.shimDirectory) -ApplicationRootDirectory $applicationRootDirectory
    }
    else {
        Resolve-PackageConfiguredPath -PathValue 'Shims' -ApplicationRootDirectory $applicationRootDirectory
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
        ShimDirectory                       = $shimDirectory
        PackageInventoryFilePath            = $packageInventoryFilePath
        PackageOperationHistoryFilePath     = $packageOperationHistoryFilePath
        EnvironmentSources                  = $effectiveAcquisitionEnvironment.EnvironmentSources
    }
}

function Get-PackageState {
    [CmdletBinding()]
    param(
        [switch]$Raw
    )

    $config = Get-PackageStateConfig
    $packageInventory = Get-PackageInventory -PackageConfig $config
    $operationHistory = Get-PackageOperationHistory -PackageConfig $config
    $sourceInventoryInfo = $config.SourceInventoryInfo
    $depotInventoryInfo = $config.DepotInventoryInfo

    $directories = [pscustomobject]@{
        Installed           = Get-PackageStateDirectorySummary -Path $config.PreferredTargetInstallRootDirectory
        PackageFileStaging    = Get-PackageStateDirectorySummary -Path $config.PackageFileStagingRootDirectory
        PackageInstallStage   = Get-PackageStateDirectorySummary -Path $config.PackageInstallStageRootDirectory
        DefaultPackageDepot = Get-PackageStateDirectorySummary -Path $config.DefaultPackageDepotDirectory
        LocalRepositoryRoot = Get-PackageStateDirectorySummary -Path $config.LocalRepositoryRoot
        Shims               = Get-PackageStateDirectorySummary -Path $config.ShimDirectory
    }

    if ($Raw.IsPresent) {
        return [pscustomobject]@{
            Config            = $config
            PackageInventory  = $packageInventory
            OperationHistory  = $operationHistory
            DepotInventory    = $depotInventoryInfo
            SourceInventory   = $sourceInventoryInfo
            Directories       = $directories
        }
    }

    $localRoot = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$config.PackageInventoryFilePath)) {
        $localRoot = Get-PackageRootFromInventoryPath -PackageInventoryFilePath $config.PackageInventoryFilePath
    }

    $packageRecords = @($packageInventory.Records)
    $operationRecords = @($operationHistory.Records)

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
        PackageInventoryPath      = $packageInventory.Path
        PackageInventoryExists    = Test-PackageStateLeafPath -Path $packageInventory.Path
        OperationHistoryPath      = $operationHistory.Path
        OperationHistoryExists    = Test-PackageStateLeafPath -Path $operationHistory.Path
        SourceInventoryPath       = $sourceInventoryInfo.Path
        SourceInventoryExists     = [bool]$sourceInventoryInfo.Exists
        PackageRecordCount        = $packageRecords.Count
        OperationRecordCount      = $operationRecords.Count
        PackageRecords            = @($packageRecords | ForEach-Object { Select-PackageStateOwnershipRecord -Record $_ })
        OperationRecords          = @($operationRecords)
        Directories               = $directories
    }
}
