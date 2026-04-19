<#
    Eigenverft.Manifested.Sandbox.PackageModel.Install
#>

function Resolve-PackageModelExistingInstallRoot {
<#
.SYNOPSIS
Resolves an install directory from a discovered existing-install candidate path.

.DESCRIPTION
Uses the existing-install root rules to turn a discovered file path such as
`code.cmd` into the install directory that owns that file.

.PARAMETER ExistingInstallDiscovery
The existing-install discovery definition object.

.PARAMETER CandidatePath
The discovered file or directory path.

.EXAMPLE
Resolve-PackageModelExistingInstallRoot -ExistingInstallDiscovery $package.existingInstallDiscovery -CandidatePath $candidatePath
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$ExistingInstallDiscovery,

        [Parameter(Mandatory = $true)]
        [string]$CandidatePath
    )

    if (Test-Path -LiteralPath $CandidatePath -PathType Container) {
        return (Resolve-Path -LiteralPath $CandidatePath -ErrorAction Stop).Path
    }

    $leafName = Split-Path -Leaf $CandidatePath
    foreach ($rule in @($ExistingInstallDiscovery.installRootRules)) {
        if (-not $rule.PSObject.Properties['match'] -or $null -eq $rule.match) {
            continue
        }

        $matchKind = if ($rule.match.PSObject.Properties['kind']) { [string]$rule.match.kind } else { $null }
        $matchValue = if ($rule.match.PSObject.Properties['value']) { [string]$rule.match.value } else { $null }
        if ([string]::Equals($matchKind, 'fileName', [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($matchValue, $leafName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $candidateDirectory = Split-Path -Parent $CandidatePath
            $installRootRelativePath = if ($rule.PSObject.Properties['installRootRelativePath']) { [string]$rule.installRootRelativePath } else { '.' }
            return [System.IO.Path]::GetFullPath((Join-Path $candidateDirectory $installRootRelativePath))
        }
    }

    return (Split-Path -Parent $CandidatePath)
}

function Find-PackageModelExistingPackage {
<#
.SYNOPSIS
Finds an existing package install that may be reused or adopted.

.DESCRIPTION
Searches command, path, and directory candidates from the release
existingInstallDiscovery block and attaches the first matching install
directory to the PackageModel result.

.PARAMETER PackageModelResult
The PackageModel result object to enrich.

.EXAMPLE
Find-PackageModelExistingPackage -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $package = $PackageModelResult.Package
    if (-not $package -or -not $package.PSObject.Properties['existingInstallDiscovery'] -or $null -eq $package.existingInstallDiscovery) {
        return $PackageModelResult
    }

    $existingInstallDiscovery = $package.existingInstallDiscovery
    if ($existingInstallDiscovery.PSObject.Properties['enableDetection'] -and (-not [bool]$existingInstallDiscovery.enableDetection)) {
        return $PackageModelResult
    }

    foreach ($searchLocation in @($existingInstallDiscovery.searchLocations)) {
        $candidatePath = $null
        switch -Exact ([string]$searchLocation.kind) {
            'command' {
                if (-not $searchLocation.PSObject.Properties['name'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.name)) {
                    throw "PackageModel existingInstallDiscovery search for release '$($package.id)' is missing command name."
                }
                $candidatePath = Get-ManifestedResolvedApplicationPath -CommandName ([string]$searchLocation.name)
            }
            'path' {
                if (-not $searchLocation.PSObject.Properties['path'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.path)) {
                    throw "PackageModel existingInstallDiscovery search for release '$($package.id)' is missing path."
                }
                $resolvedPath = Resolve-PackageModelPathValue -PathValue ([string]$searchLocation.path)
                if (Test-Path -LiteralPath $resolvedPath) {
                    $candidatePath = $resolvedPath
                }
            }
            'directory' {
                if (-not $searchLocation.PSObject.Properties['path'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.path)) {
                    throw "PackageModel existingInstallDiscovery search for release '$($package.id)' is missing directory path."
                }
                $resolvedPath = Resolve-PackageModelPathValue -PathValue ([string]$searchLocation.path)
                if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
                    $candidatePath = $resolvedPath
                }
            }
            default {
                throw "Unsupported PackageModel existingInstallDiscovery search kind '$($searchLocation.kind)'."
            }
        }

        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            continue
        }

        $installDirectory = Resolve-PackageModelExistingInstallRoot -ExistingInstallDiscovery $existingInstallDiscovery -CandidatePath $candidatePath
        if (-not (Test-Path -LiteralPath $installDirectory -PathType Container)) {
            continue
        }

        $PackageModelResult.ExistingPackage = [pscustomobject]@{
            SearchKind       = $searchLocation.kind
            CandidatePath    = $candidatePath
            InstallDirectory = $installDirectory
            Decision         = 'Pending'
            Validation       = $null
            Classification   = $null
            OwnershipRecord  = $null
        }
        return $PackageModelResult
    }

    return $PackageModelResult
}

function Resolve-PackageModelExistingPackageDecision {
<#
.SYNOPSIS
Evaluates how PackageModel should react to a discovered existing install.

.DESCRIPTION
Validates the discovered install, combines the result with ownership
classification and release-specific policy switches, and records whether the
current run should reuse, adopt, ignore, or replace the install.

.PARAMETER PackageModelResult
The PackageModel result object to enrich.

.EXAMPLE
Resolve-PackageModelExistingPackageDecision -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    if (-not $PackageModelResult.ExistingPackage) {
        return $PackageModelResult
    }

    $package = $PackageModelResult.Package
    $existingInstallPolicy = if ($package.PSObject.Properties['existingInstallPolicy']) { $package.existingInstallPolicy } else { [pscustomobject]@{} }
    $originalInstallDirectory = $PackageModelResult.InstallDirectory
    $PackageModelResult.InstallDirectory = $PackageModelResult.ExistingPackage.InstallDirectory
    $PackageModelResult = Test-PackageModelInstalledPackage -PackageModelResult $PackageModelResult
    $PackageModelResult.ExistingPackage.Validation = $PackageModelResult.Validation

    if (-not $PackageModelResult.Validation.Accepted) {
        $PackageModelResult.ExistingPackage.Decision = 'ExistingInstallValidationFailed'
        $PackageModelResult.InstallDirectory = $originalInstallDirectory
        $PackageModelResult.Validation = $null
        return $PackageModelResult
    }

    $ownershipRecord = if ($PackageModelResult.Ownership -and $PackageModelResult.Ownership.OwnershipRecord) {
        $PackageModelResult.Ownership.OwnershipRecord
    }
    else {
        $null
    }

    $classification = if ($PackageModelResult.Ownership -and $PackageModelResult.Ownership.Classification) {
        [string]$PackageModelResult.Ownership.Classification
    }
    else {
        'ExternalInstall'
    }

    $allowAdoptExternal = $false
    if ($existingInstallPolicy.PSObject.Properties['allowAdoptExternal']) {
        $allowAdoptExternal = [bool]$existingInstallPolicy.allowAdoptExternal
    }

    $upgradeAdoptedInstall = $false
    if ($existingInstallPolicy.PSObject.Properties['upgradeAdoptedInstall']) {
        $upgradeAdoptedInstall = [bool]$existingInstallPolicy.upgradeAdoptedInstall
    }

    $requireManagedOwnership = $false
    if ($existingInstallPolicy.PSObject.Properties['requireManagedOwnership']) {
        $requireManagedOwnership = [bool]$existingInstallPolicy.requireManagedOwnership
    }

    $sameRelease = $false
    if ($ownershipRecord) {
        $sameRelease = [string]::Equals([string]$ownershipRecord.currentReleaseId, [string]$PackageModelResult.PackageId, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$ownershipRecord.currentVersion, [string]$PackageModelResult.PackageVersion, [System.StringComparison]::OrdinalIgnoreCase)
    }

    if ([string]::Equals($classification, 'ManagedByPackageModel', [System.StringComparison]::OrdinalIgnoreCase) -and $ownershipRecord) {
        if ([string]::Equals([string]$ownershipRecord.ownershipKind, 'AdoptedExternal', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($sameRelease -or (-not $upgradeAdoptedInstall)) {
                $PackageModelResult.ExistingPackage.Decision = 'AdoptExternal'
                $PackageModelResult.InstallOrigin = 'AdoptedExternal'
                return $PackageModelResult
            }

            $PackageModelResult.ExistingPackage.Decision = 'UpgradeAdoptedInstall'
            $PackageModelResult.InstallDirectory = $originalInstallDirectory
            $PackageModelResult.Validation = $null
            return $PackageModelResult
        }

        if ($sameRelease) {
            $PackageModelResult.ExistingPackage.Decision = 'ReuseManaged'
            $PackageModelResult.InstallOrigin = 'ManagedReused'
            return $PackageModelResult
        }

        $PackageModelResult.ExistingPackage.Decision = 'UpgradeManagedInstall'
        $PackageModelResult.InstallDirectory = $originalInstallDirectory
        $PackageModelResult.Validation = $null
        return $PackageModelResult
    }

    if ($requireManagedOwnership) {
        $PackageModelResult.ExistingPackage.Decision = 'ExternalIgnored'
        $PackageModelResult.InstallDirectory = $originalInstallDirectory
        $PackageModelResult.Validation = $null
        return $PackageModelResult
    }

    if ($allowAdoptExternal) {
        $PackageModelResult.ExistingPackage.Decision = 'AdoptExternal'
        $PackageModelResult.InstallOrigin = 'AdoptedExternal'
        return $PackageModelResult
    }

    $PackageModelResult.ExistingPackage.Decision = 'ExternalIgnored'
    $PackageModelResult.InstallDirectory = $originalInstallDirectory
    $PackageModelResult.Validation = $null
    return $PackageModelResult
}

function Install-PackageModelArchive {
<#
.SYNOPSIS
Installs a package by expanding an archive into the install directory.

.DESCRIPTION
Expands the saved package file into a stage directory, promotes the expanded
root into the final install directory, and creates any extra directories that
the install block requests.

.PARAMETER PackageModelResult
The PackageModel result object to install.

.EXAMPLE
Install-PackageModelArchive -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    if ([string]::IsNullOrWhiteSpace($PackageModelResult.PackageFilePath) -or -not (Test-Path -LiteralPath $PackageModelResult.PackageFilePath)) {
        throw "PackageModel archive install for '$($PackageModelResult.PackageId)' requires a saved package file."
    }

    $install = $PackageModelResult.Package.install
    $stageInfo = $null
    try {
        $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageModelResult.PackageFilePath -Prefix 'packagemodel'
        $expandedRoot = $stageInfo.ExpandedRoot
        if ($install.PSObject.Properties['expandedRoot'] -and
            -not [string]::IsNullOrWhiteSpace([string]$install.expandedRoot) -and
            [string]$install.expandedRoot -ne 'auto') {
            $expandedRoot = Join-Path $stageInfo.StagePath (([string]$install.expandedRoot) -replace '/', '\')
        }

        if (-not (Test-Path -LiteralPath $expandedRoot -PathType Container)) {
            throw "Expanded package root '$expandedRoot' was not found for '$($PackageModelResult.PackageId)'."
        }

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $PackageModelResult.InstallDirectory) -Force
        if (Test-Path -LiteralPath $PackageModelResult.InstallDirectory) {
            Remove-Item -LiteralPath $PackageModelResult.InstallDirectory -Recurse -Force
        }

        New-Item -ItemType Directory -Path $PackageModelResult.InstallDirectory -Force | Out-Null
        Get-ChildItem -LiteralPath $expandedRoot -Force | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination $PackageModelResult.InstallDirectory -Force
        }

        foreach ($relativePath in @($install.createDirectories)) {
            $targetDirectory = Join-Path $PackageModelResult.InstallDirectory (([string]$relativePath) -replace '/', '\')
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
    }
    finally {
        if ($stageInfo) {
            Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
        }
    }

    return [pscustomobject]@{
        Status           = 'Installed'
        InstallKind      = 'expandArchive'
        InstallDirectory = $PackageModelResult.InstallDirectory
        ReusedExisting   = $false
    }
}

function Invoke-PackageModelInstallerProcess {
<#
.SYNOPSIS
Runs an installer-style package command and waits for completion.

.DESCRIPTION
Starts the configured installer command, applies timeout and exit-code rules,
and returns the install log path and restart flag when configured.

.PARAMETER PackageModelResult
The PackageModel result object that owns the install.

.EXAMPLE
Invoke-PackageModelInstallerProcess -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $install = $PackageModelResult.Package.install
    $commandPath = if ($install.PSObject.Properties['commandPath'] -and -not [string]::IsNullOrWhiteSpace([string]$install.commandPath)) {
        Resolve-PackageModelTemplateText -Text ([string]$install.commandPath) -PackageModelConfig $PackageModelResult.PackageModelConfig -Package $PackageModelResult.Package
    }
    else {
        $PackageModelResult.PackageFilePath
    }

    $timestamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
    $logPath = $null
    if ($install.PSObject.Properties['logRelativePath'] -and -not [string]::IsNullOrWhiteSpace([string]$install.logRelativePath)) {
        $logRelativePath = Resolve-PackageModelTemplateText -Text ([string]$install.logRelativePath) -PackageModelConfig $PackageModelResult.PackageModelConfig -Package $PackageModelResult.Package -ExtraTokens @{ timestamp = $timestamp }
        $logPath = [System.IO.Path]::GetFullPath((Join-Path $PackageModelResult.PackageModelConfig.PreferredTargetInstallRootDirectory ($logRelativePath -replace '/', '\')))
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force
    }

    $commandArguments = @()
    foreach ($argument in @($install.commandArguments)) {
        $commandArguments += (Resolve-PackageModelTemplateText -Text ([string]$argument) -PackageModelConfig $PackageModelResult.PackageModelConfig -Package $PackageModelResult.Package -ExtraTokens @{
                packageFilePath   = $PackageModelResult.PackageFilePath
                installDirectory  = $PackageModelResult.InstallDirectory
                installWorkspaceDirectory = $PackageModelResult.InstallWorkspaceDirectory
                downloadDirectory = $PackageModelResult.InstallWorkspaceDirectory
                logPath           = $logPath
                timestamp         = $timestamp
            })
    }

    $timeoutSec = if ($install.PSObject.Properties['timeoutSec']) { [int]$install.timeoutSec } else { 300 }
    $successExitCodes = if ($install.PSObject.Properties['successExitCodes']) { @($install.successExitCodes | ForEach-Object { [int]$_ }) } else { @(0) }
    $restartExitCodes = if ($install.PSObject.Properties['restartExitCodes']) { @($install.restartExitCodes | ForEach-Object { [int]$_ }) } else { @() }

    $null = New-Item -ItemType Directory -Path $PackageModelResult.InstallDirectory -Force
    $process = Start-Process -FilePath $commandPath -ArgumentList $commandArguments -WorkingDirectory $PackageModelResult.InstallDirectory -PassThru
    if (-not $process.WaitForExit($timeoutSec * 1000)) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
        }

        throw "PackageModel installer command exceeded the timeout of $timeoutSec seconds."
    }

    $process.Refresh()
    $exitCode = [int]$process.ExitCode
    $acceptedExitCodes = @($successExitCodes) + @($restartExitCodes)
    if ($exitCode -notin $acceptedExitCodes) {
        throw "PackageModel installer command failed with exit code $exitCode."
    }

    return [pscustomobject]@{
        ExitCode         = $exitCode
        RestartRequired  = ($exitCode -in $restartExitCodes)
        LogPath          = $logPath
        CommandPath      = $commandPath
        CommandArguments = @($commandArguments)
    }
}

function Install-PackageModelPackageManagerPackage {
<#
.SYNOPSIS
Installs a package through a package-manager command.

.DESCRIPTION
Runs the configured package-manager command with tokenized arguments and uses
the install directory as the default working directory.

.PARAMETER PackageModelResult
The PackageModel result object to install.

.EXAMPLE
Install-PackageModelPackageManagerPackage -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $install = $PackageModelResult.Package.install
    if (-not $install.PSObject.Properties['managerCommandPath'] -or [string]::IsNullOrWhiteSpace([string]$install.managerCommandPath)) {
        throw "PackageModel package-manager install for '$($PackageModelResult.PackageId)' requires install.managerCommandPath."
    }

    $managerCommandPath = Resolve-PackageModelTemplateText -Text ([string]$install.managerCommandPath) -PackageModelConfig $PackageModelResult.PackageModelConfig -Package $PackageModelResult.Package
    $commandArguments = @()
    foreach ($argument in @($install.commandArguments)) {
        $commandArguments += (Resolve-PackageModelTemplateText -Text ([string]$argument) -PackageModelConfig $PackageModelResult.PackageModelConfig -Package $PackageModelResult.Package -ExtraTokens @{
                packageSpec      = if ($install.PSObject.Properties['packageSpec']) { [string]$install.packageSpec } else { $null }
                packageFilePath  = $PackageModelResult.PackageFilePath
                installDirectory = $PackageModelResult.InstallDirectory
                installWorkspaceDirectory = $PackageModelResult.InstallWorkspaceDirectory
                downloadDirectory = $PackageModelResult.InstallWorkspaceDirectory
            })
    }

    $null = New-Item -ItemType Directory -Path $PackageModelResult.InstallDirectory -Force
    Push-Location $PackageModelResult.InstallDirectory
    try {
        & $managerCommandPath @commandArguments
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
    }
    finally {
        Pop-Location
    }

    $successExitCodes = if ($install.PSObject.Properties['successExitCodes']) { @($install.successExitCodes | ForEach-Object { [int]$_ }) } else { @(0) }
    if ($exitCode -notin $successExitCodes) {
        throw "PackageModel package-manager install failed with exit code $exitCode."
    }

    return [pscustomobject]@{
        Status           = 'Installed'
        InstallKind      = 'packageManagerInstall'
        InstallDirectory = $PackageModelResult.InstallDirectory
        ReusedExisting   = $false
        CommandPath      = $managerCommandPath
        CommandArguments = @($commandArguments)
        ExitCode         = $exitCode
    }
}

function Install-PackageModelPackage {
<#
.SYNOPSIS
Installs or reuses the selected package.

.DESCRIPTION
Reuses or adopts a valid existing install when the earlier ownership/policy
decision allows it, otherwise executes the configured install kind and attaches
the install result to the PackageModel result object.

.PARAMETER PackageModelResult
The PackageModel result object to enrich.

.EXAMPLE
Install-PackageModelPackage -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $package = $PackageModelResult.Package
    $install = $package.install
    if (-not $install -or -not $install.PSObject.Properties['kind']) {
        throw "PackageModel release '$($package.id)' does not define install.kind."
    }

    if ($PackageModelResult.ExistingPackage -and $PackageModelResult.ExistingPackage.Decision -eq 'ReuseManaged') {
        $PackageModelResult.InstallDirectory = $PackageModelResult.ExistingPackage.InstallDirectory
        $PackageModelResult.InstallOrigin = 'ManagedReused'
        $PackageModelResult.Install = [pscustomobject]@{
            Status           = 'ReusedManaged'
            InstallKind      = 'existingInstall'
            InstallDirectory = $PackageModelResult.ExistingPackage.InstallDirectory
            ReusedExisting   = $true
            CandidatePath    = $PackageModelResult.ExistingPackage.CandidatePath
        }
        $PackageModelResult.Validation = $PackageModelResult.ExistingPackage.Validation
        return $PackageModelResult
    }

    if ($PackageModelResult.ExistingPackage -and $PackageModelResult.ExistingPackage.Decision -eq 'AdoptExternal') {
        $PackageModelResult.InstallDirectory = $PackageModelResult.ExistingPackage.InstallDirectory
        $PackageModelResult.InstallOrigin = 'AdoptedExternal'
        $PackageModelResult.Install = [pscustomobject]@{
            Status           = 'AdoptedExternal'
            InstallKind      = 'existingInstall'
            InstallDirectory = $PackageModelResult.ExistingPackage.InstallDirectory
            ReusedExisting   = $true
            CandidatePath    = $PackageModelResult.ExistingPackage.CandidatePath
        }
        $PackageModelResult.Validation = $PackageModelResult.ExistingPackage.Validation
        return $PackageModelResult
    }

    if ([string]::Equals([string]$install.kind, 'reuseExisting', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "PackageModel release '$($package.id)' requires an existing install, but no reusable install passed validation."
    }

    if ($PackageModelResult.PackageFileSave -and -not $PackageModelResult.PackageFileSave.Success) {
        throw $PackageModelResult.PackageFileSave.ErrorMessage
    }

    switch -Exact ([string]$install.kind) {
        'expandArchive' {
            $PackageModelResult.Install = Install-PackageModelArchive -PackageModelResult $PackageModelResult
        }
        'runInstaller' {
            $installerResult = Invoke-PackageModelInstallerProcess -PackageModelResult $PackageModelResult
            $PackageModelResult.Install = [pscustomobject]@{
                Status           = 'Installed'
                InstallKind      = 'runInstaller'
                InstallDirectory = $PackageModelResult.InstallDirectory
                ReusedExisting   = $false
                Installer        = $installerResult
            }
        }
        'packageManagerInstall' {
            $PackageModelResult.Install = Install-PackageModelPackageManagerPackage -PackageModelResult $PackageModelResult
        }
        default {
            throw "Unsupported PackageModel install kind '$($install.kind)'."
        }
    }

    $PackageModelResult.InstallOrigin = 'ManagedInstalled'
    return $PackageModelResult
}
