<#
    PackageModel-focused Pester coverage for the module.
#>

function global:ConvertTo-TestPsObject {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    return (($InputObject | ConvertTo-Json -Depth 40) | ConvertFrom-Json)
}

function global:Get-TestFileContentSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $bytes = $encoding.GetBytes($Content)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

function global:Write-TestTextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $directoryPath = Split-Path -Parent $Path
    if ($directoryPath) {
        $null = New-Item -ItemType Directory -Path $directoryPath -Force
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function global:Write-TestJsonDocument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Document
    )

    $directoryPath = Split-Path -Parent $Path
    if ($directoryPath) {
        $null = New-Item -ItemType Directory -Path $directoryPath -Force
    }

    $Document | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function global:Write-TestZipFromDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ZipPath
    )

    $zipDirectory = Split-Path -Parent $ZipPath
    if ($zipDirectory) {
        $null = New-Item -ItemType Directory -Path $zipDirectory -Force
    }

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }

    Compress-Archive -Path (Join-Path $SourceDirectory '*') -DestinationPath $ZipPath -Force
}

function global:New-TestPackageArchiveInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [string]$ArchiveFileName = 'package.zip'
    )

    $layoutRoot = Join-Path $RootPath 'layout'
    $binDirectory = Join-Path $layoutRoot 'bin'
    $null = New-Item -ItemType Directory -Path $binDirectory -Force
    Write-TestTextFile -Path (Join-Path $layoutRoot 'Code.exe') -Content 'fake-vscode-binary'
    Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content "@echo off`r`necho $Version`r`n"

    $zipPath = Join-Path $RootPath $ArchiveFileName
    Write-TestZipFromDirectory -SourceDirectory $layoutRoot -ZipPath $zipPath

    return [pscustomobject]@{
        LayoutRoot = $layoutRoot
        ZipPath    = $zipPath
        Sha256     = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function global:New-TestPackageModelGlobalDocument {
    param(
        [string]$InstallWorkspaceDirectory,
        [string]$DefaultPackageDepotDirectory,
        [string]$PreferredTargetInstallDirectory,
        [string]$ArtifactIndexFilePath,
        [string]$OwnershipIndexFilePath,
        [bool]$AllowFallback = $true,
        [bool]$MirrorDownloadedArtifactsToDefaultPackageDepot = $true,
        [string]$ReleaseTrack = 'stable',
        [string]$Strategy = 'latestByVersion',
        [hashtable]$EnvironmentSources = $null
    )

    $acquisitionEnvironment = @{
        stores = @{
            installWorkspaceDirectory = if ($PSBoundParameters.ContainsKey('InstallWorkspaceDirectory')) { $InstallWorkspaceDirectory } else { '%LOCALAPPDATA%/Eigenverft.Manifested.Sandbox/PackageModel/InstallWorkspace' }
            defaultPackageDepotDirectory = if ($PSBoundParameters.ContainsKey('DefaultPackageDepotDirectory')) { $DefaultPackageDepotDirectory } else { '%LOCALAPPDATA%/Eigenverft.Manifested.Sandbox/PackageModel/DefaultPackageDepot' }
        }
        defaults = @{
            allowFallback = $AllowFallback
            mirrorDownloadedArtifactsToDefaultPackageDepot = $MirrorDownloadedArtifactsToDefaultPackageDepot
        }
        tracking = @{
            artifactIndexFilePath = if ($PSBoundParameters.ContainsKey('ArtifactIndexFilePath')) { $ArtifactIndexFilePath } else { '%LOCALAPPDATA%/Eigenverft.Manifested.Sandbox/PackageModel/artifact-index.json' }
        }
    }
    if ($PSBoundParameters.ContainsKey('EnvironmentSources') -and $null -ne $EnvironmentSources) {
        $acquisitionEnvironment.environmentSources = $EnvironmentSources
    }

    return @{
        packageModel = @{
            preferredTargetInstallDirectory = if ($PSBoundParameters.ContainsKey('PreferredTargetInstallDirectory')) { $PreferredTargetInstallDirectory } else { '%LOCALAPPDATA%/Eigenverft.Manifested.Sandbox/PackageModel/Installs' }
            acquisitionEnvironment = $acquisitionEnvironment
            ownershipTracking = @{
                indexFilePath = if ($PSBoundParameters.ContainsKey('OwnershipIndexFilePath')) { $OwnershipIndexFilePath } else { '%LOCALAPPDATA%/Eigenverft.Manifested.Sandbox/PackageModel/ownership-index.json' }
            }
            selectionDefaults = @{
                releaseTrack = $ReleaseTrack
                strategy     = $Strategy
            }
        }
    }
}

function global:New-TestSourceInventoryDocument {
    param(
        [hashtable]$GlobalEnvironmentSources = @{},
        [hashtable]$SiteEnvironmentSources = @{},
        [string]$SiteCode = 'BER',
        [hashtable]$GlobalDefaults = @{},
        [hashtable]$SiteDefaults = @{}
    )

    $sites = @{}
    if ($SiteEnvironmentSources.Count -gt 0 -or $SiteDefaults.Count -gt 0) {
        $sites[$SiteCode] = @{}
        if ($SiteEnvironmentSources.Count -gt 0) {
            $sites[$SiteCode].environmentSources = $SiteEnvironmentSources
        }
        if ($SiteDefaults.Count -gt 0) {
            $sites[$SiteCode].defaults = $SiteDefaults
        }
    }

    $global = @{}
    if ($GlobalEnvironmentSources.Count -gt 0) {
        $global.environmentSources = $GlobalEnvironmentSources
    }
    if ($GlobalDefaults.Count -gt 0) {
        $global.defaults = $GlobalDefaults
    }

    return @{
        inventoryVersion = 1
        global           = $global
        sites            = $sites
    }
}

function global:New-TestValidation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [string[]]$Directories = @('data')
    )

    return @{
        files = @(
            'Code.exe',
            'bin/code.cmd'
        )
        directories = $Directories
        commandChecks = @(
            @{
                entryPoint    = 'code'
                arguments     = @('--version')
                outputPattern = '(?m)^(?<value>\d+\.\d+\.\d+)\s*$'
                expectedValue = '{version}'
            }
        )
        metadataFiles = @()
        signatures    = @()
        fileDetails   = @()
        registryChecks = @()
    }
}

function global:New-TestExistingInstallDiscovery {
    param(
        [bool]$EnableDetection = $false,
        [array]$SearchLocations = @(),
        [array]$InstallRootRules = @()
    )

    return @{
        enableDetection = $EnableDetection
        searchLocations = $SearchLocations
        installRootRules = $InstallRootRules
    }
}

function global:New-TestExistingInstallPolicy {
    param(
        [bool]$AllowAdoptExternal = $false,
        [bool]$UpgradeAdoptedInstall = $false,
        [bool]$RequirePackageModelOwnership = $false
    )

    return @{
        allowAdoptExternal    = $AllowAdoptExternal
        upgradeAdoptedInstall = $UpgradeAdoptedInstall
        requirePackageModelOwnership = $RequirePackageModelOwnership
    }
}

function global:New-TestPackageModelRelease {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Architecture,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$ReleaseTrack = 'stable',

        [string]$FileName = '',

        [string]$PackageFileSha256 = '',

        [array]$AcquisitionCandidates = @(),

        [hashtable]$Requirements = $null,

        [hashtable]$Install = $null,

        [hashtable]$Validation = $null,

        [hashtable]$ExistingInstallDiscovery = $null,

        [hashtable]$ExistingInstallPolicy = $null
    )

    $release = [ordered]@{
        id           = $Id
        version      = $Version
        releaseTrack = $ReleaseTrack
        flavor       = $Flavor
        constraints  = @{
            os  = @('windows')
            cpu = @($Architecture)
        }
        packageFile  = if ([string]::IsNullOrWhiteSpace($FileName)) {
            $null
        }
        else {
            $packageFile = @{
                fileName            = $FileName
                format              = 'zip'
                portable            = $true
                autoUpdateSupported = $false
            }
            if (-not [string]::IsNullOrWhiteSpace($PackageFileSha256)) {
                $packageFile.integrity = @{
                    algorithm = 'sha256'
                    sha256    = $PackageFileSha256
                }
            }
            $packageFile
        }
        acquisitionCandidates = $AcquisitionCandidates
    }

    if ($PSBoundParameters.ContainsKey('Requirements')) {
        $release.requirements = $Requirements
    }
    if ($PSBoundParameters.ContainsKey('Install')) {
        $release.install = $Install
    }
    if ($PSBoundParameters.ContainsKey('Validation')) {
        $release.validation = $Validation
    }
    if ($PSBoundParameters.ContainsKey('ExistingInstallDiscovery')) {
        $release.existingInstallDiscovery = $ExistingInstallDiscovery
    }
    if ($PSBoundParameters.ContainsKey('ExistingInstallPolicy')) {
        $release.existingInstallPolicy = $ExistingInstallPolicy
    }

    return (ConvertTo-TestPsObject $release)
}

function global:New-TestVSCodeDefinitionDocument {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Releases,

        [string]$UpstreamBaseUri = 'https://update.code.visualstudio.com',

        [hashtable]$ReleaseDefaultsInstall = $null,

        [hashtable]$ReleaseDefaultsValidation = $null,

        [hashtable]$ReleaseDefaultsExistingInstallDiscovery = $null,

        [hashtable]$ReleaseDefaultsExistingInstallPolicy = $null
    )

    if ($null -eq $ReleaseDefaultsInstall) {
        $ReleaseDefaultsInstall = @{
            kind             = 'expandArchive'
            installDirectory = 'vscode-runtime/{releaseTrack}/{version}/{flavor}'
            pathRegistration = @{
                mode   = 'user'
                source = @{
                    kind  = 'commandEntryPoint'
                    value = 'code'
                }
            }
            expandedRoot     = 'auto'
            createDirectories = @('data')
        }
    }
    if ($null -eq $ReleaseDefaultsValidation) {
        $ReleaseDefaultsValidation = New-TestValidation -Version '0.0.0'
    }
    if ($null -eq $ReleaseDefaultsExistingInstallDiscovery) {
        $ReleaseDefaultsExistingInstallDiscovery = New-TestExistingInstallDiscovery -EnableDetection $false
    }
    if ($null -eq $ReleaseDefaultsExistingInstallPolicy) {
        $ReleaseDefaultsExistingInstallPolicy = New-TestExistingInstallPolicy
    }

    return @{
        schemaVersion = '1.0'
        id = 'VSCodeRuntime'
        display = @{
            default       = @{
                name        = 'Visual Studio Code'
                publisher   = 'Microsoft'
                corporation = 'Microsoft Corporation'
                summary     = 'Code editor'
            }
            localizations = @{}
        }
        upstreamSources = @{
            vsCodeUpdateService = @{
                kind    = 'download'
                baseUri = $UpstreamBaseUri
            }
        }
        providedTools = @{
            commands = @(
                @{
                    name         = 'code'
                    relativePath = 'bin/code.cmd'
                }
            )
            apps = @(
                @{
                    name         = 'Code'
                    relativePath = 'Code.exe'
                }
            )
        }
        releaseDefaults = @{
            requirements             = @{
                checks = @()
            }
            install                  = $ReleaseDefaultsInstall
            validation               = $ReleaseDefaultsValidation
            existingInstallDiscovery = $ReleaseDefaultsExistingInstallDiscovery
            existingInstallPolicy    = $ReleaseDefaultsExistingInstallPolicy
        }
        releases = $Releases
    }
}

function global:Write-TestPackageModelDocuments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [object]$GlobalDocument,

        [Parameter(Mandatory = $true)]
        [object]$DefinitionDocument,

        [AllowNull()]
        [object]$SourceInventoryDocument
    )

    $globalConfigPath = Join-Path $RootPath 'PackageModel.Global.json'
    $definitionPath = Join-Path $RootPath "$($DefinitionDocument.id).json"
    Write-TestJsonDocument -Path $globalConfigPath -Document $GlobalDocument
    Write-TestJsonDocument -Path $definitionPath -Document $DefinitionDocument

    $sourceInventoryPath = $null
    if ($PSBoundParameters.ContainsKey('SourceInventoryDocument') -and $null -ne $SourceInventoryDocument) {
        $sourceInventoryPath = Join-Path $RootPath 'SourceInventory.json'
        Write-TestJsonDocument -Path $sourceInventoryPath -Document $SourceInventoryDocument
    }

    return [pscustomobject]@{
        GlobalConfigPath   = $globalConfigPath
        DefinitionPath     = $definitionPath
        SourceInventoryPath = $sourceInventoryPath
    }
}

Describe 'Eigenverft.Manifested.Sandbox PackageModel' {
    BeforeAll {
        . "$PSScriptRoot\Eigenverft.Manifested.Sandbox.TestImports.ps1"
        $script:ModuleManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Eigenverft.Manifested.Sandbox\Eigenverft.Manifested.Sandbox.psd1'
        $script:SourceInventoryEnvVarName = Get-PackageModelSourceInventoryPathEnvironmentVariableName
        $script:SiteCodeEnvVarName = Get-PackageModelSiteCodeEnvironmentVariableName
    }

    BeforeEach {
        $script:OriginalSourceInventoryPath = [Environment]::GetEnvironmentVariable($script:SourceInventoryEnvVarName, 'Process')
        $script:OriginalSiteCode = [Environment]::GetEnvironmentVariable($script:SiteCodeEnvVarName, 'Process')
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $script:OriginalSourceInventoryPath, 'Process')
        [Environment]::SetEnvironmentVariable($script:SiteCodeEnvVarName, $script:OriginalSiteCode, 'Process')
    }

    It 'exports Invoke-PackageModel-VSCodeRuntime and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-PackageModel-VSCodeRuntime'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'loads the shipped global config without baked-in environment sources' {
        $globalInfo = Read-PackageModelJsonDocument -Path (Get-PackageModelGlobalConfigPath)

        $globalInfo.Document.packageModel.PSObject.Properties.Name | Should -Contain 'preferredTargetInstallDirectory'
        $globalInfo.Document.packageModel.acquisitionEnvironment.stores.PSObject.Properties.Name | Should -Contain 'installWorkspaceDirectory'
        $globalInfo.Document.packageModel.acquisitionEnvironment.stores.PSObject.Properties.Name | Should -Contain 'defaultPackageDepotDirectory'
        $globalInfo.Document.packageModel.acquisitionEnvironment.PSObject.Properties['environmentSources'] | Should -BeNullOrEmpty
    }

    It 'fails clearly when the shipped global config still defines vsCodeUpdateService as an environment source' {
        $globalConfigPath = Join-Path $TestDrive 'PackageModel.Global.json'
        $badGlobal = New-TestPackageModelGlobalDocument -EnvironmentSources @{
            vsCodeUpdateService = @{ kind = 'download'; baseUri = 'https://example.invalid/' }
        }
        Write-TestJsonDocument -Path $globalConfigPath -Document $badGlobal

        $globalInfo = Read-PackageModelJsonDocument -Path $globalConfigPath
        { Assert-PackageModelGlobalConfigSchema -GlobalDocumentInfo $globalInfo } | Should -Throw '*vsCodeUpdateService*'
    }

    It 'fails clearly when a definition still uses requireManagedOwnership' {
        $rootPath = Join-Path $TestDrive 'retired-require-managed-ownership'
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0') -ReleaseDefaultsExistingInstallPolicy @{
            allowAdoptExternal    = $false
            upgradeAdoptedInstall = $false
            requireManagedOwnership = $false
        }
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument $definitionDocument

        $definitionInfo = Read-PackageModelJsonDocument -Path $documents.DefinitionPath
        { Assert-PackageModelDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*requireManagedOwnership*'
    }

    It 'fails clearly when a definition is missing schemaVersion' {
        $rootPath = Join-Path $TestDrive 'missing-schema-version'
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release)
        $null = $definitionDocument.Remove('schemaVersion')
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument $definitionDocument

        $definitionInfo = Read-PackageModelJsonDocument -Path $documents.DefinitionPath
        { Assert-PackageModelDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*schemaVersion*'
    }

    It 'fails clearly when a definition still uses requirements.packages' {
        $rootPath = Join-Path $TestDrive 'retired-requirements-packages'
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release)
        $definitionDocument.releaseDefaults.requirements = @{
            packages = @()
        }
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument $definitionDocument

        $definitionInfo = Read-PackageModelJsonDocument -Path $documents.DefinitionPath
        { Assert-PackageModelDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*requirements.checks*'
    }

    It 'uses the default source inventory path when the env var is unset' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $null, 'Process')
        (Get-PackageModelSourceInventoryPath) | Should -Be (Get-PackageModelDefaultSourceInventoryPath)
    }

    It 'loads source inventory from the env-var path and applies the inventory global overlay when no site code is set' {
        $rootPath = Join-Path $TestDrive 'inventory-global'
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                    @{
                        kind        = 'packageDepot'
                        priority    = 100
                        verification = @{ mode = 'none' }
                    }
                )
            )) -SourceInventoryDocument (New-TestSourceInventoryDocument -GlobalEnvironmentSources @{
                remotePackageDepot = @{
                    kind     = 'filesystem'
                    basePath = (Join-Path $TestDrive 'global-remote')
                }
            })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $documents.SourceInventoryPath, 'Process')
        [Environment]::SetEnvironmentVariable($script:SiteCodeEnvVarName, $null, 'Process')

        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'

        $config.EnvironmentSources.PSObject.Properties.Name | Should -Contain 'remotePackageDepot'
        $config.EnvironmentSources.remotePackageDepot.basePath | Should -Be (Join-Path $TestDrive 'global-remote')
    }

    It 'applies the site overlay on top of the inventory global overlay when site code is present' {
        $rootPath = Join-Path $TestDrive 'inventory-site'
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
                    @{
                        kind        = 'packageDepot'
                        priority    = 100
                        verification = @{ mode = 'none' }
                    }
                )
            )) -SourceInventoryDocument (New-TestSourceInventoryDocument -GlobalEnvironmentSources @{
                remotePackageDepot = @{
                    kind     = 'filesystem'
                    basePath = (Join-Path $TestDrive 'global-remote')
                }
            } -SiteEnvironmentSources @{
                remotePackageDepot = @{
                    kind     = 'filesystem'
                    basePath = (Join-Path $TestDrive 'site-remote')
                }
            } -SiteCode 'BER')

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $documents.SourceInventoryPath, 'Process')
        [Environment]::SetEnvironmentVariable($script:SiteCodeEnvVarName, 'BER', 'Process')

        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'

        $config.EnvironmentSources.remotePackageDepot.basePath | Should -Be (Join-Path $TestDrive 'site-remote')
    }

    It 'rejects a selected release when requirements.checks are not satisfied' {
        $rootPath = Join-Path $TestDrive 'requirements-checks-fail'
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Requirements @{
            checks = @(
                @{
                    kind    = 'osFamily'
                    allowed = @('linux')
                }
            )
        } -Validation (New-TestValidation -Version '2.0.0')
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config

        { Resolve-PackageModelPackage -PackageModelResult $result } | Should -Throw '*requirements.checks*'
    }

    It 'resolves environment and definition source refs from the effective acquisition environment and upstream sources' {
        $rootPath = Join-Path $TestDrive 'source-resolution'
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
            ) -UpstreamBaseUri 'https://example.invalid/vscode/') -SourceInventoryDocument (New-TestSourceInventoryDocument -GlobalEnvironmentSources @{
                remotePackageDepot = @{
                    kind     = 'filesystem'
                    basePath = (Join-Path $TestDrive 'remote-depot')
                }
            })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $documents.SourceInventoryPath, 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $environmentSource = Get-PackageModelSourceDefinition -PackageModelConfig $config -SourceRef ([pscustomobject]@{ scope = 'environment'; id = 'remotePackageDepot' })
        $definitionSource = Get-PackageModelSourceDefinition -PackageModelConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'vsCodeUpdateService' })

        $environmentSource.Kind | Should -Be 'filesystem'
        $environmentSource.BasePath | Should -Be (Join-Path $TestDrive 'remote-depot')
        $definitionSource.Kind | Should -Be 'download'
        $definitionSource.BaseUri | Should -Be 'https://example.invalid/vscode/'
    }

    It 'builds an effective release from releaseDefaults and uses ReleaseTrack in path resolution' {
        $rootPath = Join-Path $TestDrive 'effective-release'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0'
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind        = 'packageDepot'
                priority    = 10
                verification = @{ mode = 'optional'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            }
        )
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument -ReleaseTrack 'stable') -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result

        $result.EffectiveRelease | Should -Not -BeNullOrEmpty
        $result.Package.install.kind | Should -Be 'expandArchive'
        $result.Package.validation.commandChecks[0].expectedValue | Should -Be '{version}'
        $result.PackageFilePath | Should -Match '\\stable\\2\.0\.0\\win32-x64\\'
        $result.DefaultPackageDepotFilePath | Should -Match '\\stable\\2\.0\.0\\win32-x64\\'
    }

    It 'writes resolved paths as separate console lines' {
        $rootPath = Join-Path $TestDrive 'resolved-path-lines'
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                priority     = 10
                verification = @{ mode = 'none' }
            }
        )
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $messages = New-Object System.Collections.Generic.List[string]
        Mock Write-StandardMessage {
            param([string]$Message, [string]$Level)
            $messages.Add($Message) | Out-Null
        }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $null = Resolve-PackageModelPaths -PackageModelResult $result

        @($messages) | Should -Contain '[STATE] Resolved paths:'
        @($messages | Where-Object { $_.StartsWith('[PATH] Install workspace:') }).Count | Should -Be 1
        @($messages | Where-Object { $_.StartsWith('[PATH] Target install directory:') }).Count | Should -Be 1
        @($messages | Where-Object { $_.StartsWith('[PATH] Package file:') }).Count | Should -Be 1
        @($messages | Where-Object { $_.StartsWith('[PATH] Default package depot file:') }).Count | Should -Be 1
    }

    It 'skips PATH registration when mode is none' {
        $installRoot = Join-Path $TestDrive 'path-registration-none'
        $null = New-Item -ItemType Directory -Path $installRoot -Force
        $packageModelResult = [pscustomobject]@{
            PackageModelConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @()
                        apps     = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode = 'none'
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'PackageModelInstalled'
        }

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageModelResult = Register-PackageModelPath -PackageModelResult $packageModelResult

        $packageModelResult.PathRegistration.Status | Should -Be 'Skipped'
        Assert-MockCalled Set-EnvironmentVariableValue -Times 0
    }

    It 'registers a command entry point directory in Process and User PATH for user mode' {
        $installRoot = Join-Path $TestDrive 'path-registration-user'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content '@echo off'

        $packageModelResult = [pscustomobject]@{
            PackageModelConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @(
                            @{
                                name         = 'code'
                                relativePath = 'bin/code.cmd'
                            }
                        )
                        apps = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'user'
                        source = @{
                            kind  = 'commandEntryPoint'
                            value = 'code'
                        }
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'PackageModelInstalled'
        }

        $writes = New-Object System.Collections.Generic.List[object]
        Mock Get-EnvironmentVariableValue {
            param([string]$Name, [string]$Target)
            switch ($Target) {
                'Process' { 'C:\Windows\System32' }
                'User' { 'C:\Users\Test\bin' }
                default { $null }
            }
        }
        Mock Set-EnvironmentVariableValue {
            param([string]$Name, [string]$Value, [string]$Target)
            $writes.Add([pscustomobject]@{
                Name   = $Name
                Value  = $Value
                Target = $Target
            }) | Out-Null
        }

        $packageModelResult = Register-PackageModelPath -PackageModelResult $packageModelResult

        $packageModelResult.PathRegistration.Status | Should -Be 'Registered'
        @($packageModelResult.PathRegistration.UpdatedTargets) | Should -Be @('Process', 'User')
        $packageModelResult.PathRegistration.RegisteredPath | Should -Be $binDirectory
        @($writes | ForEach-Object { $_.Target }) | Should -Be @('Process', 'User')
        $expectedBinPattern = [regex]::Escape($binDirectory)
        @($writes | Where-Object { $_.Target -eq 'Process' })[0].Value | Should -Match $expectedBinPattern
        @($writes | Where-Object { $_.Target -eq 'User' })[0].Value | Should -Match $expectedBinPattern
    }

    It 'skips PATH registration for adopted external installs' {
        $installRoot = Join-Path $TestDrive 'path-registration-adopted-external'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content '@echo off'

        $packageModelResult = [pscustomobject]@{
            PackageModelConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @(
                            @{
                                name         = 'code'
                                relativePath = 'bin/code.cmd'
                            }
                        )
                        apps = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'user'
                        source = @{
                            kind  = 'commandEntryPoint'
                            value = 'code'
                        }
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'AdoptedExternal'
        }

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageModelResult = Register-PackageModelPath -PackageModelResult $packageModelResult

        $packageModelResult.PathRegistration.Status | Should -Be 'SkippedNotPackageModelOwned'
        Assert-MockCalled Set-EnvironmentVariableValue -Times 0
    }

    It 'removes stale PackageModel-owned paths for the same install slot before registering the active path' {
        $oldInstallRoot = Join-Path $TestDrive 'path-registration-stale-owned\old'
        $newInstallRoot = Join-Path $TestDrive 'path-registration-stale-owned\new'
        $oldBinDirectory = Join-Path $oldInstallRoot 'bin'
        $newBinDirectory = Join-Path $newInstallRoot 'bin'
        $null = New-Item -ItemType Directory -Path $oldBinDirectory -Force
        $null = New-Item -ItemType Directory -Path $newBinDirectory -Force
        Write-TestTextFile -Path (Join-Path $newBinDirectory 'code.cmd') -Content '@echo off'

        $packageModelResult = [pscustomobject]@{
            PackageModelConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @(
                            @{
                                name         = 'code'
                                relativePath = 'bin/code.cmd'
                            }
                        )
                        apps = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'user'
                        source = @{
                            kind  = 'commandEntryPoint'
                            value = 'code'
                        }
                    }
                }
            }
            ExistingPackage = [pscustomobject]@{
                InstallDirectory = $oldInstallRoot
                Classification   = 'PackageModelOwned'
                Decision         = 'ReplacePackageModelOwnedInstall'
            }
            Ownership = [pscustomobject]@{
                InstallSlotId   = 'VSCodeRuntime:stable:win32-x64'
                Classification  = 'PackageModelOwned'
                OwnershipRecord = [pscustomobject]@{
                    installDirectory = $oldInstallRoot
                    ownershipKind    = 'PackageModelInstalled'
                }
            }
            InstallDirectory = $newInstallRoot
            InstallOrigin    = 'PackageModelInstalled'
        }

        $writes = New-Object System.Collections.Generic.List[object]
        Mock Get-EnvironmentVariableValue {
            param([string]$Name, [string]$Target)
            switch ($Target) {
                'Process' { "C:\\Windows\\System32;$oldBinDirectory" }
                'User' { "C:\\Users\\Test\\bin;$oldBinDirectory;C:\\Users\\Test\\ExternalVSCode\\bin" }
                default { $null }
            }
        }
        Mock Set-EnvironmentVariableValue {
            param([string]$Name, [string]$Value, [string]$Target)
            $writes.Add([pscustomobject]@{
                Name   = $Name
                Value  = $Value
                Target = $Target
            }) | Out-Null
        }

        $packageModelResult = Register-PackageModelPath -PackageModelResult $packageModelResult

        $packageModelResult.PathRegistration.Status | Should -Be 'Registered'
        @($packageModelResult.PathRegistration.CleanedTargets) | Should -Be @('Process', 'User')
        $packageModelResult.PathRegistration.CleanupDirectories | Should -Contain $oldBinDirectory
        @($writes | ForEach-Object { $_.Target }) | Should -Be @('Process', 'User')
        @($writes | Where-Object { $_.Target -eq 'Process' })[0].Value | Should -Not -Match ([regex]::Escape($oldBinDirectory))
        @($writes | Where-Object { $_.Target -eq 'Process' })[0].Value | Should -Match ([regex]::Escape($newBinDirectory))
        @($writes | Where-Object { $_.Target -eq 'User' })[0].Value | Should -Not -Match ([regex]::Escape($oldBinDirectory))
        @($writes | Where-Object { $_.Target -eq 'User' })[0].Value | Should -Match ([regex]::Escape($newBinDirectory))
    }

    It 'registers an install-relative directory in Process and Machine PATH for machine mode' {
        $installRoot = Join-Path $TestDrive 'path-registration-machine'
        $null = New-Item -ItemType Directory -Path $installRoot -Force

        $packageModelResult = [pscustomobject]@{
            PackageModelConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @()
                        apps     = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'machine'
                        source = @{
                            kind  = 'installRelativeDirectory'
                            value = '.'
                        }
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'PackageModelInstalled'
        }

        $writes = New-Object System.Collections.Generic.List[object]
        Mock Get-EnvironmentVariableValue {
            param([string]$Name, [string]$Target)
            switch ($Target) {
                'Process' { 'C:\Windows\System32' }
                'Machine' { 'C:\Program Files\Common Files' }
                default { $null }
            }
        }
        Mock Set-EnvironmentVariableValue {
            param([string]$Name, [string]$Value, [string]$Target)
            $writes.Add([pscustomobject]@{
                Name   = $Name
                Value  = $Value
                Target = $Target
            }) | Out-Null
        }

        $packageModelResult = Register-PackageModelPath -PackageModelResult $packageModelResult

        $packageModelResult.PathRegistration.Status | Should -Be 'Registered'
        @($packageModelResult.PathRegistration.UpdatedTargets) | Should -Be @('Process', 'Machine')
        $packageModelResult.PathRegistration.RegisteredPath | Should -Be $installRoot
        @($writes | ForEach-Object { $_.Target }) | Should -Be @('Process', 'Machine')
    }

    It 'fails clearly when shim PATH registration is requested' {
        $installRoot = Join-Path $TestDrive 'path-registration-shim'
        $null = New-Item -ItemType Directory -Path $installRoot -Force

        $packageModelResult = [pscustomobject]@{
            PackageModelConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @()
                        apps     = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'user'
                        source = @{
                            kind  = 'shim'
                            value = 'bin/code.cmd'
                        }
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'PackageModelInstalled'
        }

        { Register-PackageModelPath -PackageModelResult $packageModelResult } | Should -Throw '*shim*not implemented*'
    }

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

        (Resolve-PackageModelExistingInstallRoot -ExistingInstallDiscovery $discovery -CandidatePath $codeCmdPath) | Should -Be $installRoot
        (Resolve-PackageModelExistingInstallRoot -ExistingInstallDiscovery $discovery -CandidatePath $codeExePath) | Should -Be $installRoot
    }

    It 'keeps installWorkspace and defaultPackageDepot distinct in the resolved paths' {
        $rootPath = Join-Path $TestDrive 'distinct-roots'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0'
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind        = 'packageDepot'
                priority    = 10
                verification = @{ mode = 'optional'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            }
        )
        $globalDocument = New-TestPackageModelGlobalDocument -InstallWorkspaceDirectory (Join-Path $rootPath 'workspace') -DefaultPackageDepotDirectory (Join-Path $rootPath 'default-depot')
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result

        $result.InstallWorkspaceDirectory | Should -Not -Be $config.DefaultPackageDepotDirectory
        $result.PackageFilePath | Should -Not -Be $result.DefaultPackageDepotFilePath
        Split-Path -Parent $result.DefaultPackageDepotFilePath | Should -Match 'default-depot'
    }

    It 'hydrates the install workspace from the default package depot before upstream download' {
        $rootPath = Join-Path $TestDrive 'default-depot-hydration'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0' -ArchiveFileName 'VSCode-win32-x64-2.0.0.zip'
        $globalDocument = New-TestPackageModelGlobalDocument -InstallWorkspaceDirectory (Join-Path $rootPath 'workspace') -DefaultPackageDepotDirectory (Join-Path $rootPath 'default-depot')
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -AcquisitionCandidates @(
            @{
                kind        = 'packageDepot'
                priority    = 10
                verification = @{ mode = 'required'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            },
            @{
                kind        = 'download'
                sourceId    = 'vsCodeUpdateService'
                priority    = 100
                sourcePath  = '2.0.0/win32-x64-archive/stable'
                verification = @{ mode = 'required'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            }
        )
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }
        Mock Save-PackageModelDownloadFile { throw 'download should not run when the default package depot already has a verified artifact' }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result
        $result = Build-PackageModelAcquisitionPlan -PackageModelResult $result

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $result.DefaultPackageDepotFilePath) -Force
        Copy-Item -LiteralPath $packageArchive.ZipPath -Destination $result.DefaultPackageDepotFilePath -Force

        $result = Save-PackageModelPackageFile -PackageModelResult $result

        $result.PackageFileSave.Success | Should -BeTrue
        $result.PackageFileSave.Status | Should -Be 'HydratedFromDefaultPackageDepot'
        Test-Path -LiteralPath $result.PackageFilePath | Should -BeTrue
        (Get-FileHash -LiteralPath $result.PackageFilePath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $packageArchive.Sha256
        Assert-MockCalled Save-PackageModelDownloadFile -Times 0
    }

    It 'uses packageFile.integrity when acquisition candidates only declare verification mode' {
        $rootPath = Join-Path $TestDrive 'packagefile-integrity'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0' -ArchiveFileName 'VSCode-win32-x64-2.0.0.zip'
        $globalDocument = New-TestPackageModelGlobalDocument -InstallWorkspaceDirectory (Join-Path $rootPath 'workspace') -DefaultPackageDepotDirectory (Join-Path $rootPath 'default-depot')
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -PackageFileSha256 $packageArchive.Sha256 -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                priority     = 10
                verification = @{ mode = 'required' }
            }
        )
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result
        $result = Build-PackageModelAcquisitionPlan -PackageModelResult $result

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $result.DefaultPackageDepotFilePath) -Force
        Copy-Item -LiteralPath $packageArchive.ZipPath -Destination $result.DefaultPackageDepotFilePath -Force

        $result = Save-PackageModelPackageFile -PackageModelResult $result

        $result.PackageFileSave.Success | Should -BeTrue
        $result.PackageFileSave.Verification.Status | Should -Be 'VerificationPassed'
        $result.PackageFileSave.Verification.ExpectedHash | Should -Be $packageArchive.Sha256
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
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -ExistingInstallDiscovery $discovery -ExistingInstallPolicy $policy -Validation $validation
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument -OwnershipIndexFilePath (Join-Path $rootPath 'ownership.json')) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation $validation)

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result
        $result = Find-PackageModelExistingPackage -PackageModelResult $result
        $result = Classify-PackageModelExistingPackage -PackageModelResult $result
        $result = Resolve-PackageModelExistingPackageDecision -PackageModelResult $result

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
        $policy = New-TestExistingInstallPolicy -AllowAdoptExternal $true -RequirePackageModelOwnership $true
        $validation = New-TestValidation -Version '2.0.0' -Directories @()
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -ExistingInstallDiscovery $discovery -ExistingInstallPolicy $policy -Validation $validation
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument -OwnershipIndexFilePath (Join-Path $rootPath 'ownership.json')) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation $validation)

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result
        $result = Find-PackageModelExistingPackage -PackageModelResult $result
        $result = Classify-PackageModelExistingPackage -PackageModelResult $result
        $result = Resolve-PackageModelExistingPackageDecision -PackageModelResult $result

        $result.ExistingPackage.Decision | Should -Be 'ExternalIgnored'
        $result.Validation | Should -BeNullOrEmpty
    }

    It 'reuses a managed install when the ownership record matches the install slot and current release' {
        $rootPath = Join-Path $TestDrive 'reuse-managed'
        $installRoot = Join-Path $rootPath 'managed-install'
        $binDirectory = Join-Path $installRoot 'bin'
        $ownershipIndexPath = Join-Path $rootPath 'ownership.json'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'Code.exe') -Content 'fake'
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content "@echo off`r`necho 2.0.0`r`n"
        Write-TestJsonDocument -Path $ownershipIndexPath -Document @{
            records = @(
                @{
                    installSlotId    = 'VSCodeRuntime:stable:win32-x64'
                    definitionId     = 'VSCodeRuntime'
                    releaseTrack     = 'stable'
                    flavor           = 'win32-x64'
                    currentReleaseId = 'vsCode-win-x64-stable'
                    currentVersion   = '2.0.0'
                    installDirectory = $installRoot
                    ownershipKind    = 'PackageModelInstalled'
                    updatedAtUtc     = [DateTime]::UtcNow.ToString('o')
                }
            )
        }

        $discovery = New-TestExistingInstallDiscovery -EnableDetection $true -SearchLocations @(
            @{ kind = 'directory'; path = $installRoot }
        ) -InstallRootRules @()
        $policy = New-TestExistingInstallPolicy -AllowAdoptExternal $true
        $validation = New-TestValidation -Version '2.0.0' -Directories @()
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -ExistingInstallDiscovery $discovery -ExistingInstallPolicy $policy -Validation $validation
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument -OwnershipIndexFilePath $ownershipIndexPath) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation $validation)

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result
        $result = Find-PackageModelExistingPackage -PackageModelResult $result
        $result = Classify-PackageModelExistingPackage -PackageModelResult $result
        $result = Resolve-PackageModelExistingPackageDecision -PackageModelResult $result

        $result.ExistingPackage.Decision | Should -Be 'ReusePackageModelOwned'
        $result.InstallOrigin | Should -Be 'PackageModelReused'
    }

    It 'discovers and reuses the current managed install path even when ownership tracking is missing' {
        $rootPath = Join-Path $TestDrive 'reuse-managed-untracked'
        $installRoot = Join-Path $rootPath 'managed-install'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'Code.exe') -Content 'fake'
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content "@echo off`r`necho 2.0.0`r`n"

        $validation = New-TestValidation -Version '2.0.0' -Directories @()
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{
            kind             = 'reuseExisting'
            installDirectory = $installRoot
        } -ExistingInstallDiscovery (New-TestExistingInstallDiscovery -EnableDetection $true -SearchLocations @()) -ExistingInstallPolicy (New-TestExistingInstallPolicy -AllowAdoptExternal $true) -Validation $validation
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument -PreferredTargetInstallDirectory (Join-Path $rootPath 'managed-root') -OwnershipIndexFilePath (Join-Path $rootPath 'ownership.json')) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation $validation)

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result
        $result = Find-PackageModelExistingPackage -PackageModelResult $result
        $result = Classify-PackageModelExistingPackage -PackageModelResult $result
        $result = Resolve-PackageModelExistingPackageDecision -PackageModelResult $result
        $result = Install-PackageModelPackage -PackageModelResult $result

        $result.ExistingPackage.SearchKind | Should -Be 'packageModelTargetInstallPath'
        $result.ExistingPackage.Decision | Should -Be 'ReusePackageModelOwned'
        $result.InstallOrigin | Should -Be 'PackageModelReused'
        $result.Install.Status | Should -Be 'ReusedPackageModelOwned'
    }

    It 'marks a failed validation on the managed install path as a repaired managed install after reinstall' {
        $rootPath = Join-Path $TestDrive 'repair-managed'
        $packageArchive = New-TestPackageArchiveInfo -RootPath (Join-Path $rootPath 'archive') -Version '2.0.0' -ArchiveFileName 'VSCode-win32-x64-2.0.0.zip'
        $globalDocument = New-TestPackageModelGlobalDocument -InstallWorkspaceDirectory (Join-Path $rootPath 'workspace') -DefaultPackageDepotDirectory (Join-Path $rootPath 'default-depot') -PreferredTargetInstallDirectory (Join-Path $rootPath 'installs')
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -FileName 'VSCode-win32-x64-2.0.0.zip' -Install @{
            kind             = 'expandArchive'
            installDirectory = 'vscode-runtime/stable/2.0.0/win32-x64'
            expandedRoot     = 'auto'
            createDirectories = @('data')
        } -AcquisitionCandidates @(
            @{
                kind         = 'packageDepot'
                priority     = 10
                verification = @{ mode = 'required'; algorithm = 'sha256'; sha256 = $packageArchive.Sha256 }
            }
        ) -Validation (New-TestValidation -Version '2.0.0')
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '2.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result
        $result = Build-PackageModelAcquisitionPlan -PackageModelResult $result

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $result.DefaultPackageDepotFilePath) -Force
        Copy-Item -LiteralPath $packageArchive.ZipPath -Destination $result.DefaultPackageDepotFilePath -Force
        $result = Save-PackageModelPackageFile -PackageModelResult $result
        $result = Install-PackageModelPackage -PackageModelResult $result

        Remove-Item -LiteralPath (Join-Path $result.InstallDirectory 'data') -Recurse -Force

        $rerun = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $rerun = Resolve-PackageModelPackage -PackageModelResult $rerun
        $rerun = Resolve-PackageModelPaths -PackageModelResult $rerun
        $rerun = Build-PackageModelAcquisitionPlan -PackageModelResult $rerun
        $rerun = Find-PackageModelExistingPackage -PackageModelResult $rerun
        $rerun = Classify-PackageModelExistingPackage -PackageModelResult $rerun
        $rerun = Resolve-PackageModelExistingPackageDecision -PackageModelResult $rerun
        $rerun = Save-PackageModelPackageFile -PackageModelResult $rerun
        $rerun = Install-PackageModelPackage -PackageModelResult $rerun

        $rerun.ExistingPackage.SearchKind | Should -Be 'packageModelTargetInstallPath'
        $rerun.ExistingPackage.Decision | Should -Be 'ExistingInstallValidationFailed'
        $rerun.Install.Status | Should -Be 'RepairedPackageModelOwnedInstall'
    }

    It 'prefers Write-StandardMessage when it is available' {
        Mock Write-StandardMessage {}
        Mock Write-Host {}

        { Write-PackageModelExecutionMessage -Message '[STEP] Example step' } | Should -Not -Throw

        Assert-MockCalled Write-StandardMessage -Times 1
        Assert-MockCalled Write-Host -Times 0
    }

    It 'falls back to Write-Host when Write-StandardMessage throws' {
        Mock Write-StandardMessage { throw 'logger unavailable' }
        Mock Write-Host {}

        { Write-PackageModelExecutionMessage -Message '[STEP] Example step' } | Should -Not -Throw

        Assert-MockCalled Write-StandardMessage -Times 1
        Assert-MockCalled Write-Host -Times 1
    }

    It 'loads Write-StandardMessage from ExecutionEngine and the PackageModel logger adapter from Support Package' {
        $writeStandardMessage = Get-Command Write-StandardMessage -CommandType Function
        $packageModelExecutionMessage = Get-Command Write-PackageModelExecutionMessage -CommandType Function

        $writeStandardMessage.ScriptBlock.File | Should -Match 'PackageModel\\Support\\ExecutionEngine\\.*StandardMessage\.ps1$'
        $packageModelExecutionMessage.ScriptBlock.File | Should -Match 'PackageModel\\Support\\Package\\.*ExecutionMessage\.ps1$'
    }

    It 'registers PATH from generic inputs without a PackageModel result object' {
        $registeredDirectory = Join-Path $TestDrive 'generic-path-registration\bin'
        $null = New-Item -ItemType Directory -Path $registeredDirectory -Force

        $writes = New-Object System.Collections.Generic.List[object]
        Mock Get-EnvironmentVariableValue {
            param([string]$Name, [string]$Target)
            switch ($Target) {
                'Process' { 'C:\Windows\System32' }
                'User' { 'C:\Users\Test\bin' }
                default { $null }
            }
        }
        Mock Set-EnvironmentVariableValue {
            param([string]$Name, [string]$Value, [string]$Target)
            $writes.Add([pscustomobject]@{
                Name   = $Name
                Value  = $Value
                Target = $Target
            }) | Out-Null
        }

        $registration = Register-PathEnvironment -Mode 'user' -RegisteredPath $registeredDirectory -CleanupDirectories @()

        $registration.Status | Should -Be 'Registered'
        @($registration.UpdatedTargets) | Should -Be @('Process', 'User')
        $registration.RegisteredPath | Should -Be $registeredDirectory
        @($writes | ForEach-Object { $_.Target }) | Should -Be @('Process', 'User')
    }

    It 'writes ownership records keyed by install slot and updates current release metadata' {
        $rootPath = Join-Path $TestDrive 'ownership-record'
        $installRoot = Join-Path $rootPath 'managed-install'
        $ownershipIndexPath = Join-Path $rootPath 'ownership.json'
        $null = New-Item -ItemType Directory -Path $installRoot -Force

        $globalDocument = New-TestPackageModelGlobalDocument -OwnershipIndexFilePath $ownershipIndexPath
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '3.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '3.0.0')
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '3.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result.InstallDirectory = $installRoot
        $result.Validation = [pscustomobject]@{
            Accepted = $true
        }
        $result.InstallOrigin = 'PackageModelInstalled'

        $result = Update-PackageModelOwnershipRecord -PackageModelResult $result
        $savedDocument = Read-PackageModelJsonDocument -Path $ownershipIndexPath
        $record = $savedDocument.Document.records[0]

        $record.installSlotId | Should -Be 'VSCodeRuntime:stable:win32-x64'
        $record.currentReleaseId | Should -Be 'vsCode-win-x64-stable'
        $record.currentVersion | Should -Be '3.0.0'
        $record.installDirectory | Should -Be $installRoot
    }

    It 'resolves source inventory absence as no additional environment sources' {
        $rootPath = Join-Path $TestDrive 'no-inventory'
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
            ))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $rootPath 'missing-source-inventory.json'), 'Process')
        [Environment]::SetEnvironmentVariable($script:SiteCodeEnvVarName, 'BER', 'Process')

        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'

        @($config.EnvironmentSources.PSObject.Properties.Name) | Should -Be @('defaultPackageDepot')
    }
}
