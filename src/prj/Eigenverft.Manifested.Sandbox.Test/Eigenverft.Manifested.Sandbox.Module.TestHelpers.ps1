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
        [string]$ShimDirectory,
        [string]$PackageInventoryFilePath,
        [string]$PackageOperationHistoryFilePath,
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
            shimDirectory = if ($PSBoundParameters.ContainsKey('ShimDirectory')) { $ShimDirectory } else { '{applicationRootDirectory}/Shims' }
            layout = @{
                packageDepotRelativePath = $PackageDepotRelativePath
                packageWorkSlotDirectory = $PackageWorkSlotDirectory
            }
            acquisitionEnvironment = $acquisitionEnvironment
            packageState = @{
                inventoryFilePath = if ($PSBoundParameters.ContainsKey('PackageInventoryFilePath')) { $PackageInventoryFilePath } else { '{applicationRootDirectory}/State/package-inventory.json' }
                operationHistoryFilePath = if ($PSBoundParameters.ContainsKey('PackageOperationHistoryFilePath')) { $PackageOperationHistoryFilePath } else { '{applicationRootDirectory}/State/package-operation-history.json' }
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

function global:New-TestInstalledStateDiscovery {
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

function global:New-TestOwnershipPolicy {
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

        [hashtable]$StateDiscovery = $null,

        [hashtable]$OwnershipPolicy = $null
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
        $release.assigned = $Install
    }
    if ($PSBoundParameters.ContainsKey('Validation')) {
        $release.validation = $Validation
    }
    if ($PSBoundParameters.ContainsKey('StateDiscovery')) {
        $release.discovery = $StateDiscovery
    }
    if ($PSBoundParameters.ContainsKey('OwnershipPolicy')) {
        $release.ownershipPolicy = $OwnershipPolicy
    }

    return (ConvertTo-TestPsObject $release)
}

function global:New-TestVSCodeDefinitionDocument {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Releases,

        [string]$UpstreamBaseUri = 'https://update.code.visualstudio.com',

        [hashtable]$UpstreamSources = $null,

        [hashtable]$SharedInstall = $null,

        [hashtable]$SharedValidation = $null,

        [hashtable]$SharedStateDiscovery = $null,

        [hashtable]$SharedOwnershipPolicy = $null
    )

    $firstRelease = $Releases | Where-Object { $null -ne $_ } | Select-Object -First 1

    if ($null -eq $SharedInstall) {
        $SharedInstall = @{
            kind             = 'expandArchive'
            installDirectory = 'vscode-runtime/{channel}/{version}/{platformTarget}'
            pathRegistration = @{
                mode   = 'user'
                source = @{
                    kind = 'shim'
                    use  = 'discovery.commands'
                }
            }
            expandedRoot     = 'auto'
            createDirectories = @('data')
        }
    }
    if ($null -eq $SharedValidation) {
        $SharedValidation = New-TestValidation -Version '0.0.0'
    }
    if ($null -eq $SharedStateDiscovery) {
        $SharedStateDiscovery = New-TestInstalledStateDiscovery -EnableDetection $false
    }
    if ($null -eq $SharedOwnershipPolicy) {
        $SharedOwnershipPolicy = New-TestOwnershipPolicy
    }

    $assigned = if ($firstRelease -and $firstRelease.PSObject.Properties['assigned']) {
        $firstRelease.assigned
    }
    else {
        $SharedInstall
    }
    $assigned = ConvertTo-TestPsObject $assigned
    if ($assigned.pathRegistration -and
        $assigned.pathRegistration.source -and
        [string]::Equals([string]$assigned.pathRegistration.source.kind, 'shim', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $assigned.pathRegistration.source.PSObject.Properties['use']) {
        $assigned.pathRegistration.source.PSObject.Properties.Remove('value')
        $assigned.pathRegistration.source | Add-Member -MemberType NoteProperty -Name 'use' -Value 'discovery.commands' -Force
    }

    $validation = if ($firstRelease -and $firstRelease.PSObject.Properties['validation']) {
        $firstRelease.validation
    }
    else {
        $SharedValidation
    }
    $validation = ConvertTo-TestPsObject $validation
    if (-not $assigned.PSObject.Properties['installedStateCheck']) {
        $assigned | Add-Member -MemberType NoteProperty -Name 'installedStateCheck' -Value @{
            use             = 'discovery'
            expectedVersion = '{version}'
            require         = @{
                files         = (@($validation.files).Count -gt 0)
                directories   = (@($validation.directories).Count -gt 0)
                commands      = (@($validation.commandChecks).Count -gt 0)
                apps          = $true
                metadataFiles = (@($validation.metadataFiles).Count -gt 0)
                signatures    = (@($validation.signatures).Count -gt 0)
                fileDetails   = (@($validation.fileDetails).Count -gt 0)
                registry      = (@($validation.registryChecks).Count -gt 0)
            }
        } -Force
    }
    $compatibility = if ($firstRelease -and $firstRelease.PSObject.Properties['compatibility']) {
        $firstRelease.compatibility
    }
    else {
        @{
            checks = [object[]]@()
        }
    }
    $installedDiscovery = if ($firstRelease -and $firstRelease.PSObject.Properties['discovery']) {
        $firstRelease.discovery
    }
    else {
        $SharedStateDiscovery
    }
    $ownershipPolicy = if ($firstRelease -and $firstRelease.PSObject.Properties['ownershipPolicy']) {
        $firstRelease.ownershipPolicy
    }
    else {
        $SharedOwnershipPolicy
    }
    $compatibility = ConvertTo-TestPsObject $compatibility
    $installedDiscovery = ConvertTo-TestPsObject $installedDiscovery
    $ownershipPolicy = ConvertTo-TestPsObject $ownershipPolicy

    $commandStateChecksByName = @{}
    foreach ($commandCheck in @($validation.commandChecks)) {
        if ($null -eq $commandCheck -or [string]::IsNullOrWhiteSpace([string]$commandCheck.entryPoint)) {
            continue
        }
        $entryPointName = [string]$commandCheck.entryPoint
        if (-not $commandStateChecksByName.ContainsKey($entryPointName)) {
            $commandStateChecksByName[$entryPointName] = New-Object System.Collections.Generic.List[object]
        }
        $stateCheck = [ordered]@{}
        foreach ($propertyName in @('arguments', 'outputPattern', 'expectedValue')) {
            if ($commandCheck.PSObject.Properties[$propertyName]) {
                $stateCheck[$propertyName] = $commandCheck.$propertyName
            }
        }
        $commandStateChecksByName[$entryPointName].Add($stateCheck) | Out-Null
    }
    if (-not $commandStateChecksByName.ContainsKey('code')) {
        $commandStateChecksByName['code'] = New-Object System.Collections.Generic.List[object]
    }

    $commands = @(
        foreach ($commandName in @($commandStateChecksByName.Keys)) {
            @{
                name         = [string]$commandName
                relativePath = if ([string]::Equals([string]$commandName, 'code', [System.StringComparison]::OrdinalIgnoreCase)) { 'bin/code.cmd' } else { "$commandName.cmd" }
                required     = $true
                exposed      = $true
                stateChecks  = @($commandStateChecksByName[$commandName].ToArray())
            }
        }
    )

    $packageTargets = @()
    $versionCatalog = @()
    foreach ($release in @($Releases)) {
        if ($null -eq $release) {
            continue
        }

        $targetId = [string]$release.id
        $artifactSources = @(
            foreach ($candidate in @($release.acquisitionCandidates)) {
                if ($null -eq $candidate) {
                    continue
                }
                $source = [ordered]@{
                    kind = [string]$candidate.kind
                }
                foreach ($propertyName in @('sourceId', 'sourcePath', 'searchOrder', 'priority', 'verification')) {
                    if ($candidate.PSObject.Properties[$propertyName]) {
                        $source[$propertyName] = $candidate.$propertyName
                    }
                }
                if (-not $source.Contains('sourceId') -and $candidate.PSObject.Properties['sourceRef'] -and $candidate.sourceRef.PSObject.Properties['id']) {
                    $source.sourceId = [string]$candidate.sourceRef.id
                }
                $source
            }
        )

        $packageTarget = @{
            id              = $targetId
            channel         = [string]$release.releaseTrack
            platformTarget  = [string]$release.flavor
            constraints     = $release.constraints
            versionSelection = @{
                strategy        = 'latestByVersion'
                allowPrerelease = $false
            }
        }
        if ($artifactSources.Count -gt 0) {
            $packageTarget.artifactDefaults = @{
                artifactSources = $artifactSources
            }
        }
        $packageTargets += $packageTarget

        $artifact = [ordered]@{
            releaseId = [string]$release.id
        }
        if ($release.packageFile -and $release.packageFile.PSObject.Properties['fileName']) {
            $artifact.fileName = [string]$release.packageFile.fileName
        }
        if ($release.packageFile -and $release.packageFile.PSObject.Properties['contentHash']) {
            $artifact.contentHash = $release.packageFile.contentHash
        }
        foreach ($packageFileProperty in @('publisherSignature', 'autoUpdateSupported', 'integrity', 'authenticode')) {
            if ($release.packageFile -and $release.packageFile.PSObject.Properties[$packageFileProperty]) {
                $artifact[$packageFileProperty] = $release.packageFile.$packageFileProperty
            }
        }
        if ($release.PSObject.Properties['sourcePath']) {
            $artifact.sourcePath = [string]$release.sourcePath
        }

        $versionEntry = [ordered]@{
            version           = [string]$release.version
            channels          = @([string]$release.releaseTrack)
            artifactsByTarget = @{
                $targetId = $artifact
            }
        }
        if ($release.PSObject.Properties['releaseTag'] -and -not [string]::IsNullOrWhiteSpace([string]$release.releaseTag)) {
            $versionEntry.releaseTag = [string]$release.releaseTag
        }
        $versionCatalog += $versionEntry
    }

    return @{
        schemaVersion = '1.2'
        id = 'VSCodeRuntime'
        display = @{
            default       = @{
                name        = 'Visual Studio Code'
                publisher   = 'Microsoft'
                corporation = 'Microsoft Corporation'
                summary     = 'Code editor'
            }
        }
        packageTargets = $packageTargets
        versionCatalog = $versionCatalog
        discovery = @{
            files         = @($validation.files)
            directories   = @($validation.directories)
            commands      = $commands
            apps          = @(
                @{
                    name         = 'Code'
                    relativePath = 'Code.exe'
                    required     = $true
                    exposed      = $true
                }
            )
            metadataFiles = @($validation.metadataFiles)
            signatures    = @($validation.signatures)
            fileDetails   = @($validation.fileDetails)
            registry      = @($validation.registryChecks)
        }
        stateDiscovery = @{
            installed = $installedDiscovery
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
        packageOperations = @{
            shared = @{
                ownershipPolicy = $ownershipPolicy
                compatibility   = $compatibility
            }
            assigned = $assigned
            removed = @{
                operation = @{
                    kind = 'none'
                }
                verifyAbsent = @{
                    use     = 'discovery'
                    require = @{
                        files         = $true
                        directories   = $false
                        commands      = $false
                        apps          = $false
                        metadataFiles = $false
                        signatures    = $false
                        fileDetails   = $false
                        registry      = $false
                    }
                }
                cleanup = @{
                    inventory       = $true
                    shims           = $true
                    path            = $true
                    workDirectories = $true
                }
            }
        }
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

