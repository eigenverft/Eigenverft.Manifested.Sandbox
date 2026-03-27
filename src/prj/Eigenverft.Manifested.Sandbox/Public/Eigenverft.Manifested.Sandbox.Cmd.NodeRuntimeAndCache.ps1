<#
    Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache
#>

$script:ManifestedNodeRuntimeVersionSpec = Get-ManifestedVersionSpec -Definition (Get-ManifestedCommandDefinition -CommandName 'Initialize-NodeRuntime')

function Get-NodeRelease {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-NodeRuntime'
    }

    $response = Invoke-WebRequestEx -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
    $items = $response.Content | ConvertFrom-Json

    $release = $items |
        Where-Object { $_.lts -and $_.lts -ne $false } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedVersionObjectFromRule -VersionText $_.version -Rule $script:ManifestedNodeRuntimeVersionSpec.RuntimeVersionRule } } |
        Select-Object -First 1

    if (-not $release) {
        throw 'Unable to determine the latest Node.js LTS release.'
    }

    $fileName = 'node-{0}-{1}.zip' -f $release.version, $Flavor
    $baseUrl = 'https://nodejs.org/dist/{0}' -f $release.version

    [pscustomobject]@{
        Version     = $release.version
        Flavor      = $Flavor
        FileName    = $fileName
        Path        = $null
        Source      = 'online'
        Action      = 'SelectedOnline'
        NpmVersion  = $release.npm
        DownloadUrl = '{0}/{1}' -f $baseUrl, $fileName
        ShasumsUrl  = '{0}/SHASUMS256.txt' -f $baseUrl
    }
}

function Get-CachedNodeRuntimePackages {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-NodeRuntime'
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $layout.NodeCacheRoot)) {
        return @()
    }

    $pattern = '^node-(v\d+\.\d+\.\d+)-' + [regex]::Escape($Flavor) + '\.zip$'

    $items = Get-ChildItem -LiteralPath $layout.NodeCacheRoot -File -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            [pscustomobject]@{
                Version     = $matches[1]
                Flavor      = $Flavor
                FileName    = $_.Name
                Path        = $_.FullName
                Source      = 'cache'
                Action      = 'SelectedCache'
                NpmVersion  = $null
                DownloadUrl = $null
                ShasumsUrl  = $null
            }
        } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedVersionObjectFromRule -VersionText $_.Version -Rule $script:ManifestedNodeRuntimeVersionSpec.RuntimeVersionRule } }

    return @($items)
}

function Get-LatestCachedNodeRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-CachedNodeRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot | Select-Object -First 1)
}

function Get-ManagedNodeRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Join-Path $layout.NodeToolsRoot ($Version.TrimStart('v') + '\' + $Flavor))
}

function Test-NodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeHome
    )

    $nodeExe = Join-Path $NodeHome 'node.exe'
    $npmCmd = Join-Path $NodeHome 'npm.cmd'

    if (-not (Test-Path -LiteralPath $NodeHome)) {
        $status = 'Missing'
    }
    elseif ((Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $npmCmd)) {
        $status = 'Ready'
    }
    else {
        $status = 'NeedsRepair'
    }

    [pscustomobject]@{
        Status   = $status
        IsReady  = ($status -eq 'Ready')
        NodeHome = $NodeHome
        NodeExe  = $nodeExe
        NpmCmd   = $npmCmd
    }
}

function Get-InstalledNodeRuntime {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-NodeRuntime'
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.NodeToolsRoot) {
        $versionRoots = Get-ChildItem -LiteralPath $layout.NodeToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedVersionObjectFromRule -VersionText ('v' + $_.Name) -Rule $script:ManifestedNodeRuntimeVersionSpec.RuntimeVersionRule } }

        foreach ($versionRoot in $versionRoots) {
            $nodeHome = Join-Path $versionRoot.FullName $Flavor
            if (-not (Test-Path -LiteralPath $nodeHome)) {
                continue
            }

            $validation = Test-NodeRuntime -NodeHome $nodeHome
            $entries += [pscustomobject]@{
                Version    = ('v' + $versionRoot.Name)
                Flavor     = $Flavor
                NodeHome   = $nodeHome
                NodeExe    = $validation.NodeExe
                NpmCmd     = $validation.NpmCmd
                Validation = $validation
                IsReady    = $validation.IsReady
            }
        }
    }

    [pscustomobject]@{
        Current = ($entries | Where-Object { $_.IsReady } | Select-Object -First 1)
        Valid   = @($entries | Where-Object { $_.IsReady })
        Invalid = @($entries | Where-Object { -not $_.IsReady })
    }
}

function Get-SystemNodeRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $additionalPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $additionalPaths += (Join-Path $env:ProgramFiles 'nodejs\node.exe')
    }

    $nodeExe = Get-ManifestedApplicationPath -CommandName 'node.exe' -ExcludedRoots @($layout.NodeToolsRoot) -AdditionalPaths $additionalPaths
    if ([string]::IsNullOrWhiteSpace($nodeExe)) {
        return $null
    }

    $nodeHome = Split-Path -Parent $nodeExe
    $validation = Test-NodeRuntime -NodeHome $nodeHome
    if (-not $validation.IsReady) {
        return $null
    }

    $reportedVersion = $null
    try {
        $reportedVersion = (& $nodeExe --version 2>$null | Select-Object -First 1)
        if ($reportedVersion) {
            $reportedVersion = $reportedVersion.ToString().Trim()
        }
    }
    catch {
        $reportedVersion = $null
    }

    $versionObject = ConvertTo-ManifestedVersionObjectFromRule -VersionText $reportedVersion -Rule $script:ManifestedNodeRuntimeVersionSpec.RuntimeVersionRule
    if (-not $versionObject) {
        return $null
    }

    [pscustomobject]@{
        Version    = ('v' + $versionObject.ToString())
        Flavor     = $null
        NodeHome   = $nodeHome
        NodeExe    = $validation.NodeExe
        NpmCmd     = $validation.NpmCmd
        Validation = $validation
        IsReady    = $true
        Source     = 'External'
        Discovery  = 'Path'
    }
}

function Get-NodePackageExpectedSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShasumsUrl,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $response = Invoke-WebRequestEx -Uri $ShasumsUrl -UseBasicParsing
    $line = ($response.Content -split "`n" | Where-Object { $_ -match ('\s' + [regex]::Escape($FileName) + '$') } | Select-Object -First 1)

    if (-not $line) {
        throw "Could not find SHA256 for $FileName."
    }

    return (($line -split '\s+')[0]).Trim().ToLowerInvariant()
}

function Test-NodeRuntimePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo
    )

    if (-not (Test-Path -LiteralPath $PackageInfo.Path)) {
        return [pscustomobject]@{
            Status       = 'Missing'
            Version      = $PackageInfo.Version
            Flavor       = $PackageInfo.Flavor
            FileName     = $PackageInfo.FileName
            Path         = $PackageInfo.Path
            Source       = $PackageInfo.Source
            Verified     = $false
            Verification = 'Missing'
            ExpectedHash = $null
            ActualHash   = $null
        }
    }

    $status = 'Ready'
    $verified = $false
    $verification = 'OfflineCache'
    $expectedHash = $null
    $actualHash = $null

    if ($PackageInfo.ShasumsUrl) {
        $expectedHash = Get-NodePackageExpectedSha256 -ShasumsUrl $PackageInfo.ShasumsUrl -FileName $PackageInfo.FileName
        $actualHash = (Get-FileHash -LiteralPath $PackageInfo.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        $verified = $true
        $verification = 'SHA256'
        if ($actualHash -ne $expectedHash) {
            $status = 'CorruptCache'
        }
    }

    [pscustomobject]@{
        Status       = $status
        Version      = $PackageInfo.Version
        Flavor       = $PackageInfo.Flavor
        FileName     = $PackageInfo.FileName
        Path         = $PackageInfo.Path
        Source       = $PackageInfo.Source
        Verified     = $verified
        Verification = $verification
        ExpectedHash = $expectedHash
        ActualHash   = $actualHash
    }
}

function Get-NodeRuntimeState {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Flavor)) {
            $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-NodeRuntime'
        }

        $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    }
    catch {
        return [pscustomobject]@{
            Status              = 'Blocked'
            LocalRoot           = $LocalRoot
            Layout              = $null
            Flavor              = $Flavor
            CurrentVersion      = $null
            RuntimeHome         = $null
            RuntimeSource       = $null
            ExecutablePath      = $null
            Runtime             = $null
            InvalidRuntimeHomes = @()
            Package             = $null
            PackagePath         = $null
            PartialPaths        = @()
            BlockedReason       = $_.Exception.Message
        }
    }

    $partialPaths = @()
    if (Test-Path -LiteralPath $layout.NodeCacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.NodeCacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'node' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledNodeRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemNodeRuntime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty NodeHome)
    $package = Get-LatestCachedNodeRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot

    if ($invalidRuntimeHomes.Count -gt 0) {
        $status = 'NeedsRepair'
    }
    elseif ($partialPaths.Count -gt 0) {
        $status = 'Partial'
    }
    elseif ($currentRuntime) {
        $status = 'Ready'
    }
    elseif ($package) {
        $status = 'NeedsInstall'
    }
    else {
        $status = 'Missing'
    }

    [pscustomobject]@{
        Status              = $status
        LocalRoot           = $layout.LocalRoot
        Layout              = $layout
        Flavor              = $Flavor
        CurrentVersion      = if ($currentRuntime) { $currentRuntime.Version } elseif ($package) { $package.Version } else { $null }
        RuntimeHome         = if ($currentRuntime) { $currentRuntime.NodeHome } else { $null }
        RuntimeSource       = $runtimeSource
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.NodeExe } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

function Repair-NodeRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-NodeRuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
    }

    $pathsToRemove = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($State.PartialPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($State.InvalidRuntimeHomes)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($CorruptPackagePaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }

    $removedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in ($pathsToRemove | Select-Object -Unique)) {
        if (Remove-ManifestedPath -Path $path) {
            $removedPaths.Add($path) | Out-Null
        }
    }

    [pscustomobject]@{
        Action       = if ($removedPaths.Count -gt 0) { 'Repaired' } else { 'Skipped' }
        RemovedPaths = @($removedPaths)
        LocalRoot    = $State.LocalRoot
        Layout       = $State.Layout
    }
}

function Save-NodeRuntimePackage {
    [CmdletBinding()]
    param(
        [switch]$RefreshNode,
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-NodeRuntime'
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.NodeCacheRoot | Out-Null

    $release = $null
    try {
        $release = Get-NodeRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    if ($release) {
        $packagePath = Join-Path $layout.NodeCacheRoot $release.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($RefreshNode -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                Write-Host "Downloading Node.js $($release.Version) ($Flavor)..."
                Invoke-WebRequestEx -Uri $release.DownloadUrl -OutFile $downloadPath -UseBasicParsing
                Move-Item -LiteralPath $downloadPath -Destination $packagePath -Force
                $action = 'Downloaded'
            }
            catch {
                Remove-ManifestedPath -Path $downloadPath | Out-Null
                if (-not (Test-Path -LiteralPath $packagePath)) {
                    throw
                }

                Write-Warning ('Could not refresh the Node.js package. Using cached copy. ' + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        return [pscustomobject]@{
            Version     = $release.Version
            Flavor      = $Flavor
            FileName    = $release.FileName
            Path        = $packagePath
            Source      = if ($action -eq 'Downloaded') { 'online' } else { 'cache' }
            Action      = $action
            NpmVersion  = $release.NpmVersion
            DownloadUrl = $release.DownloadUrl
            ShasumsUrl  = $release.ShasumsUrl
        }
    }

    $cachedPackage = Get-LatestCachedNodeRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    if (-not $cachedPackage) {
        throw 'Could not reach nodejs.org and no cached Node.js ZIP was found.'
    }

    return [pscustomobject]@{
        Version     = $cachedPackage.Version
        Flavor      = $cachedPackage.Flavor
        FileName    = $cachedPackage.FileName
        Path        = $cachedPackage.Path
        Source      = 'cache'
        Action      = 'SelectedCache'
        NpmVersion  = $null
        DownloadUrl = $null
        ShasumsUrl  = $null
    }
}

function Install-NodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-ManifestedCommandFlavor -CommandName 'Initialize-NodeRuntime' }
    }

    $nodeHome = Get-ManagedNodeRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $currentValidation = Test-NodeRuntime -NodeHome $nodeHome

    if ($currentValidation.Status -ne 'Ready') {
        New-ManifestedDirectory -Path (Split-Path -Parent $nodeHome) | Out-Null

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix 'node'
            if (-not (Test-Path -LiteralPath $stageInfo.ExpandedRoot)) {
                throw 'The Node.js ZIP did not extract as expected.'
            }

            if (Test-Path -LiteralPath $nodeHome) {
                Remove-Item -LiteralPath $nodeHome -Recurse -Force
            }

            New-ManifestedDirectory -Path $nodeHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $nodeHome -Force
            }
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $validation = Test-NodeRuntime -NodeHome $nodeHome
    if ($validation.Status -ne 'Ready') {
        throw "Node runtime validation failed after install at $nodeHome."
    }

    [pscustomobject]@{
        Action     = if ($currentValidation.Status -eq 'Ready') { 'Skipped' } else { 'Installed' }
        Version    = $PackageInfo.Version
        Flavor     = $Flavor
        NodeHome   = $nodeHome
        NodeExe    = $validation.NodeExe
        NpmCmd     = $validation.NpmCmd
        Source     = $PackageInfo.Source
        NpmVersion = $PackageInfo.NpmVersion
    }
}

function Get-NodeRuntimeFacts {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = $null
    try {
        if ([string]::IsNullOrWhiteSpace($Flavor)) {
            $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-NodeRuntime'
        }

        $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    }
    catch {
        return (New-ManifestedRuntimeFacts -RuntimeName 'NodeRuntime' -CommandName 'Initialize-NodeRuntime' -RuntimeKind 'PortablePackage' -LocalRoot $LocalRoot -Layout $layout -PlatformSupported:$false -BlockedReason $_.Exception.Message -AdditionalProperties @{
            Flavor              = $Flavor
            Package             = $null
            PackagePath         = $null
            InvalidRuntimeHomes = @()
        })
    }

    $partialPaths = @()
    if (Test-Path -LiteralPath $layout.NodeCacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.NodeCacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'node' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledNodeRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemNodeRuntime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $package = Get-LatestCachedNodeRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty NodeHome)

    $currentVersion = $null
    if ($currentRuntime) {
        $currentVersion = $currentRuntime.Version
    }
    elseif ($package) {
        $currentVersion = $package.Version
    }

    $runtimeHome = $null
    $runtimeSource = $null
    $executablePath = $null
    $runtimeValidation = $null
    if ($currentRuntime) {
        $runtimeHome = $currentRuntime.NodeHome
        $executablePath = $currentRuntime.NodeExe
        $runtimeValidation = $currentRuntime.Validation
    }
    if ($managedRuntime) {
        $runtimeSource = 'Managed'
    }
    elseif ($externalRuntime) {
        $runtimeSource = 'External'
    }

    return (New-ManifestedRuntimeFacts -RuntimeName 'NodeRuntime' -CommandName 'Initialize-NodeRuntime' -RuntimeKind 'PortablePackage' -LocalRoot $layout.LocalRoot -Layout $layout -ManagedRuntime $managedRuntime -ExternalRuntime $externalRuntime -Artifact $package -PartialPaths $partialPaths -InvalidPaths $invalidRuntimeHomes -Version $currentVersion -RuntimeHome $runtimeHome -RuntimeSource $runtimeSource -ExecutablePath $executablePath -RuntimeValidation $runtimeValidation -AdditionalProperties @{
        Flavor              = $Flavor
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
    })
}

function Initialize-NodeRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshNode
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-NodeRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshNode -WhatIfMode:$WhatIfPreference)
}
