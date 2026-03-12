<#
    Eigenverft.Manifested.Sandbox.VCRuntimeAndCache
#>

function ConvertTo-SandboxVCRuntimeVersion {
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

function Format-SandboxProcessArgument {
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

function Get-SandboxVCRuntimeInstallerInfo {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-SandboxDefaultLocalRoot)
    )

    $layout = Get-SandboxLayout -LocalRoot $LocalRoot

    [pscustomobject]@{
        Architecture = 'x64'
        FileName     = 'vc_redist.x64.exe'
        DownloadUrl  = 'https://aka.ms/vc14/vc_redist.x64.exe'
        CachePath    = (Join-Path $layout.VCRuntimeCacheRoot 'vc_redist.x64.exe')
    }
}

function Get-CachedSandboxVCRuntimeInstaller {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-SandboxDefaultLocalRoot)
    )

    $info = Get-SandboxVCRuntimeInstallerInfo -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $info.CachePath)) {
        return $null
    }

    $item = Get-Item -LiteralPath $info.CachePath
    $versionObject = ConvertTo-SandboxVCRuntimeVersion -VersionText $item.VersionInfo.FileVersion

    [pscustomobject]@{
        Architecture = $info.Architecture
        FileName     = $info.FileName
        Path         = $info.CachePath
        Version      = if ($versionObject) { $versionObject.ToString() } else { $item.VersionInfo.FileVersion }
        VersionObject = $versionObject
        LastWriteTime = $item.LastWriteTimeUtc
    }
}

function Get-InstalledSandboxVCRuntime {
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
                    $versionObject = ConvertTo-SandboxVCRuntimeVersion -VersionText $versionText

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
                            Installed   = $true
                            Architecture = 'x64'
                            Version     = $versionText
                            VersionObject = $versionObject
                            KeyPath     = $subKeyPath
                            RegistryView = $view.ToString()
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
        Installed    = $false
        Architecture = 'x64'
        Version      = $null
        VersionObject = $null
        KeyPath      = $null
        RegistryView = $null
    }
}

function Ensure-SandboxVCRuntimeInstaller {
    [CmdletBinding()]
    param(
        [switch]$RefreshVCRuntime,
        [string]$LocalRoot = (Get-SandboxDefaultLocalRoot)
    )

    $layout = Get-SandboxLayout -LocalRoot $LocalRoot
    $info = Get-SandboxVCRuntimeInstallerInfo -LocalRoot $LocalRoot
    Ensure-SandboxDirectory -Path $layout.VCRuntimeCacheRoot | Out-Null

    $cacheExists = Test-Path -LiteralPath $info.CachePath
    $source = if ($cacheExists) { 'cache' } else { $null }

    if ($RefreshVCRuntime -or -not $cacheExists) {
        $downloadPath = $info.CachePath + '.download'
        if (Test-Path -LiteralPath $downloadPath) {
            Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        }

        try {
            Write-Host 'Downloading Microsoft Visual C++ Redistributable bootstrapper...'
            Invoke-WebRequest -Uri $info.DownloadUrl -OutFile $downloadPath -UseBasicParsing
            Move-Item -LiteralPath $downloadPath -Destination $info.CachePath -Force
            $source = 'online'
        }
        catch {
            if (Test-Path -LiteralPath $downloadPath) {
                Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
            }

            if (-not $cacheExists) {
                throw
            }

            Write-Warning ('Could not refresh the VC++ redistributable bootstrapper. Using cached copy. ' + $_.Exception.Message)
            $source = 'cache'
        }
    }

    if (-not (Test-Path -LiteralPath $info.CachePath)) {
        throw 'Could not acquire the VC++ redistributable bootstrapper and no cached copy was found.'
    }

    $signature = Get-AuthenticodeSignature -FilePath $info.CachePath
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "The cached VC++ redistributable bootstrapper signature is $($signature.Status)."
    }

    if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        throw 'The cached VC++ redistributable bootstrapper is not signed by Microsoft Corporation.'
    }

    $cached = Get-CachedSandboxVCRuntimeInstaller -LocalRoot $LocalRoot

    [pscustomobject]@{
        Architecture  = $info.Architecture
        FileName      = $info.FileName
        DownloadUrl   = $info.DownloadUrl
        Path          = $info.CachePath
        Version       = if ($cached) { $cached.Version } else { $null }
        VersionObject = if ($cached) { $cached.VersionObject } else { $null }
        Source        = $source
    }
}

function Invoke-SandboxVCRuntimeInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,

        [int]$TimeoutSec = 300,

        [string]$LocalRoot = (Get-SandboxDefaultLocalRoot)
    )

    $layout = Get-SandboxLayout -LocalRoot $LocalRoot
    Ensure-SandboxDirectory -Path $layout.VCRuntimeCacheRoot | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $layout.VCRuntimeCacheRoot ("vc_redist.install.$timestamp.log")

    $argumentList = @(
        '/install',
        '/passive',
        '/norestart',
        '/log',
        (Format-SandboxProcessArgument -Value $logPath)
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

function Ensure-SandboxVCRuntime {
    [CmdletBinding()]
    param(
        [switch]$RefreshVCRuntime,
        [int]$InstallTimeoutSec = 300,
        [string]$LocalRoot = (Get-SandboxDefaultLocalRoot)
    )

    $installed = Get-InstalledSandboxVCRuntime
    $installer = Ensure-SandboxVCRuntimeInstaller -RefreshVCRuntime:$RefreshVCRuntime -LocalRoot $LocalRoot

    if ($installed.Installed) {
        if (-not $installer.VersionObject -or ($installed.VersionObject -and $installed.VersionObject -ge $installer.VersionObject)) {
            return [pscustomobject]@{
                Installed        = $true
                Architecture     = $installed.Architecture
                Version          = $installed.Version
                VersionObject    = $installed.VersionObject
                InstallerVersion = $installer.Version
                InstallerPath    = $installer.Path
                InstallerSource  = $installer.Source
                Action           = 'skipped'
                ExitCode         = 0
                RestartRequired  = $false
                LogPath          = $null
            }
        }
    }

    Write-Host 'Installing Microsoft Visual C++ Redistributable prerequisites for the sandbox...'
    $installResult = Invoke-SandboxVCRuntimeInstaller -InstallerPath $installer.Path -TimeoutSec $InstallTimeoutSec -LocalRoot $LocalRoot
    $refreshed = Get-InstalledSandboxVCRuntime

    if (-not $refreshed.Installed) {
        throw "VC++ redistributable installation exited with code $($installResult.ExitCode), but the runtime was not detected afterwards. Check $($installResult.LogPath)."
    }

    if ($installer.VersionObject -and $refreshed.VersionObject -and $refreshed.VersionObject -lt $installer.VersionObject) {
        throw "VC++ redistributable installation completed, but version $($refreshed.Version) is still older than the cached installer version $($installer.Version). Check $($installResult.LogPath)."
    }

    if ($installResult.ExitCode -notin @(0, 3010, 1638)) {
        throw "VC++ redistributable installation failed with exit code $($installResult.ExitCode). Check $($installResult.LogPath)."
    }

    [pscustomobject]@{
        Installed        = $true
        Architecture     = $refreshed.Architecture
        Version          = $refreshed.Version
        VersionObject    = $refreshed.VersionObject
        InstallerVersion = $installer.Version
        InstallerPath    = $installer.Path
        InstallerSource  = $installer.Source
        Action           = 'installed'
        ExitCode         = $installResult.ExitCode
        RestartRequired  = $installResult.RestartRequired
        LogPath          = $installResult.LogPath
    }
}
