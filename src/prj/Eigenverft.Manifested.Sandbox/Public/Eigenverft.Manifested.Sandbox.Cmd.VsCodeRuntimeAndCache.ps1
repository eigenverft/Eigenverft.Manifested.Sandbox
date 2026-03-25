<#
    Eigenverft.Manifested.Sandbox.Cmd.VsCodeRuntimeAndCache
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

    $commandState = Get-ManifestedCommandState -CommandName 'Initialize-VSCodeRuntime' -LocalRoot $LocalRoot
    if ($commandState -and $commandState.PSObject.Properties['Details']) {
        return $commandState.Details
    }

    return $null
}

function ConvertTo-VSCodeSha256 {
    [CmdletBinding()]
    param(
        [string]$Sha256
    )

    if ([string]::IsNullOrWhiteSpace($Sha256)) {
        return $null
    }

    $normalized = $Sha256.Trim().ToLowerInvariant()
    if ($normalized -notmatch '^[a-f0-9]{64}$') {
        return $null
    }

    return $normalized
}

function Invoke-ManifestedVSCodeHeadRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    Enable-ManifestedTls12Support

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'Eigenverft.Manifested.Sandbox'

    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    if ($proxy) {
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $request.Proxy = $proxy
    }

    $response = $null
    try {
        try {
            $response = [System.Net.HttpWebResponse]$request.GetResponse()
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                $response = [System.Net.HttpWebResponse]$_.Exception.Response
            }
            else {
                throw
            }
        }

        [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Location   = $response.Headers['Location']
            Sha256     = ConvertTo-VSCodeSha256 -Sha256 $response.Headers['X-SHA256']
            Headers    = $response.Headers
        }
    }
    finally {
        if ($response) {
            $response.Close()
        }
    }
}

function Get-VSCodeRelease {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-VSCodeFlavor
    }

    $channel = 'stable'
    $latestUri = 'https://update.code.visualstudio.com/latest/{0}/{1}' -f (Get-VSCodeUpdateTarget -Flavor $Flavor), $channel
    $headResult = Invoke-ManifestedVSCodeHeadRequest -Uri $latestUri

    if ($headResult.StatusCode -notin @(301, 302, 303, 307, 308)) {
        throw "Unexpected VS Code update response status code $($headResult.StatusCode)."
    }
    if ([string]::IsNullOrWhiteSpace($headResult.Location)) {
        throw 'The VS Code update service did not return a redirect location.'
    }
    if ([string]::IsNullOrWhiteSpace($headResult.Sha256)) {
        throw 'The VS Code update service did not return an X-SHA256 header.'
    }

    $resolvedUri = [uri]$headResult.Location
    $fileName = Split-Path -Leaf $resolvedUri.AbsolutePath
    $match = [regex]::Match($fileName, '^(VSCode-(win32-(?:x64|arm64))-(\d+\.\d+\.\d+)\.zip)$')
    if (-not $match.Success) {
        throw "Could not parse the VS Code archive name '$fileName'."
    }
    if ($match.Groups[2].Value -ne $Flavor) {
        throw "The VS Code update service resolved flavor '$($match.Groups[2].Value)' instead of '$Flavor'."
    }

    [pscustomobject]@{
        TagName     = $channel
        Version     = $match.Groups[3].Value
        Flavor      = $Flavor
        Channel     = $channel
        FileName    = $match.Groups[1].Value
        Path        = $null
        Source      = 'online'
        Action      = 'SelectedOnline'
        DownloadUrl = $resolvedUri.AbsoluteUri
        Sha256      = $headResult.Sha256
        ShaSource   = 'X-SHA256'
        ReleaseUrl  = $latestUri
    }
}

function Get-CachedVSCodeRuntimePackages {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-VSCodeFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $layout.VsCodeCacheRoot)) {
        return @()
    }

    $persistedDetails = Get-VSCodePersistedPackageDetails -LocalRoot $layout.LocalRoot
    $pattern = '^VSCode-(' + [regex]::Escape($Flavor) + ')-(\d+\.\d+\.\d+)\.zip$'

    $items = Get-ChildItem -LiteralPath $layout.VsCodeCacheRoot -File -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            $sha256 = $null
            $downloadUrl = $null
            $shaSource = $null
            $channel = 'stable'

            if ($persistedDetails -and $persistedDetails.PSObject.Properties['AssetName'] -and $persistedDetails.AssetName -eq $_.Name) {
                $sha256 = if ($persistedDetails.PSObject.Properties['Sha256']) { $persistedDetails.Sha256 } else { $null }
                $downloadUrl = if ($persistedDetails.PSObject.Properties['DownloadUrl']) { $persistedDetails.DownloadUrl } else { $null }
                $shaSource = if ($persistedDetails.PSObject.Properties['ShaSource']) { $persistedDetails.ShaSource } else { $null }
                if ($persistedDetails.PSObject.Properties['Channel'] -and $persistedDetails.Channel) {
                    $channel = $persistedDetails.Channel
                }
            }

            [pscustomobject]@{
                TagName     = $channel
                Version     = $matches[2]
                Flavor      = $matches[1]
                Channel     = $channel
                FileName    = $_.Name
                Path        = $_.FullName
                Source      = 'cache'
                Action      = 'SelectedCache'
                DownloadUrl = $downloadUrl
                Sha256      = $sha256
                ShaSource   = $shaSource
                ReleaseUrl  = $null
            }
        } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-VSCodeVersion -VersionText $_.Version } }

    return @($items)
}

function Get-LatestCachedVSCodeRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $cachedPackages = @(Get-CachedVSCodeRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot)
    $trustedPackage = @($cachedPackages | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sha256) } | Select-Object -First 1)
    if ($trustedPackage) {
        return $trustedPackage[0]
    }

    return ($cachedPackages | Select-Object -First 1)
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
    return (Join-Path $layout.VsCodeToolsRoot ($Version + '\' + $Flavor))
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

function Test-VSCodeRuntimePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo
    )

    if (-not (Test-Path -LiteralPath $PackageInfo.Path)) {
        return [pscustomobject]@{
            Status       = 'Missing'
            TagName      = $PackageInfo.TagName
            Version      = $PackageInfo.Version
            Flavor       = $PackageInfo.Flavor
            Channel      = $PackageInfo.Channel
            FileName     = $PackageInfo.FileName
            Path         = $PackageInfo.Path
            Source       = $PackageInfo.Source
            Verified     = $false
            Verification = 'Missing'
            ExpectedHash = $null
            ActualHash   = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($PackageInfo.Sha256)) {
        return [pscustomobject]@{
            Status       = 'UnverifiedCache'
            TagName      = $PackageInfo.TagName
            Version      = $PackageInfo.Version
            Flavor       = $PackageInfo.Flavor
            Channel      = $PackageInfo.Channel
            FileName     = $PackageInfo.FileName
            Path         = $PackageInfo.Path
            Source       = $PackageInfo.Source
            Verified     = $false
            Verification = 'MissingTrustedHash'
            ExpectedHash = $null
            ActualHash   = $null
        }
    }

    $actualHash = (Get-FileHash -LiteralPath $PackageInfo.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = $PackageInfo.Sha256.ToLowerInvariant()

    [pscustomobject]@{
        Status       = if ($actualHash -eq $expectedHash) { 'Ready' } else { 'CorruptCache' }
        TagName      = $PackageInfo.TagName
        Version      = $PackageInfo.Version
        Flavor       = $PackageInfo.Flavor
        Channel      = $PackageInfo.Channel
        FileName     = $PackageInfo.FileName
        Path         = $PackageInfo.Path
        Source       = $PackageInfo.Source
        Verified     = $true
        Verification = if ($PackageInfo.ShaSource) { $PackageInfo.ShaSource } else { 'SHA256' }
        ExpectedHash = $expectedHash
        ActualHash   = $actualHash
    }
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

    $partialPaths = @()
    if (Test-Path -LiteralPath $layout.VsCodeCacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.VsCodeCacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'vscode' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledVSCodeRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemVSCodeRuntime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty RuntimeHome)
    $package = Get-LatestCachedVSCodeRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot

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
        Channel             = 'stable'
        CurrentVersion      = if ($currentRuntime) { $currentRuntime.Version } elseif ($package) { $package.Version } else { $null }
        RuntimeHome         = if ($currentRuntime) { $currentRuntime.RuntimeHome } else { $null }
        RuntimeSource       = $runtimeSource
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.CodePath } else { $null }
        CliCommandPath      = if ($currentRuntime) { $currentRuntime.CodeCmd } else { $null }
        PortableMode        = if ($currentRuntime) { [bool]$currentRuntime.Validation.PortableMode } else { $false }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

function Repair-VSCodeRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-VSCodeRuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
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

function Save-VSCodeRuntimePackage {
    [CmdletBinding()]
    param(
        [switch]$RefreshVSCode,
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-VSCodeFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.VsCodeCacheRoot | Out-Null

    $release = $null
    try {
        $release = Get-VSCodeRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    if ($release) {
        $packagePath = Join-Path $layout.VsCodeCacheRoot $release.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($RefreshVSCode -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                Write-Host "Downloading VS Code $($release.Version) ($Flavor)..."
                Enable-ManifestedTls12Support
                Invoke-WebRequestEx -Uri $release.DownloadUrl -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -OutFile $downloadPath -UseBasicParsing
                Move-Item -LiteralPath $downloadPath -Destination $packagePath -Force
                $action = 'Downloaded'
            }
            catch {
                Remove-ManifestedPath -Path $downloadPath | Out-Null
                if (-not (Test-Path -LiteralPath $packagePath)) {
                    throw
                }

                Write-Warning ('Could not refresh the VS Code package. Using cached copy. ' + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        return [pscustomobject]@{
            TagName     = $release.TagName
            Version     = $release.Version
            Flavor      = $Flavor
            Channel     = $release.Channel
            FileName    = $release.FileName
            Path        = $packagePath
            Source      = if ($action -eq 'Downloaded') { 'online' } else { 'cache' }
            Action      = $action
            DownloadUrl = $release.DownloadUrl
            Sha256      = $release.Sha256
            ShaSource   = $release.ShaSource
            ReleaseUrl  = $release.ReleaseUrl
        }
    }

    $cachedPackage = Get-LatestCachedVSCodeRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    if (-not $cachedPackage) {
        throw 'Could not reach the VS Code update service and no cached VS Code ZIP was found.'
    }

    return [pscustomobject]@{
        TagName     = $cachedPackage.TagName
        Version     = $cachedPackage.Version
        Flavor      = $cachedPackage.Flavor
        Channel     = $cachedPackage.Channel
        FileName    = $cachedPackage.FileName
        Path        = $cachedPackage.Path
        Source      = 'cache'
        Action      = 'SelectedCache'
        DownloadUrl = $cachedPackage.DownloadUrl
        Sha256      = $cachedPackage.Sha256
        ShaSource   = $cachedPackage.ShaSource
        ReleaseUrl  = $cachedPackage.ReleaseUrl
    }
}

function Install-VSCodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-VSCodeFlavor }
    }

    $runtimeHome = Get-ManagedVSCodeRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $currentValidation = Test-VSCodeRuntime -RuntimeHome $runtimeHome -RequirePortableMode

    if ($currentValidation.Status -ne 'Ready') {
        New-ManifestedDirectory -Path (Split-Path -Parent $runtimeHome) | Out-Null

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix 'vscode'

            if (Test-Path -LiteralPath $runtimeHome) {
                Remove-Item -LiteralPath $runtimeHome -Recurse -Force
            }

            New-ManifestedDirectory -Path $runtimeHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $runtimeHome -Force
            }

            New-ManifestedDirectory -Path (Join-Path $runtimeHome 'data') | Out-Null
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $validation = Test-VSCodeRuntime -RuntimeHome $runtimeHome -RequirePortableMode
    if ($validation.Status -ne 'Ready') {
        throw "VS Code runtime validation failed after install at $runtimeHome."
    }

    [pscustomobject]@{
        Action       = if ($currentValidation.Status -eq 'Ready') { 'Skipped' } else { 'Installed' }
        TagName      = $PackageInfo.TagName
        Version      = $PackageInfo.Version
        Flavor       = $Flavor
        Channel      = $PackageInfo.Channel
        RuntimeHome  = $runtimeHome
        CodePath     = $validation.CodePath
        CodeCmd      = $validation.CodeCmd
        PortableMode = $validation.PortableMode
        Source       = $PackageInfo.Source
        DownloadUrl  = $PackageInfo.DownloadUrl
        Sha256       = $PackageInfo.Sha256
    }
}

function Initialize-VSCodeRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshVSCode
    )

    return (Invoke-ManifestedGitHubPortableRuntimeInitialization -CommandName 'Initialize-VSCodeRuntime' -Refresh:$RefreshVSCode)

    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $plannedActions = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $packageInfo = $null
    $packageTest = $null
    $installResult = $null
    $commandEnvironment = $null

    $initialState = Get-VSCodeRuntimeState -LocalRoot $LocalRoot
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-VSCodeRuntime' -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-VSCodeRuntime' -RuntimeState $state
        $result = [pscustomobject]@{
            LocalRoot          = $state.LocalRoot
            Layout             = $state.Layout
            InitialState       = $initialState
            FinalState         = $state
            ActionTaken        = @('None')
            PlannedActions     = @()
            RestartRequired    = $false
            Package            = $null
            PackageTest        = $null
            RuntimeTest        = $null
            RepairResult       = $null
            InstallResult      = $null
            CommandEnvironment = $commandEnvironment
            Elevation          = $elevationPlan
        }

        if ($WhatIfPreference) {
            Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
            return $result
        }

        $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-VSCodeRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
            Version        = $state.CurrentVersion
            Flavor         = $state.Flavor
            Channel        = $state.Channel
            RuntimeHome    = $state.RuntimeHome
            RuntimeSource  = $state.RuntimeSource
            ExecutablePath = $state.ExecutablePath
            CliCommandPath = $state.CliCommandPath
            PortableMode   = $state.PortableMode
        }
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force
        return $result
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $RefreshVSCode -or -not $state.RuntimeHome
    $needsAcquire = $RefreshVSCode -or (-not $state.PackagePath)

    if ($needsRepair) {
        $plannedActions.Add('Repair-VSCodeRuntime') | Out-Null
    }
    if ($needsInstall -and $needsAcquire) {
        $plannedActions.Add('Save-VSCodeRuntimePackage') | Out-Null
    }
    if ($needsInstall) {
        $plannedActions.Add('Test-VSCodeRuntimePackage') | Out-Null
        $plannedActions.Add('Install-VSCodeRuntime') | Out-Null
    }
    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null

    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-VSCodeRuntime' -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.VsCodeToolsRoot, 'Repair VS Code runtime state')) {
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
                RepairResult       = $null
                InstallResult      = $null
                CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-VSCodeRuntime' -RuntimeState $state)
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $repairResult = Repair-VSCodeRuntime -State $state -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add('Repair-VSCodeRuntime') | Out-Null
        }

        $state = Get-VSCodeRuntimeState -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        $needsInstall = $RefreshVSCode -or -not $state.RuntimeHome
        $needsAcquire = $RefreshVSCode -or (-not $state.PackagePath)
    }

    if ($needsInstall) {
        if ($needsAcquire) {
            if (-not $PSCmdlet.ShouldProcess($state.Layout.VsCodeCacheRoot, 'Acquire VS Code runtime package')) {
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
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-VSCodeRuntime' -RuntimeState $state)
                    PersistedStatePath = $null
                    Elevation          = $elevationPlan
                }
            }

            $packageInfo = Save-VSCodeRuntimePackage -RefreshVSCode:$RefreshVSCode -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-VSCodeRuntimePackage') | Out-Null
            }
        }
        else {
            $packageInfo = $state.Package
        }

        $packageTest = Test-VSCodeRuntimePackage -PackageInfo $packageInfo
        if ($packageTest.Status -eq 'CorruptCache') {
            if (-not $PSCmdlet.ShouldProcess($packageInfo.Path, 'Repair corrupt VS Code runtime package')) {
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
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-VSCodeRuntime' -RuntimeState $state)
                    PersistedStatePath = $null
                    Elevation          = $elevationPlan
                }
            }

            $repairResult = Repair-VSCodeRuntime -State $state -CorruptPackagePaths @($packageInfo.Path) -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($repairResult.Action -eq 'Repaired') {
                $actionsTaken.Add('Repair-VSCodeRuntime') | Out-Null
            }

            $packageInfo = Save-VSCodeRuntimePackage -RefreshVSCode:$true -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-VSCodeRuntimePackage') | Out-Null
            }

            $packageTest = Test-VSCodeRuntimePackage -PackageInfo $packageInfo
        }

        if ($packageTest.Status -eq 'UnverifiedCache') {
            throw "VS Code runtime package validation failed because no trusted checksum could be resolved for $($packageInfo.FileName)."
        }

        if ($packageTest.Status -ne 'Ready') {
            throw "VS Code runtime package validation failed with status $($packageTest.Status)."
        }

        $commandParameters = @{}
        if ($RefreshVSCode) {
            $commandParameters['RefreshVSCode'] = $true
        }
        if ($PSBoundParameters.ContainsKey('WhatIf')) {
            $commandParameters['WhatIf'] = $true
        }

        $elevatedResult = Invoke-ManifestedElevatedCommand -ElevationPlan $elevationPlan -CommandName 'Initialize-VSCodeRuntime' -CommandParameters $commandParameters
        if ($null -ne $elevatedResult) {
            return $elevatedResult
        }

        if (-not $PSCmdlet.ShouldProcess($state.Layout.VsCodeToolsRoot, 'Install VS Code runtime')) {
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
                CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-VSCodeRuntime' -RuntimeState $state)
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $installResult = Install-VSCodeRuntime -PackageInfo $packageInfo -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add('Install-VSCodeRuntime') | Out-Null
        }
    }

    $finalState = Get-VSCodeRuntimeState -Flavor $state.Flavor -LocalRoot $state.LocalRoot
    $runtimeTest = if ($finalState.RuntimeHome) { Test-VSCodeRuntime -RuntimeHome $finalState.RuntimeHome -RequirePortableMode:($finalState.RuntimeSource -eq 'Managed') } else { $null }

    $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-VSCodeRuntime' -RuntimeState $finalState
    if ($commandEnvironment.Applicable) {
        if (-not $PSCmdlet.ShouldProcess($commandEnvironment.DesiredCommandDirectory, 'Synchronize VS Code command-line environment')) {
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
                CommandEnvironment = $commandEnvironment
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $commandEnvironment = Sync-ManifestedCommandLineEnvironment -Specification (Get-ManifestedCommandEnvironmentSpec -CommandName 'Initialize-VSCodeRuntime' -RuntimeState $finalState)
        if ($commandEnvironment.Status -eq 'Updated') {
            $actionsTaken.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
        }
    }

    $result = [pscustomobject]@{
        LocalRoot          = $finalState.LocalRoot
        Layout             = $finalState.Layout
        InitialState       = $initialState
        FinalState         = $finalState
        ActionTaken        = if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }
        PlannedActions     = @($plannedActions)
        RestartRequired    = $false
        Package            = $packageInfo
        PackageTest        = $packageTest
        RuntimeTest        = $runtimeTest
        RepairResult       = $repairResult
        InstallResult      = $installResult
        CommandEnvironment = $commandEnvironment
        Elevation          = $elevationPlan
    }

    if ($WhatIfPreference) {
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
        return $result
    }

    $detailsPackage = if ($packageInfo) { $packageInfo } elseif ($finalState.Package) { $finalState.Package } else { $null }
    $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-VSCodeRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
        Tag            = if ($detailsPackage) { $detailsPackage.TagName } else { $null }
        Version        = $finalState.CurrentVersion
        Flavor         = $finalState.Flavor
        Channel        = $finalState.Channel
        AssetName      = if ($detailsPackage) { $detailsPackage.FileName } else { $null }
        PackagePath    = if ($detailsPackage) { $detailsPackage.Path } else { $finalState.PackagePath }
        RuntimeHome    = $finalState.RuntimeHome
        RuntimeSource  = $finalState.RuntimeSource
        ExecutablePath = $finalState.ExecutablePath
        CliCommandPath = $finalState.CliCommandPath
        PortableMode   = $finalState.PortableMode
        DownloadUrl    = if ($detailsPackage) { $detailsPackage.DownloadUrl } else { $null }
        Sha256         = if ($detailsPackage) { $detailsPackage.Sha256 } else { $null }
        ShaSource      = if ($detailsPackage) { $detailsPackage.ShaSource } else { $null }
    }
    Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force

    return $result
}
