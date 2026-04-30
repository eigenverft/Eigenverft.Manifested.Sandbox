<#
    Package-focused Pester coverage for the module.
#>

function global:Invoke-TestPackageDescribe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    Describe $Name {
        BeforeAll {
            . "$PSScriptRoot\Eigenverft.Manifested.Sandbox.TestImports.ps1"
            $script:ModuleManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Eigenverft.Manifested.Sandbox\Eigenverft.Manifested.Sandbox.psd1'
            $script:SourceInventoryEnvVarName = Get-PackageSourceInventoryPathEnvironmentVariableName
            $script:SiteCodeEnvVarName = Get-PackageSiteCodeEnvironmentVariableName
        }

        BeforeEach {
            $script:OriginalSourceInventoryPath = [Environment]::GetEnvironmentVariable($script:SourceInventoryEnvVarName, 'Process')
            $script:OriginalSiteCode = [Environment]::GetEnvironmentVariable($script:SiteCodeEnvVarName, 'Process')
            $script:OriginalLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
            [Environment]::SetEnvironmentVariable('LOCALAPPDATA', (Join-Path $TestDrive 'LocalAppData'), 'Process')
        }

        AfterEach {
            [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, $script:OriginalSourceInventoryPath, 'Process')
            [Environment]::SetEnvironmentVariable($script:SiteCodeEnvVarName, $script:OriginalSiteCode, 'Process')
            [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $script:OriginalLocalAppData, 'Process')
        }

        & $Body
    }
}

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

function global:New-TestPackageGlobalDocument {
    param(
        [string]$ApplicationRootDirectory,
        [string]$PackageFileStagingDirectory,
        [string]$PackageInstallStageDirectory,
        [string]$DefaultPackageDepotDirectory,
        [string]$PreferredTargetInstallDirectory,
        [string]$LocalRepositoryRoot,
        [string]$PackageFileIndexFilePath,
        [string]$PackageStateIndexFilePath,
        [string]$PackageDepotRelativePath = '{definitionId}/{releaseTrack}/{version}/{flavor}',
        [string]$PackageWorkSlotDirectory = '{definitionId}-{slotHash}',
        [bool]$AllowFallback = $true,
        [string]$ReleaseTrack = 'stable',
        [string]$Strategy = 'latestByVersion',
        [hashtable]$EnvironmentSources = $null
    )

    $acquisitionEnvironment = @{
        stores = @{
            packageFileStagingDirectory = if ($PSBoundParameters.ContainsKey('PackageFileStagingDirectory')) { $PackageFileStagingDirectory } else { '{applicationRootDirectory}/FileStage' }
            packageInstallStageDirectory = if ($PSBoundParameters.ContainsKey('PackageInstallStageDirectory')) { $PackageInstallStageDirectory } else { '{applicationRootDirectory}/InstStage' }
        }
        defaults = @{
            allowFallback = $AllowFallback
        }
        tracking = @{
            packageFileIndexFilePath = if ($PSBoundParameters.ContainsKey('PackageFileIndexFilePath')) { $PackageFileIndexFilePath } else { '{applicationRootDirectory}/State/package-file-index.json' }
        }
    }
    if ($PSBoundParameters.ContainsKey('EnvironmentSources') -and $null -ne $EnvironmentSources) {
        $acquisitionEnvironment.environmentSources = $EnvironmentSources
    }

    return @{
        package = @{
            applicationRootDirectory = if ($PSBoundParameters.ContainsKey('ApplicationRootDirectory')) { $ApplicationRootDirectory } else { '%LOCALAPPDATA%/Programs/Evf.Sandbox' }
            preferredTargetInstallDirectory = if ($PSBoundParameters.ContainsKey('PreferredTargetInstallDirectory')) { $PreferredTargetInstallDirectory } else { '{applicationRootDirectory}/Installed' }
            repositorySources = @{
                EigenverftModule = @{
                    kind = 'moduleLocal'
                    definitionRoot = 'Repositories/EigenverftModule'
                }
            }
            localRepositoryRoot = if ($PSBoundParameters.ContainsKey('LocalRepositoryRoot')) { $LocalRepositoryRoot } else { '{applicationRootDirectory}/PackageRepositories' }
            layout = @{
                packageDepotRelativePath = $PackageDepotRelativePath
                packageWorkSlotDirectory = $PackageWorkSlotDirectory
            }
            acquisitionEnvironment = $acquisitionEnvironment
            packageState = @{
                indexFilePath = if ($PSBoundParameters.ContainsKey('PackageStateIndexFilePath')) { $PackageStateIndexFilePath } else { '{applicationRootDirectory}/State/package-state-index.json' }
            }
            selectionDefaults = @{
                releaseTrack = $ReleaseTrack
                strategy     = $Strategy
            }
        }
    }
}

function global:Add-TestFilesystemSourceCapabilities {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Source,

        [bool]$Readable = $true,
        [bool]$Writable = $false,
        [bool]$MirrorTarget = $false,
        [bool]$EnsureExists = $false
    )

    if (-not $Source.ContainsKey('readable')) {
        $Source.readable = $Readable
    }
    if (-not $Source.ContainsKey('writable')) {
        $Source.writable = $Writable
    }
    if (-not $Source.ContainsKey('mirrorTarget')) {
        $Source.mirrorTarget = $MirrorTarget
    }
    if (-not $Source.ContainsKey('ensureExists')) {
        $Source.ensureExists = $EnsureExists
    }

    return $Source
}

function global:New-TestDepotInventoryDocument {
    param(
        [string]$DefaultPackageDepotDirectory,
        [hashtable]$EnvironmentSources = @{}
    )

    $sources = @{}
    $sources.defaultPackageDepot = Add-TestFilesystemSourceCapabilities -Source @{
        kind         = 'filesystem'
        enabled      = $true
        searchOrder  = 300
        basePath     = if ($PSBoundParameters.ContainsKey('DefaultPackageDepotDirectory')) { $DefaultPackageDepotDirectory } else { '{applicationRootDirectory}/DefaultPackageDepot' }
    } -Writable $true -MirrorTarget $true -EnsureExists $true
    foreach ($key in @($EnvironmentSources.Keys)) {
        $sources[$key] = if ([string]::Equals([string]$EnvironmentSources[$key].kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-TestFilesystemSourceCapabilities -Source $EnvironmentSources[$key]
        }
        else {
            $EnvironmentSources[$key]
        }
    }

    return @{
        inventoryVersion = 1
        acquisitionEnvironment = @{
            environmentSources = $sources
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
    foreach ($key in @($GlobalEnvironmentSources.Keys)) {
        if ([string]::Equals([string]$GlobalEnvironmentSources[$key].kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
            $GlobalEnvironmentSources[$key] = Add-TestFilesystemSourceCapabilities -Source $GlobalEnvironmentSources[$key]
        }
    }
    foreach ($key in @($SiteEnvironmentSources.Keys)) {
        if ([string]::Equals([string]$SiteEnvironmentSources[$key].kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
            $SiteEnvironmentSources[$key] = Add-TestFilesystemSourceCapabilities -Source $SiteEnvironmentSources[$key]
        }
    }
    if ($SiteEnvironmentSources.Count -gt 0 -or $SiteDefaults.Count -gt 0) {
        $sites[$SiteCode] = @{}
        if ($SiteEnvironmentSources.Count -gt 0) {
            $sites[$SiteCode].acquisitionEnvironment = @{
                environmentSources = $SiteEnvironmentSources
            }
        }
        if ($SiteDefaults.Count -gt 0) {
            if (-not $sites[$SiteCode].ContainsKey('acquisitionEnvironment')) {
                $sites[$SiteCode].acquisitionEnvironment = @{}
            }
            $sites[$SiteCode].acquisitionEnvironment.defaults = $SiteDefaults
        }
    }

    $global = @{}
    if ($GlobalEnvironmentSources.Count -gt 0) {
        $global.acquisitionEnvironment = @{
            environmentSources = $GlobalEnvironmentSources
        }
    }
    if ($GlobalDefaults.Count -gt 0) {
        if (-not $global.ContainsKey('acquisitionEnvironment')) {
            $global.acquisitionEnvironment = @{}
        }
        $global.acquisitionEnvironment.defaults = $GlobalDefaults
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
        [bool]$RequirePackageOwnership = $false
    )

    return @{
        allowAdoptExternal    = $AllowAdoptExternal
        upgradeAdoptedInstall = $UpgradeAdoptedInstall
        requirePackageOwnership = $RequirePackageOwnership
    }
}

function global:New-TestPackageRelease {
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
                fileName = $FileName
                format   = 'zip'
                portable = $true
            }
            if (-not [string]::IsNullOrWhiteSpace($PackageFileSha256)) {
                $packageFile.contentHash = @{
                    algorithm = 'sha256'
                    value     = $PackageFileSha256
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

function global:Write-TestPackageDocuments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [object]$GlobalDocument,

        [Parameter(Mandatory = $true)]
        [object]$DefinitionDocument,

        [AllowNull()]
        [object]$DepotInventoryDocument,

        [AllowNull()]
        [object]$SourceInventoryDocument
    )

    $globalConfigPath = Join-Path $RootPath 'Configuration\Internal\Config.json'
    $depotInventoryPath = Join-Path $RootPath 'Configuration\Internal\DepotInventory.json'
    $definitionPath = Join-Path $RootPath "$($DefinitionDocument.id).json"
    Write-TestJsonDocument -Path $globalConfigPath -Document $GlobalDocument
    if (-not $PSBoundParameters.ContainsKey('DepotInventoryDocument') -or $null -eq $DepotInventoryDocument) {
        $DepotInventoryDocument = New-TestDepotInventoryDocument -DefaultPackageDepotDirectory (Join-Path $RootPath 'DefaultPackageDepot')
    }
    Write-TestJsonDocument -Path $depotInventoryPath -Document $DepotInventoryDocument
    Write-TestJsonDocument -Path $definitionPath -Document $DefinitionDocument

    $sourceInventoryPath = $null
    if ($PSBoundParameters.ContainsKey('SourceInventoryDocument') -and $null -ne $SourceInventoryDocument) {
        $sourceInventoryPath = Join-Path $RootPath 'SourceInventory.json'
        Write-TestJsonDocument -Path $sourceInventoryPath -Document $SourceInventoryDocument
    }

    return [pscustomobject]@{
        GlobalConfigPath   = $globalConfigPath
        DepotInventoryPath = $depotInventoryPath
        DefinitionPath     = $definitionPath
        SourceInventoryPath = $sourceInventoryPath
    }
}

