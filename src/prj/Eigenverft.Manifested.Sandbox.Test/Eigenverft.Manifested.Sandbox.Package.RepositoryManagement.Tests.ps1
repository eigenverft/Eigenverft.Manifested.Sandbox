<#
    Eigenverft.Manifested.Sandbox Package - package endpoint (scan root) management
#>

. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.Module.TestHelpers.ps1"

Invoke-TestPackageDescribe -Name 'Eigenverft.Manifested.Sandbox Package - endpoint management' -Body {
    It 'exports package endpoint management commands' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru

        foreach ($commandName in @('Get-PackageEndpoint', 'Add-PackageEndpoint', 'Add-TeamPackageEndpoint', 'Set-PackageEndpoint', 'Remove-PackageEndpoint', 'Trust-PackageEndpoint')) {
            $module.ExportedCommands.Keys | Should -Contain $commandName
        }
    }

    It 'adds a team package endpoint as enabled and trusted at searchOrder 150 by default' {
        $root = Join-Path $TestDrive 'repo-add-team'
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageEndpointInventory.json'
        Write-TestJsonDocument -Path $inventoryPath -Document (New-TestEndpointInventoryDocument)

        Mock Get-PackageEndpointInventoryPath { $inventoryPath }

        $result = Add-TeamPackageEndpoint -BasePath '\\team-share\PackageRepository' -WarningAction SilentlyContinue
        $source = Get-TestRepositorySource -Document (Read-PackageJsonDocument -Path $inventoryPath).Document -SourceId 'teamPackageRepository'

        $result.Action | Should -Be 'Add'
        $source.kind | Should -Be 'filesystem'
        $source.enabled | Should -BeTrue
        $source.searchOrder | Should -Be 150
        $source.basePath | Should -Be '\\team-share\PackageRepository'
        $source.trusted | Should -BeTrue
        $source.trustMode | Should -Be 'unsignedExplicit'
        $source.trustedAtUtc | Should -Not -BeNullOrEmpty
        $result.Notes -join "`n" | Should -Match 'trusts unsigned'
    }

    It 'adds a team package endpoint untrusted when -Untrusted is specified' {
        $root = Join-Path $TestDrive 'repo-add-team-untrusted'
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageEndpointInventory.json'
        Write-TestJsonDocument -Path $inventoryPath -Document (New-TestEndpointInventoryDocument)

        Mock Get-PackageEndpointInventoryPath { $inventoryPath }

        $null = Add-TeamPackageEndpoint -BasePath '\\team-share\PackageRepository' -Untrusted -WarningAction SilentlyContinue
        $source = Get-TestRepositorySource -Document (Read-PackageJsonDocument -Path $inventoryPath).Document -SourceId 'teamPackageRepository'

        $source.trusted | Should -BeFalse
        $source.trustMode | Should -Be 'unsigned'
    }

    It 'places a package endpoint after an existing endpoint when requested' {
        $root = Join-Path $TestDrive 'repo-add-after'
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageEndpointInventory.json'
        $inventory = New-TestEndpointInventoryDocument -EndpointSources @{
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

        Mock Get-PackageEndpointInventoryPath { $inventoryPath }

        Add-PackageEndpoint -EndpointName 'betweenRepository' -BasePath '\\between-share\PackageRepository' -After 'moduleDefaults' -WarningAction SilentlyContinue | Out-Null
        $source = Get-TestRepositorySource -Document (Read-PackageJsonDocument -Path $inventoryPath).Document -SourceId 'betweenRepository'

        $source.searchOrder | Should -Be 150
    }

    It 'trusts an existing filesystem endpoint only with explicit unsigned permission' {
        $root = Join-Path $TestDrive 'repo-trust'
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageEndpointInventory.json'
        $inventory = New-TestEndpointInventoryDocument -EndpointSources @{
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

        Mock Get-PackageEndpointInventoryPath { $inventoryPath }

        { Trust-PackageEndpoint -EndpointName 'teamPackageRepository' } | Should -Throw '*-AllowUnsignedDefinitions*'

        $result = Trust-PackageEndpoint -EndpointName 'teamPackageRepository' -AllowUnsignedDefinitions -WarningAction SilentlyContinue
        $source = Get-TestRepositorySource -Document (Read-PackageJsonDocument -Path $inventoryPath).Document -SourceId 'teamPackageRepository'

        $result.Status | Should -Be 'Trusted'
        $source.trusted | Should -BeTrue
        $source.trustMode | Should -Be 'unsignedExplicit'
        $source.trustedAtUtc | Should -Not -BeNullOrEmpty
    }

    It 'removes an endpoint entry without deleting repository files' {
        $root = Join-Path $TestDrive 'repo-remove'
        $repositoryRoot = Join-Path $root 'team-repo'
        $markerPath = Join-Path $repositoryRoot 'keep.json'
        Write-TestJsonDocument -Path $markerPath -Document @{ keep = $true }
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageEndpointInventory.json'
        $inventory = New-TestEndpointInventoryDocument -EndpointSources @{
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

        Mock Get-PackageEndpointInventoryPath { $inventoryPath }

        $result = Remove-PackageEndpoint -EndpointName 'teamPackageRepository' -Confirm:$false -WarningAction SilentlyContinue
        $sources = (Read-PackageJsonDocument -Path $inventoryPath).Document.endpoints

        $result.Status | Should -Be 'Removed'
        @(($sources | Where-Object { [string]::Equals([string]$_.endpointName, 'teamPackageRepository', [System.StringComparison]::OrdinalIgnoreCase) })).Count | Should -Be 0
        Test-Path -LiteralPath $markerPath -PathType Leaf | Should -BeTrue
        $result.Notes -join "`n" | Should -Match 'were not deleted'
    }

    It 'rejects disabled or untrusted filesystem repositories during definition resolution' {
        $root = Join-Path $TestDrive 'repo-reject'
        $repositoryRoot = Join-Path $root 'team-repo'
        Write-TestJsonDocument -Path (Join-Path $repositoryRoot 'VSCodeRuntime.json') -Document (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-v1' -Version '1.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))
        $inventoryPath = Join-Path $root 'Configuration\Internal\PackageEndpointInventory.json'
        $inventory = New-TestEndpointInventoryDocument -EndpointSources @{
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

        $inventoryDocInfo = Read-PackageJsonDocument -Path $inventoryPath
        $inventoryDocInfo | Add-Member -MemberType NoteProperty -Name Exists -Value $true -Force
        Mock Get-PackageEndpointInventoryInfo { return $inventoryDocInfo }

        { Resolve-PackageDefinitionReference -DefinitionId 'VSCodeRuntime' } | Should -Throw '*was not found*'
    }

    It 'reads live filesystem repository definitions on every assignment selection' {
        $root = Join-Path $TestDrive 'repo-live-update'
        $applicationRoot = Join-Path $root 'AppRoot'
        $repositoryRoot = Join-Path $root 'team-repo'
        $definitionPath = Join-Path $repositoryRoot 'VSCodeRuntime.json'
        Write-TestJsonDocument -Path $definitionPath -Document (New-TestVSCodeDefinitionDocument -RepositoryId 'TeamLiveRepo' -Releases @(
                New-TestPackageRelease -Id 'vsCode-v1' -Version '1.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory $applicationRoot
        $depotInventory = New-TestDepotInventoryDocument -DefaultPackageDepotDirectory (Join-Path $root 'PkgDepot')
        $endpointInventory = @{
            inventoryVersion = 2
            endpoints        = @(
                @{
                    endpointName = 'teamPackageRepository'
                    kind           = 'filesystem'
                    enabled        = $true
                    searchOrder    = 150
                    basePath       = $repositoryRoot
                    trusted        = $true
                    trustMode      = 'unsignedExplicit'
                }
            )
        }
        $documents = Write-TestPackageDocuments -RootPath $root -GlobalDocument $globalDocument -DepotInventoryDocument $depotInventory -EndpointInventoryDocument $endpointInventory -DefinitionDocument (New-TestVSCodeDefinitionDocument -RepositoryId 'TeamLiveRepo' -Releases @(
                New-TestPackageRelease -Id 'unused' -Version '0.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))

        Mock Get-PackageConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageEndpointInventoryInfo {
            $docInfo = Read-PackageJsonDocument -Path $documents.EndpointInventoryPath
            $docInfo | Add-Member -MemberType NoteProperty -Name Exists -Value $true -Force
            return $docInfo
        }

        $firstResult = Resolve-PackagePackage -PackageResult (New-PackageResult -PackageConfig (Get-PackageConfig -RepositoryId 'TeamLiveRepo' -DefinitionId 'VSCodeRuntime')))
        $firstResult.PackageVersion | Should -Be '1.0.0'

        Write-TestJsonDocument -Path $definitionPath -Document (New-TestVSCodeDefinitionDocument -RepositoryId 'TeamLiveRepo' -Releases @(
                New-TestPackageRelease -Id 'vsCode-v2' -Version '2.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))

        $secondResult = Resolve-PackagePackage -PackageResult (New-PackageResult -PackageConfig (Get-PackageConfig -RepositoryId 'TeamLiveRepo' -DefinitionId 'VSCodeRuntime')))
        $secondResult.PackageVersion | Should -Be '2.0.0'
    }

    It 'falls back to an inventory definition snapshot for removed state when the live repository is unavailable' {
        $root = Join-Path $TestDrive 'repo-removed-snapshot'
        $applicationRoot = Join-Path $root 'AppRoot'
        $snapshotPath = Join-Path $applicationRoot 'PkgRepos\Assigned\Eigenverft\VSCodeRuntime.json'
        Write-TestJsonDocument -Path $snapshotPath -Document (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-v1' -Version '1.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))
        $globalDocument = New-TestPackageGlobalDocument -ApplicationRootDirectory $applicationRoot
        $depotInventory = New-TestDepotInventoryDocument -DefaultPackageDepotDirectory (Join-Path $root 'PkgDepot')
        $endpointInventory = @{
            inventoryVersion = 2
            endpoints        = @(
                @{
                    endpointName = 'teamPackageRepository'
                    kind           = 'filesystem'
                    enabled        = $false
                    searchOrder    = 150
                    basePath       = (Join-Path $root 'missing-repo')
                    trusted        = $true
                    trustMode      = 'unsignedExplicit'
                }
            )
        }
        $documents = Write-TestPackageDocuments -RootPath $root -GlobalDocument $globalDocument -DepotInventoryDocument $depotInventory -EndpointInventoryDocument $endpointInventory -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'unused' -Version '0.0.0' -Architecture 'x64' -ArtifactDistributionVariant 'win32-x64'
            ))
        $inventoryPath = Join-Path $applicationRoot 'State\PackageAssignmentInventory.json'
        Write-TestJsonDocument -Path $inventoryPath -Document @{
            schemaVersion = 1
            records = @(
                @{
                    installSlotId = 'VSCodeRuntime:stable:win32-x64'
                    definitionId = 'VSCodeRuntime'
                    definitionPublisherId = 'Eigenverft'
                    definitionPublisherName = 'Eigenverft'
                    definitionRevision = 1
                    definitionPublishedAtUtc = '2026-05-13T12:00:00Z'
                    definitionRepositorySourceId = 'EigenverftModule'
                    definitionSourceKind = 'filesystem'
                    definitionSourcePath = Join-Path $root 'missing-repo'
                    definitionAssignedSnapshotPath = $snapshotPath
                    definitionAssignedSnapshotHash = (Get-PackageFileSha256 -Path $snapshotPath)
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
        $snapshotInventoryDocInfo = Read-PackageJsonDocument -Path $documents.EndpointInventoryPath
        $snapshotInventoryDocInfo | Add-Member -MemberType NoteProperty -Name Exists -Value $true -Force
        Mock Get-PackageEndpointInventoryInfo { return $snapshotInventoryDocInfo }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime' -DesiredState Removed

        $config.DefinitionSnapshotFallback | Should -BeTrue
        $config.DefinitionPath | Should -Be ([System.IO.Path]::GetFullPath($snapshotPath))
    }
}

