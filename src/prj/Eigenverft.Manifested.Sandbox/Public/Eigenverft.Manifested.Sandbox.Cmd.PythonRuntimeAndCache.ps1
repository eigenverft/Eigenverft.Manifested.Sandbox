<#
    Eigenverft.Manifested.Sandbox.Cmd.PythonRuntimeAndCache
#>

function ConvertTo-PythonVersion {
<#
.SYNOPSIS
Normalizes Python version text into a comparable version object.

.DESCRIPTION
Extracts the first `major.minor.patch` fragment from arbitrary Python version
text and converts it into a `[version]` instance so runtime release checks can
compare versions consistently.

.PARAMETER VersionText
Raw version text emitted by Python tooling or release metadata.

.EXAMPLE
ConvertTo-PythonVersion -VersionText 'Python 3.13.2'

.EXAMPLE
ConvertTo-PythonVersion -VersionText '3.13.2rc1'

.NOTES
Returns `$null` when no semantic version fragment can be found.
#>
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

function Get-PythonManagedBaselineVersion {
    [CmdletBinding()]
    param()

    return [version]'3.13.0'
}

function Test-PythonManagedReleaseVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [version]$Version
    )

    $baseline = Get-PythonManagedBaselineVersion
    return ($Version.Major -eq $baseline.Major) -and ($Version.Minor -eq $baseline.Minor) -and ($Version -ge $baseline)
}

function Test-PythonExternalRuntimeVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [version]$Version
    )

    $baseline = Get-PythonManagedBaselineVersion
    return ($Version.Major -gt $baseline.Major) -or (($Version.Major -eq $baseline.Major) -and ($Version.Minor -ge $baseline.Minor))
}

function Get-PythonFlavor {
    [CmdletBinding()]
    param()

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Only Windows hosts are supported by this Python runtime bootstrap.'
    }

    $archHints = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) -join ';'
    if ($archHints -match 'ARM64') {
        return 'arm64'
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return 'amd64'
    }

    throw 'Only 64-bit Windows targets are supported by this Python runtime bootstrap.'
}

function Get-PythonReleaseDescriptionForFlavor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Flavor
    )

    switch ($Flavor) {
        'amd64' { return 'Windows embeddable package (64-bit)' }
        'arm64' { return 'Windows embeddable package (ARM64)' }
        default { throw "Unsupported Python flavor '$Flavor'." }
    }
}

function Get-PythonPersistedPackageDetails {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $commandState = Get-ManifestedCommandState -CommandName 'Initialize-PythonRuntime' -LocalRoot $LocalRoot
    if ($commandState -and $commandState.PSObject.Properties['Details']) {
        return $commandState.Details
    }

    return $null
}

function Get-PythonReleaseCandidates {
    [CmdletBinding()]
    param()

    $response = Invoke-WebRequestEx -Uri 'https://www.python.org/downloads/windows/' -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -UseBasicParsing
    $matches = [regex]::Matches($response.Content, '(?is)<a href="/downloads/release/python-(?<slug>313\d+)/">Python (?<version>3\.13\.\d+) - (?<releaseDate>[^<]+)</a>')
    $items = New-Object System.Collections.Generic.List[object]
    $seenVersions = @{}

    foreach ($match in $matches) {
        $versionText = $match.Groups['version'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($versionText) -or $seenVersions.ContainsKey($versionText)) {
            continue
        }

        $versionObject = ConvertTo-PythonVersion -VersionText $versionText
        if (-not $versionObject -or -not (Test-PythonManagedReleaseVersion -Version $versionObject)) {
            continue
        }

        $seenVersions[$versionText] = $true
        $items.Add([pscustomobject]@{
            ReleaseId   = $match.Groups['slug'].Value.Trim()
            Version     = $versionText
            ReleaseDate = $match.Groups['releaseDate'].Value.Trim()
            ReleaseUrl  = ('https://www.python.org/downloads/release/python-{0}/' -f $match.Groups['slug'].Value.Trim())
        }) | Out-Null
    }

    return @($items | Sort-Object -Descending -Property @{ Expression = { ConvertTo-PythonVersion -VersionText $_.Version } })
}

function Get-PythonReleaseAssetDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReleaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$Flavor
    )

    $descriptionPattern = switch ($Flavor) {
        'amd64' { 'Windows\s+embeddable\s+package\s+\(64-bit\)' }
        'arm64' { 'Windows\s+embeddable\s+package\s+\(ARM64\)' }
        default { throw "Unsupported Python flavor '$Flavor'." }
    }

    $response = Invoke-WebRequestEx -Uri $ReleaseUrl -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -UseBasicParsing
    $pattern = '(?is)<tr>\s*<td><a href="(?<url>[^"]+)">' + $descriptionPattern + '</a>.*?<td><code class="checksum">(?<checksumHtml>.*?)</code></td>\s*</tr>'
    $match = [regex]::Match($response.Content, $pattern)
    if (-not $match.Success) {
        throw "Could not find the Python embeddable package row for flavor '$Flavor' in $ReleaseUrl."
    }

    $downloadUrl = $match.Groups['url'].Value.Trim()
    $checksumText = ($match.Groups['checksumHtml'].Value -replace '<[^>]+>', '')
    $checksum = ($checksumText -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
    if ($checksum.Length -ne 64) {
        throw "Could not resolve a trusted SHA256 checksum for '$downloadUrl'."
    }

    [pscustomobject]@{
        DownloadUrl = $downloadUrl
        FileName    = [System.IO.Path]::GetFileName(([uri]$downloadUrl).AbsolutePath)
        Sha256      = $checksum
        ShaSource   = 'ReleaseHtml'
    }
}

function Get-PythonRelease {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-PythonFlavor
    }

    foreach ($candidate in @(Get-PythonReleaseCandidates)) {
        try {
            $assetDetails = Get-PythonReleaseAssetDetails -ReleaseUrl $candidate.ReleaseUrl -Flavor $Flavor
            return [pscustomobject]@{
                ReleaseId   = $candidate.ReleaseId
                Version     = $candidate.Version
                Flavor      = $Flavor
                FileName    = $assetDetails.FileName
                Path        = $null
                Source      = 'online'
                Action      = 'SelectedOnline'
                DownloadUrl = $assetDetails.DownloadUrl
                Sha256      = $assetDetails.Sha256
                ShaSource   = $assetDetails.ShaSource
                ReleaseUrl  = $candidate.ReleaseUrl
                ReleaseDate = $candidate.ReleaseDate
            }
        }
        catch {
            continue
        }
    }

    throw 'Unable to determine the latest stable Python 3.13 embeddable release.'
}

function Get-CachedPythonRuntimePackages {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-PythonFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $layout.PythonCacheRoot)) {
        return @()
    }

    $persistedDetails = Get-PythonPersistedPackageDetails -LocalRoot $layout.LocalRoot
    $pattern = '^python-(\d+\.\d+\.\d+)-embed-' + [regex]::Escape($Flavor) + '\.zip$'

    $items = Get-ChildItem -LiteralPath $layout.PythonCacheRoot -File -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            $sha256 = $null
            $downloadUrl = $null
            $shaSource = $null
            $releaseUrl = $null
            $releaseId = $null

            if ($persistedDetails -and $persistedDetails.PSObject.Properties['AssetName'] -and $persistedDetails.AssetName -eq $_.Name) {
                $sha256 = if ($persistedDetails.PSObject.Properties['Sha256']) { $persistedDetails.Sha256 } else { $null }
                $downloadUrl = if ($persistedDetails.PSObject.Properties['DownloadUrl']) { $persistedDetails.DownloadUrl } else { $null }
                $shaSource = if ($persistedDetails.PSObject.Properties['ShaSource']) { $persistedDetails.ShaSource } else { $null }
                $releaseUrl = if ($persistedDetails.PSObject.Properties['ReleaseUrl']) { $persistedDetails.ReleaseUrl } else { $null }
                $releaseId = if ($persistedDetails.PSObject.Properties['ReleaseId']) { $persistedDetails.ReleaseId } else { $null }
            }

            [pscustomobject]@{
                ReleaseId   = $releaseId
                Version     = $matches[1]
                Flavor      = $Flavor
                FileName    = $_.Name
                Path        = $_.FullName
                Source      = 'cache'
                Action      = 'SelectedCache'
                DownloadUrl = $downloadUrl
                Sha256      = $sha256
                ShaSource   = $shaSource
                ReleaseUrl  = $releaseUrl
                ReleaseDate = $null
            }
        } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-PythonVersion -VersionText $_.Version } }

    return @($items)
}

function Get-LatestCachedPythonRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $cachedPackages = @(Get-CachedPythonRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot)
    $trustedPackage = @($cachedPackages | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sha256) } | Select-Object -First 1)
    if ($trustedPackage) {
        return $trustedPackage[0]
    }

    return ($cachedPackages | Select-Object -First 1)
}

function Get-ManagedPythonRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Join-Path $layout.PythonToolsRoot ($Version + '\' + $Flavor))
}

function Get-PythonRuntimePthPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    if (-not (Test-Path -LiteralPath $PythonHome)) {
        return $null
    }

    $pthFile = @(Get-ChildItem -LiteralPath $PythonHome -File -Filter 'python*._pth' -ErrorAction SilentlyContinue | Sort-Object -Property Name | Select-Object -First 1)
    if (-not $pthFile) {
        return $null
    }

    return $pthFile[0].FullName
}

function Test-PythonSiteImportsEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    $pthPath = Get-PythonRuntimePthPath -PythonHome $PythonHome
    if ([string]::IsNullOrWhiteSpace($pthPath) -or -not (Test-Path -LiteralPath $pthPath)) {
        return [pscustomobject]@{
            Exists                 = $false
            PthPath                = $pthPath
            ImportSiteEnabled      = $false
            SitePackagesPathListed = $false
            IsReady                = $false
        }
    }

    $lines = @(Get-Content -LiteralPath $pthPath -ErrorAction SilentlyContinue)
    $importSiteEnabled = $false
    $sitePackagesPathListed = $false

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq 'import site') {
            $importSiteEnabled = $true
        }
        elseif ($trimmedLine -ieq 'Lib\site-packages') {
            $sitePackagesPathListed = $true
        }
    }

    [pscustomobject]@{
        Exists                 = $true
        PthPath                = $pthPath
        ImportSiteEnabled      = $importSiteEnabled
        SitePackagesPathListed = $sitePackagesPathListed
        IsReady                = ($importSiteEnabled -and $sitePackagesPathListed)
    }
}

function Enable-PythonSiteImports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    $pthState = Test-PythonSiteImportsEnabled -PythonHome $PythonHome
    if (-not $pthState.Exists) {
        throw "Could not find the Python runtime ._pth file under $PythonHome."
    }

    $sitePackagesRoot = Join-Path $PythonHome 'Lib\site-packages'
    New-ManifestedDirectory -Path $sitePackagesRoot | Out-Null

    $lines = @(Get-Content -LiteralPath $pthState.PthPath -ErrorAction Stop)
    $updatedLines = New-Object System.Collections.Generic.List[string]
    $hasImportSite = $false
    $hasSitePackages = $false

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()

        if ($trimmedLine -match '^(#\s*)?import\s+site$') {
            if (-not $hasImportSite) {
                $updatedLines.Add('import site') | Out-Null
                $hasImportSite = $true
            }

            continue
        }

        if ($trimmedLine -ieq 'Lib\site-packages') {
            if (-not $hasSitePackages) {
                $updatedLines.Add('Lib\site-packages') | Out-Null
                $hasSitePackages = $true
            }

            continue
        }

        $updatedLines.Add($line) | Out-Null
    }

    if (-not $hasSitePackages) {
        $updatedLines.Add('Lib\site-packages') | Out-Null
    }
    if (-not $hasImportSite) {
        $updatedLines.Add('import site') | Out-Null
    }

    Set-Content -LiteralPath $pthState.PthPath -Value @($updatedLines) -Encoding ASCII
    return (Test-PythonSiteImportsEnabled -PythonHome $PythonHome)
}

function Get-PythonReportedVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $probe = Get-PythonReportedVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    return $probe.ReportedVersion
}

function Get-PythonReportedVersionProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not (Test-Path -LiteralPath $PythonExe)) {
        return [pscustomobject]@{
            ReportedVersion = $null
            CommandResult   = $null
        }
    }

    $commandResult = Invoke-ManifestedPythonCommand -PythonExe $PythonExe -Arguments @('-c', 'import sys; print(*sys.version_info[:3], sep=chr(46))') -LocalRoot $LocalRoot
    $reportedVersion = $null
    if ($commandResult.ExitCode -eq 0) {
        $versionLine = @($commandResult.OutputLines | Select-Object -First 1)
        if ($versionLine) {
            $reportedVersion = $versionLine[0].ToString().Trim()
        }
    }

    return [pscustomobject]@{
        ReportedVersion = $reportedVersion
        CommandResult   = $commandResult
    }
}

function Get-PythonPipVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $probe = Get-PythonPipVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    return $probe.PipVersion
}

function Get-PythonPipVersionProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not (Test-Path -LiteralPath $PythonExe)) {
        return [pscustomobject]@{
            PipVersion    = $null
            CommandResult = $null
        }
    }

    $commandResult = Invoke-ManifestedPipAwarePythonCommand -PythonExe $PythonExe -Arguments @('-m', 'pip', '--version') -LocalRoot $LocalRoot
    $pipVersion = $null
    if ($commandResult.ExitCode -eq 0) {
        $versionLine = @($commandResult.OutputLines | Select-Object -First 1)
        if ($versionLine) {
            $pipVersion = $versionLine[0].ToString().Trim()
        }
    }

    return [pscustomobject]@{
        PipVersion    = $pipVersion
        CommandResult = $commandResult
    }
}

function Test-PythonRuntimePackageHasTrustedHash {
    [CmdletBinding()]
    param(
        [pscustomobject]$PackageInfo
    )

    return ($PackageInfo -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Sha256))
}

function Get-PythonCommandFailureHint {
    [CmdletBinding()]
    param(
        [pscustomobject]$CommandResult,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $CommandResult) {
        return $null
    }

    $combinedText = @(
        $CommandResult.ExceptionMessage
        $CommandResult.OutputText
    ) -join [Environment]::NewLine

    if ($combinedText -match 'No module named encodings|init_fs_encoding') {
        return 'The Python process started with an invalid import-path configuration. The managed runtime now clears PYTHONHOME and PYTHONPATH automatically; if this persists, repair the managed runtime cache and retry.'
    }

    return $null
}

function New-PythonRuntimePackageTrustFailureMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$MetadataRefreshError
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("Python runtime package verification could not establish a trusted SHA256 for cached package '{0}'." -f $PackageInfo.FileName)) | Out-Null
    $lines.Add(("Cached path: {0}" -f $PackageInfo.Path)) | Out-Null

    if ($PackageInfo.PSObject.Properties['Version'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Version)) {
        $lines.Add(("Cached version: {0}" -f $PackageInfo.Version)) | Out-Null
    }
    if ($PackageInfo.PSObject.Properties['Flavor'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Flavor)) {
        $lines.Add(("Cached flavor: {0}" -f $PackageInfo.Flavor)) | Out-Null
    }
    if ($PackageInfo.PSObject.Properties['Source'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Source)) {
        $lines.Add(("Package source: {0}" -f $PackageInfo.Source)) | Out-Null
    }

    $lines.Add('The cached ZIP is present, but this run does not have trusted release metadata attached to verify it.') | Out-Null
    $lines.Add('This usually happens when an earlier Python bootstrap downloaded the ZIP but failed before package metadata was persisted.') | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($MetadataRefreshError)) {
        $lines.Add(("Metadata refresh attempt failed: {0}" -f $MetadataRefreshError)) | Out-Null
    }
    else {
        $lines.Add('A metadata refresh attempt did not produce a trusted checksum for the cached ZIP.') | Out-Null
    }

    $lines.Add('Retry with normal network access so python.org release metadata can be resolved, or use Initialize-PythonRuntime -RefreshPython to reacquire the package.') | Out-Null
    return (@($lines) -join [Environment]::NewLine)
}

function New-PythonRuntimeValidationFailureMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [string]$ExpectedVersion,

        [string]$ReportedVersion,

        [pscustomobject]$CommandResult,

        [pscustomobject]$SiteImportsState,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("Python runtime validation failed during {0} at {1}." -f $Operation, $PythonHome)) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
        $lines.Add(("Expected version: {0}." -f $ExpectedVersion)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($ReportedVersion)) {
        $lines.Add(("Reported version: {0}." -f $ReportedVersion)) | Out-Null
    }
    if ($CommandResult -and $null -ne $CommandResult.ExitCode) {
        $lines.Add(("python.exe exit code: {0}." -f $CommandResult.ExitCode)) | Out-Null
    }
    if ($CommandResult -and -not [string]::IsNullOrWhiteSpace($CommandResult.ExceptionMessage)) {
        $lines.Add(("Startup error: {0}" -f $CommandResult.ExceptionMessage)) | Out-Null
    }
    if ($CommandResult -and -not [string]::IsNullOrWhiteSpace($CommandResult.OutputText)) {
        $lines.Add(("python.exe output:{0}{1}" -f [Environment]::NewLine, $CommandResult.OutputText)) | Out-Null
    }
    if ($SiteImportsState) {
        $lines.Add(("Site imports: import site={0}; Lib\\site-packages listed={1}; pth={2}." -f $SiteImportsState.ImportSiteEnabled, $SiteImportsState.SitePackagesPathListed, $SiteImportsState.PthPath)) | Out-Null
    }
    if ($CommandResult -and $CommandResult.IsManagedPython -and @($CommandResult.SanitizedVariables).Count -gt 0) {
        $lines.Add(("Managed runtime startup cleared: {0}." -f (@($CommandResult.SanitizedVariables) -join ', '))) | Out-Null
    }

    $hint = Get-PythonCommandFailureHint -CommandResult $CommandResult -LocalRoot $LocalRoot
    if (-not [string]::IsNullOrWhiteSpace($hint)) {
        $lines.Add($hint) | Out-Null
    }

    return (@($lines) -join [Environment]::NewLine)
}

function Test-PythonRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $pythonExe = Join-Path $PythonHome 'python.exe'
    $pipCmd = Join-Path $PythonHome 'pip.cmd'
    $pip3Cmd = Join-Path $PythonHome 'pip3.cmd'
    $siteState = Test-PythonSiteImportsEnabled -PythonHome $PythonHome
    $versionCommandResult = $null
    $pipCommandResult = $null

    if (-not (Test-Path -LiteralPath $PythonHome)) {
        $status = 'Missing'
        $reportedVersion = $null
        $pipVersion = $null
    }
    elseif (-not (Test-Path -LiteralPath $pythonExe)) {
        $status = 'NeedsRepair'
        $reportedVersion = $null
        $pipVersion = $null
        $versionCommandResult = $null
        $pipCommandResult = $null
    }
    else {
        $versionProbe = Get-PythonReportedVersionProbe -PythonExe $pythonExe -LocalRoot $LocalRoot
        $reportedVersion = $versionProbe.ReportedVersion
        $versionCommandResult = $versionProbe.CommandResult
        $versionObject = ConvertTo-PythonVersion -VersionText $reportedVersion
        $pipProbe = if ($siteState.ImportSiteEnabled) { Get-PythonPipVersionProbe -PythonExe $pythonExe -LocalRoot $LocalRoot } else { $null }
        $pipVersion = if ($pipProbe) { $pipProbe.PipVersion } else { $null }
        $pipCommandResult = if ($pipProbe) { $pipProbe.CommandResult } else { $null }
        $hasWrappers = (Test-Path -LiteralPath $pipCmd) -and (Test-Path -LiteralPath $pip3Cmd)
        $status = if ($versionObject -and $siteState.IsReady -and $hasWrappers -and -not [string]::IsNullOrWhiteSpace($pipVersion)) { 'Ready' } else { 'NeedsRepair' }
    }

    [pscustomobject]@{
        Status            = $status
        IsReady           = ($status -eq 'Ready')
        PythonHome        = $PythonHome
        PythonExe         = $pythonExe
        PipCmd            = $pipCmd
        Pip3Cmd           = $pip3Cmd
        ReportedVersion   = $reportedVersion
        PipVersion        = $pipVersion
        PthPath           = $siteState.PthPath
        SiteImports       = $siteState
        VersionCommandResult = $versionCommandResult
        PipCommandResult  = $pipCommandResult
        ValidationHint    = if (-not [string]::IsNullOrWhiteSpace($reportedVersion) -and -not [string]::IsNullOrWhiteSpace($pipVersion)) {
            $null
        }
        elseif ($versionCommandResult -and [string]::IsNullOrWhiteSpace($reportedVersion)) {
            Get-PythonCommandFailureHint -CommandResult $versionCommandResult -LocalRoot $LocalRoot
        }
        elseif ($pipCommandResult -and [string]::IsNullOrWhiteSpace($pipVersion)) {
            Get-PythonCommandFailureHint -CommandResult $pipCommandResult -LocalRoot $LocalRoot
        }
        else {
            $null
        }
    }
}

function Get-InstalledPythonRuntime {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-PythonFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.PythonToolsRoot) {
        $versionRoots = Get-ChildItem -LiteralPath $layout.PythonToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-PythonVersion -VersionText $_.Name } }

        foreach ($versionRoot in $versionRoots) {
            $pythonHome = Join-Path $versionRoot.FullName $Flavor
            if (-not (Test-Path -LiteralPath $pythonHome)) {
                continue
            }

            $validation = Test-PythonRuntime -PythonHome $pythonHome -LocalRoot $layout.LocalRoot
            $expectedVersion = ConvertTo-PythonVersion -VersionText $versionRoot.Name
            $reportedVersion = ConvertTo-PythonVersion -VersionText $validation.ReportedVersion
            $versionMatches = (-not $reportedVersion) -or (-not $expectedVersion) -or ($reportedVersion -eq $expectedVersion)

            $entries += [pscustomobject]@{
                Version        = $versionRoot.Name
                Flavor         = $Flavor
                PythonHome     = $pythonHome
                PythonExe      = $validation.PythonExe
                Validation     = $validation
                VersionMatches = $versionMatches
                PipVersion     = $validation.PipVersion
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

function Get-ManifestedPythonExternalPaths {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    foreach ($commandName in @('python.exe', 'python')) {
        foreach ($command in @(Get-Command -Name $commandName -CommandType Application -All -ErrorAction SilentlyContinue)) {
            $commandPath = $null
            if ($command.PSObject.Properties['Path'] -and $command.Path) {
                $commandPath = $command.Path
            }
            elseif ($command.PSObject.Properties['Source'] -and $command.Source) {
                $commandPath = $command.Source
            }

            if (-not [string]::IsNullOrWhiteSpace($commandPath) -and $commandPath -like '*.exe') {
                $candidatePaths.Add($commandPath) | Out-Null
            }
        }
    }

    $additionalPatterns = @()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $additionalPatterns += (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\python.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $additionalPatterns += (Join-Path $env:ProgramFiles 'Python*\python.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $additionalPatterns += (Join-Path $env:USERPROFILE '.pyenv\pyenv-win\versions\*\python.exe')
    }

    foreach ($pattern in $additionalPatterns) {
        foreach ($candidate in @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)) {
            $candidatePaths.Add($candidate.FullName) | Out-Null
        }
    }

    $resolvedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $fullCandidatePath = Get-ManifestedFullPath -Path $candidatePath
        if ([string]::IsNullOrWhiteSpace($fullCandidatePath) -or -not (Test-Path -LiteralPath $fullCandidatePath)) {
            continue
        }
        if (Test-ManifestedPathIsUnderRoot -Path $fullCandidatePath -RootPath $layout.PythonToolsRoot) {
            continue
        }
        if ($fullCandidatePath -like '*\WindowsApps\python.exe') {
            continue
        }

        $resolvedPaths.Add($fullCandidatePath) | Out-Null
    }

    return @($resolvedPaths | Select-Object -Unique)
}

function Test-ExternalPythonRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $versionProbe = Get-PythonReportedVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    $reportedVersion = $versionProbe.ReportedVersion
    $versionObject = ConvertTo-PythonVersion -VersionText $reportedVersion
    $pipProbe = if ($versionObject -and (Test-PythonExternalRuntimeVersion -Version $versionObject)) { Get-PythonPipVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot } else { $null }
    $pipVersion = if ($pipProbe) { $pipProbe.PipVersion } else { $null }
    $isReady = ($versionObject -and (Test-PythonExternalRuntimeVersion -Version $versionObject) -and -not [string]::IsNullOrWhiteSpace($pipVersion))

    [pscustomobject]@{
        Status          = if ($isReady) { 'Ready' } else { 'Invalid' }
        IsReady         = $isReady
        PythonHome      = if (Test-Path -LiteralPath $PythonExe) { Split-Path -Parent $PythonExe } else { $null }
        PythonExe       = $PythonExe
        ReportedVersion = if ($versionObject) { $versionObject.ToString() } else { $reportedVersion }
        PipVersion      = $pipVersion
        VersionCommandResult = $versionProbe.CommandResult
        PipCommandResult = if ($pipProbe) { $pipProbe.CommandResult } else { $null }
    }
}

function Get-ManifestedPythonRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CandidatePath,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $validation = Test-ExternalPythonRuntime -PythonExe $CandidatePath -LocalRoot $LocalRoot
    if (-not $validation.IsReady) {
        return $null
    }

    [pscustomobject]@{
        Version     = $validation.ReportedVersion
        Flavor      = $null
        PythonHome  = $validation.PythonHome
        PythonExe   = $validation.PythonExe
        Validation  = $validation
        PipVersion  = $validation.PipVersion
        IsReady     = $true
        Source      = 'External'
        Discovery   = 'Path'
    }
}

function Get-SystemPythonRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    foreach ($candidatePath in @(Get-ManifestedPythonExternalPaths -LocalRoot $LocalRoot)) {
        $runtime = Get-ManifestedPythonRuntimeFromCandidatePath -CandidatePath $candidatePath -LocalRoot $LocalRoot
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Test-PythonRuntimePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo
    )

    if (-not (Test-Path -LiteralPath $PackageInfo.Path)) {
        return [pscustomobject]@{
            Status       = 'Missing'
            ReleaseId    = if ($PackageInfo.PSObject.Properties['ReleaseId']) { $PackageInfo.ReleaseId } else { $null }
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

    if ([string]::IsNullOrWhiteSpace($PackageInfo.Sha256)) {
        return [pscustomobject]@{
            Status       = 'UnverifiedCache'
            ReleaseId    = if ($PackageInfo.PSObject.Properties['ReleaseId']) { $PackageInfo.ReleaseId } else { $null }
            Version      = $PackageInfo.Version
            Flavor       = $PackageInfo.Flavor
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
        ReleaseId    = if ($PackageInfo.PSObject.Properties['ReleaseId']) { $PackageInfo.ReleaseId } else { $null }
        Version      = $PackageInfo.Version
        Flavor       = $PackageInfo.Flavor
        FileName     = $PackageInfo.FileName
        Path         = $PackageInfo.Path
        Source       = $PackageInfo.Source
        Verified     = $true
        Verification = if ($PackageInfo.PSObject.Properties['ShaSource'] -and $PackageInfo.ShaSource) { $PackageInfo.ShaSource } else { 'SHA256' }
        ExpectedHash = $expectedHash
        ActualHash   = $actualHash
    }
}

function Get-PythonRuntimeState {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Flavor)) {
            $Flavor = Get-PythonFlavor
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
            PipVersion          = $null
            InvalidRuntimeHomes = @()
            Package             = $null
            PackagePath         = $null
            PartialPaths        = @()
            BlockedReason       = $_.Exception.Message
        }
    }

    $partialPaths = @()
    if (Test-Path -LiteralPath $layout.PythonCacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.PythonCacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'python' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledPythonRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemPythonRuntime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty PythonHome)
    $package = Get-LatestCachedPythonRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot

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
        RuntimeHome         = if ($currentRuntime) { $currentRuntime.PythonHome } else { $null }
        RuntimeSource       = $runtimeSource
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.PythonExe } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        PipVersion          = if ($currentRuntime -and $currentRuntime.PSObject.Properties['PipVersion']) { $currentRuntime.PipVersion } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

function Repair-PythonRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-PythonRuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
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

function Save-PythonRuntimePackage {
    [CmdletBinding()]
    param(
        [switch]$RefreshPython,
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-PythonFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.PythonCacheRoot | Out-Null

    $release = $null
    try {
        $release = Get-PythonRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    if ($release) {
        $packagePath = Join-Path $layout.PythonCacheRoot $release.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($RefreshPython -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                Write-Host "Downloading Python $($release.Version) embeddable runtime ($Flavor)..."
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

                Write-Warning ('Could not refresh the Python runtime package. Using cached copy. ' + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        return [pscustomobject]@{
            ReleaseId   = $release.ReleaseId
            Version     = $release.Version
            Flavor      = $Flavor
            FileName    = $release.FileName
            Path        = $packagePath
            Source      = if ($action -eq 'Downloaded') { 'online' } else { 'cache' }
            Action      = $action
            DownloadUrl = $release.DownloadUrl
            Sha256      = $release.Sha256
            ShaSource   = $release.ShaSource
            ReleaseUrl  = $release.ReleaseUrl
            ReleaseDate = $release.ReleaseDate
        }
    }

    $cachedPackage = Get-LatestCachedPythonRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    if (-not $cachedPackage) {
        throw 'Could not reach python.org and no cached Python embeddable ZIP was found.'
    }

    return [pscustomobject]@{
        ReleaseId   = $cachedPackage.ReleaseId
        Version     = $cachedPackage.Version
        Flavor      = $cachedPackage.Flavor
        FileName    = $cachedPackage.FileName
        Path        = $cachedPackage.Path
        Source      = 'cache'
        Action      = 'SelectedCache'
        DownloadUrl = $cachedPackage.DownloadUrl
        Sha256      = $cachedPackage.Sha256
        ShaSource   = $cachedPackage.ShaSource
        ReleaseUrl  = $cachedPackage.ReleaseUrl
        ReleaseDate = $cachedPackage.ReleaseDate
    }
}

function Resolve-PythonRuntimeTrustedPackageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $PackageInfo) {
        return [pscustomobject]@{
            PackageInfo           = $PackageInfo
            MetadataRefreshError  = $null
            MetadataRefreshTried  = $false
            UsedTrustedPackage    = $true
        }
    }

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.PSObject.Properties['Flavor'] -and $PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-PythonFlavor }
    }

    $refreshedPackage = $null
    $metadataRefreshError = $null
    try {
        $refreshedPackage = Save-PythonRuntimePackage -RefreshPython:$false -Flavor $Flavor -LocalRoot $LocalRoot
    }
    catch {
        $metadataRefreshError = $_.Exception.Message
    }

    if ($refreshedPackage -and (Test-Path -LiteralPath $PackageInfo.Path) -and (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $refreshedPackage)) {
        $samePackagePath = ((Get-ManifestedFullPath -Path $refreshedPackage.Path) -eq (Get-ManifestedFullPath -Path $PackageInfo.Path))
        $samePackageName = ($refreshedPackage.FileName -eq $PackageInfo.FileName)

        if ($samePackagePath -or $samePackageName) {
            return [pscustomobject]@{
                PackageInfo           = $refreshedPackage
                MetadataRefreshError  = $metadataRefreshError
                MetadataRefreshTried  = $true
                UsedTrustedPackage    = $true
            }
        }
    }

    return [pscustomobject]@{
        PackageInfo           = $PackageInfo
        MetadataRefreshError  = $metadataRefreshError
        MetadataRefreshTried  = $true
        UsedTrustedPackage    = (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $PackageInfo)
    }
}

function Save-PythonGetPipScript {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $scriptPath = Join-Path $layout.PythonCacheRoot 'get-pip.py'
    $downloadPath = Get-ManifestedDownloadPath -TargetPath $scriptPath
    New-ManifestedDirectory -Path $layout.PythonCacheRoot | Out-Null

    $action = 'ReusedCache'
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Remove-ManifestedPath -Path $downloadPath | Out-Null

        try {
            Write-Host 'Downloading get-pip.py bootstrap script...'
            Enable-ManifestedTls12Support
            Invoke-WebRequestEx -Uri 'https://bootstrap.pypa.io/get-pip.py' -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -OutFile $downloadPath -UseBasicParsing
            Move-Item -LiteralPath $downloadPath -Destination $scriptPath -Force
            $action = 'Downloaded'
        }
        catch {
            Remove-ManifestedPath -Path $downloadPath | Out-Null
            if (-not (Test-Path -LiteralPath $scriptPath)) {
                throw
            }

            Write-Warning ('Could not refresh get-pip.py. Using cached copy. ' + $_.Exception.Message)
            $action = 'ReusedCache'
        }
    }

    [pscustomobject]@{
        Path   = $scriptPath
        Action = $action
        Uri    = 'https://bootstrap.pypa.io/get-pip.py'
    }
}

function Ensure-PythonPip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $pipProxyConfiguration = Get-ManifestedPipProxyConfigurationStatus -PythonExe $PythonExe -LocalRoot $LocalRoot
    if ($pipProxyConfiguration.Action -eq 'NeedsManagedProxy') {
        $pipProxyConfiguration = Sync-ManifestedPipProxyConfiguration -PythonExe $PythonExe -Status $pipProxyConfiguration -LocalRoot $LocalRoot
    }

    $existingPipProbe = Get-PythonPipVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    $existingPipVersion = $existingPipProbe.PipVersion
    if (-not [string]::IsNullOrWhiteSpace($existingPipVersion)) {
        $wrapperInfo = Set-ManifestedManagedPipWrappers -PythonHome $PythonHome -LocalRoot $LocalRoot
        return [pscustomobject]@{
            Action                = 'Reused'
            Bootstrap             = 'Existing'
            PipVersion            = $existingPipVersion
            GetPipScript          = $null
            WrapperInfo           = $wrapperInfo
            PipProxyConfiguration = $pipProxyConfiguration
            ExistingPipProbe      = $existingPipProbe
        }
    }

    $bootstrap = 'EnsurePip'
    $ensurePipResult = Invoke-ManifestedPipAwarePythonCommand -PythonExe $PythonExe -Arguments @('-m', 'ensurepip', '--default-pip') -LocalRoot $LocalRoot
    $pipVersion = Get-PythonPipVersion -PythonExe $PythonExe -LocalRoot $LocalRoot
    $getPipScript = $null

    if ($ensurePipResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($pipVersion)) {
        $bootstrap = 'GetPip'
        $getPipScript = Save-PythonGetPipScript -LocalRoot $LocalRoot
        $getPipResult = Invoke-ManifestedPipAwarePythonCommand -PythonExe $PythonExe -Arguments @($getPipScript.Path) -LocalRoot $LocalRoot
        if ($getPipResult.ExitCode -ne 0) {
            throw (New-PythonRuntimeValidationFailureMessage -Operation 'get-pip bootstrap' -PythonHome $PythonHome -CommandResult $getPipResult -LocalRoot $LocalRoot)
        }

        $pipVersion = Get-PythonPipVersion -PythonExe $PythonExe -LocalRoot $LocalRoot
    }

    if ([string]::IsNullOrWhiteSpace($pipVersion)) {
        $bootstrapCommandResult = if ($bootstrap -eq 'EnsurePip') { $ensurePipResult } else { $getPipResult }
        throw (New-PythonRuntimeValidationFailureMessage -Operation 'pip bootstrap' -PythonHome $PythonHome -CommandResult $bootstrapCommandResult -LocalRoot $LocalRoot)
    }

    $wrapperInfo = Set-ManifestedManagedPipWrappers -PythonHome $PythonHome -LocalRoot $LocalRoot

    [pscustomobject]@{
        Action                = if ($bootstrap -eq 'EnsurePip') { 'InstalledEnsurePip' } else { 'InstalledGetPip' }
        Bootstrap             = $bootstrap
        PipVersion            = $pipVersion
        GetPipScript          = $getPipScript
        WrapperInfo           = $wrapperInfo
        PipProxyConfiguration = $pipProxyConfiguration
    }
}

function Install-PythonRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot),
        [switch]$ForceInstall
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-PythonFlavor }
    }

    $pythonHome = Get-ManagedPythonRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $currentValidation = Test-PythonRuntime -PythonHome $pythonHome -LocalRoot $LocalRoot

    if ($ForceInstall -or $currentValidation.Status -ne 'Ready') {
        New-ManifestedDirectory -Path (Split-Path -Parent $pythonHome) | Out-Null

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix 'python'
            if (-not (Test-Path -LiteralPath $stageInfo.ExpandedRoot)) {
                throw 'The Python embeddable ZIP did not extract as expected.'
            }

            if (Test-Path -LiteralPath $pythonHome) {
                Remove-Item -LiteralPath $pythonHome -Recurse -Force
            }

            New-ManifestedDirectory -Path $pythonHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $pythonHome -Force
            }

            $siteState = Enable-PythonSiteImports -PythonHome $pythonHome
            if (-not $siteState.IsReady) {
                throw "Python site import enablement failed for $pythonHome."
            }
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $pythonExe = Join-Path $pythonHome 'python.exe'
    $versionProbe = Get-PythonReportedVersionProbe -PythonExe $pythonExe -LocalRoot $LocalRoot
    $reportedVersion = $versionProbe.ReportedVersion
    $reportedVersionObject = ConvertTo-PythonVersion -VersionText $reportedVersion
    $expectedVersionObject = ConvertTo-PythonVersion -VersionText $PackageInfo.Version
    if (-not $reportedVersionObject -or -not $expectedVersionObject -or $reportedVersionObject -ne $expectedVersionObject) {
        throw (New-PythonRuntimeValidationFailureMessage -Operation 'post-install version check' -PythonHome $pythonHome -ExpectedVersion $PackageInfo.Version -ReportedVersion $reportedVersion -CommandResult $versionProbe.CommandResult -SiteImportsState $siteState -LocalRoot $LocalRoot)
    }

    $pipResult = Ensure-PythonPip -PythonExe $pythonExe -PythonHome $pythonHome -LocalRoot $LocalRoot
    $validation = Test-PythonRuntime -PythonHome $pythonHome -LocalRoot $LocalRoot
    if ($validation.Status -ne 'Ready') {
        $validationCommandResult = if ([string]::IsNullOrWhiteSpace($validation.ReportedVersion)) {
            $validation.VersionCommandResult
        }
        elseif ([string]::IsNullOrWhiteSpace($validation.PipVersion)) {
            $validation.PipCommandResult
        }
        else {
            $validation.VersionCommandResult
        }

        throw (New-PythonRuntimeValidationFailureMessage -Operation 'post-pip validation' -PythonHome $pythonHome -ExpectedVersion $PackageInfo.Version -ReportedVersion $validation.ReportedVersion -CommandResult $validationCommandResult -SiteImportsState $validation.SiteImports -LocalRoot $LocalRoot)
    }

    [pscustomobject]@{
        Action                = if ($ForceInstall -or $currentValidation.Status -ne 'Ready') { 'Installed' } else { 'Skipped' }
        Version               = $PackageInfo.Version
        Flavor                = $Flavor
        PythonHome            = $pythonHome
        PythonExe             = $validation.PythonExe
        PipCmd                = $validation.PipCmd
        Pip3Cmd               = $validation.Pip3Cmd
        PthPath               = $validation.PthPath
        PipVersion            = $validation.PipVersion
        PipResult             = $pipResult
        Source                = $PackageInfo.Source
    }
}

function Test-PythonRuntimeFromState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State.RuntimeHome -and -not $State.ExecutablePath) {
        return $null
    }

    if ($State.RuntimeSource -eq 'Managed' -and $State.RuntimeHome) {
        return (Test-PythonRuntime -PythonHome $State.RuntimeHome -LocalRoot $LocalRoot)
    }

    if ($State.RuntimeSource -eq 'External' -and $State.ExecutablePath) {
        return (Test-ExternalPythonRuntime -PythonExe $State.ExecutablePath -LocalRoot $LocalRoot)
    }

    return $null
}

function Initialize-PythonRuntime {
<#
.SYNOPSIS
Ensures a managed or reusable Python runtime is available for the sandbox.

.DESCRIPTION
Discovers existing managed or external Python runtimes, repairs partial or
broken managed state, acquires a trusted CPython embeddable ZIP when needed,
installs the managed runtime, bootstraps pip, and synchronizes the command-line
environment so `python` resolves consistently for follow-up tooling.

.PARAMETER RefreshPython
Forces the managed Python package to be reacquired and reinstalled instead of
reusing the currently installed or cached copy.

.EXAMPLE
Initialize-PythonRuntime

.EXAMPLE
Initialize-PythonRuntime -RefreshPython

.NOTES
Supports `-WhatIf` and follows the module's shared state and environment
synchronization conventions for public runtime commands.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshPython
    )

    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $plannedActions = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $packageInfo = $null
    $packageTest = $null
    $installResult = $null
    $pipSetupResult = $null
    $commandEnvironment = $null

    $initialState = Get-PythonRuntimeState -LocalRoot $LocalRoot
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-PythonRuntime' -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-PythonRuntime' -RuntimeState $state
        $result = [pscustomobject]@{
            LocalRoot            = $state.LocalRoot
            Layout               = $state.Layout
            InitialState         = $initialState
            FinalState           = $state
            ActionTaken          = @('None')
            PlannedActions       = @()
            RestartRequired      = $false
            Package              = $null
            PackageTest          = $null
            RuntimeTest          = $null
            RepairResult         = $null
            InstallResult        = $null
            PipSetupResult       = $null
            PipProxyConfiguration = $null
            CommandEnvironment   = $commandEnvironment
            Elevation            = $elevationPlan
        }

        if ($WhatIfPreference) {
            Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
            return $result
        }

        $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-PythonRuntime' -Result $result -LocalRoot $LocalRoot -Details @{}
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force
        return $result
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $RefreshPython -or -not $state.RuntimeHome
    $needsAcquire = $RefreshPython -or (-not $state.PackagePath) -or (-not (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $state.Package))

    if ($needsRepair) {
        $plannedActions.Add('Repair-PythonRuntime') | Out-Null
    }
    if ($needsInstall -and $needsAcquire) {
        $plannedActions.Add('Save-PythonRuntimePackage') | Out-Null
    }
    if ($needsInstall) {
        $plannedActions.Add('Test-PythonRuntimePackage') | Out-Null
        $plannedActions.Add('Install-PythonRuntime') | Out-Null
        $plannedActions.Add('Ensure-PythonPip') | Out-Null
    }
    elseif ($state.RuntimeSource -eq 'Managed') {
        $plannedActions.Add('Ensure-PythonPip') | Out-Null
    }
    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null

    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-PythonRuntime' -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($WhatIfPreference) {
        return [pscustomobject]@{
            LocalRoot             = $state.LocalRoot
            Layout                = $state.Layout
            InitialState          = $initialState
            FinalState            = $state
            ActionTaken           = @('WhatIf')
            PlannedActions        = @($plannedActions)
            RestartRequired       = $false
            Package               = $state.Package
            PackageTest           = $null
            RuntimeTest           = $state.Runtime
            RepairResult          = $null
            InstallResult         = $null
            PipSetupResult        = $null
            PipProxyConfiguration = $null
            CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-PythonRuntime' -RuntimeState $state)
            PersistedStatePath    = $null
            Elevation             = $elevationPlan
        }
    }

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.PythonToolsRoot, 'Repair Python runtime state')) {
            return [pscustomobject]@{
                LocalRoot             = $state.LocalRoot
                Layout                = $state.Layout
                InitialState          = $initialState
                FinalState            = $state
                ActionTaken           = @('Cancelled')
                PlannedActions        = @($plannedActions)
                RestartRequired       = $false
                Package               = $state.Package
                PackageTest           = $null
                RuntimeTest           = $state.Runtime
                RepairResult          = $null
                InstallResult         = $null
                PipSetupResult        = $null
                PipProxyConfiguration = $null
                CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-PythonRuntime' -RuntimeState $state)
                PersistedStatePath    = $null
                Elevation             = $elevationPlan
            }
        }

        $repairResult = Repair-PythonRuntime -State $state -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add('Repair-PythonRuntime') | Out-Null
        }

        $state = Get-PythonRuntimeState -Flavor $state.Flavor -LocalRoot $state.LocalRoot
    }

    $needsInstall = $RefreshPython -or -not $state.RuntimeHome
    $needsAcquire = $RefreshPython -or (-not $state.PackagePath) -or (-not (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $state.Package))

    if ($needsInstall) {
        if ($needsAcquire) {
            $packageInfo = Save-PythonRuntimePackage -RefreshPython:$RefreshPython -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-PythonRuntimePackage') | Out-Null
            }
        }
        else {
            $packageInfo = $state.Package
        }

        $packageTest = Test-PythonRuntimePackage -PackageInfo $packageInfo
        if ($packageTest.Status -eq 'UnverifiedCache') {
            $trustedPackageResolution = Resolve-PythonRuntimeTrustedPackageInfo -PackageInfo $packageInfo -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            $packageInfo = $trustedPackageResolution.PackageInfo
            $packageTest = Test-PythonRuntimePackage -PackageInfo $packageInfo

            if ($packageTest.Status -eq 'UnverifiedCache') {
                throw (New-PythonRuntimePackageTrustFailureMessage -PackageInfo $packageInfo -MetadataRefreshError $trustedPackageResolution.MetadataRefreshError)
            }
        }

        if ($packageTest.Status -eq 'CorruptCache') {
            if (-not $PSCmdlet.ShouldProcess($packageInfo.Path, 'Repair corrupt Python runtime package')) {
                return [pscustomobject]@{
                    LocalRoot             = $state.LocalRoot
                    Layout                = $state.Layout
                    InitialState          = $initialState
                    FinalState            = $state
                    ActionTaken           = @('Cancelled')
                    PlannedActions        = @($plannedActions)
                    RestartRequired       = $false
                    Package               = $packageInfo
                    PackageTest           = $packageTest
                    RuntimeTest           = $state.Runtime
                    RepairResult          = $repairResult
                    InstallResult         = $null
                    PipSetupResult        = $null
                    PipProxyConfiguration = $null
                    CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-PythonRuntime' -RuntimeState $state)
                    PersistedStatePath    = $null
                    Elevation             = $elevationPlan
                }
            }

            $repairResult = Repair-PythonRuntime -State $state -CorruptPackagePaths @($packageInfo.Path) -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($repairResult.Action -eq 'Repaired') {
                $actionsTaken.Add('Repair-PythonRuntime') | Out-Null
            }

            $packageInfo = Save-PythonRuntimePackage -RefreshPython:$true -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-PythonRuntimePackage') | Out-Null
            }

            $packageTest = Test-PythonRuntimePackage -PackageInfo $packageInfo
        }

        if ($packageTest.Status -ne 'Ready') {
            throw "Python runtime package validation failed with status $($packageTest.Status)."
        }

        $commandParameters = @{}
        if ($RefreshPython) {
            $commandParameters['RefreshPython'] = $true
        }
        if ($PSBoundParameters.ContainsKey('WhatIf')) {
            $commandParameters['WhatIf'] = $true
        }

        $elevatedResult = Invoke-ManifestedElevatedCommand -ElevationPlan $elevationPlan -CommandName 'Initialize-PythonRuntime' -CommandParameters $commandParameters
        if ($null -ne $elevatedResult) {
            return $elevatedResult
        }

        if (-not $PSCmdlet.ShouldProcess($state.Layout.PythonToolsRoot, 'Install Python runtime')) {
            return [pscustomobject]@{
                LocalRoot             = $state.LocalRoot
                Layout                = $state.Layout
                InitialState          = $initialState
                FinalState            = $state
                ActionTaken           = @('Cancelled')
                PlannedActions        = @($plannedActions)
                RestartRequired       = $false
                Package               = $packageInfo
                PackageTest           = $packageTest
                RuntimeTest           = $state.Runtime
                RepairResult          = $repairResult
                InstallResult         = $null
                PipSetupResult        = $null
                PipProxyConfiguration = $null
                CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-PythonRuntime' -RuntimeState $state)
                PersistedStatePath    = $null
                Elevation             = $elevationPlan
            }
        }

        $installResult = Install-PythonRuntime -PackageInfo $packageInfo -Flavor $state.Flavor -LocalRoot $state.LocalRoot -ForceInstall:$RefreshPython
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add('Install-PythonRuntime') | Out-Null
        }
        if ($installResult.PSObject.Properties['PipResult'] -and $installResult.PipResult) {
            if ($installResult.PipResult.Action -ne 'Reused') {
                $actionsTaken.Add('Ensure-PythonPip') | Out-Null
            }
            elseif ($installResult.PipResult.PipProxyConfiguration -and $installResult.PipResult.PipProxyConfiguration.Action -eq 'ConfiguredManagedProxy') {
                $actionsTaken.Add('Sync-ManifestedPipProxyConfiguration') | Out-Null
            }
        }
    }

    $finalState = Get-PythonRuntimeState -Flavor $state.Flavor -LocalRoot $state.LocalRoot
    $runtimeTest = Test-PythonRuntimeFromState -State $finalState -LocalRoot $finalState.LocalRoot
    if ($finalState.Status -ne 'Ready' -or -not $runtimeTest -or -not $runtimeTest.IsReady) {
        throw 'Python runtime validation did not reach the Ready state.'
    }

    if ($finalState.RuntimeSource -eq 'Managed' -and $finalState.ExecutablePath) {
        $pipSetupResult = Ensure-PythonPip -PythonExe $finalState.ExecutablePath -PythonHome $finalState.RuntimeHome -LocalRoot $finalState.LocalRoot
        if ($pipSetupResult.Action -ne 'Reused') {
            $actionsTaken.Add('Ensure-PythonPip') | Out-Null
        }
        elseif ($pipSetupResult.PipProxyConfiguration -and $pipSetupResult.PipProxyConfiguration.Action -eq 'ConfiguredManagedProxy') {
            $actionsTaken.Add('Sync-ManifestedPipProxyConfiguration') | Out-Null
        }

        $runtimeTest = Test-PythonRuntimeFromState -State $finalState -LocalRoot $finalState.LocalRoot
    }

    $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-PythonRuntime' -RuntimeState $finalState
    if ($commandEnvironment.Applicable -and $commandEnvironment.Status -eq 'NeedsSync') {
        $commandEnvironment = Sync-ManifestedCommandLineEnvironment -Specification (Get-ManifestedCommandEnvironmentSpec -CommandName 'Initialize-PythonRuntime' -RuntimeState $finalState)
        if ($commandEnvironment.Status -eq 'Updated') {
            $actionsTaken.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
        }
    }

    $effectivePackageInfo = if ($packageInfo) { $packageInfo } elseif ($finalState.Package) { $finalState.Package } else { $null }
    $result = [pscustomobject]@{
        LocalRoot             = $finalState.LocalRoot
        Layout                = $finalState.Layout
        InitialState          = $initialState
        FinalState            = $finalState
        ActionTaken           = if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }
        PlannedActions        = @($plannedActions)
        RestartRequired       = $false
        Package               = $effectivePackageInfo
        PackageTest           = $packageTest
        RuntimeTest           = $runtimeTest
        RepairResult          = $repairResult
        InstallResult         = $installResult
        PipSetupResult        = $pipSetupResult
        PipProxyConfiguration = if ($pipSetupResult) { $pipSetupResult.PipProxyConfiguration } else { $null }
        CommandEnvironment    = $commandEnvironment
        PersistedStatePath    = $null
        Elevation             = $elevationPlan
    }

    $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-PythonRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
        Version        = $finalState.CurrentVersion
        Flavor         = $finalState.Flavor
        RuntimeHome    = $finalState.RuntimeHome
        RuntimeSource  = $finalState.RuntimeSource
        ExecutablePath = $finalState.ExecutablePath
        PipVersion     = if ($runtimeTest -and $runtimeTest.PSObject.Properties['PipVersion']) { $runtimeTest.PipVersion } else { $null }
        PipConfigPath  = if ($pipSetupResult -and $pipSetupResult.PipProxyConfiguration) { $pipSetupResult.PipProxyConfiguration.PipConfigPath } else { $null }
        AssetName      = if ($effectivePackageInfo) { $effectivePackageInfo.FileName } else { $null }
        Sha256         = if ($effectivePackageInfo) { $effectivePackageInfo.Sha256 } else { $null }
        ShaSource      = if ($effectivePackageInfo) { $effectivePackageInfo.ShaSource } else { $null }
        DownloadUrl    = if ($effectivePackageInfo) { $effectivePackageInfo.DownloadUrl } else { $null }
        ReleaseUrl     = if ($effectivePackageInfo) { $effectivePackageInfo.ReleaseUrl } else { $null }
        ReleaseId      = if ($effectivePackageInfo) { $effectivePackageInfo.ReleaseId } else { $null }
    }

    Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force
    return $result
}
