<#
    Eigenverft.Manifested.Sandbox Package - acquisition and ownership
#>

. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.Module.TestHelpers.ps1"

Invoke-TestPackageDescribe -Name 'Eigenverft.Manifested.Sandbox Package - acquisition and ownership' -Body {
    It 'resolves installRootRules for code.cmd and Code.exe' {
        $installRoot = Join-Path $TestDrive 'existing-root'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        $codeCmdPath = Join-Path $binDirectory 'code.cmd'
        $codeExePath = Join-Path $installRoot 'Code.exe'
        Write-TestTextFile -Path $codeCmdPath -Content '@echo off'
        Write-TestTextFile -Path $codeExePath -Content 'fake'

        $discovery = ConvertTo-TestPsObject @{
            enableDetection = $true
            searchLocations = @()
            installRootRules = @(
                @{
                    match = @{
                        kind  = 'fileName'
                        value = 'code.cmd'
                    }
                    installRootRelativePath = '..'
                },
                @{
                    match = @{
                        kind  = 'fileName'
                        value = 'Code.exe'
                    }
                    installRootRelativePath = '.'
                }
            )
        }

        (Resolve-PackageExistingInstallRoot -ExistingInstallDiscovery $discovery -CandidatePath $codeCmdPath) | Should -Be $installRoot
        (Resolve-PackageExistingInstallRoot -ExistingInstallDiscovery $discovery -CandidatePath $codeExePath) | Should -Be $installRoot
    }

    It 'keeps packageFileStaging and defaultPackageDepot distinct in the resolved paths' {
        $rootPath = Join-Path $TestDrive 'distinct-roots'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0'
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind        = 'packageDepot'
                searchOrder    = 10
                verification = @{ mode = 'optional'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            }
        )
        $globalDocument = New-TestPackageGlobalDocument -PackageFileStagingDirectory (Join-Path $rootPath 'workspace')
        $depotInventoryDocument = New-TestDepotInventoryDocument -DefaultPackageDepotDirectory (Join-Path $rootPath 'default-depot')
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DepotInventoryDocument $depotInventoryDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result

        $result.PackageFileStagingDirectory | Should -Not -Be $config.DefaultPackageDepotDirectory
        $result.PackageFilePath | Should -Not -Be $result.DefaultPackageDepotFilePath
        Split-Path -Parent $result.DefaultPackageDepotFilePath | Should -Match 'default-depot'
    }

    It 'hydrates the package file staging from the default package depot before upstream download' {
        $rootPath = Join-Path $TestDrive 'default-depot-hydration'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0' -ArchiveFileName 'VSCode-win32-x64-2.0.0.zip'
        $globalDocument = New-TestPackageGlobalDocument -PackageFileStagingDirectory (Join-Path $rootPath 'workspace') -DefaultPackageDepotDirectory (Join-Path $rootPath 'default-depot')
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind        = 'packageDepot'
                searchOrder    = 10
                verification = @{ mode = 'required'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            },
            @{
                kind        = 'download'
                sourceId    = 'vsCodeUpdateService'
                searchOrder    = 100
                sourcePath  = '2.0.0/win32-x64-archive/stable'
                verification = @{ mode = 'required'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            }
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }
        Mock Save-PackageDownloadFile { throw 'download should not run when the default package depot already has a verified artifact' }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result
        $result = Build-PackageAcquisitionPlan -PackageResult $result

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $result.DefaultPackageDepotFilePath) -Force
        Copy-Item -LiteralPath $packageArchive.ZipPath -Destination $result.DefaultPackageDepotFilePath -Force

        $result = Prepare-PackageInstallFile -PackageResult $result

        $result.PackageFilePreparation.Success | Should -BeTrue
        $result.PackageFilePreparation.Status | Should -Be 'HydratedFromDefaultPackageDepot'
        Test-Path -LiteralPath $result.PackageFilePath | Should -BeTrue
        (Get-FileHash -LiteralPath $result.PackageFilePath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $packageArchive.Sha256
        Assert-MockCalled Save-PackageDownloadFile -Times 0
    }

    It 'hydrates from a read-only default package depot without trying to create or mirror into it' {
        $rootPath = Join-Path $TestDrive 'readonly-default-depot-hydration'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0' -ArchiveFileName 'VSCode-win32-x64-2.0.0.zip'
        $defaultDepotPath = Join-Path $rootPath 'readonly-default-depot'
        $globalDocument = New-TestPackageGlobalDocument -PackageFileStagingDirectory (Join-Path $rootPath 'workspace')
        $depotInventoryDocument = New-TestDepotInventoryDocument -DefaultPackageDepotDirectory $defaultDepotPath
        $depotInventoryDocument.acquisitionEnvironment.environmentSources.defaultPackageDepot.writable = $false
        $depotInventoryDocument.acquisitionEnvironment.environmentSources.defaultPackageDepot.mirrorTarget = $false
        $depotInventoryDocument.acquisitionEnvironment.environmentSources.defaultPackageDepot.ensureExists = $false
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                searchOrder  = 10
                verification = @{ mode = 'required'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            },
            @{
                kind         = 'download'
                sourceId     = 'vsCodeUpdateService'
                searchOrder  = 100
                sourcePath   = '2.0.0/win32-x64-archive/stable'
                verification = @{ mode = 'required'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            }
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DepotInventoryDocument $depotInventoryDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDepotInventoryPath { $documents.DepotInventoryPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }
        Mock Save-PackageDownloadFile { throw 'download should not run when a readable package depot already has a verified artifact' }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result
        $result = Build-PackageAcquisitionPlan -PackageResult $result

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $result.DefaultPackageDepotFilePath) -Force
        Copy-Item -LiteralPath $packageArchive.ZipPath -Destination $result.DefaultPackageDepotFilePath -Force

        $result = Prepare-PackageInstallFile -PackageResult $result

        $result.PackageFilePreparation.Success | Should -BeTrue
        $result.PackageFilePreparation.Status | Should -Be 'HydratedFromDefaultPackageDepot'
        Test-Path -LiteralPath $result.PackageFilePath | Should -BeTrue
        Assert-MockCalled Save-PackageDownloadFile -Times 0
    }

    It 'uses packageFile.contentHash when acquisition candidates only declare verification mode' {
        $rootPath = Join-Path $TestDrive 'packagefile-contenthash'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0' -ArchiveFileName 'VSCode-win32-x64-2.0.0.zip'
        $globalDocument = New-TestPackageGlobalDocument -PackageFileStagingDirectory (Join-Path $rootPath 'workspace') -DefaultPackageDepotDirectory (Join-Path $rootPath 'default-depot')
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -PackageFileSha256 $packageArchive.Sha256 -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                searchOrder     = 10
                verification = @{ mode = 'required' }
            }
        )
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result
        $result = Build-PackageAcquisitionPlan -PackageResult $result

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $result.DefaultPackageDepotFilePath) -Force
        Copy-Item -LiteralPath $packageArchive.ZipPath -Destination $result.DefaultPackageDepotFilePath -Force

        $result = Prepare-PackageInstallFile -PackageResult $result

        $result.PackageFilePreparation.Success | Should -BeTrue
        $result.PackageFilePreparation.Verification.Status | Should -Be 'VerificationPassed'
        $result.PackageFilePreparation.Verification.ExpectedHash | Should -Be $packageArchive.Sha256
    }

    It 'adopts a valid external install when policy allows it' {
        $rootPath = Join-Path $TestDrive 'adopt-external'
        $installRoot = Join-Path $rootPath 'external-install'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'Code.exe') -Content 'fake'
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content "@echo off`r`necho 2.0.0`r`n"

        $discovery = New-TestExistingInstallDiscovery -EnableDetection $true -SearchLocations @(
            @{ kind = 'directory'; path = $installRoot }
        ) -InstallRootRules @()
        $policy = New-TestExistingInstallPolicy -AllowAdoptExternal $true
        $validation = New-TestValidation -Version '2.0.0' -Directories @()
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -ExistingInstallDiscovery $discovery -ExistingInstallPolicy $policy -Validation $validation
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument -PackageStateIndexFilePath (Join-Path $rootPath 'package-state.json')) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation $validation)

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result
        $result = Find-PackageExistingPackage -PackageResult $result
        $result = Classify-PackageExistingPackage -PackageResult $result
        $result = Resolve-PackageExistingPackageDecision -PackageResult $result

        $result.ExistingPackage.Decision | Should -Be 'AdoptExternal'
        $result.InstallOrigin | Should -Be 'AdoptedExternal'
    }

    It 'ignores a valid external install when managed ownership is required' {
        $rootPath = Join-Path $TestDrive 'ignore-external'
        $installRoot = Join-Path $rootPath 'external-install'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'Code.exe') -Content 'fake'
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content "@echo off`r`necho 2.0.0`r`n"

        $discovery = New-TestExistingInstallDiscovery -EnableDetection $true -SearchLocations @(
            @{ kind = 'directory'; path = $installRoot }
        ) -InstallRootRules @()
        $policy = New-TestExistingInstallPolicy -AllowAdoptExternal $true -RequirePackageOwnership $true
        $validation = New-TestValidation -Version '2.0.0' -Directories @()
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -ExistingInstallDiscovery $discovery -ExistingInstallPolicy $policy -Validation $validation
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument -PackageStateIndexFilePath (Join-Path $rootPath 'package-state.json')) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation $validation)

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result
        $result = Find-PackageExistingPackage -PackageResult $result
        $result = Classify-PackageExistingPackage -PackageResult $result
        $result = Resolve-PackageExistingPackageDecision -PackageResult $result

        $result.ExistingPackage.Decision | Should -Be 'ExternalIgnored'
        $result.Validation | Should -BeNullOrEmpty
    }

    It 'reuses a managed install when the ownership record matches the install slot and current release' {
        $rootPath = Join-Path $TestDrive 'reuse-managed'
        $installRoot = Join-Path $rootPath 'managed-install'
        $binDirectory = Join-Path $installRoot 'bin'
        $packageStateIndexPath = Join-Path $rootPath 'package-state.json'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'Code.exe') -Content 'fake'
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content "@echo off`r`necho 2.0.0`r`n"
        Write-TestJsonDocument -Path $packageStateIndexPath -Document @{
            records = @(
                @{
                    installSlotId    = 'VSCodeRuntime:stable:win32-x64'
                    definitionId     = 'VSCodeRuntime'
                    releaseTrack     = 'stable'
                    flavor           = 'win32-x64'
                    currentReleaseId = 'vsCode-win-x64-stable'
                    currentVersion   = '2.0.0'
                    installDirectory = $installRoot
                    ownershipKind    = 'PackageInstalled'
                    updatedAtUtc     = [DateTime]::UtcNow.ToString('o')
                }
            )
        }

        $discovery = New-TestExistingInstallDiscovery -EnableDetection $true -SearchLocations @(
            @{ kind = 'directory'; path = $installRoot }
        ) -InstallRootRules @()
        $policy = New-TestExistingInstallPolicy -AllowAdoptExternal $true
        $validation = New-TestValidation -Version '2.0.0' -Directories @()
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -ExistingInstallDiscovery $discovery -ExistingInstallPolicy $policy -Validation $validation
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument -PackageStateIndexFilePath $packageStateIndexPath) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation $validation)

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result
        $result = Find-PackageExistingPackage -PackageResult $result
        $result = Classify-PackageExistingPackage -PackageResult $result
        $result = Resolve-PackageExistingPackageDecision -PackageResult $result

        $result.ExistingPackage.Decision | Should -Be 'ReusePackageOwned'
        $result.InstallOrigin | Should -Be 'PackageReused'
    }

    It 'discovers and reuses the current managed install path even when ownership tracking is missing' {
        $rootPath = Join-Path $TestDrive 'reuse-managed-untracked'
        $installRoot = Join-Path $rootPath 'managed-install'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'Code.exe') -Content 'fake'
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content "@echo off`r`necho 2.0.0`r`n"

        $validation = New-TestValidation -Version '2.0.0' -Directories @()
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{
            kind             = 'reuseExisting'
            installDirectory = $installRoot
        } -ExistingInstallDiscovery (New-TestExistingInstallDiscovery -EnableDetection $true -SearchLocations @()) -ExistingInstallPolicy (New-TestExistingInstallPolicy -AllowAdoptExternal $true) -Validation $validation
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument -PreferredTargetInstallDirectory (Join-Path $rootPath 'managed-root') -PackageStateIndexFilePath (Join-Path $rootPath 'package-state.json')) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation $validation)

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result
        $result = Find-PackageExistingPackage -PackageResult $result
        $result = Classify-PackageExistingPackage -PackageResult $result
        $result = Resolve-PackageExistingPackageDecision -PackageResult $result
        $result = Install-PackagePackage -PackageResult $result

        $result.ExistingPackage.SearchKind | Should -Be 'packageTargetInstallPath'
        $result.ExistingPackage.Decision | Should -Be 'ReusePackageOwned'
        $result.InstallOrigin | Should -Be 'PackageReused'
        $result.Install.Status | Should -Be 'ReusedPackageOwned'
    }

    It 'marks a failed validation on the managed install path as a repaired managed install after reinstall' {
        $rootPath = Join-Path $TestDrive 'repair-managed'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0' -ArchiveFileName 'VSCode-win32-x64-2.0.0.zip'
        $globalDocument = New-TestPackageGlobalDocument -PackageFileStagingDirectory (Join-Path $rootPath 'workspace') -DefaultPackageDepotDirectory (Join-Path $rootPath 'default-depot') -PreferredTargetInstallDirectory (Join-Path $rootPath 'installs')
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -Install @{
            kind             = 'expandArchive'
            installDirectory = 'vscode-runtime/stable/2.0.0/win32-x64'
            expandedRoot     = 'auto'
            createDirectories = @('data')
        } -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                searchOrder     = 10
                verification = @{ mode = 'required'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            }
        ) -Validation (New-TestValidation -Version '2.0.0')
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result
        $result = Build-PackageAcquisitionPlan -PackageResult $result

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $result.DefaultPackageDepotFilePath) -Force
        Copy-Item -LiteralPath $packageArchive.ZipPath -Destination $result.DefaultPackageDepotFilePath -Force
        $result = Prepare-PackageInstallFile -PackageResult $result
        $result = Install-PackagePackage -PackageResult $result

        Remove-Item -LiteralPath (Join-Path $result.InstallDirectory 'data') -Recurse -Force

        $rerun = New-PackageResult -CommandName 'test' -PackageConfig $config
        $rerun = Resolve-PackagePackage -PackageResult $rerun
        $rerun = Resolve-PackagePaths -PackageResult $rerun
        $rerun = Build-PackageAcquisitionPlan -PackageResult $rerun
        $rerun = Find-PackageExistingPackage -PackageResult $rerun
        $rerun = Classify-PackageExistingPackage -PackageResult $rerun
        $rerun = Resolve-PackageExistingPackageDecision -PackageResult $rerun
        $rerun = Prepare-PackageInstallFile -PackageResult $rerun
        $rerun = Install-PackagePackage -PackageResult $rerun

        $rerun.ExistingPackage.SearchKind | Should -Be 'packageTargetInstallPath'
        $rerun.ExistingPackage.Decision | Should -Be 'ExistingInstallValidationFailed'
        $rerun.Install.Status | Should -Be 'RepairedPackageOwnedInstall'
    }

}
