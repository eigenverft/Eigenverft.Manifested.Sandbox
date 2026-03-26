<#
    Eigenverft.Manifested.Sandbox.Runtime.VsCode.Discovery
#>

function ConvertTo-VSCodeVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-VSCodeFlavor {
    [CmdletBinding()]
    param()

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Only Windows hosts are supported by this VS Code runtime bootstrap.'
    }

    $archHints = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) -join ';'
    if ($archHints -match 'ARM64') {
        return 'win32-arm64'
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return 'win32-x64'
    }

    throw 'Only 64-bit Windows targets are supported by this VS Code runtime bootstrap.'
}

function Get-VSCodeUpdateTarget {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-VSCodeFlavor
    }

    switch ($Flavor) {
        'win32-x64' { return 'win32-x64-archive' }
        'win32-arm64' { return 'win32-arm64-archive' }
        default { throw "Unsupported VS Code flavor '$Flavor'." }
    }
}

function Get-VSCodePersistedPackageDetails {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-ManifestedArchivePersistedPackageDetails -CommandName 'Initialize-VSCodeRuntime' -LocalRoot $LocalRoot)
}

function Get-ManagedVSCodeRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Get-ManagedManifestedArchiveRuntimeHome -ToolsRootPath $layout.VsCodeToolsRoot -Version $Version -Flavor $Flavor)
}

function Test-VSCodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome,

        [switch]$RequirePortableMode
    )

    $codePath = Join-Path $RuntimeHome 'Code.exe'
    $codeCmd = Join-Path $RuntimeHome 'bin\code.cmd'
    $dataPath = Join-Path $RuntimeHome 'data'

    $reportedVersion = $null
    $productName = $null
    $fileDescription = $null
    $signatureStatus = $null
    $signerSubject = $null
    $isMicrosoftSigned = $false
    $portableMode = Test-Path -LiteralPath $dataPath

    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        $status = 'Missing'
    }
    elseif (-not (Test-Path -LiteralPath $codePath) -or -not (Test-Path -LiteralPath $codeCmd)) {
        $status = 'NeedsRepair'
    }
    else {
        try {
            $item = Get-Item -LiteralPath $codePath
            $productName = $item.VersionInfo.ProductName
            $fileDescription = $item.VersionInfo.FileDescription
        }
        catch {
            $productName = $null
            $fileDescription = $null
        }

        try {
            $signature = Get-AuthenticodeSignature -FilePath $codePath
            $signatureStatus = $signature.Status.ToString()
            $signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
            $isMicrosoftSigned = ($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid) -and ($signerSubject -match 'Microsoft Corporation')
        }
        catch {
            $signatureStatus = $null
            $signerSubject = $null
            $isMicrosoftSigned = $false
        }

        try {
            $reportedVersion = (& $codeCmd --version 2>$null | Select-Object -First 1)
            if (-not $reportedVersion) {
                $reportedVersion = (& $codePath --version 2>$null | Select-Object -First 1)
            }

            if ($reportedVersion) {
                $reportedVersion = $reportedVersion.ToString().Trim()
            }
        }
        catch {
            $reportedVersion = $null
        }

        $versionObject = ConvertTo-VSCodeVersion -VersionText $reportedVersion
        $isStableProduct = ($productName -eq 'Visual Studio Code') -or ($fileDescription -eq 'Visual Studio Code')
        $portableMode = Test-Path -LiteralPath $dataPath

        if ($RequirePortableMode -and -not $portableMode) {
            $status = 'NeedsRepair'
        }
        elseif (-not $versionObject -or -not $isMicrosoftSigned -or -not $isStableProduct) {
            $status = 'NeedsRepair'
        }
        else {
            $status = 'Ready'
        }
    }

    [pscustomobject]@{
        Status            = $status
        IsReady           = ($status -eq 'Ready')
        RuntimeHome       = $RuntimeHome
        CodePath          = $codePath
        CodeCmd           = $codeCmd
        DataPath          = $dataPath
        PortableMode      = $portableMode
        ReportedVersion   = $reportedVersion
        ProductName       = $productName
        FileDescription   = $fileDescription
        SignatureStatus   = $signatureStatus
        SignerSubject     = $signerSubject
        IsMicrosoftSigned = $isMicrosoftSigned
    }
}

function Get-InstalledVSCodeRuntime {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-VSCodeFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.VsCodeToolsRoot) {
        $versionRoots = Get-ChildItem -LiteralPath $layout.VsCodeToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-VSCodeVersion -VersionText $_.Name } }

        foreach ($versionRoot in $versionRoots) {
            $runtimeHome = Join-Path $versionRoot.FullName $Flavor
            if (-not (Test-Path -LiteralPath $runtimeHome)) {
                continue
            }

            $validation = Test-VSCodeRuntime -RuntimeHome $runtimeHome -RequirePortableMode
            $expectedVersion = ConvertTo-VSCodeVersion -VersionText $versionRoot.Name
            $reportedVersion = ConvertTo-VSCodeVersion -VersionText $validation.ReportedVersion
            $versionMatches = (-not $reportedVersion) -or (-not $expectedVersion) -or ($reportedVersion -eq $expectedVersion)

            $entries += [pscustomobject]@{
                Version        = $versionRoot.Name
                Flavor         = $Flavor
                RuntimeHome    = $runtimeHome
                CodePath       = $validation.CodePath
                CodeCmd        = $validation.CodeCmd
                Validation     = $validation
                VersionMatches = $versionMatches
                IsReady        = ($validation.IsReady -and $versionMatches)
            }
        }
    }

    [pscustomobject]@{
        Current = ($entries | Where-Object { $_.IsReady } | Select-Object -First 1)
        Valid   = @($entries | Where-Object { $_.IsReady })
        Invalid = @($entries | Where-Object { -not $_.IsReady })
    }
}

function Get-ManifestedVSCodeExternalPaths {
    [CmdletBinding()]
    param()

    $codePaths = New-Object System.Collections.Generic.List[string]
    $cliPaths = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $runtimeHome = Join-Path $env:ProgramFiles 'Microsoft VS Code'
        $codePaths.Add((Join-Path $runtimeHome 'Code.exe')) | Out-Null
        $cliPaths.Add((Join-Path $runtimeHome 'bin\code.cmd')) | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $runtimeHome = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code'
        $codePaths.Add((Join-Path $runtimeHome 'Code.exe')) | Out-Null
        $cliPaths.Add((Join-Path $runtimeHome 'bin\code.cmd')) | Out-Null
    }

    [pscustomobject]@{
        CodePaths = @($codePaths | Select-Object -Unique)
        CliPaths  = @($cliPaths | Select-Object -Unique)
    }
}

function Get-ManifestedVSCodeRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    $resolvedCandidatePath = Get-ManifestedFullPath -Path $CandidatePath
    if ([string]::IsNullOrWhiteSpace($resolvedCandidatePath) -or -not (Test-Path -LiteralPath $resolvedCandidatePath)) {
        return $null
    }

    $leafName = Split-Path -Leaf $resolvedCandidatePath
    $runtimeHome = $null
    if ($leafName -ieq 'Code.exe') {
        $runtimeHome = Split-Path -Parent $resolvedCandidatePath
    }
    elseif ($leafName -ieq 'code.cmd') {
        $runtimeHome = Split-Path (Split-Path -Parent $resolvedCandidatePath) -Parent
    }
    else {
        return $null
    }

    $validation = Test-VSCodeRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        return $null
    }

    $versionObject = ConvertTo-VSCodeVersion -VersionText $validation.ReportedVersion
    if (-not $versionObject) {
        return $null
    }

    [pscustomobject]@{
        Version     = $versionObject.ToString()
        Flavor      = $null
        RuntimeHome = $runtimeHome
        CodePath    = $validation.CodePath
        CodeCmd     = $validation.CodeCmd
        Validation  = $validation
        IsReady     = $true
        Source      = 'External'
        Discovery   = 'Path'
    }
}

function Get-SystemVSCodeRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $externalPaths = Get-ManifestedVSCodeExternalPaths
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    $codeCmdPath = Get-ManifestedApplicationPath -CommandName 'code.cmd' -ExcludedRoots @($layout.VsCodeToolsRoot) -AdditionalPaths $externalPaths.CliPaths
    if (-not [string]::IsNullOrWhiteSpace($codeCmdPath)) {
        $candidatePaths.Add($codeCmdPath) | Out-Null
    }

    $codePath = Get-ManifestedApplicationPath -CommandName 'code' -ExcludedRoots @($layout.VsCodeToolsRoot) -AdditionalPaths (@($externalPaths.CliPaths) + @($externalPaths.CodePaths))
    if (-not [string]::IsNullOrWhiteSpace($codePath)) {
        $candidatePaths.Add($codePath) | Out-Null
    }

    $codeExePath = Get-ManifestedApplicationPath -CommandName 'Code.exe' -ExcludedRoots @($layout.VsCodeToolsRoot) -AdditionalPaths $externalPaths.CodePaths
    if (-not [string]::IsNullOrWhiteSpace($codeExePath)) {
        $candidatePaths.Add($codeExePath) | Out-Null
    }

    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $runtime = Get-ManifestedVSCodeRuntimeFromCandidatePath -CandidatePath $candidatePath
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Get-VSCodeRuntimeState {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Flavor)) {
            $Flavor = Get-VSCodeFlavor
        }

        $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    }
    catch {
        return [pscustomobject]@{
            Status              = 'Blocked'
            LocalRoot           = $LocalRoot
            Layout              = $null
            Flavor              = $Flavor
            Channel             = 'stable'
            CurrentVersion      = $null
            RuntimeHome         = $null
            RuntimeSource       = $null
            ExecutablePath      = $null
            CliCommandPath      = $null
            PortableMode        = $false
            Runtime             = $null
            InvalidRuntimeHomes = @()
            Package             = $null
            PackagePath         = $null
            PartialPaths        = @()
            BlockedReason       = $_.Exception.Message
        }
    }

    $partialPaths = @(Get-ManifestedArchiveRuntimePartialPaths -CacheRootPath $layout.VsCodeCacheRoot -StagePrefix 'vscode' -LegacyRootPaths @($layout.ToolsRoot))

    $installed = Get-InstalledVSCodeRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemVSCodeRuntime -LocalRoot $layout.LocalRoot
    }

    $package = Get-LatestCachedVSCodeRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $runtimeSelection = Get-ManifestedArchiveRuntimeSelection -Installed $installed -ExternalRuntime $externalRuntime -Package $package -PartialPaths $partialPaths

    [pscustomobject]@{
        Status              = $runtimeSelection.Status
        LocalRoot           = $layout.LocalRoot
        Layout              = $layout
        Flavor              = $Flavor
        Channel             = 'stable'
        CurrentVersion      = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.Version } elseif ($package) { $package.Version } else { $null }
        RuntimeHome         = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.RuntimeHome } else { $null }
        RuntimeSource       = $runtimeSelection.RuntimeSource
        ExecutablePath      = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.CodePath } else { $null }
        CliCommandPath      = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.CodeCmd } else { $null }
        PortableMode        = if ($runtimeSelection.CurrentRuntime) { [bool]$runtimeSelection.CurrentRuntime.Validation.PortableMode } else { $false }
        Runtime             = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $runtimeSelection.InvalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

