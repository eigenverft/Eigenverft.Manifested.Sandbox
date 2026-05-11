<#
    Public package state command surface.
#>

function Get-PackageState {
    [CmdletBinding()]
    param(
        [switch]$Raw
    )

    $config = Get-PackageStateConfig
    $packageInventory = Get-PackageInventory -PackageConfig $config
    $operationHistory = Get-PackageOperationHistory -PackageConfig $config
    $sourceInventoryInfo = $config.SourceInventoryInfo
    $repositoryInventoryInfo = $config.RepositoryInventoryInfo
    $depotInventoryInfo = $config.DepotInventoryInfo

    $directories = [pscustomobject]@{
        Installed           = Get-PackageStateDirectorySummary -Path $config.PreferredTargetInstallRootDirectory
        PackageFileStaging  = Get-PackageStateDirectorySummary -Path $config.PackageFileStagingRootDirectory
        PackageInstallStage = Get-PackageStateDirectorySummary -Path $config.PackageInstallStageRootDirectory
        DefaultPackageDepot = Get-PackageStateDirectorySummary -Path $config.DefaultPackageDepotDirectory
        LocalRepositoryRoot = Get-PackageStateDirectorySummary -Path $config.LocalRepositoryRoot
        Shims               = Get-PackageStateDirectorySummary -Path $config.ShimDirectory
    }

    if ($Raw.IsPresent) {
        return [pscustomobject]@{
            Config           = $config
            PackageInventory = $packageInventory
            OperationHistory = $operationHistory
            RepositoryInventory = $repositoryInventoryInfo
            DepotInventory   = $depotInventoryInfo
            SourceInventory  = $sourceInventoryInfo
            Directories      = $directories
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
        LocalRepositoryInventoryPath = $config.LocalRepositoryInventoryPath
        LocalRepositoryInventoryExists = Test-PackageStateLeafPath -Path $config.LocalRepositoryInventoryPath
        RepositoryInventoryPath    = $repositoryInventoryInfo.Path
        RepositoryInventoryExists  = [bool]$repositoryInventoryInfo.Exists
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
