<#
    Eigenverft.Manifested.Sandbox Package - exports and state
#>

. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.Module.TestHelpers.ps1"

Invoke-TestPackageDescribe -Name 'Eigenverft.Manifested.Sandbox Package - exports and state' -Body {
    It 'exports Invoke-PackageDefinitionCommand with generic package parameters' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-PackageDefinitionCommand'

        $command | Should -Not -BeNullOrEmpty
        $command.Parameters.Keys | Should -Contain 'DefinitionId'
        $command.Parameters.Keys | Should -Contain 'RepositoryId'
        $command.Parameters.Keys | Should -Contain 'DesiredState'
        $command.Parameters.Keys | Should -Not -Contain 'CommandName'
        $command.Parameters.Keys | Should -Not -Contain 'DependencyStack'
    }

    It 'exports Invoke-Package as the slim public package command' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-Package'

        $command | Should -Not -BeNullOrEmpty
        $command.Parameters.Keys | Should -Contain 'DefinitionId'
        $command.Parameters.Keys | Should -Contain 'DesiredState'
        $command.Parameters.Keys | Should -Not -Contain 'RepositoryId'
        $command.Parameters.Keys | Should -Not -Contain 'DependencyStack'
    }

    It 'exports Invoke-VSCodeRuntime and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-VSCodeRuntime'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-NotepadPlusPlus and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-NotepadPlusPlus'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-LlamaCppRuntime and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-LlamaCppRuntime'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-Qwen35-2B-Q8-0-Model and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-Qwen35-2B-Q8-0-Model'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-GitRuntime and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-GitRuntime'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-GitHubCli and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-GitHubCli'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-Qwen35-9B-Q6-K-Model and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-Qwen35-9B-Q6-K-Model'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-NodeRuntime and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-NodeRuntime'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports npm-backed Package CLI runtime commands and keeps them parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru

        foreach ($commandName in @(
                'Invoke-CodexCli'
                'Invoke-GeminiCli'
                'Invoke-OpenCodeCli'
                'Invoke-QwenCli'
            )) {
            $command = Get-Command -Name $commandName
            $command | Should -Not -BeNullOrEmpty
            $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                    $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                    $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
            $publicParameterNames.Count | Should -Be 0
        }
    }

    It 'exports Invoke-PythonRuntime and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-PythonRuntime'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-PowerShell7 and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-PowerShell7'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-VisualCppRedistributable and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-VisualCppRedistributable'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        })
        $publicParameterNames.Count | Should -Be 0
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

    It 'returns an empty package state when durable inventory/history files and local directories are absent' {
        $root = Join-Path $TestDrive 'empty-package-state'
        $config = [pscustomobject]@{
            LocalConfigurationPath              = Join-Path $root 'Configuration\Internal\Config.json'
            PreferredTargetInstallRootDirectory = Join-Path $root 'Installed'
            PackageFileStagingRootDirectory       = Join-Path $root 'PackageFileStaging'
            PackageInstallStageRootDirectory    = Join-Path $root 'PackageInstallStage'
            DefaultPackageDepotDirectory        = Join-Path $root 'DefaultPackageDepot'
            LocalRepositoryRoot                 = Join-Path $root 'PackageRepositories'
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
    }

    It 'gets package state without loading a package definition config' {
        $root = Join-Path $TestDrive 'definition-free-package-state'
        $config = [pscustomobject]@{
            LocalConfigurationPath              = Join-Path $root 'Configuration\Internal\Config.json'
            PreferredTargetInstallRootDirectory = Join-Path $root 'Installed'
            PackageFileStagingRootDirectory       = Join-Path $root 'PackageFileStaging'
            PackageInstallStageRootDirectory    = Join-Path $root 'PackageInstallStage'
            DefaultPackageDepotDirectory        = Join-Path $root 'DefaultPackageDepot'
            LocalRepositoryRoot                 = Join-Path $root 'PackageRepositories'
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
        $installRoot = Join-Path $root 'Installed'
        $workspaceRoot = Join-Path $root 'PackageFileStaging'
        $installStageRoot = Join-Path $root 'PackageInstallStage'
        $depotRoot = Join-Path $root 'DefaultPackageDepot'
        $localRepositoryRoot = Join-Path $root 'PackageRepositories'
        $installDirectory = Join-Path $installRoot 'vscode-runtime\stable\1.0.0\win32-x64'
        $definitionLocalPath = Join-Path $localRepositoryRoot 'EigenverftModule\VSCodeRuntime.json'
        $sourceInventoryPath = Join-Path (Join-Path $root 'Configuration\External') 'SourceInventory.json'

        $null = New-Item -ItemType Directory -Path $installDirectory -Force
        $null = New-Item -ItemType Directory -Path $workspaceRoot -Force
        $null = New-Item -ItemType Directory -Path $installStageRoot -Force
        $null = New-Item -ItemType Directory -Path $depotRoot -Force
        Write-TestJsonDocument -Path $definitionLocalPath -Document (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '1.0.0' -Architecture 'x64' -Flavor 'win32-x64'
            ))
        Write-TestJsonDocument -Path $sourceInventoryPath -Document @{ inventoryVersion = 1; global = @{}; sites = @{} }

        $config = [pscustomobject]@{
            LocalConfigurationPath              = Join-Path $root 'Configuration\Internal\Config.json'
            PreferredTargetInstallRootDirectory = $installRoot
            PackageFileStagingRootDirectory       = $workspaceRoot
            PackageInstallStageRootDirectory    = $installStageRoot
            DefaultPackageDepotDirectory        = $depotRoot
            LocalRepositoryRoot                 = $localRepositoryRoot
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
            definitionLocalPath = $definitionLocalPath
            releaseTrack     = 'stable'
            flavor           = 'win32-x64'
            currentReleaseId = 'vscode-test'
            currentVersion   = '1.0.0'
            installDirectory = $installDirectory
            ownershipKind    = 'PackageInstalled'
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
        $state.PackageRecords[0].DefinitionLocalExists | Should -BeTrue
        $state.PackageRecords[0].InstallDirectoryExists | Should -BeTrue
        $state.OperationRecords[0].operationId | Should -Be 'test-operation'
        $state.Directories.Installed.Exists | Should -BeTrue
        $state.Directories.PackageFileStaging.Exists | Should -BeTrue
        $state.Directories.PackageInstallStage.Exists | Should -BeTrue
        $state.Directories.DefaultPackageDepot.Exists | Should -BeTrue
        $state.Directories.LocalRepositoryRoot.Exists | Should -BeTrue
    }

    It 'returns the resolved raw package state on request' {
        $root = Join-Path $TestDrive 'raw-package-state'
        $config = [pscustomobject]@{
            LocalConfigurationPath              = Join-Path $root 'Configuration\Internal\Config.json'
            PreferredTargetInstallRootDirectory = Join-Path $root 'Installed'
            PackageFileStagingRootDirectory       = Join-Path $root 'PackageFileStaging'
            PackageInstallStageRootDirectory    = Join-Path $root 'PackageInstallStage'
            DefaultPackageDepotDirectory        = Join-Path $root 'DefaultPackageDepot'
            LocalRepositoryRoot                 = Join-Path $root 'PackageRepositories'
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

        Get-Command -Name 'Get-SandboxState' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-VSCodeRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-GitRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-GHCliRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-NodeRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-PythonRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-Ps7Runtime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-VCRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-CodexRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-GeminiRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-OpenCodeRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-QwenRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-CodexRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-GeminiRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-OpenCodeRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-QwenCliRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-GHCliRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Qwen35-2B-Q6K' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Qwen35-2B-Q6K-Model' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-VCRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Ps7Runtime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-VSCodeRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-GitRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-GHCliRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-NodeRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-PythonRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-Ps7Runtime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-VCRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-CodexRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-GeminiRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-OpenCodeRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-QwenCliRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-Qwen35-2B-Q6K' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Invoke-Package-LlamaCppRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

}
