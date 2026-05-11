<#
    Eigenverft.Manifested.Sandbox Package - exports and state
#>

. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.Module.TestHelpers.ps1"

Invoke-TestPackageDescribe -Name 'Eigenverft.Manifested.Sandbox Package - exports and state' -Body {
    It 'exports Invoke-Package with generic package parameters' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-Package'

        $command | Should -Not -BeNullOrEmpty
        $command.Parameters.Keys | Should -Contain 'DefinitionId'
        $command.Parameters.Keys | Should -Contain 'RepositoryId'
        $command.Parameters.Keys | Should -Contain 'DesiredState'
        $command.Parameters.Keys | Should -Contain 'FailFast'
        $command.Parameters.Keys | Should -Not -Contain 'CommandName'
        $command.Parameters.Keys | Should -Not -Contain 'DependencyStack'
    }

    It 'Get-SandboxVersion lists Invoke-Package examples for shipped definitions' {
        $null = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $text = Get-SandboxVersion

        $text | Should -Match 'Invoke-Package -DefinitionId ''GitRuntime'''
        $text | Should -Match 'Invoke-Package -DefinitionId CodexCli,'
        $text | Should -Not -Match 'VSCodeUser,'
        $text | Should -Match 'Other exported commands:'
    }

    It 'exports Get-PackageState with only the Raw view switch' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Get-PackageState'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames | Should -Be @('Raw')
    }

    It 'exports only the intended public command surface' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru

        @($module.ExportedCommands.Keys | Sort-Object) | Should -Be @(
            'Add-PackageDepot',
            'Add-PackageRepository',
            'Add-TeamPackageDepot',
            'Add-TeamPackageRepository',
            'Get-PackageDepot',
            'Get-PackageRepository',
            'Get-PackageState',
            'Get-SandboxVersion',
            'Invoke-Package',
            'Invoke-WebRequestEx',
            'Remove-PackageDepot',
            'Remove-PackageRepository',
            'Sandbox',
            'Set-PackageDepot',
            'Set-PackageRepository',
            'Trust-PackageRepository'
        )
        Get-Command -Name 'Initialize-ProxyAccessProfile' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'keeps user-facing command files in command folders' {
        $moduleProjectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Eigenverft.Manifested.Sandbox'

        Test-Path -LiteralPath (Join-Path $moduleProjectRoot 'Commands\Package\Eigenverft.Manifested.Sandbox.Cmd.InvokePackage.ps1') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $moduleProjectRoot 'Commands\Package\Eigenverft.Manifested.Sandbox.Cmd.GetPackageState.ps1') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $moduleProjectRoot 'Commands\Depot\Eigenverft.Manifested.Sandbox.Cmd.PackageDepot.ps1') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $moduleProjectRoot 'Commands\Repository\Eigenverft.Manifested.Sandbox.Cmd.PackageRepository.ps1') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $moduleProjectRoot 'Commands\Module\Eigenverft.Manifested.Sandbox.Cmd.Module.ps1') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $moduleProjectRoot 'Commands\Web\Eigenverft.Manifested.Sandbox.Cmd.InvokeWebRequestEx.ps1') -PathType Leaf | Should -BeTrue
    }

    It 'returns an empty package state when durable inventory/history files and local directories are absent' {
        $root = Join-Path $TestDrive 'empty-package-state'
        $config = [pscustomobject]@{
            LocalConfigurationPath              = Join-Path $root 'Configuration\Internal\Config.json'
            PreferredTargetInstallRootDirectory = Join-Path $root 'Inst'
            PackageFileStagingRootDirectory       = Join-Path $root 'PackageFileStaging'
            PackageInstallStageRootDirectory    = Join-Path $root 'PackageInstallStage'
            DefaultPackageDepotDirectory        = Join-Path $root 'DefaultPackageDepot'
            LocalRepositoryRoot                 = Join-Path $root 'PackageRepositories'
            ShimDirectory                       = Join-Path $root 'Shims'
            PackageInventoryFilePath            = Join-Path (Join-Path $root 'State') 'package-inventory.json'
            PackageOperationHistoryFilePath     = Join-Path (Join-Path $root 'State') 'package-operation-history.json'
        }
        $sourceInventoryPath = Join-Path (Join-Path $root 'Configuration\External') 'SourceInventory.json'

        Mock Get-PackageConfig { throw 'Get-PackageState must not load a package definition.' }
        Mock Get-PackageStateConfig { return $config }
        Mock Get-PackageInventory { return [pscustomobject]@{ Path = $config.PackageInventoryFilePath; Records = @() } }
        Mock Get-PackageOperationHistory { return [pscustomobject]@{ Path = $config.PackageOperationHistoryFilePath; Records = @() } }
        $config | Add-Member -MemberType NoteProperty -Name SourceInventoryInfo -Value ([pscustomobject]@{ Path = $sourceInventoryPath; Exists = $false; Document = $null })

        $state = Get-PackageState

        $state.LocalRoot | Should -Be $root
        $state.LocalConfigurationExists | Should -BeFalse
        $state.PackageInventoryExists | Should -BeFalse
        $state.OperationHistoryExists | Should -BeFalse
        $state.SourceInventoryExists | Should -BeFalse
        $state.PackageRecordCount | Should -Be 0
        $state.OperationRecordCount | Should -Be 0
        $state.PackageRecords.Count | Should -Be 0
        $state.OperationRecords.Count | Should -Be 0
        $state.Directories.Installed.Exists | Should -BeFalse
        $state.Directories.PackageFileStaging.Exists | Should -BeFalse
        $state.Directories.PackageInstallStage.Exists | Should -BeFalse
        $state.Directories.DefaultPackageDepot.Exists | Should -BeFalse
        $state.Directories.LocalRepositoryRoot.Exists | Should -BeFalse
        $state.Directories.Shims.Exists | Should -BeFalse
    }

    It 'gets package state without loading a package definition config' {
        $root = Join-Path $TestDrive 'definition-free-package-state'
        $config = [pscustomobject]@{
            LocalConfigurationPath              = Join-Path $root 'Configuration\Internal\Config.json'
            PreferredTargetInstallRootDirectory = Join-Path $root 'Inst'
            PackageFileStagingRootDirectory       = Join-Path $root 'PackageFileStaging'
            PackageInstallStageRootDirectory    = Join-Path $root 'PackageInstallStage'
            DefaultPackageDepotDirectory        = Join-Path $root 'DefaultPackageDepot'
            LocalRepositoryRoot                 = Join-Path $root 'PackageRepositories'
            ShimDirectory                       = Join-Path $root 'Shims'
            PackageInventoryFilePath            = Join-Path (Join-Path $root 'State') 'package-inventory.json'
            PackageOperationHistoryFilePath     = Join-Path (Join-Path $root 'State') 'package-operation-history.json'
            SourceInventoryInfo                 = [pscustomobject]@{ Path = (Join-Path (Join-Path $root 'Configuration\External') 'SourceInventory.json'); Exists = $false; Document = $null }
        }

        Mock Get-PackageConfig { throw 'VSCodeRuntime definition should not be required for state.' }
        Mock Get-PackageStateConfig { return $config }
        Mock Get-PackageInventory { return [pscustomobject]@{ Path = $config.PackageInventoryFilePath; Records = @() } }
        Mock Get-PackageOperationHistory { return [pscustomobject]@{ Path = $config.PackageOperationHistoryFilePath; Records = @() } }

        { Get-PackageState } | Should -Not -Throw
        Should -Invoke Get-PackageStateConfig -Times 1 -Exactly
        Should -Invoke Get-PackageConfig -Times 0 -Exactly
    }

    It 'summarizes package inventory records, operation records, and local directory state' {
        $root = Join-Path $TestDrive 'populated-package-state'
        $installRoot = Join-Path $root 'Inst'
        $workspaceRoot = Join-Path $root 'PackageFileStaging'
        $installStageRoot = Join-Path $root 'PackageInstallStage'
        $depotRoot = Join-Path $root 'DefaultPackageDepot'
        $localRepositoryRoot = Join-Path $root 'PackageRepositories'
        $shimDirectory = Join-Path $root 'Shims'
        $installDirectory = Join-Path $installRoot 'vsc-rt\stable\1.0.0\win32-x64'
        $definitionSnapshotPath = Join-Path $localRepositoryRoot 'EigenverftModule\VSCodeRuntime.json'
        $sourceInventoryPath = Join-Path (Join-Path $root 'Configuration\External') 'SourceInventory.json'

        $null = New-Item -ItemType Directory -Path $installDirectory -Force
        $null = New-Item -ItemType Directory -Path $workspaceRoot -Force
        $null = New-Item -ItemType Directory -Path $installStageRoot -Force
        $null = New-Item -ItemType Directory -Path $depotRoot -Force
        $null = New-Item -ItemType Directory -Path $shimDirectory -Force
        Write-TestJsonDocument -Path $definitionSnapshotPath -Document (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '1.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))
        Write-TestJsonDocument -Path $sourceInventoryPath -Document @{ inventoryVersion = 1; global = @{}; sites = @{} }

        $config = [pscustomobject]@{
            LocalConfigurationPath              = Join-Path $root 'Configuration\Internal\Config.json'
            PreferredTargetInstallRootDirectory = $installRoot
            PackageFileStagingRootDirectory       = $workspaceRoot
            PackageInstallStageRootDirectory    = $installStageRoot
            DefaultPackageDepotDirectory        = $depotRoot
            LocalRepositoryRoot                 = $localRepositoryRoot
            ShimDirectory                       = $shimDirectory
            PackageInventoryFilePath            = Join-Path (Join-Path $root 'State') 'package-inventory.json'
            PackageOperationHistoryFilePath     = Join-Path (Join-Path $root 'State') 'package-operation-history.json'
        }
        Write-TestJsonDocument -Path $config.PackageInventoryFilePath -Document @{ records = @() }
        Write-TestJsonDocument -Path $config.PackageOperationHistoryFilePath -Document @{ records = @() }

        $ownershipRecord = [pscustomobject]@{
            installSlotId    = 'VSCodeRuntime:stable:win32-x64'
            definitionId     = 'VSCodeRuntime'
            definitionRepositoryId = 'EigenverftModule'
            definitionFileName = 'VSCodeRuntime.json'
            definitionSourceKind = 'moduleLocal'
            definitionSourcePath = Join-Path $root 'VSCodeRuntime.json'
            definitionSourceHash = 'source-hash'
            definitionSnapshotPath = $definitionSnapshotPath
            definitionSnapshotHash = 'snapshot-hash'
            definitionResolvedAtUtc = '2026-04-25T11:59:00Z'
            releaseTrack     = 'stable'
            artifactDistributionVariant = 'win32-x64'
            currentReleaseId = 'vscode-test'
            currentVersion   = '1.0.0'
            installDirectory = $installDirectory
            ownershipKind    = 'PackageInstalled'
            pathRegistration = [pscustomobject]@{
                mode           = 'user'
                sourceKind     = 'shim'
                sourceValue    = 'code'
                sourcePath     = Join-Path $shimDirectory 'code.cmd'
                registeredPath = $shimDirectory
                status         = 'Registered'
            }
            updatedAtUtc     = '2026-04-25T12:00:00Z'
        }
        $operationRecord = [pscustomobject]@{
            operationId    = 'test-operation'
            repositoryId   = 'EigenverftModule'
            definitionId   = 'VSCodeRuntime'
            desiredState   = 'Assigned'
            status         = 'Ready'
            packageId      = 'vscode-test'
            packageVersion = '1.0.0'
            completedAtUtc = '2026-04-25T12:01:00Z'
        }

        $config | Add-Member -MemberType NoteProperty -Name SourceInventoryInfo -Value ([pscustomobject]@{ Path = $sourceInventoryPath; Exists = $true; Document = @{ inventoryVersion = 1 } })

        Mock Get-PackageConfig { throw 'Get-PackageState must not load a package definition.' }
        Mock Get-PackageStateConfig { return $config }
        Mock Get-PackageInventory { return [pscustomobject]@{ Path = $config.PackageInventoryFilePath; Records = @($ownershipRecord) } }
        Mock Get-PackageOperationHistory { return [pscustomobject]@{ Path = $config.PackageOperationHistoryFilePath; Records = @($operationRecord) } }

        $state = Get-PackageState

        $state.PackageInventoryExists | Should -BeTrue
        $state.OperationHistoryExists | Should -BeTrue
        $state.SourceInventoryExists | Should -BeTrue
        $state.PackageRecordCount | Should -Be 1
        $state.OperationRecordCount | Should -Be 1
        $state.PackageRecords[0].InstallSlotId | Should -Be 'VSCodeRuntime:stable:win32-x64'
        $state.PackageRecords[0].DefinitionRepositoryId | Should -Be 'EigenverftModule'
        $state.PackageRecords[0].DefinitionSnapshotExists | Should -BeTrue
        $state.PackageRecords[0].InstallDirectoryExists | Should -BeTrue
        $state.PackageRecords[0].PathRegistration.SourceKind | Should -Be 'shim'
        $state.PackageRecords[0].PathRegistration.RegisteredPath | Should -Be $shimDirectory
        $state.OperationRecords[0].operationId | Should -Be 'test-operation'
        $state.Directories.Installed.Exists | Should -BeTrue
        $state.Directories.PackageFileStaging.Exists | Should -BeTrue
        $state.Directories.PackageInstallStage.Exists | Should -BeTrue
        $state.Directories.DefaultPackageDepot.Exists | Should -BeTrue
        $state.Directories.LocalRepositoryRoot.Exists | Should -BeTrue
        $state.Directories.Shims.Exists | Should -BeTrue
    }

    It 'returns the resolved raw package state on request' {
        $root = Join-Path $TestDrive 'raw-package-state'
        $config = [pscustomobject]@{
            LocalConfigurationPath              = Join-Path $root 'Configuration\Internal\Config.json'
            PreferredTargetInstallRootDirectory = Join-Path $root 'Inst'
            PackageFileStagingRootDirectory       = Join-Path $root 'PackageFileStaging'
            PackageInstallStageRootDirectory    = Join-Path $root 'PackageInstallStage'
            DefaultPackageDepotDirectory        = Join-Path $root 'DefaultPackageDepot'
            LocalRepositoryRoot                 = Join-Path $root 'PackageRepositories'
            ShimDirectory                       = Join-Path $root 'Shims'
            PackageInventoryFilePath            = Join-Path (Join-Path $root 'State') 'package-inventory.json'
            PackageOperationHistoryFilePath     = Join-Path (Join-Path $root 'State') 'package-operation-history.json'
        }
        $packageInventory = [pscustomobject]@{ Path = $config.PackageInventoryFilePath; Records = @([pscustomobject]@{ definitionId = 'VSCodeRuntime' }) }
        $operationHistory = [pscustomobject]@{ Path = $config.PackageOperationHistoryFilePath; Records = @([pscustomobject]@{ definitionId = 'VSCodeRuntime' }) }
        $sourceInventory = [pscustomobject]@{ Path = (Join-Path (Join-Path $root 'Configuration\External') 'SourceInventory.json'); Exists = $false; Document = $null }

        $config | Add-Member -MemberType NoteProperty -Name SourceInventoryInfo -Value $sourceInventory

        Mock Get-PackageConfig { throw 'Get-PackageState must not load a package definition.' }
        Mock Get-PackageStateConfig { return $config }
        Mock Get-PackageInventory { return $packageInventory }
        Mock Get-PackageOperationHistory { return $operationHistory }

        $state = Get-PackageState -Raw

        $state.Config | Should -Be $config
        $state.PackageInventory | Should -Be $packageInventory
        $state.OperationHistory | Should -Be $operationHistory
        $state.SourceInventory | Should -Be $sourceInventory
        $state.Directories.Installed.Path | Should -Be $config.PreferredTargetInstallRootDirectory
    }

    It 'does not export migrated legacy runtime commands' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru

        # Resolve commands against this import only: another copy of the module on PSModulePath
        # (e.g. Documents\WindowsPowerShell\Modules) can otherwise satisfy Get-Command by name alone.
        Get-Command -Name 'Get-SandboxState' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-VSCodeRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-GitRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-GHCliRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-NodeRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-PythonRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-Ps7Runtime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-VCRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-CodexRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-GeminiRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-OpenCodeRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-QwenRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-CodexRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-GeminiRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-OpenCodeRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-QwenCliRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-GHCliRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Qwen35-2B-Q6K' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Qwen35-2B-Q6K-Model' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-VCRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Ps7Runtime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-VSCodeRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-GitRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-GHCliRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-NodeRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-PythonRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-Ps7Runtime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-VCRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-CodexRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-GeminiRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-OpenCodeRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-QwenCliRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-Qwen35-2B-Q6K' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-LlamaCppRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-PackageDefinitionCommand' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-CodexCli' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-GitRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-VSCodeRuntime' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-GitHubCli' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Qwen35-2B-Q8-0-Model' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-QwenCli' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-GeminiCli' -Module $module -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

}
