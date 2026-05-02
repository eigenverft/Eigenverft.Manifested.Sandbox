<#
    Eigenverft.Manifested.Sandbox Package - config and definitions
#>

. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.Module.TestHelpers.ps1"

Invoke-TestPackageDescribe -Name 'Eigenverft.Manifested.Sandbox Package - config and definitions' -Body {
    It 'loads the shipped global config without baked-in environment sources' {
        $globalInfo = Read-PackageJsonDocument -Path (Get-PackageShippedGlobalConfigPath)

        $globalInfo.Document.package.PSObject.Properties.Name | Should -Contain 'preferredTargetInstallDirectory'
        $globalInfo.Document.package.PSObject.Properties.Name | Should -Contain 'applicationRootDirectory'
        $globalInfo.Document.package.PSObject.Properties.Name | Should -Contain 'repositorySources'
        $globalInfo.Document.package.PSObject.Properties.Name | Should -Contain 'localRepositoryRoot'
        $globalInfo.Document.package.PSObject.Properties.Name | Should -Contain 'layout'
        $globalInfo.Document.package.layout.packageDepotRelativePath | Should -Be '{definitionId}/{releaseTrack}/{version}/{flavor}'
        $globalInfo.Document.package.layout.packageWorkSlotDirectory | Should -Be '{definitionId}-{slotHash}'
        $globalInfo.Document.package.PSObject.Properties.Name | Should -Contain 'packageState'
        $globalInfo.Document.package.acquisitionEnvironment.stores.PSObject.Properties.Name | Should -Contain 'packageFileStagingDirectory'
        $globalInfo.Document.package.acquisitionEnvironment.stores.PSObject.Properties.Name | Should -Contain 'packageInstallStageDirectory'
        $globalInfo.Document.package.acquisitionEnvironment.stores.packageFileStagingDirectory | Should -Be '{applicationRootDirectory}/FileStage'
        $globalInfo.Document.package.acquisitionEnvironment.stores.packageInstallStageDirectory | Should -Be '{applicationRootDirectory}/InstStage'
        $globalInfo.Document.package.acquisitionEnvironment.stores.PSObject.Properties.Name | Should -Not -Contain 'defaultPackageDepotDirectory'
        $globalInfo.Document.package.acquisitionEnvironment.defaults.PSObject.Properties.Name | Should -Contain 'allowFallback'
        $globalInfo.Document.package.acquisitionEnvironment.defaults.PSObject.Properties.Name | Should -Not -Contain 'mirrorDownloadedArtifactsToDefaultPackageDepot'
        $depotInfo = Read-PackageJsonDocument -Path (Get-PackageShippedDepotInventoryPath)
        $depotInfo.Document.acquisitionEnvironment.environmentSources.PSObject.Properties.Name | Should -Contain 'defaultPackageDepot'
        $depotInfo.Document.acquisitionEnvironment.environmentSources.defaultPackageDepot.readable | Should -BeTrue
        $depotInfo.Document.acquisitionEnvironment.environmentSources.defaultPackageDepot.writable | Should -BeTrue
        $depotInfo.Document.acquisitionEnvironment.environmentSources.defaultPackageDepot.mirrorTarget | Should -BeTrue
        $depotInfo.Document.acquisitionEnvironment.environmentSources.defaultPackageDepot.ensureExists | Should -BeTrue
        $depotInfo.Document.acquisitionEnvironment.environmentSources.defaultPackageDepot.basePath | Should -Be '{applicationRootDirectory}/DefaultPackageDepot'
        $globalInfo.Document.package.acquisitionEnvironment.tracking.PSObject.Properties.Name | Should -Contain 'packageFileIndexFilePath'
        $globalInfo.Document.package.acquisitionEnvironment.PSObject.Properties['environmentSources'] | Should -BeNullOrEmpty
    }

    It 'resolves the bootstrap local root from shipped Config.json' {
        $rootPath = Join-Path $TestDrive 'bootstrap-root-config'
        $applicationRootPath = Join-Path $rootPath 'AppRoot'
        $shippedConfigPath = Join-Path $rootPath 'Configuration\Internal\Config.json'
        Write-TestJsonDocument -Path $shippedConfigPath -Document (New-TestPackageGlobalDocument -ApplicationRootDirectory $applicationRootPath)
        Mock Get-PackageShippedGlobalConfigPath { $shippedConfigPath }

        Get-PackageLocalRoot | Should -Be ([System.IO.Path]::GetFullPath($applicationRootPath))
    }

    It 'fails clearly when shipped Config.json cannot provide an absolute bootstrap root' {
        $missingRootConfigPath = Join-Path $TestDrive 'missing-root\Config.json'
        Write-TestJsonDocument -Path $missingRootConfigPath -Document @{ package = @{} }
        $mockShippedConfigPath = $missingRootConfigPath
        Mock Get-PackageShippedGlobalConfigPath { $mockShippedConfigPath }

        { Get-PackageLocalRoot } | Should -Throw '*must define package.applicationRootDirectory*'

        $relativeRootConfigPath = Join-Path $TestDrive 'relative-root\Config.json'
        Write-TestJsonDocument -Path $relativeRootConfigPath -Document (New-TestPackageGlobalDocument -ApplicationRootDirectory 'relative-root')
        $mockShippedConfigPath = $relativeRootConfigPath

        { Get-PackageLocalRoot } | Should -Throw '*does not resolve to an absolute path*'
    }

    It 'creates the local Config.json copy from shipped configuration when missing' {
        $localGlobalPath = Get-PackageLocalGlobalConfigPath
        if (Test-Path -LiteralPath $localGlobalPath -PathType Leaf) {
            Remove-Item -LiteralPath $localGlobalPath -Force
        }

        $activeGlobalPath = Get-PackageGlobalConfigPath
        $localInfo = Read-PackageJsonDocument -Path $localGlobalPath

        $activeGlobalPath | Should -Be $localGlobalPath
        Test-Path -LiteralPath $localGlobalPath -PathType Leaf | Should -BeTrue
        $localInfo.Document.package.repositorySources.EigenverftModule.kind | Should -Be 'moduleLocal'
    }

    It 'resolves package config paths from applicationRootDirectory and supports missing applicationRootDirectory fallback' {
        $rootPath = Join-Path $TestDrive 'application-root-config'
        $applicationRootPath = Join-Path $rootPath 'AppRoot'
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory $applicationRootPath
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @(
            New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                @{
                    kind        = 'packageDepot'
                    searchOrder = 10
                }
            )
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument $definitionDocument

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'

        $config.ApplicationRootDirectory | Should -Be ([System.IO.Path]::GetFullPath($applicationRootPath))
        $config.PreferredTargetInstallRootDirectory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $applicationRootPath 'Installed')))
        $config.PackageFileStagingRootDirectory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $applicationRootPath 'FileStage')))
        $config.PackageInstallStageRootDirectory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $applicationRootPath 'InstStage')))
        $config.DefaultPackageDepotDirectory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $applicationRootPath 'DefaultPackageDepot')))
        $config.LocalRepositoryRoot | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $applicationRootPath 'PackageRepositories')))

        $fallbackRootPath = Join-Path $TestDrive 'application-root-fallback'
        $fallbackGlobalDocument = New-TestPackageGlobalDocument
        $fallbackGlobalDocument.package.Remove('applicationRootDirectory')
        $fallbackDocuments = Write-TestPackageDocuments -RootPath $fallbackRootPath -GlobalDocument $fallbackGlobalDocument -DefinitionDocument $definitionDocument
        Mock Get-PackageGlobalConfigPath { $fallbackDocuments.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $fallbackDocuments.DefinitionPath }

        $fallbackConfig = Get-PackageConfig -DefinitionId 'VSCodeRuntime'

        $fallbackConfig.ApplicationRootDirectory | Should -Be (Get-PackageDefaultApplicationRootDirectory)
        $fallbackConfig.PackageFileStagingRootDirectory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path (Get-PackageDefaultApplicationRootDirectory) 'FileStage')))
    }

    It 'resolves absolute configured paths without joining them under applicationRootDirectory' {
        $rootPath = Join-Path $TestDrive 'absolute-config-paths'
        $applicationRootPath = Join-Path $rootPath 'AppRoot'
        $absoluteInstallPath = Join-Path $rootPath 'AbsoluteInstalled'
        $absoluteFileStagingPath = Join-Path $rootPath 'AbsoluteFileStaging'
        $absoluteInstallStagingPath = Join-Path $rootPath 'AbsoluteInstallStaging'
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory $applicationRootPath -PreferredTargetInstallDirectory $absoluteInstallPath -PackageFileStagingDirectory $absoluteFileStagingPath -PackageInstallStageDirectory $absoluteInstallStagingPath
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @(
            New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                @{
                    kind        = 'packageDepot'
                    searchOrder = 10
                }
            )
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument $definitionDocument

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'

        $config.PreferredTargetInstallRootDirectory | Should -Be ([System.IO.Path]::GetFullPath($absoluteInstallPath))
        $config.PackageFileStagingRootDirectory | Should -Be ([System.IO.Path]::GetFullPath($absoluteFileStagingPath))
        $config.PackageInstallStageRootDirectory | Should -Be ([System.IO.Path]::GetFullPath($absoluteInstallStagingPath))
    }

    It 'creates the local DepotInventory.json copy from shipped configuration when missing' {
        $localDepotInventoryPath = Get-PackageLocalDepotInventoryPath
        if (Test-Path -LiteralPath $localDepotInventoryPath -PathType Leaf) {
            Remove-Item -LiteralPath $localDepotInventoryPath -Force
        }

        $activeDepotInventoryPath = Get-PackageDepotInventoryPath
        $localInfo = Read-PackageJsonDocument -Path $localDepotInventoryPath

        $activeDepotInventoryPath | Should -Be $localDepotInventoryPath
        Test-Path -LiteralPath $localDepotInventoryPath -PathType Leaf | Should -BeTrue
        $localInfo.Document.acquisitionEnvironment.environmentSources.defaultPackageDepot.enabled | Should -BeTrue
    }

    It 'initializes the local package environment once and creates only eligible depot roots' {
        $rootPath = Join-Path $TestDrive 'local-environment-init'
        $applicationRootPath = Join-Path $rootPath 'AppRoot'
        $defaultDepotPath = Join-Path $rootPath 'DefaultPackageDepot'
        $readOnlyDepotPath = Join-Path $rootPath 'ReadOnlyPackageDepot'
        $disabledDepotPath = Join-Path $rootPath 'DisabledPackageDepot'
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory $applicationRootPath
        $depotInventory = New-TestDepotInventoryDocument -DefaultPackageDepotDirectory $defaultDepotPath -EnvironmentSources @{
            readOnlyPackageDepot = @{
                kind         = 'filesystem'
                enabled      = $true
                searchOrder  = 400
                basePath     = $readOnlyDepotPath
                readable     = $true
                writable     = $false
                mirrorTarget = $false
                ensureExists = $false
            }
            disabledPackageDepot = @{
                kind         = 'filesystem'
                enabled      = $false
                searchOrder  = 500
                basePath     = $disabledDepotPath
                readable     = $true
                writable     = $true
                mirrorTarget = $true
                ensureExists = $true
            }
        }
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @(
            New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                @{
                    kind        = 'packageDepot'
                    searchOrder = 10
                }
            )
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DepotInventoryDocument $depotInventory -DefinitionDocument $definitionDocument

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $environment = Initialize-PackageLocalEnvironment -PackageConfig $config
        $markerPath = Join-Path (Join-Path $applicationRootPath 'State') 'package-local-environment.json'
        $localConfigDirectory = Split-Path -Parent (Get-PackageLocalGlobalConfigPath)
        $localDepotInventoryDirectory = Split-Path -Parent (Get-PackageLocalDepotInventoryPath)

        $environment.Status | Should -Be 'Initialized'
        $environment.InitializedNow | Should -BeTrue
        $environment.MarkerPath | Should -Be ([System.IO.Path]::GetFullPath($markerPath))
        Test-Path -LiteralPath $markerPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $applicationRootPath -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $localConfigDirectory -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $localDepotInventoryDirectory -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Join-Path $applicationRootPath 'Configuration') 'External') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $applicationRootPath 'Installed') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $applicationRootPath 'FileStage') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $applicationRootPath 'InstStage') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $applicationRootPath 'PackageRepositories') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Join-Path $applicationRootPath 'Caches') 'npm') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $defaultDepotPath -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $readOnlyDepotPath -PathType Container | Should -BeFalse
        Test-Path -LiteralPath $disabledDepotPath -PathType Container | Should -BeFalse
        @($environment.SkippedSources | Where-Object { $_.SourceId -eq 'readOnlyPackageDepot' }).Count | Should -Be 1
    }

    It 'skips all directory verification when the local environment marker already exists' {
        $rootPath = Join-Path $TestDrive 'local-environment-marker-skip'
        $applicationRootPath = Join-Path $rootPath 'AppRoot'
        $markerPath = Join-Path (Join-Path $applicationRootPath 'State') 'package-local-environment.json'
        Write-TestJsonDocument -Path $markerPath -Document @{
            schemaVersion = 1
            initializedAtUtc = [DateTime]::UtcNow.ToString('o')
            applicationRootDirectory = $applicationRootPath
            directoryVersion = 1
        }
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory $applicationRootPath
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @(
            New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                @{
                    kind        = 'packageDepot'
                    searchOrder = 10
                }
            )
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument $definitionDocument

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $environment = Initialize-PackageLocalEnvironment -PackageConfig $config

        $environment.Status | Should -Be 'AlreadyInitialized'
        $environment.InitializedNow | Should -BeFalse
        @($environment.CreatedDirectories).Count | Should -Be 0
        @($environment.ExistingDirectories).Count | Should -Be 0
        @($environment.SkippedSources).Count | Should -Be 0
        Test-Path -LiteralPath $config.LocalRepositoryRoot -PathType Container | Should -BeFalse
        Test-Path -LiteralPath $config.DefaultPackageDepotDirectory -PathType Container | Should -BeFalse
    }

    It 'reports local environment initialization failures through the package command result' {
        $rootPath = Join-Path $TestDrive 'local-environment-command-failure'
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory (Join-Path $rootPath 'AppRoot')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @(
            New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                @{
                    kind        = 'packageDepot'
                    searchOrder = 10
                }
            )
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument $definitionDocument

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }
        Mock Initialize-PackageLocalEnvironment { throw 'local environment boom' }

        $result = Invoke-PackageDefinitionCommandCore -DefinitionId 'VSCodeRuntime'

        $result.Status | Should -Be 'Failed'
        $result.FailureReason | Should -Be 'LocalEnvironmentInitializationFailed'
        $result.ErrorMessage | Should -Be 'local environment boom'
    }

    It 'runs the public package definition command with default repository and assigned state' {
        Mock Invoke-PackageDefinitionCommandCore {
            [pscustomobject]@{
                RepositoryId = $RepositoryId
                DefinitionId = $DefinitionId
                DesiredState = $DesiredState
                Status       = 'Ready'
            }
        }

        $result = Invoke-PackageDefinitionCommand -DefinitionId 'GitHubCli'

        Assert-MockCalled Invoke-PackageDefinitionCommandCore -Times 1 -ParameterFilter {
            $RepositoryId -eq 'EigenverftModule' -and
            $DefinitionId -eq 'GitHubCli' -and
            $DesiredState -eq 'Assigned'
        }
        $result.Status | Should -Be 'Ready'
    }

    It 'runs the slim public package command with default repository and assigned state' {
        Mock Invoke-PackageDefinitionCommandCore {
            [pscustomobject]@{
                RepositoryId = $RepositoryId
                DefinitionId = $DefinitionId
                DesiredState = $DesiredState
                Status       = 'Ready'
            }
        }

        $result = Invoke-Package -DefinitionId 'GitHubCli'

        Assert-MockCalled Invoke-PackageDefinitionCommandCore -Times 1 -ParameterFilter {
            $RepositoryId -eq 'EigenverftModule' -and
            $DefinitionId -eq 'GitHubCli' -and
            $DesiredState -eq 'Assigned'
        }
        $result.Status | Should -Be 'Ready'
    }

    It 'runs public package definition command arrays in listed order' {
        Mock Invoke-PackageDefinitionCommandCore {
            [pscustomobject]@{
                RepositoryId = $RepositoryId
                DefinitionId = $DefinitionId
                DesiredState = $DesiredState
                Status       = 'Ready'
            }
        }

        $results = @(Invoke-PackageDefinitionCommand -DefinitionId GitHubCli, CodexCli)

        Assert-MockCalled Invoke-PackageDefinitionCommandCore -Times 1 -ParameterFilter { $DefinitionId -eq 'GitHubCli' }
        Assert-MockCalled Invoke-PackageDefinitionCommandCore -Times 1 -ParameterFilter { $DefinitionId -eq 'CodexCli' }
        @($results.DefinitionId) | Should -Be @('GitHubCli', 'CodexCli')
    }

    It 'stops public package definition command arrays after the first failed result' {
        Mock Invoke-PackageDefinitionCommandCore {
            [pscustomobject]@{
                RepositoryId = $RepositoryId
                DefinitionId = $DefinitionId
                DesiredState = $DesiredState
                Status       = if ($DefinitionId -eq 'GitHubCli') { 'Failed' } else { 'Ready' }
            }
        }

        $results = @(Invoke-PackageDefinitionCommand -DefinitionId GitHubCli, CodexCli)

        Assert-MockCalled Invoke-PackageDefinitionCommandCore -Times 1 -ParameterFilter { $DefinitionId -eq 'GitHubCli' }
        Assert-MockCalled Invoke-PackageDefinitionCommandCore -Times 0 -ParameterFilter { $DefinitionId -eq 'CodexCli' }
        @($results.DefinitionId) | Should -Be @('GitHubCli')
        $results[0].Status | Should -Be 'Failed'
    }

    It 'resolves shipped package definitions through the default repository seam' {
        $reference = Resolve-PackageDefinitionReference -DefinitionId 'VSCodeRuntime'

        $reference.RepositoryId | Should -Be 'EigenverftModule'
        $reference.DefinitionId | Should -Be 'VSCodeRuntime'
        $reference.SourceKind | Should -Be 'moduleLocal'
        Split-Path -Leaf $reference.DefinitionPath | Should -Be 'VSCodeRuntime.json'
    }

    It 'fails clearly for unsupported package repositories' {
        { Resolve-PackageDefinitionReference -RepositoryId 'OtherRepository' -DefinitionId 'VSCodeRuntime' } | Should -Throw "*Only 'EigenverftModule' is currently supported*"
    }

    It 'returns a clean not-implemented result for removed desired state' {
        $rootPath = Join-Path $TestDrive 'removed-state-not-implemented'
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory (Join-Path $rootPath 'AppRoot')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @(
            New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                @{
                    kind        = 'packageDepot'
                    searchOrder = 10
                }
            )
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument $definitionDocument

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $result = Invoke-PackageDefinitionCommand -DefinitionId 'VSCodeRuntime' -DesiredState Removed

        $result.RepositoryId | Should -Be 'EigenverftModule'
        $result.DesiredState | Should -Be 'Removed'
        $result.Status | Should -Be 'Failed'
        $result.FailureReason | Should -Be 'PackageDesiredStateNotImplemented'
        $result.ErrorMessage | Should -Match "DesiredState 'Removed' is not implemented"
    }

    It 'fails clearly when global config still uses retired ownershipTracking' {
        $globalConfigPath = Join-Path $TestDrive 'Global-old-ownership.json'
        $badGlobal = New-TestPackageGlobalDocument
        $badGlobal.package.ownershipTracking = @{
            indexFilePath = Join-Path $TestDrive 'ownership-index.json'
        }
        Write-TestJsonDocument -Path $globalConfigPath -Document $badGlobal

        $globalInfo = Read-PackageJsonDocument -Path $globalConfigPath
        { Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalInfo } | Should -Throw '*ownershipTracking*'
    }

    It 'fails clearly when global config still uses retired artifactIndexFilePath' {
        $globalConfigPath = Join-Path $TestDrive 'Global-old-artifact.json'
        $badGlobal = New-TestPackageGlobalDocument
        $badGlobal.package.acquisitionEnvironment.tracking.Remove('packageFileIndexFilePath')
        $badGlobal.package.acquisitionEnvironment.tracking.artifactIndexFilePath = Join-Path $TestDrive 'artifact-index.json'
        Write-TestJsonDocument -Path $globalConfigPath -Document $badGlobal

        $globalInfo = Read-PackageJsonDocument -Path $globalConfigPath
        { Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalInfo } | Should -Throw '*artifactIndexFilePath*'
    }

    It 'fails clearly when global config still uses retired installWorkspaceDirectory' {
        $globalConfigPath = Join-Path $TestDrive 'Global-old-install-workspace.json'
        $badGlobal = New-TestPackageGlobalDocument
        $badGlobal.package.acquisitionEnvironment.stores.Remove('packageFileStagingDirectory')
        $badGlobal.package.acquisitionEnvironment.stores.installWorkspaceDirectory = Join-Path $TestDrive 'InstallWorkspace'
        Write-TestJsonDocument -Path $globalConfigPath -Document $badGlobal

        $globalInfo = Read-PackageJsonDocument -Path $globalConfigPath
        { Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalInfo } | Should -Throw '*installWorkspaceDirectory*'
    }

    It 'fails clearly when global config still uses retired installPreparationDirectory' {
        $globalConfigPath = Join-Path $TestDrive 'Global-old-install-preparation.json'
        $badGlobal = New-TestPackageGlobalDocument
        $badGlobal.package.acquisitionEnvironment.stores.Remove('packageFileStagingDirectory')
        $badGlobal.package.acquisitionEnvironment.stores.Remove('packageInstallStageDirectory')
        $badGlobal.package.acquisitionEnvironment.stores.installPreparationDirectory = Join-Path $TestDrive 'InstallPreparation'
        Write-TestJsonDocument -Path $globalConfigPath -Document $badGlobal

        $globalInfo = Read-PackageJsonDocument -Path $globalConfigPath
        { Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalInfo } | Should -Throw '*installPreparationDirectory*'
    }

    It 'fails clearly when global config still uses retired mirrorDownloadedArtifactsToDefaultPackageDepot' {
        $globalConfigPath = Join-Path $TestDrive 'Global-old-mirror-default.json'
        $badGlobal = New-TestPackageGlobalDocument
        $badGlobal.package.acquisitionEnvironment.defaults.mirrorDownloadedArtifactsToDefaultPackageDepot = $true
        Write-TestJsonDocument -Path $globalConfigPath -Document $badGlobal

        $globalInfo = Read-PackageJsonDocument -Path $globalConfigPath
        { Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalInfo } | Should -Throw '*mirrorDownloadedArtifactsToDefaultPackageDepot*'
    }

    It 'rejects filesystem depot inventory entries without explicit capability fields' {
        $depotInventoryPath = Join-Path $TestDrive 'DepotInventory-missing-capability.json'
        $badDepotInventory = New-TestDepotInventoryDocument
        $badDepotInventory.acquisitionEnvironment.environmentSources.defaultPackageDepot.Remove('readable')
        Write-TestJsonDocument -Path $depotInventoryPath -Document $badDepotInventory

        $depotInfo = Read-PackageJsonDocument -Path $depotInventoryPath
        { Assert-PackageDepotInventorySchema -DepotInventoryDocumentInfo $depotInfo } | Should -Throw '*readable*'
    }

    It 'rejects depot inventory mirror and ensure flags when a filesystem depot is not writable' {
        $depotInventoryPath = Join-Path $TestDrive 'DepotInventory-invalid-capabilities.json'
        $badDepotInventory = New-TestDepotInventoryDocument
        $badDepotInventory.acquisitionEnvironment.environmentSources.defaultPackageDepot.writable = $false
        $badDepotInventory.acquisitionEnvironment.environmentSources.defaultPackageDepot.mirrorTarget = $true
        $badDepotInventory.acquisitionEnvironment.environmentSources.defaultPackageDepot.ensureExists = $true
        Write-TestJsonDocument -Path $depotInventoryPath -Document $badDepotInventory

        $depotInfo = Read-PackageJsonDocument -Path $depotInventoryPath
        { Assert-PackageDepotInventorySchema -DepotInventoryDocumentInfo $depotInfo } | Should -Throw '*mirrorTarget=true*'

        $badDepotInventory.acquisitionEnvironment.environmentSources.defaultPackageDepot.mirrorTarget = $false
        Write-TestJsonDocument -Path $depotInventoryPath -Document $badDepotInventory
        $depotInfo = Read-PackageJsonDocument -Path $depotInventoryPath
        { Assert-PackageDepotInventorySchema -DepotInventoryDocumentInfo $depotInfo } | Should -Throw '*ensureExists=true*'
    }

    It 'loads the shipped LlamaCppRuntime definition and selects the fixed GitHub-backed release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageConfig -DefinitionId 'LlamaCppRuntime'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'llamaCppGitHub' })

        $config.DefinitionId | Should -Be 'LlamaCppRuntime'
        @($config.Definition.dependencies.definitionId) | Should -Be @('VisualCppRedistributable')
        @($config.Definition.dependencies.repositoryId) | Should -Be @('EigenverftModule')
        $sourceDefinition.Kind | Should -Be 'githubRelease'
        $sourceDefinition.RepositoryOwner | Should -Be 'ggml-org'
        $sourceDefinition.RepositoryName | Should -Be 'llama.cpp'
        $result.PackageId | Should -Be 'llama-cpp-win-cpu-x64-stable'
        $result.Package.version | Should -Be '8863'
        $result.Package.releaseTag | Should -Be 'b8863'
        $result.Package.packageFile.fileName | Should -Be 'llama-b8863-bin-win-cpu-x64.zip'
    }

    It 'loads the shipped GitRuntime definition and selects the fixed GitHub-backed release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageConfig -DefinitionId 'GitRuntime'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'gitForWindowsGitHub' })

        $expectedFileName = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            'MinGit-2.54.0-arm64.zip'
        }
        else {
            'MinGit-2.54.0-64-bit.zip'
        }
        $expectedSha256 = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            '68f6bdda5b58f4e40f431c0da48b05ba5596445314d5e491e7b4aebb1ec2e985'
        }
        else {
            '04f937e1f0918b17b9be6f2294cb2bb66e96e1d9832d1c298e2de088a1d0e668'
        }

        $config.DefinitionId | Should -Be 'GitRuntime'
        $sourceDefinition.Kind | Should -Be 'githubRelease'
        $sourceDefinition.RepositoryOwner | Should -Be 'git-for-windows'
        $sourceDefinition.RepositoryName | Should -Be 'git'
        $result.Package.version | Should -Be '2.54.0'
        $result.Package.releaseTag | Should -Be 'v2.54.0.windows.1'
        $result.Package.packageFile.fileName | Should -Be $expectedFileName
        $result.Package.packageFile.contentHash.value | Should -Be $expectedSha256
        $result.Package.install.pathRegistration.source.value | Should -Be 'git'
    }

    It 'loads the shipped GitHubCli definition and selects the fixed GitHub-backed release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageConfig -DefinitionId 'GitHubCli'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'ghCliGitHub' })

        $expectedFileName = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            'gh_2.91.0_windows_arm64.zip'
        }
        else {
            'gh_2.91.0_windows_amd64.zip'
        }
        $expectedSha256 = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            'ae0333d2f9b13fc28f785ca7379514f9a1cea382cd4726abb6e6f4d2a874dd15'
        }
        else {
            'ced3e6f4bb5a9865056b594b7ad0cf42137dc92c494346f1ca705b5dbf14c88e'
        }

        $config.DefinitionId | Should -Be 'GitHubCli'
        $sourceDefinition.Kind | Should -Be 'githubRelease'
        $sourceDefinition.RepositoryOwner | Should -Be 'cli'
        $sourceDefinition.RepositoryName | Should -Be 'cli'
        $result.Package.version | Should -Be '2.91.0'
        $result.Package.releaseTag | Should -Be 'v2.91.0'
        $result.Package.packageFile.fileName | Should -Be $expectedFileName
        $result.Package.packageFile.contentHash.value | Should -Be $expectedSha256
        $result.Package.install.pathRegistration.source.value | Should -Be 'gh'
    }

    It 'loads the shipped NotepadPlusPlus definition and selects the fixed NSIS installer release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageConfig -DefinitionId 'NotepadPlusPlus'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'notepadPlusPlusGitHubRelease' })

        $expectedFileName = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            'npp.8.9.4.Installer.arm64.exe'
        }
        else {
            'npp.8.9.4.Installer.x64.exe'
        }
        $expectedSha256 = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            '7d59f0c62caa4d2366f900ca8169fb37cf1dcfce5c79cb3ccb08089b1adbc91'
        }
        else {
            'f3629f500d0754d8e870255fff0e00384a37f5402d6f3ad8dd1f4f67d707b593'
        }

        $config.DefinitionId | Should -Be 'NotepadPlusPlus'
        $sourceDefinition.Kind | Should -Be 'download'
        $sourceDefinition.BaseUri | Should -Be 'https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.4/'
        $result.Package.version | Should -Be '8.9.4'
        $result.Package.install.kind | Should -Be 'nsisInstaller'
        $result.Package.install.targetDirectoryArgument.prefix | Should -Be '/D='
        $result.Package.existingInstallDiscovery.searchLocations[0].kind | Should -Be 'windowsUninstallRegistryKey'
        $result.Package.existingInstallDiscovery.searchLocations[0].installDirectorySource | Should -Be 'displayIconDirectory'
        $result.Package.packageFile.fileName | Should -Be $expectedFileName
        $result.Package.packageFile.contentHash.value | Should -Be $expectedSha256
    }

    It 'loads the shipped NodeRuntime definition and selects the fixed Node.js archive release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageConfig -DefinitionId 'NodeRuntime'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'nodeJsRelease' })

        $expectedFileName = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            'node-v24.15.0-win-arm64.zip'
        }
        else {
            'node-v24.15.0-win-x64.zip'
        }
        $expectedSha256 = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            'c9eb7402eda26e2ba7e44b6727fc85a8de56c5095b1f71ebd3062892211aa116'
        }
        else {
            'cc5149eabd53779ce1e7bdc5401643622d0c7e6800ade18928a767e940bb0e62'
        }

        $config.DefinitionId | Should -Be 'NodeRuntime'
        $sourceDefinition.Kind | Should -Be 'download'
        $sourceDefinition.BaseUri | Should -Be 'https://nodejs.org/dist/v24.15.0/'
        $result.Package.version | Should -Be '24.15.0'
        $result.Package.releaseTag | Should -Be 'v24.15.0'
        $result.Package.packageFile.fileName | Should -Be $expectedFileName
        $result.Package.packageFile.contentHash.value | Should -Be $expectedSha256
        $result.Package.install.pathRegistration.source.value | Should -Be 'node'
    }

    It 'loads the shipped npm-backed CLI runtime definitions without package-file acquisition' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $cases = @(
            [pscustomobject]@{ DefinitionId = 'CodexCli'; PackageSpec = '@openai/codex@{version}'; Version = '0.125.0'; Command = 'codex'; RelativePath = 'codex.cmd' }
            [pscustomobject]@{ DefinitionId = 'GeminiCli'; PackageSpec = '@google/gemini-cli@{version}'; Version = '0.39.1'; Command = 'gemini'; RelativePath = 'gemini.cmd' }
            [pscustomobject]@{ DefinitionId = 'OpenCodeCli'; PackageSpec = 'opencode-ai@{version}'; Version = '1.14.24'; Command = 'opencode'; RelativePath = 'opencode.cmd' }
            [pscustomobject]@{ DefinitionId = 'QwenCli'; PackageSpec = '@qwen-code/qwen-code@{version}'; Version = '0.15.2'; Command = 'qwen'; RelativePath = 'qwen.cmd' }
        )

        foreach ($case in $cases) {
            $config = Get-PackageConfig -DefinitionId $case.DefinitionId
            $result = New-PackageResult -PackageConfig $config
            $result = Resolve-PackagePackage -PackageResult $result
            $result = Resolve-PackagePaths -PackageResult $result
            $result = Build-PackageAcquisitionPlan -PackageResult $result

            $config.DefinitionId | Should -Be $case.DefinitionId
            $result.Package.version | Should -Be $case.Version
            $result.Package.install.kind | Should -Be 'npmGlobalPackage'
            $result.Package.install.installerCommand | Should -Be 'npm'
            $result.Package.install.packageSpec | Should -Be $case.PackageSpec
            $result.Package.install.pathRegistration.source.value | Should -Be $case.Command
            $config.Definition.providedTools.commands[0].relativePath | Should -Be $case.RelativePath
            if ($case.DefinitionId -eq 'CodexCli') {
                @($config.Definition.dependencies.definitionId) | Should -Be @('VisualCppRedistributable', 'NodeRuntime')
                @($config.Definition.dependencies.repositoryId) | Should -Be @('EigenverftModule', 'EigenverftModule')
            }
            else {
                @($config.Definition.dependencies.definitionId) | Should -Be @('NodeRuntime')
                @($config.Definition.dependencies.repositoryId) | Should -Be @('EigenverftModule')
            }
            $result.Package.PSObject.Properties['packageFile'] | Should -BeNullOrEmpty
            $result.AcquisitionPlan.PackageFileRequired | Should -BeFalse
            @($result.AcquisitionPlan.Candidates).Count | Should -Be 0
        }
    }

    It 'ensures direct package dependencies before package-specific install flow continues' {
        $definition = [pscustomobject]@{
            id           = 'CodexCli'
            dependencies = @(
                [pscustomobject]@{ repositoryId = 'EigenverftModule'; definitionId = 'VisualCppRedistributable' }
                [pscustomobject]@{ repositoryId = 'EigenverftModule'; definitionId = 'NodeRuntime' }
            )
        }
        $result = [pscustomobject]@{
            DefinitionId  = 'CodexCli'
            RepositoryId  = 'EigenverftModule'
            PackageConfig = [pscustomobject]@{
                Definition = $definition
            }
            Dependencies  = @()
        }

        Mock Invoke-PackageDefinitionCommandCore {
            [pscustomobject]@{
                RepositoryId   = $RepositoryId
                Status        = 'Ready'
                InstallOrigin = 'PackageReused'
            Install       = [pscustomobject]@{ Status = 'ReusedPackageOwned' }
            EntryPoints   = [pscustomobject]@{
                Commands = @(
                    [pscustomobject]@{
                        Name = if ($DefinitionId -eq 'NodeRuntime') { 'npm' } else { 'vc-runtime' }
                        Path = Join-Path $TestDrive "$DefinitionId.cmd"
                    }
                )
            }
        }
    }

        $resolved = Resolve-PackageDependencies -PackageResult $result

        Assert-MockCalled Invoke-PackageDefinitionCommandCore -Times 1 -ParameterFilter { $DefinitionId -eq 'VisualCppRedistributable' }
        Assert-MockCalled Invoke-PackageDefinitionCommandCore -Times 1 -ParameterFilter { $DefinitionId -eq 'NodeRuntime' }
        Assert-MockCalled Invoke-PackageDefinitionCommandCore -Times 2 -ParameterFilter { $RepositoryId -eq 'EigenverftModule' -and $DesiredState -eq 'Assigned' }
        @($resolved.Dependencies.DefinitionId) | Should -Be @('VisualCppRedistributable', 'NodeRuntime')
        @($resolved.Dependencies.RepositoryId) | Should -Be @('EigenverftModule', 'EigenverftModule')
        @($resolved.Dependencies.Status) | Should -Be @('Ready', 'Ready')
        @($resolved.Dependencies[1].Commands.Name) | Should -Be @('npm')
    }

    It 'fails clearly when direct package dependencies contain a cycle' {
        $definition = [pscustomobject]@{
            id           = 'CodexCli'
            dependencies = @(
                [pscustomobject]@{ definitionId = 'NodeRuntime' }
            )
        }
        $result = [pscustomobject]@{
            DefinitionId       = 'CodexCli'
            PackageConfig = [pscustomobject]@{
                Definition = $definition
            }
            Dependencies       = @()
        }

        { Resolve-PackageDependencies -PackageResult $result -DependencyStack @('EigenverftModule:CodexCli', 'EigenverftModule:NodeRuntime') } | Should -Throw '*dependency cycle*'
    }

    It 'loads the shipped PythonRuntime definition and selects the fixed NuGet package release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageConfig -DefinitionId 'PythonRuntime'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'pythonNuGetPackage' })

        $expectedFileName = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            'pythonarm64.3.13.13.nupkg'
        }
        else {
            'python.3.13.13.nupkg'
        }
        $expectedSha256 = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            '2a0406b834d4ff33414f70597b67797466ba2344baa534ab8f62c4eae1c3e599'
        }
        else {
            'c2347c2975f661b2dafceacc94218dfe87781955a3cd309c633d343b8c8dac31'
        }

        $config.DefinitionId | Should -Be 'PythonRuntime'
        $sourceDefinition.Kind | Should -Be 'download'
        $sourceDefinition.BaseUri | Should -Be 'https://api.nuget.org/v3-flatcontainer/'
        $result.Package.version | Should -Be '3.13.13'
        $result.Package.releaseTag | Should -Be '3.13.13'
        $result.Package.packageFile.fileName | Should -Be $expectedFileName
        $result.Package.packageFile.contentHash.value | Should -Be $expectedSha256
        $result.Package.install.expandedRoot | Should -Be 'tools'
        $result.Package.install.pathRegistration.source.value | Should -Be 'python'
        $result.Package.validation.commandChecks[1].arguments | Should -Be @('-m', 'pip', '--version')
    }

    It 'loads the shipped PowerShell7 definition and selects the fixed GitHub-backed release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageConfig -DefinitionId 'PowerShell7'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'powerShellGitHub' })

        $expectedFileName = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            'PowerShell-7.6.1-win-arm64.zip'
        }
        else {
            'PowerShell-7.6.1-win-x64.zip'
        }
        $expectedSha256 = if ([string]::Equals([string]$config.Architecture, 'arm64', [System.StringComparison]::OrdinalIgnoreCase)) {
            'f8976558a687dd610eec33a42868a090f611f3bfbc0ae69c2bc5d986e3b53847'
        }
        else {
            'b5c9e8457ca7df4998abe3cc2c58e6dd4005ad1b4c5320bbac86244a747db91d'
        }

        $config.DefinitionId | Should -Be 'PowerShell7'
        $sourceDefinition.Kind | Should -Be 'githubRelease'
        $sourceDefinition.RepositoryOwner | Should -Be 'PowerShell'
        $sourceDefinition.RepositoryName | Should -Be 'PowerShell'
        $result.Package.version | Should -Be '7.6.1'
        $result.Package.releaseTag | Should -Be 'v7.6.1'
        $result.Package.packageFile.fileName | Should -Be $expectedFileName
        $result.Package.packageFile.contentHash.value | Should -Be $expectedSha256
        $result.Package.install.pathRegistration.source.value | Should -Be 'pwsh'
    }

    It 'loads the shipped VisualCppRedistributable definition as an elevated machine prerequisite' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageConfig -DefinitionId 'VisualCppRedistributable'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'visualCppRedistributableDownload' })

        $config.DefinitionId | Should -Be 'VisualCppRedistributable'
        $sourceDefinition.Kind | Should -Be 'download'
        $sourceDefinition.BaseUri | Should -Be 'https://aka.ms/'
        $result.PackageId | Should -Be 'vc-runtime-x64-stable'
        $result.Package.install.kind | Should -Be 'runInstaller'
        $result.Package.install.targetKind | Should -Be 'machinePrerequisite'
        $result.Package.install.elevation | Should -Be 'required'
        $result.Package.install.commandArguments | Should -Be @('/install', '/quiet', '/norestart', '/log', '{logPath}')
        $result.Package.packageFile.fileName | Should -Be 'vc_redist.x64.exe'
        $result.Package.packageFile.publisherSignature.subjectContains | Should -Be 'Microsoft Corporation'
    }

    It 'loads the shipped Qwen35_2B_Q8_0_Model definition and selects the fixed Hugging Face-backed resource release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PhysicalMemoryGiB { 2.0 }
        Mock Get-VideoMemoryGiB { 1.0 }

        $config = Get-PackageConfig -DefinitionId 'Qwen35_2B_Q8_0_Model'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'huggingFaceDownload' })

        $config.DefinitionId | Should -Be 'Qwen35_2B_Q8_0_Model'
        $sourceDefinition.Kind | Should -Be 'download'
        $sourceDefinition.BaseUri | Should -Be 'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/'
        $result.PackageId | Should -Be 'qwen35-2b-q8-0-stable'
        $result.Package.version | Should -Be '3.5.0'
        $result.Package.packageFile.fileName | Should -Be 'Qwen3.5-2B-Q8_0.gguf'
        $result.Package.packageFile.contentHash.algorithm | Should -Be 'sha256'
        $result.Package.packageFile.contentHash.value | Should -Be '1b04acba824817554f4ce23639bc8495ff70453b8fcb047900c731521021f2c1'
        $result.Package.install.kind | Should -Be 'placePackageFile'
        $result.Compatibility.Count | Should -Be 1
        $result.Compatibility[0].Kind | Should -Be 'physicalOrVideoMemoryGiB'
        $result.Compatibility[0].OnFail | Should -Be 'warn'
        $result.Compatibility[0].Accepted | Should -BeFalse
    }

    It 'loads the shipped Qwen35_9B_Q6_K_Model definition and selects the fixed Hugging Face-backed resource release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PhysicalMemoryGiB { 8.0 }
        Mock Get-VideoMemoryGiB { 2.0 }

        $config = Get-PackageConfig -DefinitionId 'Qwen35_9B_Q6_K_Model'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'huggingFaceDownload' })

        $config.DefinitionId | Should -Be 'Qwen35_9B_Q6_K_Model'
        $sourceDefinition.Kind | Should -Be 'download'
        $sourceDefinition.BaseUri | Should -Be 'https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/'
        $result.PackageId | Should -Be 'qwen35-9b-q6-k-stable'
        $result.Package.version | Should -Be '3.5.0'
        $result.Package.packageFile.fileName | Should -Be 'Qwen3.5-9B-Q6_K.gguf'
        $result.Package.packageFile.contentHash.algorithm | Should -Be 'sha256'
        $result.Package.packageFile.contentHash.value | Should -Be '91898433cf5ce0a8f45516a4cc3e9343b6e01d052d01f684309098c66a326c59'
        $result.Package.install.kind | Should -Be 'placePackageFile'
        $result.Compatibility.Count | Should -Be 1
        $result.Compatibility[0].Kind | Should -Be 'physicalOrVideoMemoryGiB'
        $result.Compatibility[0].OnFail | Should -Be 'warn'
        $result.Compatibility[0].Accepted | Should -BeFalse
    }

    It 'fails clearly when the shipped global config still defines vsCodeUpdateService as an environment source' {
        $globalConfigPath = Join-Path $TestDrive 'Config.json'
        $badGlobal = New-TestPackageGlobalDocument -EnvironmentSources @{
            vsCodeUpdateService = @{ kind = 'download'; baseUri = 'https://example.invalid/' }
        }
        Write-TestJsonDocument -Path $globalConfigPath -Document $badGlobal

        $globalInfo = Read-PackageJsonDocument -Path $globalConfigPath
        { Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalInfo } | Should -Throw '*vsCodeUpdateService*'
    }

    It 'fails clearly when a definition still uses requireManagedOwnership' {
        $rootPath = Join-Path $TestDrive 'retired-require-managed-ownership'
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0') -ReleaseDefaultsExistingInstallPolicy @{
            allowAdoptExternal    = $false
            upgradeAdoptedInstall = $false
            requireManagedOwnership = $false
        }
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument $definitionDocument

        $definitionInfo = Read-PackageJsonDocument -Path $documents.DefinitionPath
        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*requireManagedOwnership*'
    }

    It 'fails clearly when npm install definitions use retired managerDependency fields' {
        $release = New-TestPackageRelease -Id 'cli-win-x64-stable' -Version '1.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{
            kind              = 'npmGlobalPackage'
            installerCommand  = 'npm'
            packageSpec       = 'example@{version}'
            managerDependency = @{
                definitionId = 'NodeRuntime'
                command      = 'npm'
            }
        } -Validation (New-TestValidation -Version '1.0.0')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '1.0.0')
        $definitionInfo = [pscustomobject]@{
            Path     = Join-Path $TestDrive 'VSCodeRuntime.json'
            Document = ConvertTo-TestPsObject -InputObject $definitionDocument
        }

        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*install.managerDependency*'
    }

    It 'fails clearly when a definition is missing schemaVersion' {
        $rootPath = Join-Path $TestDrive 'missing-schema-version'
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release)
        $null = $definitionDocument.Remove('schemaVersion')
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument $definitionDocument

        $definitionInfo = Read-PackageJsonDocument -Path $documents.DefinitionPath
        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*schemaVersion*'
    }

    It 'fails clearly when a definition still uses releaseDefaults.requirements' {
        $rootPath = Join-Path $TestDrive 'retired-requirements-packages'
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release)
        $definitionDocument.releaseDefaults.requirements = @{
            checks = [object[]]@()
        }
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument $definitionDocument

        $definitionInfo = Read-PackageJsonDocument -Path $documents.DefinitionPath
        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*releaseDefaults.requirements*'
    }

    It 'fails clearly when an acquisition candidate still uses retired priority' {
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                priority     = 100
                verification = @{ mode = 'none' }
            }
        )
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release)
        $definitionInfo = [pscustomobject]@{
            Path     = Join-Path $TestDrive 'VSCodeRuntime.json'
            Document = ConvertTo-TestPsObject -InputObject $definitionDocument
        }

        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*priority*'
    }

    It 'fails clearly when packageFile still uses retired raw-file trust properties' {
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                searchOrder  = 100
                verification = @{ mode = 'required' }
            }
        )
        $release.packageFile | Add-Member -NotePropertyName integrity -NotePropertyValue @{
            algorithm = 'sha256'
            sha256    = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        }
        $release.packageFile | Add-Member -NotePropertyName authenticode -NotePropertyValue @{
            requireValid = $true
        }
        $release.packageFile | Add-Member -NotePropertyName autoUpdateSupported -NotePropertyValue $false
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release)
        $definitionInfo = [pscustomobject]@{
            Path     = Join-Path $TestDrive 'VSCodeRuntime.json'
            Document = ConvertTo-TestPsObject -InputObject $definitionDocument
        }

        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*packageFile.autoUpdateSupported*'
        $release.packageFile.PSObject.Properties.Remove('autoUpdateSupported')
        $definitionInfo.Document = ConvertTo-TestPsObject -InputObject $definitionDocument
        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*packageFile.integrity*'
        $release.packageFile.PSObject.Properties.Remove('integrity')
        $definitionInfo.Document = ConvertTo-TestPsObject -InputObject $definitionDocument
        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*packageFile.authenticode*'
    }

    It 'rejects incomplete packageFile.contentHash and publisherSignature metadata' {
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                searchOrder  = 100
                verification = @{ mode = 'required' }
            }
        )
        $release.packageFile | Add-Member -NotePropertyName contentHash -NotePropertyValue @{
            algorithm = 'sha256'
        }
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release)
        $definitionInfo = [pscustomobject]@{
            Path     = Join-Path $TestDrive 'VSCodeRuntime.json'
            Document = ConvertTo-TestPsObject -InputObject $definitionDocument
        }

        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*packageFile.contentHash without value*'
        $release.packageFile.PSObject.Properties.Remove('contentHash')
        $release.packageFile | Add-Member -NotePropertyName contentHash -NotePropertyValue @{
            algorithm = 'sha256'
            value     = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        }
        $release.packageFile | Add-Member -NotePropertyName publisherSignature -NotePropertyValue @{
            requireValid = $true
        }
        $definitionInfo.Document = ConvertTo-TestPsObject -InputObject $definitionDocument
        { Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*packageFile.publisherSignature without kind*'
    }

    It 'uses the default source inventory path when the env var is unset' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $null, 'Process')
        (Get-PackageSourceInventoryPath) | Should -Be (Get-PackageDefaultSourceInventoryPath)
    }

    It 'resolves the default source inventory path under applicationRootDirectory when provided' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $null, 'Process')
        $applicationRootPath = Join-Path $TestDrive 'custom-app-root'
        Get-PackageSourceInventoryPath -ApplicationRootDirectory $applicationRootPath |
            Should -Be ([System.IO.Path]::GetFullPath((Join-Path (Join-Path $applicationRootPath 'Configuration\External') 'SourceInventory.json')))
    }

    It 'loads source inventory from the env-var path and applies the inventory global overlay when no site code is set' {
        $rootPath = Join-Path $TestDrive 'inventory-global'
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                    @{
                        kind        = 'packageDepot'
                        searchOrder    = 100
                        verification = @{ mode = 'none' }
                    }
                )
            )) -SourceInventoryDocument (New-TestSourceInventoryDocument -GlobalEnvironmentSources @{
                remotePackageDepot = @{
                    kind        = 'filesystem'
                    searchOrder = 150
                    basePath    = (Join-Path $TestDrive 'global-remote')
                }
            })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $documents.SourceInventoryPath, 'Process')
        [Environment]::SetEnvironmentVariable($script:SiteCodeEnvVarName, $null, 'Process')

        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'

        $config.EnvironmentSources.PSObject.Properties.Name | Should -Contain 'remotePackageDepot'
        $config.EnvironmentSources.remotePackageDepot.basePath | Should -Be (Join-Path $TestDrive 'global-remote')
    }

    It 'applies the site overlay on top of the inventory global overlay when site code is present' {
        $rootPath = Join-Path $TestDrive 'inventory-site'
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                    @{
                        kind        = 'packageDepot'
                        searchOrder    = 100
                        verification = @{ mode = 'none' }
                    }
                )
            )) -SourceInventoryDocument (New-TestSourceInventoryDocument -GlobalEnvironmentSources @{
                remotePackageDepot = @{
                    kind        = 'filesystem'
                    searchOrder = 150
                    basePath    = (Join-Path $TestDrive 'global-remote')
                }
            } -SiteEnvironmentSources @{
                remotePackageDepot = @{
                    kind        = 'filesystem'
                    searchOrder = 150
                    basePath    = (Join-Path $TestDrive 'site-remote')
                }
            } -SiteCode 'BER')

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $documents.SourceInventoryPath, 'Process')
        [Environment]::SetEnvironmentVariable($script:SiteCodeEnvVarName, 'BER', 'Process')

        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'

        $config.EnvironmentSources.remotePackageDepot.basePath | Should -Be (Join-Path $TestDrive 'site-remote')
    }

    It 'filters depot inventory sources by enabled flag and semicolon site-code list' {
        $rootPath = Join-Path $TestDrive 'depot-inventory-sites'
        $depotInventory = New-TestDepotInventoryDocument -DefaultPackageDepotDirectory (Join-Path $rootPath 'default-depot') -EnvironmentSources @{
            disabledDepot = @{
                kind     = 'filesystem'
                enabled  = $false
                searchOrder = 50
                basePath = (Join-Path $rootPath 'disabled')
            }
            departmentDepot = @{
                kind      = 'filesystem'
                enabled   = $true
                searchOrder  = 150
                siteCodes = @('BER-ENG')
                basePath  = (Join-Path $rootPath 'department')
            }
            otherSiteDepot = @{
                kind      = 'filesystem'
                enabled   = $true
                searchOrder  = 100
                siteCodes = @('PD')
                basePath  = (Join-Path $rootPath 'other-site')
            }
            globalDepot = @{
                kind     = 'filesystem'
                enabled  = $true
                searchOrder = 400
                basePath = (Join-Path $rootPath 'global')
            }
        }
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DepotInventoryDocument $depotInventory -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                    @{
                        kind        = 'packageDepot'
                        searchOrder    = 100
                        verification = @{ mode = 'none' }
                    }
                )
            ))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        [Environment]::SetEnvironmentVariable($script:SiteCodeEnvVarName, 'BER;BER-ENG', 'Process')

        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $sourceNames = @($config.EnvironmentSources.PSObject.Properties.Name)
        $depotSources = @(Get-PackagePackageDepotSources -PackageConfig $config)

        $sourceNames | Should -Contain 'defaultPackageDepot'
        $sourceNames | Should -Contain 'departmentDepot'
        $sourceNames | Should -Contain 'globalDepot'
        $sourceNames | Should -Not -Contain 'disabledDepot'
        $sourceNames | Should -Not -Contain 'otherSiteDepot'
        @($depotSources.id) | Should -Be @('departmentDepot', 'defaultPackageDepot', 'globalDepot')
    }

    It 'rejects a selected release when compatibility.checks are not satisfied with onFail fail' {
        $rootPath = Join-Path $TestDrive 'requirements-checks-fail'
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Compatibility @{
            checks = @(
                @{
                    kind    = 'osFamily'
                    allowed = @('linux')
                }
            )
        } -Validation (New-TestValidation -Version '2.0.0')
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -PackageConfig $config

        { Resolve-PackagePackage -PackageResult $result } | Should -Throw '*compatibility.checks*'
    }

    It 'resolves environment and definition source refs from the effective acquisition environment and upstream sources' {
        $rootPath = Join-Path $TestDrive 'source-resolution'
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
            ) -UpstreamBaseUri 'https://example.invalid/vscode/') -SourceInventoryDocument (New-TestSourceInventoryDocument -GlobalEnvironmentSources @{
                remotePackageDepot = @{
                    kind        = 'filesystem'
                    searchOrder = 150
                    basePath    = (Join-Path $TestDrive 'remote-depot')
                }
            })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $documents.SourceInventoryPath, 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $environmentSource = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'environment'; id = 'remotePackageDepot' })
        $definitionSource = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'vsCodeUpdateService' })

        $environmentSource.Kind | Should -Be 'filesystem'
        $environmentSource.BasePath | Should -Be (Join-Path $TestDrive 'remote-depot')
        $definitionSource.Kind | Should -Be 'download'
        $definitionSource.BaseUri | Should -Be 'https://example.invalid/vscode/'
    }

    It 'loads GitHub release upstream sources and keeps releaseTag separate from version' {
        $rootPath = Join-Path $TestDrive 'github-release-source'
        $release = New-TestPackageRelease -Id 'llama-cpu-x64-stable' -Version '0.0.1' -ReleaseTag 'b8863' -Architecture 'x64' -Flavor 'win-cpu-x64' -FileName 'llama-b8863-bin-win-cpu-x64.zip' -AcquisitionCandidates @(
            @{
                kind         = 'download'
                sourceId     = 'llamaCppGitHub'
                searchOrder     = 100
                verification = @{ mode = 'required' }
            }
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '0.0.1') -UpstreamSources @{
            llamaCppGitHub = @{
                kind            = 'githubRelease'
                repositoryOwner = 'ggml-org'
                repositoryName  = 'llama.cpp'
            }
        })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $definitionSource = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'llamaCppGitHub' })

        $definitionSource.Kind | Should -Be 'githubRelease'
        $definitionSource.RepositoryOwner | Should -Be 'ggml-org'
        $definitionSource.RepositoryName | Should -Be 'llama.cpp'
        $result.Package.version | Should -Be '0.0.1'
        $result.Package.releaseTag | Should -Be 'b8863'
    }

    It 'requires releaseTag for GitHub-backed releases' {
        $rootPath = Join-Path $TestDrive 'github-release-tag-required'
        $release = New-TestPackageRelease -Id 'llama-cpu-x64-stable' -Version '0.0.1' -Architecture 'x64' -Flavor 'win-cpu-x64' -FileName 'llama-b8863-bin-win-cpu-x64.zip' -AcquisitionCandidates @(
            @{
                kind         = 'download'
                sourceId     = 'llamaCppGitHub'
                searchOrder     = 100
                verification = @{ mode = 'required' }
            }
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '0.0.1') -UpstreamSources @{
            llamaCppGitHub = @{
                kind            = 'githubRelease'
                repositoryOwner = 'ggml-org'
                repositoryName  = 'llama.cpp'
            }
        })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        { Get-PackageConfig -DefinitionId 'VSCodeRuntime' } | Should -Throw '*requires releaseTag*'
    }

    It 'resolves a GitHub release asset URL from releaseTag and packageFile.fileName' {
        $rootPath = Join-Path $TestDrive 'github-release-resolve'
        $release = New-TestPackageRelease -Id 'llama-cpu-x64-stable' -Version '0.0.1' -ReleaseTag 'b8863' -Architecture 'x64' -Flavor 'win-cpu-x64' -FileName 'llama-b8863-bin-win-cpu-x64.zip' -AcquisitionCandidates @(
            @{
                kind         = 'download'
                sourceId     = 'llamaCppGitHub'
                searchOrder     = 100
                verification = @{ mode = 'required' }
            }
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '0.0.1') -UpstreamSources @{
            llamaCppGitHub = @{
                kind            = 'githubRelease'
                repositoryOwner = 'ggml-org'
                repositoryName  = 'llama.cpp'
            }
        })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }
        Mock Get-GitHubRelease {
            [pscustomobject]@{
                RepositoryOwner = 'ggml-org'
                RepositoryName  = 'llama.cpp'
                ReleaseTag      = 'b8863'
                Assets          = @(
                    [pscustomobject]@{
                        Name        = 'llama-b8863-bin-win-cpu-x64.zip'
                        DownloadUrl = 'https://example.invalid/ggml-org/llama.cpp/releases/download/b8863/llama-b8863-bin-win-cpu-x64.zip'
                    }
                )
            }
        }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $sourceDefinition = Get-PackageSourceDefinition -PackageConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'llamaCppGitHub' })
        $resolvedSource = Resolve-PackageSource -SourceDefinition $sourceDefinition -AcquisitionCandidate $result.Package.acquisitionCandidates[0] -Package $result.Package

        $resolvedSource.Kind | Should -Be 'download'
        $resolvedSource.ResolvedSource | Should -Be 'https://example.invalid/ggml-org/llama.cpp/releases/download/b8863/llama-b8863-bin-win-cpu-x64.zip'
        Assert-MockCalled Get-GitHubRelease -Times 1 -Exactly
    }

    It 'fails clearly when a GitHub release tag cannot be resolved' {
        Mock Invoke-WebRequestEx { throw '404 Not Found' }

        { Get-GitHubRelease -RepositoryOwner 'ggml-org' -RepositoryName 'llama.cpp' -ReleaseTag 'b9999' } | Should -Throw "*repository 'ggml-org/llama.cpp'*release tag 'b9999'*"
    }

    It 'normalizes GitHub release API metadata and assets' {
        $responseBody = @{
            id           = 42
            tag_name     = 'b8863'
            name         = 'b8863'
            html_url     = 'https://github.com/ggml-org/llama.cpp/releases/tag/b8863'
            published_at = '2026-04-20T23:54:06Z'
            draft        = $false
            prerelease   = $false
            immutable    = $false
            assets       = @(
                @{
                    id                   = 99
                    name                 = 'llama-b8863-bin-win-cpu-x64.zip'
                    browser_download_url = 'https://example.invalid/llama-b8863-bin-win-cpu-x64.zip'
                    content_type         = 'application/zip'
                    size                 = 12345
                    digest               = 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
                    created_at           = '2026-04-20T23:54:06Z'
                    updated_at           = '2026-04-20T23:54:06Z'
                }
            )
        } | ConvertTo-Json -Depth 10

        Mock Invoke-WebRequestEx {
            [pscustomobject]@{
                Content = $responseBody
            }
        }

        $release = Get-GitHubRelease -RepositoryOwner 'ggml-org' -RepositoryName 'llama.cpp' -ReleaseTag 'b8863'

        $release.ReleaseId | Should -Be '42'
        $release.ReleaseTag | Should -Be 'b8863'
        $release.RepositoryOwner | Should -Be 'ggml-org'
        $release.RepositoryName | Should -Be 'llama.cpp'
        $release.Assets.Count | Should -Be 1
        $release.Assets[0].Name | Should -Be 'llama-b8863-bin-win-cpu-x64.zip'
        $release.Assets[0].DownloadUrl | Should -Be 'https://example.invalid/llama-b8863-bin-win-cpu-x64.zip'
        $release.Assets[0].Sha256 | Should -Be '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    }

    It 'fails clearly when the GitHub release asset is missing' {
        $sourceDefinition = [pscustomobject]@{
            Scope           = 'definition'
            Id              = 'llamaCppGitHub'
            Kind            = 'githubRelease'
            RepositoryOwner = 'ggml-org'
            RepositoryName  = 'llama.cpp'
        }
        $package = ConvertTo-TestPsObject @{
            id         = 'llama-cpu-x64-stable'
            releaseTag = 'b8863'
            packageFile = @{
                fileName = 'llama-b8863-bin-win-cpu-x64.zip'
            }
        }
        $candidate = ConvertTo-TestPsObject @{
            kind     = 'download'
            sourceId = 'llamaCppGitHub'
        }

        Mock Get-GitHubRelease {
            [pscustomobject]@{
                RepositoryOwner = 'ggml-org'
                RepositoryName  = 'llama.cpp'
                ReleaseTag      = 'b8863'
                Assets          = @(
                    [pscustomobject]@{
                        Name        = 'llama-b8863-bin-win-cuda-12.4-x64.zip'
                        DownloadUrl = 'https://example.invalid/other.zip'
                    }
                )
            }
        }

        { Resolve-PackageSource -SourceDefinition $sourceDefinition -AcquisitionCandidate $candidate -Package $package } | Should -Throw '*does not contain asset*llama-b8863-bin-win-cpu-x64.zip*'
    }

    It 'builds an effective release from releaseDefaults and uses ReleaseTrack in path resolution' {
        $rootPath = Join-Path $TestDrive 'effective-release'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0'
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind        = 'packageDepot'
                searchOrder    = 10
                verification = @{ mode = 'optional'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            }
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument -ReleaseTrack 'stable') -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result

        $result.EffectiveRelease | Should -Not -BeNullOrEmpty
        $result.Package.install.kind | Should -Be 'expandArchive'
        $result.Package.validation.commandChecks[0].expectedValue | Should -Be '{version}'
        $result.PackageWorkSlotDirectory | Should -Match '^VSCodeRuntime-[0-9a-f]{8}$'
        $result.PackageFilePath | Should -Match '\\FileStage\\VSCodeRuntime-[0-9a-f]{8}\\'
        $result.PackageInstallStageDirectory | Should -Match '\\InstStage\\VSCodeRuntime-[0-9a-f]{8}$'
        (Split-Path -Leaf $result.PackageFileStagingDirectory) | Should -Be (Split-Path -Leaf $result.PackageInstallStageDirectory)
        $result.PackageDepotRelativeDirectory | Should -Be 'VSCodeRuntime\stable\2.0.0\win32-x64'
        $result.DefaultPackageDepotFilePath | Should -Match '\\stable\\2\.0\.0\\win32-x64\\'
    }

    It 'writes resolved paths as separate console lines' {
        $rootPath = Join-Path $TestDrive 'resolved-path-lines'
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                searchOrder     = 10
                verification = @{ mode = 'none' }
            }
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $messages = New-Object System.Collections.Generic.List[string]
        Mock Write-StandardMessage {
            param([string]$Message, [string]$Level)
            $messages.Add($Message) | Out-Null
        }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $null = Resolve-PackagePaths -PackageResult $result

        @($messages) | Should -Contain '[STATE] Resolved paths:'
        @($messages | Where-Object { $_.StartsWith('[PATH] Package file staging:') }).Count | Should -Be 1
        @($messages | Where-Object { $_.StartsWith('[PATH] Package install stage:') }).Count | Should -Be 1
        @($messages | Where-Object { $_.StartsWith('[PATH] Target install directory:') }).Count | Should -Be 1
        @($messages | Where-Object { $_.StartsWith('[PATH] Package file:') }).Count | Should -Be 1
        @($messages | Where-Object { $_.StartsWith('[PATH] Default package depot file:') }).Count | Should -Be 1
    }

}
