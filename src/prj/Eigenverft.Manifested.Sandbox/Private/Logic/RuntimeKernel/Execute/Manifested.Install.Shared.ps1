function Get-ManifestedRuntimeDependencyFacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeName,

        [string]$LocalRoot = (Get-ManifestedLocalRoot),

        [hashtable]$FactsCache = @{}
    )

    $dependencyContext = Get-ManifestedRuntimeContext -RuntimeName $RuntimeName
    if (-not $dependencyContext) {
        return $null
    }

    return (Get-ManifestedRuntimeFactsFromContext -Context $dependencyContext -LocalRoot $LocalRoot -FactsCache $FactsCache)
}

function Invoke-ManifestedPortableArchiveInstallFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $packageInfo = if ($Facts.PSObject.Properties['Package']) { $Facts.Package } else { $null }
    if (-not $packageInfo) {
        throw "The package for '$($Definition.commandName)' was not available for install."
    }

    $factsBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'portableRuntime'
    $installBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'portableArchive'
    if (-not $factsBlock -or -not $installBlock) {
        throw "The portable archive install blocks for '$($Definition.commandName)' were not available."
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $toolsRoot = $layout.($installBlock.toolsRootLayoutProperty)
    $versionFolderName = Expand-ManifestedDefinitionTemplate -Template $(if ($installBlock.PSObject.Properties.Match('versionFolderTemplate').Count -gt 0) { $installBlock.versionFolderTemplate } else { '{version}' }) -Version $packageInfo.Version -TagName $packageInfo.Version -Flavor $null
    $versionFolderName = $versionFolderName.Replace('{versionNoPrefixV}', $packageInfo.Version.TrimStart('v', 'V'))
    $runtimeHome = Join-Path (Join-Path $toolsRoot $versionFolderName) $Facts.Flavor
    $currentValidation = Test-ManifestedPortableRuntimeHome -Definition $Definition -RuntimeHome $runtimeHome

    if (-not $currentValidation.IsUsable) {
        New-ManifestedDirectory -Path (Split-Path -Parent $runtimeHome) | Out-Null

        $stagePrefix = if ($installBlock.PSObject.Properties.Match('stagePrefix').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($installBlock.stagePrefix)) { [string]$installBlock.stagePrefix } else { [string]$factsBlock.stagePrefix }
        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $packageInfo.Path -Prefix $stagePrefix
            if (-not (Test-Path -LiteralPath $stageInfo.ExpandedRoot)) {
                throw "The archive for '$($Definition.commandName)' did not extract as expected."
            }

            if (Test-Path -LiteralPath $runtimeHome) {
                Remove-ManifestedPath -Path $runtimeHome | Out-Null
            }

            New-ManifestedDirectory -Path $runtimeHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $runtimeHome -Force
            }

            foreach ($relativeDirectory in @($installBlock.createDirectories)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$relativeDirectory)) {
                    New-ManifestedDirectory -Path (Join-Path $runtimeHome ([string]$relativeDirectory)) | Out-Null
                }
            }
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $validation = Test-ManifestedPortableRuntimeHome -Definition $Definition -RuntimeHome $runtimeHome
    if (-not $validation.IsUsable) {
        throw "$($Definition.runtimeName) validation failed after install at $runtimeHome."
    }

    $result = [ordered]@{
        Action         = if ($currentValidation.IsUsable) { 'Skipped' } else { 'Installed' }
        Version        = $packageInfo.Version
        Flavor         = $Facts.Flavor
        RuntimeHome    = $runtimeHome
        ExecutablePath = $validation.ExecutablePath
        Source         = $packageInfo.Source
        DownloadUrl    = if ($packageInfo.PSObject.Properties['DownloadUrl']) { $packageInfo.DownloadUrl } else { $null }
        Sha256         = if ($packageInfo.PSObject.Properties['Sha256']) { $packageInfo.Sha256 } else { $null }
    }
    foreach ($property in @($validation.PSObject.Properties)) {
        if ($result.Contains($property.Name)) {
            continue
        }
        $result[$property.Name] = $property.Value
    }

    return [pscustomobject]$result
}

function Invoke-ManifestedPythonEmbeddableInstallFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [bool]$RefreshRequested = $false,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $packageInfo = if ($Facts.PSObject.Properties['Package']) { $Facts.Package } else { $null }
    if (-not $packageInfo) {
        throw "The package for '$($Definition.commandName)' was not available for install."
    }

    return (Install-ManifestedPythonEmbeddableRuntime -Definition $Definition -PackageInfo $packageInfo -Flavor $Facts.Flavor -LocalRoot $LocalRoot -ForceInstall:$RefreshRequested)
}

function Invoke-ManifestedMachineInstallerProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,

        [int]$TimeoutSec = 300
    )

    $logDirectory = Split-Path -Parent $InstallerPath
    if (-not [string]::IsNullOrWhiteSpace($logDirectory)) {
        New-ManifestedDirectory -Path $logDirectory | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPrefix = [System.IO.Path]::GetFileNameWithoutExtension($InstallerPath)
    if ([string]::IsNullOrWhiteSpace($logPrefix)) {
        $logPrefix = 'installer'
    }

    $logPath = Join-Path $logDirectory ($logPrefix + ".install.$timestamp.log")
    $quotedLogPath = if ($logPath.IndexOfAny([char[]]@(' ', "`t", '"')) -ge 0) {
        '"' + ($logPath -replace '"', '\"') + '"'
    }
    else {
        $logPath
    }

    $argumentList = @(
        '/install',
        '/quiet',
        '/norestart',
        '/log',
        $quotedLogPath
    )

    $process = Start-Process -FilePath $InstallerPath -ArgumentList $argumentList -PassThru
    if (-not $process.WaitForExit($TimeoutSec * 1000)) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
        }

        throw "Installer execution exceeded the timeout of $TimeoutSec seconds. Check $logPath."
    }

    return [pscustomobject]@{
        ExitCode        = $process.ExitCode
        LogPath         = $logPath
        RestartRequired = ($process.ExitCode -eq 3010)
    }
}

function Invoke-ManifestedMachineInstallerFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [hashtable]$CommandOptions = @{},

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $installerInfo = if ($Facts.PSObject.Properties['Artifact'] -and $Facts.Artifact) { $Facts.Artifact } elseif ($Facts.PSObject.Properties['Installer'] -and $Facts.Installer) { $Facts.Installer } else { $null }
    if (-not $installerInfo) {
        throw "The installer for '$($Definition.commandName)' was not available."
    }
    $installerInfo = Get-ManifestedMachineInstallerInfoFromDefinition -Definition $Definition -Artifact $installerInfo -LocalRoot $LocalRoot
    if ([string]::IsNullOrWhiteSpace($installerInfo.Path) -or -not (Test-Path -LiteralPath $installerInfo.Path)) {
        throw "The installer for '$($Definition.commandName)' was not available on disk."
    }

    $timeoutSec = 300
    if ($CommandOptions.ContainsKey('InstallTimeoutSec') -and $CommandOptions['InstallTimeoutSec']) {
        $timeoutSec = [int]$CommandOptions['InstallTimeoutSec']
    }

    $installed = Get-ManifestedInstalledMachinePrerequisiteRuntime -Definition $Definition
    if ($installed.Installed) {
        if (-not $installerInfo.VersionObject -or ($installed.VersionObject -and $installed.VersionObject -ge $installerInfo.VersionObject)) {
            return [pscustomobject]@{
                Action           = 'Skipped'
                Installed        = $true
                Architecture     = $installed.Architecture
                Version          = $installed.Version
                VersionObject    = $installed.VersionObject
                InstallerVersion = $installerInfo.Version
                InstallerPath    = $installerInfo.Path
                InstallerSource  = $installerInfo.Source
                ExitCode         = 0
                RestartRequired  = $false
                LogPath          = $null
            }
        }
    }

    Write-Host ('Installing machine prerequisites for ' + $Definition.runtimeName + '...')
    $installResult = Invoke-ManifestedMachineInstallerProcess -InstallerPath $installerInfo.Path -TimeoutSec $timeoutSec
    $refreshed = Get-ManifestedInstalledMachinePrerequisiteRuntime -Definition $Definition

    if (-not $refreshed.Installed) {
        throw "$($Definition.runtimeName) installation exited with code $($installResult.ExitCode), but the prerequisite was not detected afterwards. Check $($installResult.LogPath)."
    }

    if ($installerInfo.VersionObject -and $refreshed.VersionObject -and $refreshed.VersionObject -lt $installerInfo.VersionObject) {
        throw "$($Definition.runtimeName) installation completed, but version $($refreshed.Version) is still older than installer version $($installerInfo.Version). Check $($installResult.LogPath)."
    }

    if ($installResult.ExitCode -notin @(0, 3010, 1638)) {
        throw "$($Definition.runtimeName) installation failed with exit code $($installResult.ExitCode). Check $($installResult.LogPath)."
    }

    return [pscustomobject]@{
        Action           = 'Installed'
        Installed        = $true
        Architecture     = $refreshed.Architecture
        Version          = $refreshed.Version
        VersionObject    = $refreshed.VersionObject
        InstallerVersion = $installerInfo.Version
        InstallerPath    = $installerInfo.Path
        InstallerSource  = $installerInfo.Source
        ExitCode         = $installResult.ExitCode
        RestartRequired  = $installResult.RestartRequired
        LogPath          = $installResult.LogPath
    }
}

function Install-ManifestedRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [bool]$RefreshRequested = $false,

        [hashtable]$CommandOptions = @{},

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'portableArchive') {
        return (Invoke-ManifestedPortableArchiveInstallFromDefinition -Definition $Definition -Facts $Facts -LocalRoot $LocalRoot)
    }
    if (Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'pythonEmbeddableZip') {
        return (Invoke-ManifestedPythonEmbeddableInstallFromDefinition -Definition $Definition -Facts $Facts -RefreshRequested:$RefreshRequested -LocalRoot $LocalRoot)
    }
    if (Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'machineInstaller') {
        return (Invoke-ManifestedMachineInstallerFromDefinition -Definition $Definition -Facts $Facts -CommandOptions $CommandOptions -LocalRoot $LocalRoot)
    }
    if (Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'npmGlobalPackage') {
        return (Invoke-ManifestedNpmGlobalPackageInstallFromDefinition -Definition $Definition -Facts $Facts -LocalRoot $LocalRoot)
    }

    throw "No install function is defined for '$($Definition.commandName)'."
}
