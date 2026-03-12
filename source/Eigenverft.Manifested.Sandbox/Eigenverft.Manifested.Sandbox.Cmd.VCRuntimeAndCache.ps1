<#
    Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache
#>

function ConvertTo-VCRuntimeVersion {
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
            Invoke-WebRequest -Uri $info.DownloadUrl -OutFile $downloadPath -UseBasicParsing
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
        '/passive',
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

function Initialize-VCRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshVCRuntime,
        [int]$InstallTimeoutSec = 300
    )

    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $plannedActions = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $installerInfo = $null
    $installerTest = $null
    $installResult = $null

    $initialState = Get-VCRuntimeState -LocalRoot $LocalRoot
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-VCRuntime' -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $result = [pscustomobject]@{
            LocalRoot       = $state.LocalRoot
            Layout          = $state.Layout
            InitialState    = $initialState
            FinalState      = $state
            ActionTaken     = @('None')
            PlannedActions  = @()
            RestartRequired = $false
            Installer       = $null
            InstallerTest   = $null
            RuntimeTest     = $null
            RepairResult    = $null
            InstallResult   = $null
            Elevation       = $elevationPlan
        }

        if ($WhatIfPreference) {
            Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
            return $result
        }

        $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-VCRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
            Version       = $state.CurrentVersion
            InstallerPath = $state.InstallerPath
        }
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force
        return $result
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $RefreshVCRuntime -or ($state.Status -ne 'Ready')
    $needsAcquire = $RefreshVCRuntime -or (-not $state.InstallerPath) -or (-not (Test-Path -LiteralPath $state.InstallerPath))

    if ($needsRepair) {
        $plannedActions.Add('Repair-VCRuntime') | Out-Null
    }
    if ($needsInstall -and $needsAcquire) {
        $plannedActions.Add('Save-VCRuntimeInstaller') | Out-Null
    }
    if ($needsInstall) {
        $plannedActions.Add('Test-VCRuntimeInstaller') | Out-Null
        $plannedActions.Add('Install-VCRuntime') | Out-Null
    }

    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-VCRuntime' -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.InstallerPath, 'Repair VC runtime state')) {
            return [pscustomobject]@{
                LocalRoot          = $state.LocalRoot
                Layout             = $state.Layout
                InitialState       = $initialState
                FinalState         = $state
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                Installer          = $null
                InstallerTest      = $null
                RuntimeTest        = $state.Runtime
                RepairResult       = $null
                InstallResult      = $null
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $repairResult = Repair-VCRuntime -State $state -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add('Repair-VCRuntime') | Out-Null
        }

        $state = Get-VCRuntimeState -LocalRoot $state.LocalRoot
        $needsInstall = $RefreshVCRuntime -or ($state.Status -ne 'Ready')
        $needsAcquire = $RefreshVCRuntime -or (-not $state.InstallerPath) -or (-not (Test-Path -LiteralPath $state.InstallerPath))
    }

    if ($needsInstall) {
        if ($needsAcquire) {
            if (-not $PSCmdlet.ShouldProcess($state.Layout.VCRuntimeCacheRoot, 'Acquire VC runtime installer')) {
                return [pscustomobject]@{
                    LocalRoot          = $state.LocalRoot
                    Layout             = $state.Layout
                    InitialState       = $initialState
                    FinalState         = $state
                    ActionTaken        = @('WhatIf')
                    PlannedActions     = @($plannedActions)
                    RestartRequired    = $false
                    Installer          = $null
                    InstallerTest      = $null
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $repairResult
                    InstallResult      = $null
                    PersistedStatePath = $null
                    Elevation          = $elevationPlan
                }
            }

            $installerInfo = Save-VCRuntimeInstaller -RefreshVCRuntime:$RefreshVCRuntime -LocalRoot $state.LocalRoot
            if ($installerInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-VCRuntimeInstaller') | Out-Null
            }
        }
        else {
            $installerInfo = $state.Installer
        }

        $installerTest = Test-VCRuntimeInstaller -InstallerInfo $installerInfo
        if ($installerTest.Status -eq 'CorruptCache') {
            if (-not $PSCmdlet.ShouldProcess($installerInfo.Path, 'Repair corrupt VC runtime installer')) {
                return [pscustomobject]@{
                    LocalRoot          = $state.LocalRoot
                    Layout             = $state.Layout
                    InitialState       = $initialState
                    FinalState         = $state
                    ActionTaken        = @('WhatIf')
                    PlannedActions     = @($plannedActions)
                    RestartRequired    = $false
                    Installer          = $installerInfo
                    InstallerTest      = $installerTest
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $repairResult
                    InstallResult      = $null
                    PersistedStatePath = $null
                    Elevation          = $elevationPlan
                }
            }

            $repairResult = Repair-VCRuntime -State $state -CorruptInstallerPaths @($installerInfo.Path) -LocalRoot $state.LocalRoot
            if ($repairResult.Action -eq 'Repaired') {
                $actionsTaken.Add('Repair-VCRuntime') | Out-Null
            }

            $installerInfo = Save-VCRuntimeInstaller -RefreshVCRuntime:$true -LocalRoot $state.LocalRoot
            if ($installerInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-VCRuntimeInstaller') | Out-Null
            }

            $installerTest = Test-VCRuntimeInstaller -InstallerInfo $installerInfo
        }

        if ($installerTest.Status -ne 'Ready') {
            throw "VC runtime installer validation failed with status $($installerTest.Status)."
        }

        $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-VCRuntime' -PlannedActions @($plannedActions) -Context @{
            InstalledRuntime = $state.InstalledRuntime
            InstallerInfo    = $installerInfo
        } -LocalRoot $state.LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

        $commandParameters = @{
            InstallTimeoutSec = $InstallTimeoutSec
        }
        if ($RefreshVCRuntime) {
            $commandParameters['RefreshVCRuntime'] = $true
        }
        if ($PSBoundParameters.ContainsKey('WhatIf')) {
            $commandParameters['WhatIf'] = $true
        }

        $elevatedResult = Invoke-ManifestedElevatedCommand -ElevationPlan $elevationPlan -CommandName 'Initialize-VCRuntime' -CommandParameters $commandParameters
        if ($null -ne $elevatedResult) {
            return $elevatedResult
        }

        if (-not $PSCmdlet.ShouldProcess('Microsoft Visual C++ Redistributable (x64)', 'Install VC runtime')) {
            return [pscustomobject]@{
                LocalRoot          = $state.LocalRoot
                Layout             = $state.Layout
                InitialState       = $initialState
                FinalState         = $state
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                Installer          = $installerInfo
                InstallerTest      = $installerTest
                RuntimeTest        = $state.Runtime
                RepairResult       = $repairResult
                InstallResult      = $null
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $installResult = Install-VCRuntime -InstallerInfo $installerInfo -InstallTimeoutSec $InstallTimeoutSec -LocalRoot $state.LocalRoot
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add('Install-VCRuntime') | Out-Null
        }
    }

    $finalState = Get-VCRuntimeState -LocalRoot $state.LocalRoot
    $runtimeTest = Test-VCRuntime -InstalledRuntime $finalState.InstalledRuntime

    $result = [pscustomobject]@{
        LocalRoot       = $finalState.LocalRoot
        Layout          = $finalState.Layout
        InitialState    = $initialState
        FinalState      = $finalState
        ActionTaken     = if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }
        PlannedActions  = @($plannedActions)
        RestartRequired = if ($installResult) { [bool]$installResult.RestartRequired } else { $false }
        Installer       = $installerInfo
        InstallerTest   = $installerTest
        RuntimeTest     = $runtimeTest
        RepairResult    = $repairResult
        InstallResult   = $installResult
        Elevation       = $elevationPlan
    }

    if ($WhatIfPreference) {
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
        return $result
    }

    $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-VCRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
        Version       = $finalState.CurrentVersion
        InstallerPath = $finalState.InstallerPath
    }
    Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force

    return $result
}
