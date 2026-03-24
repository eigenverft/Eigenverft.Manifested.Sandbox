<#
    Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache
#>

function ConvertTo-NodeVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, 'v?(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-NodeFlavor {
    [CmdletBinding()]
    param()

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Only Windows hosts are supported by this Node runtime bootstrap.'
    }

    $archHints = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) -join ';'

    if ($archHints -match 'ARM64') {
        return 'win-arm64'
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return 'win-x64'
    }

    throw 'Only 64-bit Windows targets are supported by this Node runtime bootstrap.'
}

function Get-NodeRelease {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-NodeFlavor
    }

    $response = Invoke-WebRequestEx -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
    $items = $response.Content | ConvertFrom-Json

    $release = $items |
        Where-Object { $_.lts -and $_.lts -ne $false } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-NodeVersion -VersionText $_.version } } |
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
        $Flavor = Get-NodeFlavor
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
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-NodeVersion -VersionText $_.Version } }

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
        $Flavor = Get-NodeFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.NodeToolsRoot) {
        $versionRoots = Get-ChildItem -LiteralPath $layout.NodeToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-NodeVersion -VersionText ('v' + $_.Name) } }

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

    $versionObject = ConvertTo-NodeVersion -VersionText $reportedVersion
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
            $Flavor = Get-NodeFlavor
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
        $Flavor = Get-NodeFlavor
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
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-NodeFlavor }
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

function Initialize-NodeRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshNode
    )

    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $plannedActions = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $packageInfo = $null
    $packageTest = $null
    $installResult = $null
    $npmProxyConfiguration = $null
    $commandEnvironment = $null

    $initialState = Get-NodeRuntimeState -LocalRoot $LocalRoot
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-NodeRuntime' -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-NodeRuntime' -RuntimeState $state
        $result = [pscustomobject]@{
            LocalRoot       = $state.LocalRoot
            Layout          = $state.Layout
            InitialState    = $initialState
            FinalState      = $state
            ActionTaken     = @('None')
            PlannedActions  = @()
            RestartRequired = $false
            Package         = $null
            PackageTest     = $null
            RuntimeTest     = $null
            RepairResult    = $null
            InstallResult   = $null
            NpmProxyConfiguration = $null
            CommandEnvironment = $commandEnvironment
            Elevation       = $elevationPlan
        }

        if ($WhatIfPreference) {
            Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
            return $result
        }

        $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-NodeRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
            Version     = $state.CurrentVersion
            PackagePath = $state.PackagePath
            RuntimeHome = $state.RuntimeHome
            RuntimeSource = $state.RuntimeSource
            ExecutablePath = $state.ExecutablePath
        }
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force
        return $result
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $RefreshNode -or -not $state.RuntimeHome
    $needsAcquire = $RefreshNode -or (-not $state.PackagePath)

    if ($needsRepair) {
        $plannedActions.Add('Repair-NodeRuntime') | Out-Null
    }
    if ($needsInstall -and $needsAcquire) {
        $plannedActions.Add('Save-NodeRuntimePackage') | Out-Null
    }
    if ($needsInstall) {
        $plannedActions.Add('Test-NodeRuntimePackage') | Out-Null
        $plannedActions.Add('Install-NodeRuntime') | Out-Null
    }
    if ($needsInstall -or $state.RuntimeSource -eq 'Managed') {
        $plannedActions.Add('Sync-ManifestedNpmProxyConfiguration') | Out-Null
    }
    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null

    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-NodeRuntime' -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.NodeToolsRoot, 'Repair Node runtime state')) {
            return [pscustomobject]@{
                LocalRoot           = $state.LocalRoot
                Layout              = $state.Layout
                InitialState        = $initialState
                FinalState          = $state
                ActionTaken         = @('WhatIf')
                PlannedActions      = @($plannedActions)
                RestartRequired     = $false
                Package             = $null
                PackageTest         = $null
                RuntimeTest         = $state.Runtime
                RepairResult        = $null
                InstallResult       = $null
                NpmProxyConfiguration = $null
                CommandEnvironment  = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-NodeRuntime' -RuntimeState $state)
                PersistedStatePath  = $null
                Elevation           = $elevationPlan
            }
        }

        $repairResult = Repair-NodeRuntime -State $state -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add('Repair-NodeRuntime') | Out-Null
        }

        $state = Get-NodeRuntimeState -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        $needsInstall = $RefreshNode -or -not $state.RuntimeHome
        $needsAcquire = $RefreshNode -or (-not $state.PackagePath)
    }

    if ($needsInstall) {
        if ($needsAcquire) {
            if (-not $PSCmdlet.ShouldProcess($state.Layout.NodeCacheRoot, 'Acquire Node runtime package')) {
                return [pscustomobject]@{
                    LocalRoot          = $state.LocalRoot
                    Layout             = $state.Layout
                    InitialState       = $initialState
                    FinalState         = $state
                    ActionTaken        = @('WhatIf')
                    PlannedActions     = @($plannedActions)
                    RestartRequired    = $false
                    Package            = $null
                    PackageTest        = $null
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $repairResult
                    InstallResult      = $null
                    NpmProxyConfiguration = $null
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-NodeRuntime' -RuntimeState $state)
                    PersistedStatePath = $null
                    Elevation          = $elevationPlan
                }
            }

            $packageInfo = Save-NodeRuntimePackage -RefreshNode:$RefreshNode -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-NodeRuntimePackage') | Out-Null
            }
        }
        else {
            $packageInfo = $state.Package
        }

        $packageTest = Test-NodeRuntimePackage -PackageInfo $packageInfo
        if ($packageTest.Status -eq 'CorruptCache') {
            if (-not $PSCmdlet.ShouldProcess($packageInfo.Path, 'Repair corrupt Node runtime package')) {
                return [pscustomobject]@{
                    LocalRoot          = $state.LocalRoot
                    Layout             = $state.Layout
                    InitialState       = $initialState
                    FinalState         = $state
                    ActionTaken        = @('WhatIf')
                    PlannedActions     = @($plannedActions)
                    RestartRequired    = $false
                    Package            = $packageInfo
                    PackageTest        = $packageTest
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $repairResult
                    InstallResult      = $null
                    NpmProxyConfiguration = $null
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-NodeRuntime' -RuntimeState $state)
                    PersistedStatePath = $null
                    Elevation          = $elevationPlan
                }
            }

            $repairResult = Repair-NodeRuntime -State $state -CorruptPackagePaths @($packageInfo.Path) -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($repairResult.Action -eq 'Repaired') {
                $actionsTaken.Add('Repair-NodeRuntime') | Out-Null
            }

            $packageInfo = Save-NodeRuntimePackage -RefreshNode:$true -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-NodeRuntimePackage') | Out-Null
            }

            $packageTest = Test-NodeRuntimePackage -PackageInfo $packageInfo
        }

        if ($packageTest.Status -ne 'Ready') {
            throw "Node runtime package validation failed with status $($packageTest.Status)."
        }

        $commandParameters = @{}
        if ($RefreshNode) {
            $commandParameters['RefreshNode'] = $true
        }
        if ($PSBoundParameters.ContainsKey('WhatIf')) {
            $commandParameters['WhatIf'] = $true
        }

        $elevatedResult = Invoke-ManifestedElevatedCommand -ElevationPlan $elevationPlan -CommandName 'Initialize-NodeRuntime' -CommandParameters $commandParameters
        if ($null -ne $elevatedResult) {
            return $elevatedResult
        }

        if (-not $PSCmdlet.ShouldProcess($state.Layout.NodeToolsRoot, 'Install Node runtime')) {
            return [pscustomobject]@{
                LocalRoot          = $state.LocalRoot
                Layout             = $state.Layout
                InitialState       = $initialState
                FinalState         = $state
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                Package            = $packageInfo
                PackageTest        = $packageTest
                RuntimeTest        = $state.Runtime
                RepairResult       = $repairResult
                InstallResult      = $null
                NpmProxyConfiguration = $null
                CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-NodeRuntime' -RuntimeState $state)
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $installResult = Install-NodeRuntime -PackageInfo $packageInfo -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add('Install-NodeRuntime') | Out-Null
        }
    }

    $finalState = Get-NodeRuntimeState -Flavor $state.Flavor -LocalRoot $state.LocalRoot
    $runtimeTest = if ($finalState.RuntimeHome) {
        Test-NodeRuntime -NodeHome $finalState.RuntimeHome
    }
    else {
        [pscustomobject]@{
            Status   = 'Missing'
            IsReady  = $false
            NodeHome = $null
            NodeExe  = $null
            NpmCmd   = $null
        }
    }

    if ($finalState.RuntimeSource -eq 'Managed' -and $runtimeTest.IsReady -and -not [string]::IsNullOrWhiteSpace($runtimeTest.NpmCmd) -and (Test-Path -LiteralPath $runtimeTest.NpmCmd)) {
        $npmProxyConfiguration = Get-ManifestedNpmProxyConfigurationStatus -NpmCmd $runtimeTest.NpmCmd -LocalRoot $finalState.LocalRoot

        if ($npmProxyConfiguration.Action -eq 'NeedsManagedGlobalProxy') {
            if (-not $PSCmdlet.ShouldProcess($npmProxyConfiguration.GlobalConfigPath, 'Configure managed npm proxy settings')) {
                return [pscustomobject]@{
                    LocalRoot          = $finalState.LocalRoot
                    Layout             = $finalState.Layout
                    InitialState       = $initialState
                    FinalState         = $finalState
                    ActionTaken        = @('WhatIf')
                    PlannedActions     = @($plannedActions)
                    RestartRequired    = $false
                    Package            = $packageInfo
                    PackageTest        = $packageTest
                    RuntimeTest        = $runtimeTest
                    RepairResult       = $repairResult
                    InstallResult      = $installResult
                    NpmProxyConfiguration = $npmProxyConfiguration
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-NodeRuntime' -RuntimeState $finalState)
                    PersistedStatePath = $null
                    Elevation          = $elevationPlan
                }
            }

            $npmProxyConfiguration = Sync-ManifestedNpmProxyConfiguration -NpmCmd $runtimeTest.NpmCmd -Status $npmProxyConfiguration -LocalRoot $finalState.LocalRoot
            if ($npmProxyConfiguration.Action -eq 'ConfiguredManagedGlobalProxy') {
                $actionsTaken.Add('Sync-ManifestedNpmProxyConfiguration') | Out-Null
            }
        }
    }

    $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-NodeRuntime' -RuntimeState $finalState
    if ($commandEnvironment.Applicable) {
        if (-not $PSCmdlet.ShouldProcess($commandEnvironment.DesiredCommandDirectory, 'Synchronize Node command-line environment')) {
            return [pscustomobject]@{
                LocalRoot          = $finalState.LocalRoot
                Layout             = $finalState.Layout
                InitialState       = $initialState
                FinalState         = $finalState
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                Package            = $packageInfo
                PackageTest        = $packageTest
                RuntimeTest        = $runtimeTest
                RepairResult       = $repairResult
                InstallResult      = $installResult
                NpmProxyConfiguration = $npmProxyConfiguration
                CommandEnvironment = $commandEnvironment
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $commandEnvironment = Sync-ManifestedCommandLineEnvironment -Specification (Get-ManifestedCommandEnvironmentSpec -CommandName 'Initialize-NodeRuntime' -RuntimeState $finalState)
        if ($commandEnvironment.Status -eq 'Updated') {
            $actionsTaken.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
        }
    }

    $result = [pscustomobject]@{
        LocalRoot       = $finalState.LocalRoot
        Layout          = $finalState.Layout
        InitialState    = $initialState
        FinalState      = $finalState
        ActionTaken     = if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }
        PlannedActions  = @($plannedActions)
        RestartRequired = $false
        Package         = $packageInfo
        PackageTest     = $packageTest
        RuntimeTest     = $runtimeTest
        RepairResult    = $repairResult
        InstallResult   = $installResult
        NpmProxyConfiguration = $npmProxyConfiguration
        CommandEnvironment = $commandEnvironment
        Elevation       = $elevationPlan
    }

    if ($WhatIfPreference) {
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
        return $result
    }

    $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-NodeRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
        Version     = $finalState.CurrentVersion
        PackagePath = $finalState.PackagePath
        RuntimeHome = $finalState.RuntimeHome
        RuntimeSource = $finalState.RuntimeSource
        ExecutablePath = $finalState.ExecutablePath
    }
    Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force

    return $result
}
