<#
    Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache
#>

function ConvertTo-VCRuntimeVersion {
<#
.SYNOPSIS
Normalizes VC runtime version text into a comparable version object.

.DESCRIPTION
Extracts a semantic VC runtime version from installer metadata or registry text
and returns it as a System.Version when the input can be parsed.

.PARAMETER VersionText
Raw version text reported by the VC runtime installer or registry.

.EXAMPLE
ConvertTo-VCRuntimeVersion -VersionText '14.40.33810.0'
#>
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, '\d+(?:\.\d+){1,3}')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Value
}

function Format-VCRuntimeProcessArgument {
<#
.SYNOPSIS
Formats a VC runtime installer argument for Start-Process.

.DESCRIPTION
Quotes installer argument values when they contain whitespace or quotes so the
silent installer receives the expected log-path argument.

.PARAMETER Value
Argument value that may need quoting before process invocation.

.EXAMPLE
Format-VCRuntimeProcessArgument -Value 'C:\temp\vc runtime.log'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($Value.IndexOfAny([char[]]@(' ', "`t", '"')) -ge 0) {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    return $Value
}

function Get-VCRuntimeInstallerInfo {
<#
.SYNOPSIS
Builds the managed VC runtime installer metadata.

.DESCRIPTION
Returns the static download URL, cache path, and architecture metadata used by
the sandbox when acquiring the VC++ redistributable bootstrapper.

.PARAMETER LocalRoot
Sandbox local root used to resolve the managed cache layout.

.EXAMPLE
Get-VCRuntimeInstallerInfo
#>
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot

    [pscustomobject]@{
        Architecture = 'x64'
        FileName     = 'vc_redist.x64.exe'
        DownloadUrl  = 'https://aka.ms/vc14/vc_redist.x64.exe'
        CachePath    = (Join-Path $layout.VCRuntimeCacheRoot 'vc_redist.x64.exe')
    }
}

function Get-CachedVCRuntimeInstaller {
<#
.SYNOPSIS
Returns the currently cached VC runtime installer, if present.

.DESCRIPTION
Inspects the managed VC runtime cache location, reads file-version metadata
from the cached bootstrapper, and returns normalized cache details.

.PARAMETER LocalRoot
Sandbox local root used to resolve the managed installer cache.

.EXAMPLE
Get-CachedVCRuntimeInstaller
#>
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $info = Get-VCRuntimeInstallerInfo -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $info.CachePath)) {
        return $null
    }

    $item = Get-Item -LiteralPath $info.CachePath
    $versionObject = ConvertTo-VCRuntimeVersion -VersionText $item.VersionInfo.FileVersion

    [pscustomobject]@{
        Architecture  = $info.Architecture
        FileName      = $info.FileName
        Path          = $info.CachePath
        Version       = if ($versionObject) { $versionObject.ToString() } else { $item.VersionInfo.FileVersion }
        VersionObject = $versionObject
        LastWriteTime = $item.LastWriteTimeUtc
        Source        = 'cache'
        Action        = 'SelectedCache'
        DownloadUrl   = $info.DownloadUrl
    }
}

function Get-InstalledVCRuntime {
<#
.SYNOPSIS
Detects the installed Microsoft VC runtime from the registry.

.DESCRIPTION
Checks the 32-bit and 64-bit Visual C++ runtime registry keys and returns a
normalized installation record for the x64 redistributable.

.EXAMPLE
Get-InstalledVCRuntime
#>
    [CmdletBinding()]
    param()

    $subKeyPaths = @(
        'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
        'SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    )

    $views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32) | Select-Object -Unique

    foreach ($view in $views) {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        try {
            foreach ($subKeyPath in $subKeyPaths) {
                $subKey = $baseKey.OpenSubKey($subKeyPath)
                if (-not $subKey) {
                    continue
                }

                try {
                    $installed = [int]$subKey.GetValue('Installed', 0)
                    $versionText = [string]$subKey.GetValue('Version', '')
                    $versionObject = ConvertTo-VCRuntimeVersion -VersionText $versionText

                    if (-not $versionObject) {
                        $major = $subKey.GetValue('Major', $null)
                        $minor = $subKey.GetValue('Minor', $null)
                        $bld = $subKey.GetValue('Bld', $null)
                        $rbld = $subKey.GetValue('Rbld', $null)

                        if ($null -ne $major -and $null -ne $minor -and $null -ne $bld -and $null -ne $rbld) {
                            $versionObject = [version]::new([int]$major, [int]$minor, [int]$bld, [int]$rbld)
                            $versionText = $versionObject.ToString()
                        }
                    }

                    if ($installed -eq 1) {
                        return [pscustomobject]@{
                            Installed     = $true
                            Architecture  = 'x64'
                            Version       = $versionText
                            VersionObject = $versionObject
                            KeyPath       = $subKeyPath
                            RegistryView  = $view.ToString()
                        }
                    }
                }
                finally {
                    $subKey.Dispose()
                }
            }
        }
        finally {
            $baseKey.Dispose()
        }
    }

    [pscustomobject]@{
        Installed     = $false
        Architecture  = 'x64'
        Version       = $null
        VersionObject = $null
        KeyPath       = $null
        RegistryView  = $null
    }
}

function Test-VCRuntime {
<#
.SYNOPSIS
Normalizes installed VC runtime information into a readiness result.

.DESCRIPTION
Converts the raw installed-runtime record into the status object used by the
bootstrap flow so callers can reason about Ready versus Missing state.

.PARAMETER InstalledRuntime
Registry-based installation record returned by Get-InstalledVCRuntime.

.EXAMPLE
Test-VCRuntime -InstalledRuntime (Get-InstalledVCRuntime)
#>
    [CmdletBinding()]
    param(
        [pscustomobject]$InstalledRuntime = (Get-InstalledVCRuntime)
    )

    $status = if ($InstalledRuntime.Installed) { 'Ready' } else { 'Missing' }

    [pscustomobject]@{
        Status        = $status
        Installed     = $InstalledRuntime.Installed
        Architecture  = $InstalledRuntime.Architecture
        Version       = $InstalledRuntime.Version
        VersionObject = $InstalledRuntime.VersionObject
        KeyPath       = $InstalledRuntime.KeyPath
        RegistryView  = $InstalledRuntime.RegistryView
    }
}

function Get-VCRuntimeState {
<#
.SYNOPSIS
Builds the current VC runtime state for the manifested sandbox.

.DESCRIPTION
Combines the cached installer state, installed redistributable state, and any
partial download artifacts into the normalized runtime snapshot used by
Initialize-VCRuntime.

.PARAMETER LocalRoot
Sandbox local root used to resolve installer cache paths.

.EXAMPLE
Get-VCRuntimeState
#>
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return [pscustomobject]@{
            Status         = 'Blocked'
            LocalRoot      = $LocalRoot
            Layout         = $null
            CurrentVersion = $null
            InstalledRuntime = $null
            Runtime        = $null
            Installer      = $null
            InstallerPath  = $null
            PartialPaths   = @()
            BlockedReason  = 'Only Windows hosts are supported by this VC runtime bootstrap.'
        }
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $installerInfo = Get-VCRuntimeInstallerInfo -LocalRoot $layout.LocalRoot
    $partialPaths = @()
    $downloadPath = Get-ManifestedDownloadPath -TargetPath $installerInfo.CachePath
    if (Test-Path -LiteralPath $downloadPath) {
        $partialPaths += $downloadPath
    }

    $installedRuntime = Get-InstalledVCRuntime
    $runtime = Test-VCRuntime -InstalledRuntime $installedRuntime
    $installer = Get-CachedVCRuntimeInstaller -LocalRoot $layout.LocalRoot

    if ($partialPaths.Count -gt 0) {
        $status = 'Partial'
    }
    elseif ($runtime.Status -eq 'Ready') {
        $status = 'Ready'
    }
    elseif ($installer) {
        $status = 'NeedsInstall'
    }
    else {
        $status = 'Missing'
    }

    [pscustomobject]@{
        Status           = $status
        LocalRoot        = $layout.LocalRoot
        Layout           = $layout
        CurrentVersion   = if ($runtime.Version) { $runtime.Version } elseif ($installer) { $installer.Version } else { $null }
        InstalledRuntime = $installedRuntime
        Runtime          = $runtime
        Installer        = $installer
        InstallerPath    = if ($installer) { $installer.Path } else { $installerInfo.CachePath }
        PartialPaths     = $partialPaths
        BlockedReason    = $null
    }
}

function Repair-VCRuntime {
<#
.SYNOPSIS
Removes partial or corrupt VC runtime installer artifacts.

.DESCRIPTION
Collects staged download remnants and any explicitly supplied corrupt installer
paths, removes them, and returns a repair summary for the runtime flow.

.PARAMETER State
Existing VC runtime state to repair. When omitted, the current state is loaded.

.PARAMETER CorruptInstallerPaths
Additional installer paths to remove during the repair pass.

.PARAMETER LocalRoot
Sandbox local root used when state must be rediscovered.

.EXAMPLE
Repair-VCRuntime -State (Get-VCRuntimeState)
#>
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptInstallerPaths = @(),
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-VCRuntimeState -LocalRoot $LocalRoot
    }

    $pathsToRemove = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($State.PartialPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($CorruptInstallerPaths)) {
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

function Save-VCRuntimeInstaller {
<#
.SYNOPSIS
Ensures the VC runtime bootstrapper is available in the managed cache.

.DESCRIPTION
Downloads the Microsoft VC++ redistributable bootstrapper when needed, falls
back to the cached copy on refresh failures, and returns normalized installer
metadata for the selected cache entry.

.PARAMETER RefreshVCRuntime
Forces the installer to be re-downloaded instead of reusing the cached copy.

.PARAMETER LocalRoot
Sandbox local root used to resolve cache locations.

.EXAMPLE
Save-VCRuntimeInstaller

.EXAMPLE
Save-VCRuntimeInstaller -RefreshVCRuntime
#>
    [CmdletBinding()]
    param(
        [switch]$RefreshVCRuntime,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $info = Get-VCRuntimeInstallerInfo -LocalRoot $layout.LocalRoot
    New-ManifestedDirectory -Path $layout.VCRuntimeCacheRoot | Out-Null

    $cacheExists = Test-Path -LiteralPath $info.CachePath
    $downloadPath = Get-ManifestedDownloadPath -TargetPath $info.CachePath
    $action = 'ReusedCache'

    if ($RefreshVCRuntime -or -not $cacheExists) {
        Remove-ManifestedPath -Path $downloadPath | Out-Null

        try {
            Write-Host 'Downloading Microsoft Visual C++ Redistributable bootstrapper...'
            Invoke-WebRequestEx -Uri $info.DownloadUrl -OutFile $downloadPath -UseBasicParsing
            Move-Item -LiteralPath $downloadPath -Destination $info.CachePath -Force
            $action = 'Downloaded'
        }
        catch {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            if (-not $cacheExists) {
                throw
            }

            Write-Warning ('Could not refresh the VC++ redistributable bootstrapper. Using cached copy. ' + $_.Exception.Message)
            $action = 'ReusedCache'
        }
    }

    if (-not (Test-Path -LiteralPath $info.CachePath)) {
        throw 'Could not acquire the VC++ redistributable bootstrapper and no cached copy was found.'
    }

    $cached = Get-CachedVCRuntimeInstaller -LocalRoot $layout.LocalRoot

    [pscustomobject]@{
        Architecture  = $info.Architecture
        FileName      = $info.FileName
        DownloadUrl   = $info.DownloadUrl
        Path          = $info.CachePath
        Version       = if ($cached) { $cached.Version } else { $null }
        VersionObject = if ($cached) { $cached.VersionObject } else { $null }
        Source        = if ($action -eq 'Downloaded') { 'online' } else { 'cache' }
        Action        = $action
    }
}

function Test-VCRuntimeInstaller {
<#
.SYNOPSIS
Validates a cached VC runtime installer.

.DESCRIPTION
Verifies that the cached installer exists and is authenticode-signed by
Microsoft so the runtime flow can distinguish ready cache entries from corrupt
ones.

.PARAMETER InstallerInfo
Installer metadata returned by Save-VCRuntimeInstaller or
Get-CachedVCRuntimeInstaller.

.EXAMPLE
Test-VCRuntimeInstaller -InstallerInfo (Save-VCRuntimeInstaller)
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$InstallerInfo
    )

    if (-not (Test-Path -LiteralPath $InstallerInfo.Path)) {
        return [pscustomobject]@{
            Status          = 'Missing'
            Architecture    = $InstallerInfo.Architecture
            Path            = $InstallerInfo.Path
            Version         = $InstallerInfo.Version
            VersionObject   = $InstallerInfo.VersionObject
            SignatureStatus = 'Missing'
            SignerSubject   = $null
        }
    }

    $signature = Get-AuthenticodeSignature -FilePath $InstallerInfo.Path
    $status = 'Ready'

    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        $status = 'CorruptCache'
    }
    elseif (-not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        $status = 'CorruptCache'
    }

    [pscustomobject]@{
        Status          = $status
        Architecture    = $InstallerInfo.Architecture
        Path            = $InstallerInfo.Path
        Version         = $InstallerInfo.Version
        VersionObject   = $InstallerInfo.VersionObject
        SignatureStatus = $signature.Status.ToString()
        SignerSubject   = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
    }
}

function Invoke-VCRuntimeInstaller {
<#
.SYNOPSIS
Runs the VC runtime bootstrapper in quiet mode.

.DESCRIPTION
Starts the redistributable installer with silent arguments, waits for it to
finish, captures the generated log path, and enforces a caller-supplied
timeout.

.PARAMETER InstallerPath
Path to the VC runtime bootstrapper executable to launch.

.PARAMETER TimeoutSec
Maximum number of seconds to wait before terminating the installer.

.PARAMETER LocalRoot
Sandbox local root used to place the installer log file.

.EXAMPLE
Invoke-VCRuntimeInstaller -InstallerPath $installer.Path
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,

        [int]$TimeoutSec = 300,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.VCRuntimeCacheRoot | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $layout.VCRuntimeCacheRoot ("vc_redist.install.$timestamp.log")

    $argumentList = @(
        '/install',
        '/quiet',
        '/norestart',
        '/log',
        (Format-VCRuntimeProcessArgument -Value $logPath)
    )

    $process = Start-Process -FilePath $InstallerPath -ArgumentList $argumentList -PassThru
    if (-not $process.WaitForExit($TimeoutSec * 1000)) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
        }

        throw "VC++ redistributable installation exceeded the timeout of $TimeoutSec seconds. Check $logPath."
    }

    [pscustomobject]@{
        ExitCode        = $process.ExitCode
        LogPath         = $logPath
        RestartRequired = ($process.ExitCode -eq 3010)
    }
}

function Install-VCRuntime {
<#
.SYNOPSIS
Installs the VC runtime when the current machine is missing or behind.

.DESCRIPTION
Compares the installed VC++ redistributable with the cached installer version,
skips installation when the machine is already up to date, and otherwise runs
the installer and validates the result.

.PARAMETER InstallerInfo
Validated installer metadata for the VC runtime bootstrapper.

.PARAMETER InstallTimeoutSec
Maximum number of seconds to wait for the installer process.

.PARAMETER LocalRoot
Sandbox local root used for installer logging and cache resolution.

.EXAMPLE
Install-VCRuntime -InstallerInfo (Save-VCRuntimeInstaller)
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$InstallerInfo,

        [int]$InstallTimeoutSec = 300,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $installed = Get-InstalledVCRuntime

    if ($installed.Installed) {
        if (-not $InstallerInfo.VersionObject -or ($installed.VersionObject -and $installed.VersionObject -ge $InstallerInfo.VersionObject)) {
            return [pscustomobject]@{
                Action           = 'Skipped'
                Installed        = $true
                Architecture     = $installed.Architecture
                Version          = $installed.Version
                VersionObject    = $installed.VersionObject
                InstallerVersion = $InstallerInfo.Version
                InstallerPath    = $InstallerInfo.Path
                InstallerSource  = $InstallerInfo.Source
                ExitCode         = 0
                RestartRequired  = $false
                LogPath          = $null
            }
        }
    }

    Write-Host 'Installing Microsoft Visual C++ Redistributable prerequisites for the runtime...'
    $installResult = Invoke-VCRuntimeInstaller -InstallerPath $InstallerInfo.Path -TimeoutSec $InstallTimeoutSec -LocalRoot $LocalRoot
    $refreshed = Get-InstalledVCRuntime

    if (-not $refreshed.Installed) {
        throw "VC++ redistributable installation exited with code $($installResult.ExitCode), but the runtime was not detected afterwards. Check $($installResult.LogPath)."
    }

    if ($InstallerInfo.VersionObject -and $refreshed.VersionObject -and $refreshed.VersionObject -lt $InstallerInfo.VersionObject) {
        throw "VC++ redistributable installation completed, but version $($refreshed.Version) is still older than the cached installer version $($InstallerInfo.Version). Check $($installResult.LogPath)."
    }

    if ($installResult.ExitCode -notin @(0, 3010, 1638)) {
        throw "VC++ redistributable installation failed with exit code $($installResult.ExitCode). Check $($installResult.LogPath)."
    }

    [pscustomobject]@{
        Action           = 'Installed'
        Installed        = $true
        Architecture     = $refreshed.Architecture
        Version          = $refreshed.Version
        VersionObject    = $refreshed.VersionObject
        InstallerVersion = $InstallerInfo.Version
        InstallerPath    = $InstallerInfo.Path
        InstallerSource  = $InstallerInfo.Source
        ExitCode         = $installResult.ExitCode
        RestartRequired  = $installResult.RestartRequired
        LogPath          = $installResult.LogPath
    }
}

