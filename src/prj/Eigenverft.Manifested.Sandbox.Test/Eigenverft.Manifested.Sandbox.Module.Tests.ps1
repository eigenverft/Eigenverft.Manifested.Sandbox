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
        metadataFiles = [object[]]@()
        signatures    = [object[]]@()
        fileDetails   = [object[]]@()
        registryChecks = [object[]]@()
    }
}

function global:New-TestExistingInstallDiscovery {
    param(
        [bool]$EnableDetection = $false,
        [array]$SearchLocations = [object[]]@(),
        [array]$InstallRootRules = [object[]]@()
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

        [string]$ReleaseTag = '',

        [string]$FileName = '',

        [string]$PackageFileSha256 = '',

        [array]$AcquisitionCandidates = [object[]]@(),

        [hashtable]$Compatibility = $null,

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

    if (-not [string]::IsNullOrWhiteSpace($ReleaseTag)) {
        $release.releaseTag = $ReleaseTag
    }

    if ($PSBoundParameters.ContainsKey('Compatibility')) {
        $release.compatibility = $Compatibility
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

        [hashtable]$UpstreamSources = $null,

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
        upstreamSources = if ($PSBoundParameters.ContainsKey('UpstreamSources') -and $null -ne $UpstreamSources) {
            $UpstreamSources
        }
        else {
            @{
                vsCodeUpdateService = @{
                    kind    = 'download'
                    baseUri = $UpstreamBaseUri
                }
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
            compatibility            = @{
                checks = [object[]]@()
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

    It 'exports Invoke-PackageModel-LlamaCppRuntime and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-PackageModel-LlamaCppRuntime'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-PackageModel-Qwen35-2B-Q6K and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-PackageModel-Qwen35-2B-Q6K'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-PackageModel-GitRuntime and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-PackageModel-GitRuntime'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'exports Invoke-PackageModel-GHCliRuntime and keeps it parameterless' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
        $command = Get-Command -Name 'Invoke-PackageModel-GHCliRuntime'

        $command | Should -Not -BeNullOrEmpty
        $publicParameterNames = @($command.Parameters.Keys | Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            })
        $publicParameterNames.Count | Should -Be 0
    }

    It 'does not export migrated StateModel runtime commands' {
        $module = Import-Module -Name $script:ModuleManifestPath -Force -PassThru

        Get-Command -Name 'Initialize-VSCodeRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-GitRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name 'Initialize-GHCliRuntime' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'loads the shipped global config without baked-in environment sources' {
        $globalInfo = Read-PackageModelJsonDocument -Path (Get-PackageModelGlobalConfigPath)

        $globalInfo.Document.packageModel.PSObject.Properties.Name | Should -Contain 'preferredTargetInstallDirectory'
        $globalInfo.Document.packageModel.acquisitionEnvironment.stores.PSObject.Properties.Name | Should -Contain 'installWorkspaceDirectory'
        $globalInfo.Document.packageModel.acquisitionEnvironment.stores.PSObject.Properties.Name | Should -Contain 'defaultPackageDepotDirectory'
        $globalInfo.Document.packageModel.acquisitionEnvironment.PSObject.Properties['environmentSources'] | Should -BeNullOrEmpty
    }

    It 'loads the shipped LlamaCppRuntime definition and selects the fixed GitHub-backed release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageModelConfig -DefinitionId 'LlamaCppRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $sourceDefinition = Get-PackageModelSourceDefinition -PackageModelConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'llamaCppGitHub' })

        $config.DefinitionId | Should -Be 'LlamaCppRuntime'
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

        $config = Get-PackageModelConfig -DefinitionId 'GitRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $sourceDefinition = Get-PackageModelSourceDefinition -PackageModelConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'gitForWindowsGitHub' })

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
        $result.Package.packageFile.integrity.sha256 | Should -Be $expectedSha256
        $result.Package.install.pathRegistration.source.value | Should -Be 'git'
    }

    It 'loads the shipped GHCliRuntime definition and selects the fixed GitHub-backed release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $config = Get-PackageModelConfig -DefinitionId 'GHCliRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $sourceDefinition = Get-PackageModelSourceDefinition -PackageModelConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'ghCliGitHub' })

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

        $config.DefinitionId | Should -Be 'GHCliRuntime'
        $sourceDefinition.Kind | Should -Be 'githubRelease'
        $sourceDefinition.RepositoryOwner | Should -Be 'cli'
        $sourceDefinition.RepositoryName | Should -Be 'cli'
        $result.Package.version | Should -Be '2.91.0'
        $result.Package.releaseTag | Should -Be 'v2.91.0'
        $result.Package.packageFile.fileName | Should -Be $expectedFileName
        $result.Package.packageFile.integrity.sha256 | Should -Be $expectedSha256
        $result.Package.install.pathRegistration.source.value | Should -Be 'gh'
    }

    It 'loads the shipped Qwen35_2B_Q6K definition and selects the fixed Hugging Face-backed resource release' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PhysicalMemoryGiB { 2.0 }
        Mock Get-VideoMemoryGiB { 1.0 }

        $config = Get-PackageModelConfig -DefinitionId 'Qwen35_2B_Q6K'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $sourceDefinition = Get-PackageModelSourceDefinition -PackageModelConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'huggingFaceDownload' })

        $config.DefinitionId | Should -Be 'Qwen35_2B_Q6K'
        $sourceDefinition.Kind | Should -Be 'download'
        $sourceDefinition.BaseUri | Should -Be 'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/'
        $result.PackageId | Should -Be 'qwen35-2b-q6-k-stable'
        $result.Package.version | Should -Be '3.5.0'
        $result.Package.packageFile.fileName | Should -Be 'Qwen3.5-2B-Q6_K.gguf'
        $result.Package.packageFile.integrity.algorithm | Should -Be 'sha256'
        $result.Package.packageFile.integrity.sha256 | Should -Be 'fc90339420b4298887aafb307a4291c55440b730133bbffe6ba9630503dcb548'
        $result.Package.install.kind | Should -Be 'placePackageFile'
        $result.Compatibility.Count | Should -Be 1
        $result.Compatibility[0].Kind | Should -Be 'physicalOrVideoMemoryGiB'
        $result.Compatibility[0].OnFail | Should -Be 'warn'
        $result.Compatibility[0].Accepted | Should -BeFalse
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

    It 'fails clearly when a definition still uses releaseDefaults.requirements' {
        $rootPath = Join-Path $TestDrive 'retired-requirements-packages'
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
        $definitionDocument = New-TestVSCodeDefinitionDocument -Releases @($release)
        $definitionDocument.releaseDefaults.requirements = @{
            checks = [object[]]@()
        }
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument $definitionDocument

        $definitionInfo = Read-PackageModelJsonDocument -Path $documents.DefinitionPath
        { Assert-PackageModelDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId 'VSCodeRuntime' } | Should -Throw '*releaseDefaults.requirements*'
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

    It 'rejects a selected release when compatibility.checks are not satisfied with onFail fail' {
        $rootPath = Join-Path $TestDrive 'requirements-checks-fail'
        $release = New-TestPackageModelRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Compatibility @{
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

        { Resolve-PackageModelPackage -PackageModelResult $result } | Should -Throw '*compatibility.checks*'
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

    It 'loads GitHub release upstream sources and keeps releaseTag separate from version' {
        $rootPath = Join-Path $TestDrive 'github-release-source'
        $release = New-TestPackageModelRelease -Id 'llama-cpu-x64-stable' -Version '0.0.1' -ReleaseTag 'b8863' -Architecture 'x64' -Flavor 'win-cpu-x64' -FileName 'llama-b8863-bin-win-cpu-x64.zip' -AcquisitionCandidates @(
            @{
                kind         = 'download'
                sourceId     = 'llamaCppGitHub'
                priority     = 100
                verification = @{ mode = 'required' }
            }
        )
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '0.0.1') -UpstreamSources @{
            llamaCppGitHub = @{
                kind            = 'githubRelease'
                repositoryOwner = 'ggml-org'
                repositoryName  = 'llama.cpp'
            }
        })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $definitionSource = Get-PackageModelSourceDefinition -PackageModelConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'llamaCppGitHub' })

        $definitionSource.Kind | Should -Be 'githubRelease'
        $definitionSource.RepositoryOwner | Should -Be 'ggml-org'
        $definitionSource.RepositoryName | Should -Be 'llama.cpp'
        $result.Package.version | Should -Be '0.0.1'
        $result.Package.releaseTag | Should -Be 'b8863'
    }

    It 'requires releaseTag for GitHub-backed releases' {
        $rootPath = Join-Path $TestDrive 'github-release-tag-required'
        $release = New-TestPackageModelRelease -Id 'llama-cpu-x64-stable' -Version '0.0.1' -Architecture 'x64' -Flavor 'win-cpu-x64' -FileName 'llama-b8863-bin-win-cpu-x64.zip' -AcquisitionCandidates @(
            @{
                kind         = 'download'
                sourceId     = 'llamaCppGitHub'
                priority     = 100
                verification = @{ mode = 'required' }
            }
        )
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '0.0.1') -UpstreamSources @{
            llamaCppGitHub = @{
                kind            = 'githubRelease'
                repositoryOwner = 'ggml-org'
                repositoryName  = 'llama.cpp'
            }
        })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        { Get-PackageModelConfig -DefinitionId 'VSCodeRuntime' } | Should -Throw '*requires releaseTag*'
    }

    It 'resolves a GitHub release asset URL from releaseTag and packageFile.fileName' {
        $rootPath = Join-Path $TestDrive 'github-release-resolve'
        $release = New-TestPackageModelRelease -Id 'llama-cpu-x64-stable' -Version '0.0.1' -ReleaseTag 'b8863' -Architecture 'x64' -Flavor 'win-cpu-x64' -FileName 'llama-b8863-bin-win-cpu-x64.zip' -AcquisitionCandidates @(
            @{
                kind         = 'download'
                sourceId     = 'llamaCppGitHub'
                priority     = 100
                verification = @{ mode = 'required' }
            }
        )
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '0.0.1') -UpstreamSources @{
            llamaCppGitHub = @{
                kind            = 'githubRelease'
                repositoryOwner = 'ggml-org'
                repositoryName  = 'llama.cpp'
            }
        })

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }
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

        $config = Get-PackageModelConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $sourceDefinition = Get-PackageModelSourceDefinition -PackageModelConfig $config -SourceRef ([pscustomobject]@{ scope = 'definition'; id = 'llamaCppGitHub' })
        $resolvedSource = Resolve-PackageModelSource -SourceDefinition $sourceDefinition -AcquisitionCandidate $result.Package.acquisitionCandidates[0] -Package $result.Package

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

        { Resolve-PackageModelSource -SourceDefinition $sourceDefinition -AcquisitionCandidate $candidate -Package $package } | Should -Throw '*does not contain asset*llama-b8863-bin-win-cpu-x64.zip*'
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

    It 'resolves shipped GitRuntime PATH registration to the cmd directory' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $installRoot = Join-Path $TestDrive 'path-registration-shipped-git'
        $cmdDirectory = Join-Path $installRoot 'cmd'
        $null = New-Item -ItemType Directory -Path $cmdDirectory -Force
        Write-TestTextFile -Path (Join-Path $cmdDirectory 'git.exe') -Content 'fake git'

        $config = Get-PackageModelConfig -DefinitionId 'GitRuntime'
        $packageModelResult = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $packageModelResult = Resolve-PackageModelPackage -PackageModelResult $packageModelResult
        $packageModelResult.InstallDirectory = $installRoot
        $packageModelResult.InstallOrigin = 'PackageModelInstalled'

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageModelResult = Register-PackageModelPath -PackageModelResult $packageModelResult

        $packageModelResult.PathRegistration.Status | Should -Be 'Registered'
        $packageModelResult.PathRegistration.RegisteredPath | Should -Be $cmdDirectory
    }

    It 'resolves shipped GHCliRuntime PATH registration to the bin directory' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $installRoot = Join-Path $TestDrive 'path-registration-shipped-ghcli'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $binDirectory 'gh.exe') -Content 'fake gh'

        $config = Get-PackageModelConfig -DefinitionId 'GHCliRuntime'
        $packageModelResult = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $packageModelResult = Resolve-PackageModelPackage -PackageModelResult $packageModelResult
        $packageModelResult.InstallDirectory = $installRoot
        $packageModelResult.InstallOrigin = 'PackageModelInstalled'

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageModelResult = Register-PackageModelPath -PackageModelResult $packageModelResult

        $packageModelResult.PathRegistration.Status | Should -Be 'Registered'
        $packageModelResult.PathRegistration.RegisteredPath | Should -Be $binDirectory
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

    It 'loads archive helpers from ExecutionEngine and keeps the StateModel extraction wrapper in place' {
        $expandArchiveToStage = Get-Command Expand-ArchiveToStage -CommandType Function
        $expandManifestedArchiveToStage = Get-Command Expand-ManifestedArchiveToStage -CommandType Function

        $expandArchiveToStage.ScriptBlock.File | Should -Match 'PackageModel\\Support\\ExecutionEngine\\.*Archive\.ps1$'
        $expandManifestedArchiveToStage.ScriptBlock.File | Should -Match 'StateModel\\Support\\.*Shared\.Extraction\.ps1$'
    }

    It 'loads command resolution and filesystem helpers from ExecutionEngine' {
        $getResolvedApplicationPath = Get-Command Get-ResolvedApplicationPath -CommandType Function
        $removePathIfExists = Get-Command Remove-PathIfExists -CommandType Function
        $copyFileToPath = Get-Command Copy-FileToPath -CommandType Function

        $getResolvedApplicationPath.ScriptBlock.File | Should -Match 'PackageModel\\Support\\ExecutionEngine\\.*CommandResolution\.ps1$'
        $removePathIfExists.ScriptBlock.File | Should -Match 'PackageModel\\Support\\ExecutionEngine\\.*FileSystem\.ps1$'
        $copyFileToPath.ScriptBlock.File | Should -Match 'PackageModel\\Support\\ExecutionEngine\\.*FileSystem\.ps1$'
    }

    It 'returns null when Get-ResolvedApplicationPath cannot resolve a command' {
        Mock Get-Command { @() } -ParameterFilter { $Name -eq 'missing-tool' -and $CommandType -eq 'Application' -and $All }

        $resolvedPath = Get-ResolvedApplicationPath -CommandName 'missing-tool'

        $resolvedPath | Should -BeNullOrEmpty
    }

    It 'returns the normalized full path of the first resolved application' {
        Mock Get-Command {
            [pscustomobject]@{
                Source = 'C:\Tools\bin\tool.exe'
            }
        } -ParameterFilter { $Name -eq 'tool' -and $CommandType -eq 'Application' -and $All }

        $resolvedPath = Get-ResolvedApplicationPath -CommandName 'tool'

        $resolvedPath | Should -Be ([System.IO.Path]::GetFullPath('C:\Tools\bin\tool.exe'))
    }

    It 'returns false when Remove-PathIfExists receives a missing path' {
        $removed = Remove-PathIfExists -Path (Join-Path $TestDrive 'missing-path')

        $removed | Should -BeFalse
    }

    It 'removes an existing file and returns true' {
        $filePath = Join-Path $TestDrive 'remove-file\test.txt'
        Write-TestTextFile -Path $filePath -Content 'content'

        $removed = Remove-PathIfExists -Path $filePath

        $removed | Should -BeTrue
        Test-Path -LiteralPath $filePath | Should -BeFalse
    }

    It 'removes an existing directory and returns true' {
        $directoryPath = Join-Path $TestDrive 'remove-directory'
        Write-TestTextFile -Path (Join-Path $directoryPath 'test.txt') -Content 'content'

        $removed = Remove-PathIfExists -Path $directoryPath

        $removed | Should -BeTrue
        Test-Path -LiteralPath $directoryPath | Should -BeFalse
    }

    It 'copies a file to a target path and returns the resolved target path' {
        $sourcePath = Join-Path $TestDrive 'copy-file\source.txt'
        $targetPath = Join-Path $TestDrive 'copy-file\target.txt'
        Write-TestTextFile -Path $sourcePath -Content 'version-a'

        $resolvedTarget = Copy-FileToPath -SourcePath $sourcePath -TargetPath $targetPath

        $resolvedTarget | Should -Be ([System.IO.Path]::GetFullPath($targetPath))
        (Get-Content -LiteralPath $targetPath -Raw) | Should -Be 'version-a'
    }

    It 'overwrites a copied file when requested' {
        $sourcePath = Join-Path $TestDrive 'copy-file-overwrite\source.txt'
        $targetPath = Join-Path $TestDrive 'copy-file-overwrite\target.txt'
        Write-TestTextFile -Path $sourcePath -Content 'version-b'
        Write-TestTextFile -Path $targetPath -Content 'version-a'

        Copy-FileToPath -SourcePath $sourcePath -TargetPath $targetPath -Overwrite | Out-Null

        (Get-Content -LiteralPath $targetPath -Raw) | Should -Be 'version-b'
    }

    It 'extracts an archive into an empty destination directory' {
        $rootPath = Join-Path $TestDrive 'archive-extract-empty'
        $sourceDirectory = Join-Path $rootPath 'source'
        $destinationDirectory = Join-Path $rootPath 'destination'
        $zipPath = Join-Path $rootPath 'package.zip'

        $null = New-Item -ItemType Directory -Path (Join-Path $sourceDirectory 'bin') -Force
        Write-TestTextFile -Path (Join-Path $sourceDirectory 'Code.exe') -Content 'binary-a'
        Write-TestTextFile -Path (Join-Path $sourceDirectory 'bin\code.cmd') -Content '@echo off'
        Write-TestZipFromDirectory -SourceDirectory $sourceDirectory -ZipPath $zipPath

        $resolvedDestination = Expand-ArchiveToDirectory -ArchivePath $zipPath -DestinationDirectory $destinationDirectory

        $resolvedDestination | Should -Be ([System.IO.Path]::GetFullPath($destinationDirectory))
        Test-Path -LiteralPath (Join-Path $destinationDirectory 'Code.exe') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $destinationDirectory 'bin\code.cmd') | Should -BeTrue
    }

    It 'overwrites existing extracted files when requested' {
        $rootPath = Join-Path $TestDrive 'archive-extract-overwrite'
        $firstSourceDirectory = Join-Path $rootPath 'source-a'
        $secondSourceDirectory = Join-Path $rootPath 'source-b'
        $destinationDirectory = Join-Path $rootPath 'destination'
        $firstZipPath = Join-Path $rootPath 'package-a.zip'
        $secondZipPath = Join-Path $rootPath 'package-b.zip'

        $null = New-Item -ItemType Directory -Path $firstSourceDirectory -Force
        $null = New-Item -ItemType Directory -Path $secondSourceDirectory -Force
        Write-TestTextFile -Path (Join-Path $firstSourceDirectory 'app.txt') -Content 'version-a'
        Write-TestTextFile -Path (Join-Path $secondSourceDirectory 'app.txt') -Content 'version-b'
        Write-TestZipFromDirectory -SourceDirectory $firstSourceDirectory -ZipPath $firstZipPath
        Write-TestZipFromDirectory -SourceDirectory $secondSourceDirectory -ZipPath $secondZipPath

        Expand-ArchiveToDirectory -ArchivePath $firstZipPath -DestinationDirectory $destinationDirectory | Out-Null
        Expand-ArchiveToDirectory -ArchivePath $secondZipPath -DestinationDirectory $destinationDirectory -Overwrite | Out-Null

        (Get-Content -LiteralPath (Join-Path $destinationDirectory 'app.txt') -Raw) | Should -Be 'version-b'
    }

    It 'returns the single child directory when expanded content lands under one top-level folder' {
        $stagePath = Join-Path $TestDrive 'expanded-root-single-child'
        $childDirectory = Join-Path $stagePath 'payload'
        $null = New-Item -ItemType Directory -Path $childDirectory -Force
        Write-TestTextFile -Path (Join-Path $childDirectory 'tool.exe') -Content 'tool'

        $expandedRoot = Get-ExpandedArchiveRoot -StagePath $stagePath

        $expandedRoot | Should -Be ([System.IO.Path]::GetFullPath($childDirectory))
    }

    It 'returns the stage root when files are expanded directly into the stage' {
        $stagePath = Join-Path $TestDrive 'expanded-root-stage'
        $null = New-Item -ItemType Directory -Path $stagePath -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $stagePath 'payload') -Force
        Write-TestTextFile -Path (Join-Path $stagePath 'tool.exe') -Content 'tool'

        $expandedRoot = Get-ExpandedArchiveRoot -StagePath $stagePath

        $expandedRoot | Should -Be ([System.IO.Path]::GetFullPath($stagePath))
    }

    It 'creates a temporary stage and resolves the expanded root from the extracted archive' {
        $rootPath = Join-Path $TestDrive 'archive-stage'
        $sourceDirectory = Join-Path $rootPath 'source'
        $payloadDirectory = Join-Path $sourceDirectory 'payload'
        $zipPath = Join-Path $rootPath 'package.zip'
        $null = New-Item -ItemType Directory -Path $payloadDirectory -Force
        Write-TestTextFile -Path (Join-Path $payloadDirectory 'tool.exe') -Content 'tool'
        Write-TestZipFromDirectory -SourceDirectory $sourceDirectory -ZipPath $zipPath

        $stageInfo = Expand-ArchiveToStage -ArchivePath $zipPath -Prefix 'pester'

        try {
            Test-Path -LiteralPath $stageInfo.StagePath -PathType Container | Should -BeTrue
            $stageInfo.ExpandedRoot | Should -Be (Join-Path $stageInfo.StagePath 'payload')
            Test-Path -LiteralPath (Join-Path $stageInfo.ExpandedRoot 'tool.exe') -PathType Leaf | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $stageInfo.StagePath) {
                Remove-Item -LiteralPath $stageInfo.StagePath -Recurse -Force
            }
        }
    }

    It 'routes PackageModel archive installs through Expand-ArchiveToStage' {
        $rootPath = Join-Path $TestDrive 'package-install-archive-route'
        $packageFilePath = Join-Path $rootPath 'package.zip'
        $stagePath = Join-Path $rootPath 'stage'
        $expandedRoot = Join-Path $stagePath 'payload'
        $installDirectory = Join-Path $rootPath 'install'
        $null = New-Item -ItemType Directory -Path $expandedRoot -Force
        Write-TestTextFile -Path $packageFilePath -Content 'placeholder'
        Write-TestTextFile -Path (Join-Path $expandedRoot 'Code.exe') -Content 'binary'

        Mock Expand-ArchiveToStage {
            [pscustomobject]@{
                StagePath    = $stagePath
                ExpandedRoot = $expandedRoot
            }
        }
        Mock Expand-ManifestedArchiveToStage {
            throw 'legacy extraction path should not be used'
        }
        Mock Remove-PathIfExists { return $true }
        Mock Remove-ManifestedPath {
            throw 'legacy cleanup path should not be used'
        }

        $packageModelResult = [pscustomobject]@{
            PackageId        = 'VSCodeRuntime'
            PackageFilePath  = $packageFilePath
            InstallDirectory = $installDirectory
            Package          = [pscustomobject]@{
                install = [pscustomobject]@{
                    kind              = 'expandArchive'
                    expandedRoot      = 'auto'
                    createDirectories = @('data')
                }
            }
            ExistingPackage = $null
        }

        $installResult = Install-PackageModelArchive -PackageModelResult $packageModelResult

        Assert-MockCalled Expand-ArchiveToStage -Times 1
        Assert-MockCalled Expand-ManifestedArchiveToStage -Times 0
        Assert-MockCalled Remove-PathIfExists -Times 1 -ParameterFilter { $Path -eq $stagePath }
        Assert-MockCalled Remove-ManifestedPath -Times 0
        $installResult.InstallKind | Should -Be 'expandArchive'
        Test-Path -LiteralPath (Join-Path $installDirectory 'Code.exe') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installDirectory 'data') -PathType Container | Should -BeTrue
    }

    It 'installs a single package file into the configured target-relative path' {
        $rootPath = Join-Path $TestDrive 'package-install-file-route'
        $packageFilePath = Join-Path $rootPath 'package\Qwen3.5-2B-Q6_K.gguf'
        $installDirectory = Join-Path $rootPath 'install'
        Write-TestTextFile -Path $packageFilePath -Content 'gguf-binary'

        $packageModelResult = [pscustomobject]@{
            PackageId        = 'Qwen35_2B_Q6K'
            PackageFilePath  = $packageFilePath
            InstallDirectory = $installDirectory
            Package          = [pscustomobject]@{
                packageFile = [pscustomobject]@{
                    fileName = 'Qwen3.5-2B-Q6_K.gguf'
                }
                install = [pscustomobject]@{
                    kind               = 'placePackageFile'
                    targetRelativePath = 'models/Qwen3.5-2B-Q6_K.gguf'
                }
            }
            ExistingPackage = $null
        }

        $installResult = Install-PackageModelPackageFile -PackageModelResult $packageModelResult

        $installResult.InstallKind | Should -Be 'placePackageFile'
        $installResult.InstalledFilePath | Should -Be (Join-Path $installDirectory 'models\Qwen3.5-2B-Q6_K.gguf')
        Test-Path -LiteralPath $installResult.InstalledFilePath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $installResult.InstalledFilePath -Raw) | Should -Be 'gguf-binary'
    }

    It 'installs a shipped single-file resource from the default package depot and validates it' {
        $rootPath = Join-Path $TestDrive 'resource-package-flow'
        $installWorkspaceDirectory = Join-Path $rootPath 'workspace'
        $defaultPackageDepotDirectory = Join-Path $rootPath 'default-depot'
        $preferredTargetInstallDirectory = Join-Path $rootPath 'installs'
        $ownershipIndexFilePath = Join-Path $rootPath 'ownership.json'
        $definitionDocument = @{
            schemaVersion = '1.0'
            id = 'Qwen35_2B_Q6K'
            display = @{
                default = @{
                    name = 'Qwen 3.5 2B Q6_K'
                    publisher = 'Unsloth'
                    corporation = 'Unsloth AI'
                    summary = 'Quantized GGUF model resource'
                }
                localizations = @{}
            }
            upstreamSources = @{
                huggingFaceDownload = @{
                    kind = 'download'
                    baseUri = 'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/'
                }
            }
            providedTools = @{
                commands = [object[]]@()
                apps = [object[]]@()
            }
            releaseDefaults = @{
                compatibility = @{
                    checks = @(
                        @{
                            kind = 'physicalOrVideoMemoryGiB'
                            operator = '>='
                            value = 4
                            onFail = 'warn'
                        }
                    )
                }
                install = @{
                    kind = 'placePackageFile'
                    installDirectory = 'qwen35-2b/{releaseTrack}/{version}/{flavor}'
                    targetRelativePath = 'Qwen3.5-2B-Q6_K.gguf'
                    pathRegistration = @{
                        mode = 'none'
                    }
                }
                validation = @{
                    files = @('Qwen3.5-2B-Q6_K.gguf')
                    directories = [object[]]@()
                    commandChecks = [object[]]@()
                    metadataFiles = [object[]]@()
                    signatures = [object[]]@()
                    fileDetails = [object[]]@()
                    registryChecks = [object[]]@()
                }
                existingInstallDiscovery = @{
                    enableDetection = $false
                    searchLocations = [object[]]@()
                    installRootRules = [object[]]@()
                }
                existingInstallPolicy = @{
                    allowAdoptExternal = $false
                    upgradeAdoptedInstall = $false
                    requirePackageModelOwnership = $false
                }
            }
            releases = @(
                @{
                    id = 'qwen35-2b-q6-k-stable'
                    version = '3.5.0'
                    releaseTrack = 'stable'
                    flavor = 'q6-k'
                    constraints = @{
                        os = @('windows')
                        cpu = @('x64')
                    }
                    packageFile = @{
                        fileName = 'Qwen3.5-2B-Q6_K.gguf'
                        format = 'gguf'
                        portable = $true
                        autoUpdateSupported = $false
                    }
                    acquisitionCandidates = @(
                        @{
                            kind = 'packageDepot'
                            priority = 250
                            verification = @{
                                mode = 'none'
                            }
                        }
                    )
                }
            )
        }
        $documents = Write-TestPackageModelDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageModelGlobalDocument -InstallWorkspaceDirectory $installWorkspaceDirectory -DefaultPackageDepotDirectory $defaultPackageDepotDirectory -PreferredTargetInstallDirectory $preferredTargetInstallDirectory -OwnershipIndexFilePath $ownershipIndexFilePath) -DefinitionDocument $definitionDocument

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageModelGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageModelDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageModelConfig -DefinitionId 'Qwen35_2B_Q6K'
        $result = New-PackageModelResult -CommandName 'test' -PackageModelConfig $config
        $result = Resolve-PackageModelPackage -PackageModelResult $result
        $result = Resolve-PackageModelPaths -PackageModelResult $result
        $result = Build-PackageModelAcquisitionPlan -PackageModelResult $result

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $result.DefaultPackageDepotFilePath) -Force
        Write-TestTextFile -Path $result.DefaultPackageDepotFilePath -Content 'gguf-binary'

        $result = Save-PackageModelPackageFile -PackageModelResult $result
        $result = Install-PackageModelPackage -PackageModelResult $result
        $result = Test-PackageModelInstalledPackage -PackageModelResult $result

        $result.PackageFileSave.Status | Should -Be 'HydratedFromDefaultPackageDepot'
        $result.Install.InstallKind | Should -Be 'placePackageFile'
        $result.Install.InstalledFilePath | Should -Be (Join-Path $result.InstallDirectory 'Qwen3.5-2B-Q6_K.gguf')
        Test-Path -LiteralPath $result.Install.InstalledFilePath -PathType Leaf | Should -BeTrue
        $result.Validation.Accepted | Should -BeTrue
    }

    It 'discovers command-based existing installs through Get-ResolvedApplicationPath' {
        $rootPath = Join-Path $TestDrive 'command-discovery-route'
        $installRoot = Join-Path $rootPath 'existing-install'
        $commandPath = Join-Path $installRoot 'bin\code.cmd'
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $commandPath) -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'Code.exe') -Content 'fake'
        Write-TestTextFile -Path $commandPath -Content '@echo off'

        $packageModelResult = [pscustomobject]@{
            InstallDirectory = $null
            ExistingPackage  = $null
            Package          = [pscustomobject]@{
                id = 'VSCodeRuntime'
                existingInstallDiscovery = [pscustomobject]@{
                    enableDetection = $true
                    searchLocations = @(
                        [pscustomobject]@{
                            kind = 'command'
                            name = 'code'
                        }
                    )
                    installRootRules = @(
                        [pscustomobject]@{
                            match = [pscustomobject]@{
                                kind  = 'fileName'
                                value = 'code.cmd'
                            }
                            installRootRelativePath = '..'
                        }
                    )
                }
            }
        }

        Mock Get-ResolvedApplicationPath { $commandPath } -ParameterFilter { $CommandName -eq 'code' }
        Mock Get-ManifestedResolvedApplicationPath {
            throw 'legacy command resolution path should not be used'
        }

        $packageModelResult = Find-PackageModelExistingPackage -PackageModelResult $packageModelResult

        Assert-MockCalled Get-ResolvedApplicationPath -Times 1 -ParameterFilter { $CommandName -eq 'code' }
        Assert-MockCalled Get-ManifestedResolvedApplicationPath -Times 0
        $packageModelResult.ExistingPackage.SearchKind | Should -Be 'command'
        $packageModelResult.ExistingPackage.CandidatePath | Should -Be $commandPath
        $packageModelResult.ExistingPackage.InstallDirectory | Should -Be ([System.IO.Path]::GetFullPath($installRoot))
    }

    It 'routes filesystem package saves through Copy-FileToPath' {
        $sourcePath = Join-Path $TestDrive 'filesystem-save\source.zip'
        $targetPath = Join-Path $TestDrive 'filesystem-save\target.zip'
        Write-TestTextFile -Path $sourcePath -Content 'archive'

        Mock Copy-FileToPath { $TargetPath } -ParameterFilter { $SourcePath -eq $sourcePath -and $TargetPath -eq $targetPath -and $Overwrite }

        $resolvedPath = Save-PackageModelFilesystemFile -SourcePath $sourcePath -TargetPath $targetPath

        Assert-MockCalled Copy-FileToPath -Times 1 -ParameterFilter { $SourcePath -eq $sourcePath -and $TargetPath -eq $targetPath -and $Overwrite }
        $resolvedPath | Should -Be $targetPath
    }

    It 'keeps Expand-ManifestedArchiveToStage as a compatibility wrapper over the generic archive helper' {
        $packagePath = Join-Path $TestDrive 'compat-package.zip'
        Write-TestTextFile -Path $packagePath -Content 'placeholder'
        Mock Expand-ArchiveToStage {
            [pscustomobject]@{
                StagePath    = 'C:\temp\stage'
                ExpandedRoot = 'C:\temp\stage\payload'
            }
        }

        $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $packagePath -Prefix 'compat'

        Assert-MockCalled Expand-ArchiveToStage -Times 1 -ParameterFilter { $ArchivePath -eq $packagePath -and $Prefix -eq 'compat' }
        $stageInfo.StagePath | Should -Be 'C:\temp\stage'
        $stageInfo.ExpandedRoot | Should -Be 'C:\temp\stage\payload'
    }

    It 'returns physical memory GiB from Win32_ComputerSystem' {
        Mock Get-CimInstance { [pscustomobject]@{ TotalPhysicalMemory = [uint64](16GB) } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }

        $physicalMemoryGiB = Get-PhysicalMemoryGiB

        $physicalMemoryGiB | Should -Be 16
    }

    It 'returns the highest valid video memory GiB from Win32_VideoController' {
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ AdapterRAM = [uint64](2GB) }
                [pscustomobject]@{ AdapterRAM = [uint64](8GB) }
                [pscustomobject]@{ AdapterRAM = [uint64]0 }
            )
        } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }

        $videoMemoryGiB = Get-VideoMemoryGiB

        $videoMemoryGiB | Should -Be 8
    }

    It 'evaluates physicalMemoryGiB and videoMemoryGiB compatibility checks with mocked helper outputs' {
        $packageModelConfig = [pscustomobject]@{
            Platform     = 'windows'
            Architecture = 'x64'
            OSVersion    = '10.0'
        }
        $compatibility = [pscustomobject]@{
            checks = @(
                [pscustomobject]@{
                    kind     = 'physicalMemoryGiB'
                    operator = '>='
                    value    = 8
                },
                [pscustomobject]@{
                    kind     = 'videoMemoryGiB'
                    operator = '>='
                    value    = 4
                }
            )
        }
        Mock Get-PhysicalMemoryGiB { 16.0 }
        Mock Get-VideoMemoryGiB { 8.0 }

        $evaluation = Test-PackageModelCompatibilityChecks -PackageModelConfig $packageModelConfig -Compatibility $compatibility

        $evaluation.Accepted | Should -BeTrue
        $evaluation.BlockingAccepted | Should -BeTrue
        @($evaluation.Checks | ForEach-Object { $_.Accepted }) | Should -Be @($true, $true)
        @($evaluation.Checks | ForEach-Object { $_.OnFail }) | Should -Be @('fail', 'fail')
    }

    It 'passes a physicalOrVideoMemoryGiB requirement when either RAM or VRAM satisfies it' {
        Mock Get-PhysicalMemoryGiB { 2.0 }
        Mock Get-VideoMemoryGiB { 8.0 }

        $evaluation = Test-PhysicalOrVideoMemoryRequirement -Operator '>=' -ValueGiB 4

        $evaluation.Accepted | Should -BeTrue
        $evaluation.PhysicalMemoryGiB | Should -Be 2
        $evaluation.VideoMemoryGiB | Should -Be 8
    }

    It 'fails a physicalOrVideoMemoryGiB requirement when neither RAM nor VRAM satisfies it' {
        Mock Get-PhysicalMemoryGiB { 2.0 }
        Mock Get-VideoMemoryGiB { 1.0 }

        $evaluation = Test-PhysicalOrVideoMemoryRequirement -Operator '>=' -ValueGiB 4

        $evaluation.Accepted | Should -BeFalse
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
