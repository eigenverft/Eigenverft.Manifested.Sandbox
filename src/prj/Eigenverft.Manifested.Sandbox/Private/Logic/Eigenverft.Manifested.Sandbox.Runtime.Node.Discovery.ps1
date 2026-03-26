<#
    Eigenverft.Manifested.Sandbox.Runtime.Node.Discovery
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

