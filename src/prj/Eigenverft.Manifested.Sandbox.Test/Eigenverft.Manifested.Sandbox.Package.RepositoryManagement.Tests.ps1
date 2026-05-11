<#
    Eigenverft.Manifested.Sandbox Package - repository management
#>

. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.Module.TestHelpers.ps1"

Invoke-TestPackageDescribe -Name 'Eigenverft.Manifested.Sandbox Package - repository management' -Body {
    It 'exports repository management commands' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru

        foreach ($commandName in @('Get-PackageRepository', 'Add-PackageRepository', 'Add-TeamPackageRepository', 'Set-PackageRepository', 'Remove-PackageRepository', 'Trust-PackageRepository')) {
            $module.ExportedCommands.Keys | Should -Contain $commandName
        }
    }

    It 'adds a team package repository as enabled but untrusted at searchOrder 150 by default' {
        $root = Join-Path $TestDrive 'repo-add-team'
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageRepositoryInventory.json'
        Write-TestJsonDocument -Path $inventoryPath -Document (New-TestRepositoryInventoryDocument)

        Mock Get-PackageRepositoryInventoryPath { $inventoryPath }

        $result = Add-TeamPackageRepository -BasePath '\\team-share\PackageRepository' -WarningAction SilentlyContinue
        $source = (Read-PackageJsonDocument -Path $inventoryPath).Document.repositorySources.teamPackageRepository

        $result.Action | Should -Be 'Add'
        $source.kind | Should -Be 'filesystem'
        $source.enabled | Should -BeTrue
        $source.searchOrder | Should -Be 150
        $source.basePath | Should -Be '\\team-share\PackageRepository'
        $source.trusted | Should -BeFalse
        $source.trustMode | Should -Be 'unsigned'
        $result.Notes -join "`n" | Should -Match 'untrusted'
    }

    It 'places a package repository after an existing repository when requested' {
        $root = Join-Path $TestDrive 'repo-add-after'
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageRepositoryInventory.json'
        $inventory = New-TestRepositoryInventoryDocument -RepositorySources @{
            sitePackageRepository = @{
                kind        = 'filesystem'
                enabled     = $true
                searchOrder = 200
                basePath    = '\\site-share\PackageRepository'
                trusted     = $false
                trustMode   = 'unsigned'
            }
        }
        Write-TestJsonDocument -Path $inventoryPath -Document $inventory

        Mock Get-PackageRepositoryInventoryPath { $inventoryPath }

        Add-PackageRepository -RepositoryId 'betweenRepository' -BasePath '\\between-share\PackageRepository' -After 'EigenverftModule' -WarningAction SilentlyContinue | Out-Null
        $source = (Read-PackageJsonDocument -Path $inventoryPath).Document.repositorySources.betweenRepository

        $source.searchOrder | Should -Be 150
    }

    It 'trusts an existing filesystem repository only with explicit unsigned permission' {
        $root = Join-Path $TestDrive 'repo-trust'
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageRepositoryInventory.json'
        $inventory = New-TestRepositoryInventoryDocument -RepositorySources @{
            teamPackageRepository = @{
                kind        = 'filesystem'
                enabled     = $true
                searchOrder = 150
                basePath    = '\\team-share\PackageRepository'
                trusted     = $false
                trustMode   = 'unsigned'
            }
        }
        Write-TestJsonDocument -Path $inventoryPath -Document $inventory

        Mock Get-PackageRepositoryInventoryPath { $inventoryPath }

        { Trust-PackageRepository -RepositoryId 'teamPackageRepository' } | Should -Throw '*-AllowUnsignedDefinitions*'

        $result = Trust-PackageRepository -RepositoryId 'teamPackageRepository' -AllowUnsignedDefinitions -WarningAction SilentlyContinue
        $source = (Read-PackageJsonDocument -Path $inventoryPath).Document.repositorySources.teamPackageRepository

        $result.Status | Should -Be 'Trusted'
        $source.trusted | Should -BeTrue
        $source.trustMode | Should -Be 'unsignedExplicit'
        $source.trustedAtUtc | Should -Not -BeNullOrEmpty
    }

    It 'removes a repository entry without deleting repository files' {
        $root = Join-Path $TestDrive 'repo-remove'
        $repositoryRoot = Join-Path $root 'team-repo'
        $markerPath = Join-Path $repositoryRoot 'keep.json'
        Write-TestJsonDocument -Path $markerPath -Document @{ keep = $true }
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageRepositoryInventory.json'
        $inventory = New-TestRepositoryInventoryDocument -RepositorySources @{
            teamPackageRepository = @{
                kind        = 'filesystem'
                enabled     = $true
                searchOrder = 150
                basePath    = $repositoryRoot
                trusted     = $true
                trustMode   = 'unsignedExplicit'
            }
        }
        Write-TestJsonDocument -Path $inventoryPath -Document $inventory

        Mock Get-PackageRepositoryInventoryPath { $inventoryPath }

        $result = Remove-PackageRepository -RepositoryId 'teamPackageRepository' -Confirm:$false -WarningAction SilentlyContinue
        $sources = (Read-PackageJsonDocument -Path $inventoryPath).Document.repositorySources

        $result.Status | Should -Be 'Removed'
        $sources.PSObject.Properties['teamPackageRepository'] | Should -BeNullOrEmpty
        Test-Path -LiteralPath $markerPath -PathType Leaf | Should -BeTrue
        $result.Notes -join "`n" | Should -Match 'were not deleted'
    }

    It 'rejects disabled or untrusted filesystem repositories during definition resolution' {
        $root = Join-Path $TestDrive 'repo-reject'
        $repositoryRoot = Join-Path $root 'team-repo'
        Write-TestJsonDocument -Path (Join-Path $repositoryRoot 'VSCodeRuntime.json') -Document (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-v1' -Version '1.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageRepositoryInventory.json'
        $inventory = New-TestRepositoryInventoryDocument -RepositorySources @{
            disabledRepository = @{
                kind        = 'filesystem'
                enabled     = $false
                searchOrder = 150
                basePath    = $repositoryRoot
                trusted     = $true
                trustMode   = 'unsignedExplicit'
            }
            untrustedRepository = @{
                kind        = 'filesystem'
                enabled     = $true
                searchOrder = 160
                basePath    = $repositoryRoot
                trusted     = $false
                trustMode   = 'unsigned'
            }
        }
        Write-TestJsonDocument -Path $inventoryPath -Document $inventory

        Mock Get-PackageRepositoryInventoryPath { $inventoryPath }

        { Resolve-PackageDefinitionReference -RepositoryId 'disabledRepository' -DefinitionId 'VSCodeRuntime' } | Should -Throw '*disabled*'
        { Resolve-PackageDefinitionReference -RepositoryId 'untrustedRepository' -DefinitionId 'VSCodeRuntime' } | Should -Throw '*not trusted*'
    }

    It 'reads live filesystem repository definitions on every assignment selection' {
        $root = Join-Path $TestDrive 'repo-live-update'
        $applicationRoot = Join-Path $root 'AppRoot'
        $repositoryRoot = Join-Path $root 'team-repo'
        $definitionPath = Join-Path $repositoryRoot 'VSCodeRuntime.json'
        Write-TestJsonDocument -Path $definitionPath -Document (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-v1' -Version '1.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory $applicationRoot
        $depotInventory = New-TestDepotInventoryDocument -DefaultPackageDepotDirectory (Join-Path $root 'PkgDepot')
        $repositoryInventory = New-TestRepositoryInventoryDocument -RepositorySources @{
            teamPackageRepository = @{
                kind        = 'filesystem'
                enabled     = $true
                searchOrder = 150
                basePath    = $repositoryRoot
                trusted     = $true
                trustMode   = 'unsignedExplicit'
            }
        }
        $documents = Write-TestPackageDocuments -RootPath $root -GlobalDocument $globalDocument -DepotInventoryDocument $depotInventory -RepositoryInventoryDocument $repositoryInventory -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'unused' -Version '0.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))

        Mock Get-PackageConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageRepositoryInventoryPath { $documents.RepositoryInventoryPath }

        $firstResult = Resolve-PackagePackage -PackageResult (New-PackageResult -PackageConfig (Get-PackageConfig -RepositoryId 'teamPackageRepository' -DefinitionId 'VSCodeRuntime'))
        $firstResult.PackageVersion | Should -Be '1.0.0'

        Write-TestJsonDocument -Path $definitionPath -Document (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-v2' -Version '2.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))

        $secondResult = Resolve-PackagePackage -PackageResult (New-PackageResult -PackageConfig (Get-PackageConfig -RepositoryId 'teamPackageRepository' -DefinitionId 'VSCodeRuntime'))
        $secondResult.PackageVersion | Should -Be '2.0.0'
    }

    It 'falls back to an inventory definition snapshot for removed state when the live repository is unavailable' {
        $root = Join-Path $TestDrive 'repo-removed-snapshot'
        $applicationRoot = Join-Path $root 'AppRoot'
        $snapshotPath = Join-Path $applicationRoot 'PkgRepos\teamPackageRepository\VSCodeRuntime.json'
        Write-TestJsonDocument -Path $snapshotPath -Document (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-v1' -Version '1.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory $applicationRoot
        $depotInventory = New-TestDepotInventoryDocument -DefaultPackageDepotDirectory (Join-Path $root 'PkgDepot')
        $repositoryInventory = New-TestRepositoryInventoryDocument -RepositorySources @{
            teamPackageRepository = @{
                kind        = 'filesystem'
                enabled     = $false
                searchOrder = 150
                basePath    = (Join-Path $root 'missing-repo')
                trusted     = $true
                trustMode   = 'unsignedExplicit'
            }
        }
        $documents = Write-TestPackageDocuments -RootPath $root -GlobalDocument $globalDocument -DepotInventoryDocument $depotInventory -RepositoryInventoryDocument $repositoryInventory -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'unused' -Version '0.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))
        $inventoryPath = Join-Path $applicationRoot 'State\PackageAssignmentInventory.json'
        Write-TestJsonDocument -Path $inventoryPath -Document @{
            schemaVersion = 1
            records = @(
                @{
                    installSlotId = 'VSCodeRuntime:stable:win32-x64'
                    definitionId = 'VSCodeRuntime'
                    definitionRepositoryId = 'teamPackageRepository'
                    definitionFileName = 'VSCodeRuntime.json'
                    definitionSourceKind = 'filesystem'
                    definitionSourcePath = Join-Path $root 'missing-repo'
                    definitionSnapshotPath = $snapshotPath
                    definitionSnapshotHash = (Get-PackageFileSha256 -Path $snapshotPath)
                    releaseTrack = 'stable'
                    artifactDistributionVariant = 'win32-x64'
                    currentReleaseId = 'vsCode-v1'
                    currentVersion = '1.0.0'
                    installDirectory = Join-Path $applicationRoot 'Inst\vscode'
                    ownershipKind = 'PackageInstalled'
                    updatedAtUtc = '2026-05-11T00:00:00Z'
                }
            )
        }

        Mock Get-PackageConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageRepositoryInventoryPath { $documents.RepositoryInventoryPath }

        $config = Get-PackageConfig -RepositoryId 'teamPackageRepository' -DefinitionId 'VSCodeRuntime' -DesiredState Removed

        $config.DefinitionSnapshotFallback | Should -BeTrue
        $config.DefinitionPath | Should -Be ([System.IO.Path]::GetFullPath($snapshotPath))
    }
}
