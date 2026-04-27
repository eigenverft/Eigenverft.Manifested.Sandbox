<#
    Eigenverft.Manifested.Sandbox.Package.Install
#>

function Resolve-PackageExistingInstallRoot {
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
Resolve-PackageExistingInstallRoot -ExistingInstallDiscovery $package.existingInstallDiscovery -CandidatePath $candidatePath
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

function Find-PackageExistingPackage {
<#
.SYNOPSIS
Finds an existing package install that may be reused or adopted.

.DESCRIPTION
Searches command, path, and directory candidates from the release
existingInstallDiscovery block and attaches the first matching install
directory to the Package result.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Find-PackageExistingPackage -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory) -and
        (Test-Path -LiteralPath $PackageResult.InstallDirectory -PathType Container)) {
        $resolvedPackageOwnedInstallDirectory = [System.IO.Path]::GetFullPath([string]$PackageResult.InstallDirectory)
        $PackageResult.ExistingPackage = [pscustomobject]@{
            SearchKind       = 'packageTargetInstallPath'
            CandidatePath    = $resolvedPackageOwnedInstallDirectory
            InstallDirectory = $resolvedPackageOwnedInstallDirectory
            Decision         = 'Pending'
            Validation       = $null
            Classification   = $null
            OwnershipRecord  = $null
        }
        Write-PackageExecutionMessage -Message ("[DISCOVERY] Found Package target install directory '{0}'." -f $resolvedPackageOwnedInstallDirectory)
        return $PackageResult
    }

    $package = $PackageResult.Package
    if (-not $package -or -not $package.PSObject.Properties['existingInstallDiscovery'] -or $null -eq $package.existingInstallDiscovery) {
        return $PackageResult
    }

    $existingInstallDiscovery = $package.existingInstallDiscovery
    if ($existingInstallDiscovery.PSObject.Properties['enableDetection'] -and (-not [bool]$existingInstallDiscovery.enableDetection)) {
        return $PackageResult
    }

    foreach ($searchLocation in @($existingInstallDiscovery.searchLocations)) {
        $candidatePath = $null
        switch -Exact ([string]$searchLocation.kind) {
            'command' {
                if (-not $searchLocation.PSObject.Properties['name'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.name)) {
                    throw "Package existingInstallDiscovery search for release '$($package.id)' is missing command name."
                }
                $candidatePath = Get-ResolvedApplicationPath -CommandName ([string]$searchLocation.name)
            }
            'path' {
                if (-not $searchLocation.PSObject.Properties['path'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.path)) {
                    throw "Package existingInstallDiscovery search for release '$($package.id)' is missing path."
                }
                $resolvedPath = Resolve-PackagePathValue -PathValue ([string]$searchLocation.path)
                if (Test-Path -LiteralPath $resolvedPath) {
                    $candidatePath = $resolvedPath
                }
            }
            'directory' {
                if (-not $searchLocation.PSObject.Properties['path'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.path)) {
                    throw "Package existingInstallDiscovery search for release '$($package.id)' is missing directory path."
                }
                $resolvedPath = Resolve-PackagePathValue -PathValue ([string]$searchLocation.path)
                if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
                    $candidatePath = $resolvedPath
                }
            }
            default {
                throw "Unsupported Package existingInstallDiscovery search kind '$($searchLocation.kind)'."
            }
        }

        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            continue
        }

        $installDirectory = Resolve-PackageExistingInstallRoot -ExistingInstallDiscovery $existingInstallDiscovery -CandidatePath $candidatePath
        if (-not (Test-Path -LiteralPath $installDirectory -PathType Container)) {
            continue
        }

        $PackageResult.ExistingPackage = [pscustomobject]@{
            SearchKind       = $searchLocation.kind
            CandidatePath    = $candidatePath
            InstallDirectory = $installDirectory
            Decision         = 'Pending'
            Validation       = $null
            Classification   = $null
            OwnershipRecord  = $null
        }
        Write-PackageExecutionMessage -Message ("[DISCOVERY] Found existing package candidate '{0}' via '{1}'." -f $candidatePath, $searchLocation.kind)
        return $PackageResult
    }

    return $PackageResult
}

function Resolve-PackageExistingPackageDecision {
<#
.SYNOPSIS
Evaluates how Package should react to a discovered existing install.

.DESCRIPTION
Validates the discovered install, combines the result with ownership
classification and release-specific policy switches, and records whether the
current run should reuse, adopt, ignore, or replace the install.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Resolve-PackageExistingPackageDecision -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if (-not $PackageResult.ExistingPackage) {
        return $PackageResult
    }

    $package = $PackageResult.Package
    $existingInstallPolicy = if ($package.PSObject.Properties['existingInstallPolicy']) { $package.existingInstallPolicy } else { [pscustomobject]@{} }
    $originalInstallDirectory = $PackageResult.InstallDirectory
    $PackageResult.InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
    $PackageResult = Test-PackageInstalledPackage -PackageResult $PackageResult
    $PackageResult.ExistingPackage.Validation = $PackageResult.Validation

    if (-not $PackageResult.Validation.Accepted) {
        $PackageResult.ExistingPackage.Decision = 'ExistingInstallValidationFailed'
        $PackageResult.InstallDirectory = $originalInstallDirectory
        $PackageResult.Validation = $null
        return $PackageResult
    }

    $ownershipRecord = if ($PackageResult.Ownership -and $PackageResult.Ownership.OwnershipRecord) {
        $PackageResult.Ownership.OwnershipRecord
    }
    else {
        $null
    }

    $classification = if ($PackageResult.Ownership -and $PackageResult.Ownership.Classification) {
        [string]$PackageResult.Ownership.Classification
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

    $requirePackageOwnership = $false
    if ($existingInstallPolicy.PSObject.Properties['requirePackageOwnership']) {
        $requirePackageOwnership = [bool]$existingInstallPolicy.requirePackageOwnership
    }

    $sameRelease = $false
    if ($ownershipRecord) {
        $sameRelease = [string]::Equals([string]$ownershipRecord.currentReleaseId, [string]$PackageResult.PackageId, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$ownershipRecord.currentVersion, [string]$PackageResult.PackageVersion, [System.StringComparison]::OrdinalIgnoreCase)
    }

    if ([string]::Equals($classification, 'PackageOwned', [System.StringComparison]::OrdinalIgnoreCase) -and -not $ownershipRecord) {
        $PackageResult.ExistingPackage.Decision = 'ReusePackageOwned'
        $PackageResult.InstallOrigin = 'PackageReused'
        Write-PackageExecutionMessage -Message ("[DECISION] Reusing Package-owned target install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
        Write-PackageExecutionMessage -Message ("[STATE] Existing install decision resolved to '{0}' with installOrigin='{1}'." -f $PackageResult.ExistingPackage.Decision, $PackageResult.InstallOrigin)
        return $PackageResult
    }

    if ([string]::Equals($classification, 'PackageOwned', [System.StringComparison]::OrdinalIgnoreCase) -and $ownershipRecord) {
        if ([string]::Equals([string]$ownershipRecord.ownershipKind, 'AdoptedExternal', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($sameRelease -or (-not $upgradeAdoptedInstall)) {
                $PackageResult.ExistingPackage.Decision = 'AdoptExternal'
                $PackageResult.InstallOrigin = 'AdoptedExternal'
                Write-PackageExecutionMessage -Message ("[DECISION] Reusing adopted external install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
                Write-PackageExecutionMessage -Message ("[STATE] Existing install decision resolved to '{0}' with installOrigin='{1}'." -f $PackageResult.ExistingPackage.Decision, $PackageResult.InstallOrigin)
                return $PackageResult
            }

            $PackageResult.ExistingPackage.Decision = 'UpgradeAdoptedInstall'
            $PackageResult.InstallDirectory = $originalInstallDirectory
            $PackageResult.Validation = $null
            Write-PackageExecutionMessage -Level 'WRN' -Message ("[DECISION] Replacing adopted install at '{0}' with a Package-owned install." -f $PackageResult.ExistingPackage.InstallDirectory)
            Write-PackageExecutionMessage -Message ("[STATE] Existing install decision resolved to '{0}'." -f $PackageResult.ExistingPackage.Decision)
            return $PackageResult
        }

        if ($sameRelease) {
            $PackageResult.ExistingPackage.Decision = 'ReusePackageOwned'
            $PackageResult.InstallOrigin = 'PackageReused'
            Write-PackageExecutionMessage -Message ("[DECISION] Reusing Package-owned install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
            Write-PackageExecutionMessage -Message ("[STATE] Existing install decision resolved to '{0}' with installOrigin='{1}'." -f $PackageResult.ExistingPackage.Decision, $PackageResult.InstallOrigin)
            return $PackageResult
        }

        $PackageResult.ExistingPackage.Decision = 'ReplacePackageOwnedInstall'
        $PackageResult.InstallDirectory = $originalInstallDirectory
        $PackageResult.Validation = $null
        Write-PackageExecutionMessage -Level 'WRN' -Message ("[DECISION] Replacing outdated Package-owned install at '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
        Write-PackageExecutionMessage -Message ("[STATE] Existing install decision resolved to '{0}'." -f $PackageResult.ExistingPackage.Decision)
        return $PackageResult
    }

    if ($requirePackageOwnership) {
        $PackageResult.ExistingPackage.Decision = 'ExternalIgnored'
        $PackageResult.InstallDirectory = $originalInstallDirectory
        $PackageResult.Validation = $null
        Write-PackageExecutionMessage -Level 'WRN' -Message ("[DECISION] Ignoring external install '{0}' because Package ownership is required." -f $PackageResult.ExistingPackage.InstallDirectory)
        Write-PackageExecutionMessage -Message ("[STATE] Existing install decision resolved to '{0}'." -f $PackageResult.ExistingPackage.Decision)
        return $PackageResult
    }

    if ($allowAdoptExternal) {
        $PackageResult.ExistingPackage.Decision = 'AdoptExternal'
        $PackageResult.InstallOrigin = 'AdoptedExternal'
        Write-PackageExecutionMessage -Message ("[DECISION] Adopting external install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
        Write-PackageExecutionMessage -Message ("[STATE] Existing install decision resolved to '{0}' with installOrigin='{1}'." -f $PackageResult.ExistingPackage.Decision, $PackageResult.InstallOrigin)
        return $PackageResult
    }

    $PackageResult.ExistingPackage.Decision = 'ExternalIgnored'
    $PackageResult.InstallDirectory = $originalInstallDirectory
    $PackageResult.Validation = $null
    Write-PackageExecutionMessage -Level 'WRN' -Message ("[DECISION] Ignoring external install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
    Write-PackageExecutionMessage -Message ("[STATE] Existing install decision resolved to '{0}'." -f $PackageResult.ExistingPackage.Decision)
    return $PackageResult
}

function Get-PackageOwnedInstallStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if ($PackageResult.ExistingPackage) {
        switch -Exact ([string]$PackageResult.ExistingPackage.Decision) {
            'ExistingInstallValidationFailed' {
                if ([string]::Equals([string]$PackageResult.ExistingPackage.SearchKind, 'packageTargetInstallPath', [System.StringComparison]::OrdinalIgnoreCase)) {
                    return 'RepairedPackageOwnedInstall'
                }
            }
            'ReplacePackageOwnedInstall' { return 'ReplacedPackageOwnedInstall' }
            'UpgradeAdoptedInstall' { return 'ReplacedAdoptedInstall' }
        }
    }

    return 'Installed'
}

function Get-PackageInstallTargetKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Package
    )

    if ($Package.install -and $Package.install.PSObject.Properties['targetKind'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Package.install.targetKind)) {
        return [string]$Package.install.targetKind
    }

    return 'directory'
}

function Get-PackageInstallerElevationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $install = $PackageResult.Package.install
    $mode = if ($install.PSObject.Properties['elevation'] -and -not [string]::IsNullOrWhiteSpace([string]$install.elevation)) {
        ([string]$install.elevation).ToLowerInvariant()
    }
    else {
        'none'
    }
    $processIsElevated = Test-ProcessElevation
    $shouldElevate = ($mode -in @('required', 'auto')) -and (-not $processIsElevated)

    return [pscustomobject]@{
        Mode              = $mode
        ProcessIsElevated = $processIsElevated
        ShouldElevate     = $shouldElevate
    }
}

function Resolve-PackagePreInstallSatisfaction {
<#
.SYNOPSIS
Checks whether a machine-prerequisite package is already satisfied.

.DESCRIPTION
Runs validation before acquisition/install for prerequisite-style packages that
do not own an install directory. When validation succeeds, later acquisition
and installer steps are skipped.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Resolve-PackagePreInstallSatisfaction -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $package = $PackageResult.Package
    if (-not $package -or -not $package.install) {
        return $PackageResult
    }

    $installKind = if ($package.install.PSObject.Properties['kind']) { [string]$package.install.kind } else { $null }
    $targetKind = Get-PackageInstallTargetKind -Package $package
    if (-not [string]::Equals($installKind, 'runInstaller', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($targetKind, 'machinePrerequisite', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $PackageResult
    }

    $PackageResult = Test-PackageInstalledPackage -PackageResult $PackageResult
    if ($PackageResult.Validation -and $PackageResult.Validation.Accepted) {
        $PackageResult.InstallOrigin = 'AlreadySatisfied'
        $PackageResult.Install = [pscustomobject]@{
            Status           = 'AlreadySatisfied'
            InstallKind      = 'runInstaller'
            TargetKind       = 'machinePrerequisite'
            InstallDirectory = $null
            ReusedExisting   = $true
        }
        Write-PackageExecutionMessage -Message "[DECISION] Machine prerequisite is already satisfied; skipping acquisition and installer execution."
    }
    else {
        $failedCount = if ($PackageResult.Validation) {
            @(
                @($PackageResult.Validation.Files) +
                @($PackageResult.Validation.Directories) +
                @($PackageResult.Validation.Commands) +
                @($PackageResult.Validation.MetadataFiles) +
                @($PackageResult.Validation.Signatures) +
                @($PackageResult.Validation.FileDetails) +
                @($PackageResult.Validation.Registry) |
                    Where-Object { $_.Status -ne 'Ready' }
            ).Count
        }
        else {
            0
        }
        Write-PackageExecutionMessage -Message ("[STATE] Machine prerequisite is not satisfied yet; failedChecks={0}." -f $failedCount)
        $PackageResult.Validation = $null
    }

    return $PackageResult
}

function Install-PackageArchive {
<#
.SYNOPSIS
Installs a package by expanding an archive into the install directory.

.DESCRIPTION
Expands the saved package file into a stage directory, promotes the expanded
root into the final install directory, and creates any extra directories that
the install block requests.

.PARAMETER PackageResult
The Package result object to install.

.EXAMPLE
Install-PackageArchive -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if ([string]::IsNullOrWhiteSpace($PackageResult.PackageFilePath) -or -not (Test-Path -LiteralPath $PackageResult.PackageFilePath)) {
        throw "Package archive install for '$($PackageResult.PackageId)' requires a saved package file."
    }

    $install = $PackageResult.Package.install
    $stageInfo = $null
    try {
        $stageInfo = Expand-ArchiveToStage -ArchivePath $PackageResult.PackageFilePath -Prefix 'package'
        $expandedRoot = $stageInfo.ExpandedRoot
        if ($install.PSObject.Properties['expandedRoot'] -and
            -not [string]::IsNullOrWhiteSpace([string]$install.expandedRoot) -and
            [string]$install.expandedRoot -ne 'auto') {
            $expandedRoot = Join-Path $stageInfo.StagePath (([string]$install.expandedRoot) -replace '/', '\')
        }

        if (-not (Test-Path -LiteralPath $expandedRoot -PathType Container)) {
            throw "Expanded package root '$expandedRoot' was not found for '$($PackageResult.PackageId)'."
        }

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $PackageResult.InstallDirectory) -Force
        if (Test-Path -LiteralPath $PackageResult.InstallDirectory) {
            Remove-Item -LiteralPath $PackageResult.InstallDirectory -Recurse -Force
        }

        New-Item -ItemType Directory -Path $PackageResult.InstallDirectory -Force | Out-Null
        Get-ChildItem -LiteralPath $expandedRoot -Force | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination $PackageResult.InstallDirectory -Force
        }

        foreach ($relativePath in @($install.createDirectories)) {
            $targetDirectory = Join-Path $PackageResult.InstallDirectory (([string]$relativePath) -replace '/', '\')
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
    }
    finally {
        if ($stageInfo) {
            Remove-PathIfExists -Path $stageInfo.StagePath | Out-Null
        }
    }

    return [pscustomobject]@{
        Status           = Get-PackageOwnedInstallStatus -PackageResult $PackageResult
        InstallKind      = 'expandArchive'
        InstallDirectory = $PackageResult.InstallDirectory
        ReusedExisting   = $false
    }
}

function Get-PackageInstalledFilePath {
<#
.SYNOPSIS
Resolves the final installed file path for a single-file package install.

.DESCRIPTION
Uses install.targetRelativePath when present and otherwise falls back to the
canonical packageFile.fileName so single-file resource packages can share one
simple install model.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $install = $PackageResult.Package.install
    $targetRelativePath = $null
    if ($install.PSObject.Properties['targetRelativePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$install.targetRelativePath)) {
        $targetRelativePath = ([string]$install.targetRelativePath) -replace '/', '\'
    }
    elseif ($PackageResult.Package -and
        $PackageResult.Package.PSObject.Properties['packageFile'] -and
        $PackageResult.Package.packageFile -and
        $PackageResult.Package.packageFile.PSObject.Properties['fileName'] -and
        -not [string]::IsNullOrWhiteSpace([string]$PackageResult.Package.packageFile.fileName)) {
        $targetRelativePath = [string]$PackageResult.Package.packageFile.fileName
    }
    else {
        throw "Package single-file install for '$($PackageResult.PackageId)' requires install.targetRelativePath or packageFile.fileName."
    }

    return (Join-Path $PackageResult.InstallDirectory $targetRelativePath)
}

function Install-PackagePackageFile {
<#
.SYNOPSIS
Installs a package by placing one saved package file into the install directory.

.DESCRIPTION
Creates or replaces the target install directory, then copies the verified
saved package file into the configured target-relative path.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if ([string]::IsNullOrWhiteSpace($PackageResult.PackageFilePath) -or -not (Test-Path -LiteralPath $PackageResult.PackageFilePath -PathType Leaf)) {
        throw "Package single-file install for '$($PackageResult.PackageId)' requires a saved package file."
    }

    $installedFilePath = Get-PackageInstalledFilePath -PackageResult $PackageResult
    $targetDirectory = Split-Path -Parent $installedFilePath

    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $PackageResult.InstallDirectory) -Force
    if (Test-Path -LiteralPath $PackageResult.InstallDirectory) {
        Remove-PathIfExists -Path $PackageResult.InstallDirectory | Out-Null
    }

    $null = New-Item -ItemType Directory -Path $PackageResult.InstallDirectory -Force
    if (-not [string]::IsNullOrWhiteSpace($targetDirectory)) {
        $null = New-Item -ItemType Directory -Path $targetDirectory -Force
    }

    $null = Copy-FileToPath -SourcePath $PackageResult.PackageFilePath -TargetPath $installedFilePath -Overwrite

    return [pscustomobject]@{
        Status           = Get-PackageOwnedInstallStatus -PackageResult $PackageResult
        InstallKind      = 'placePackageFile'
        InstallDirectory = $PackageResult.InstallDirectory
        InstalledFilePath = $installedFilePath
        ReusedExisting   = $false
    }
}

function Format-PackageProcessArgument {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    if ($text.Length -ge 2 -and $text.StartsWith('"') -and $text.EndsWith('"')) {
        return $text
    }
    if ($text.IndexOfAny([char[]]@(' ', "`t", '"')) -lt 0) {
        return $text
    }

    return '"' + ($text -replace '"', '\"') + '"'
}

function Invoke-PackageInstallerProcess {
<#
.SYNOPSIS
Runs an installer-style package command and waits for completion.

.DESCRIPTION
Starts the configured installer command, applies timeout and exit-code rules,
and returns the install log path and restart flag when configured.

.PARAMETER PackageResult
The Package result object that owns the install.

.EXAMPLE
Invoke-PackageInstallerProcess -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $install = $PackageResult.Package.install
    $commandPath = if ($install.PSObject.Properties['commandPath'] -and -not [string]::IsNullOrWhiteSpace([string]$install.commandPath)) {
        Resolve-PackageTemplateText -Text ([string]$install.commandPath) -PackageConfig $PackageResult.PackageConfig -Package $PackageResult.Package
    }
    else {
        $PackageResult.PackageFilePath
    }

    $timestamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
    $logPath = $null
    if ($install.PSObject.Properties['logRelativePath'] -and -not [string]::IsNullOrWhiteSpace([string]$install.logRelativePath)) {
        $logRelativePath = Resolve-PackageTemplateText -Text ([string]$install.logRelativePath) -PackageConfig $PackageResult.PackageConfig -Package $PackageResult.Package -ExtraTokens @{ timestamp = $timestamp }
        $packageRoot = Get-PackageRootFromStateIndexPath -PackageStateIndexFilePath ([string]$PackageResult.PackageConfig.PackageStateIndexFilePath)
        $logRoot = [System.IO.Path]::GetFullPath((Join-Path $packageRoot 'Logs'))
        $logPath = [System.IO.Path]::GetFullPath((Join-Path $logRoot ($logRelativePath -replace '/', '\')))
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force
    }

    $commandArguments = @()
    foreach ($argument in @($install.commandArguments)) {
        $resolvedArgument = Resolve-PackageTemplateText -Text ([string]$argument) -PackageConfig $PackageResult.PackageConfig -Package $PackageResult.Package -ExtraTokens @{
                packageFilePath   = $PackageResult.PackageFilePath
                installDirectory  = $PackageResult.InstallDirectory
                installWorkspaceDirectory = $PackageResult.InstallWorkspaceDirectory
                downloadDirectory = $PackageResult.InstallWorkspaceDirectory
                logPath           = $logPath
                timestamp         = $timestamp
            }
        $commandArguments += (Format-PackageProcessArgument -Value $resolvedArgument)
    }

    $timeoutSec = if ($install.PSObject.Properties['timeoutSec']) { [int]$install.timeoutSec } else { 300 }
    $successExitCodes = if ($install.PSObject.Properties['successExitCodes']) { @($install.successExitCodes | ForEach-Object { [int]$_ }) } else { @(0) }
    $restartExitCodes = if ($install.PSObject.Properties['restartExitCodes']) { @($install.restartExitCodes | ForEach-Object { [int]$_ }) } else { @() }
    $targetKind = Get-PackageInstallTargetKind -Package $PackageResult.Package
    $workingDirectory = if (-not [string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory)) {
        $null = New-Item -ItemType Directory -Path $PackageResult.InstallDirectory -Force
        $PackageResult.InstallDirectory
    }
    else {
        $PackageResult.InstallWorkspaceDirectory
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$workingDirectory)) {
        $null = New-Item -ItemType Directory -Path $workingDirectory -Force
    }

    $elevationPlan = Get-PackageInstallerElevationPlan -PackageResult $PackageResult
    $installerKind = if ($install.PSObject.Properties['installerKind'] -and -not [string]::IsNullOrWhiteSpace([string]$install.installerKind)) { [string]$install.installerKind } else { '<unspecified>' }
    $uiMode = if ($install.PSObject.Properties['uiMode'] -and -not [string]::IsNullOrWhiteSpace([string]$install.uiMode)) { [string]$install.uiMode } else { '<unspecified>' }
    Write-PackageExecutionMessage -Message ("[STATE] Installer execution: targetKind='{0}', installerKind='{1}', uiMode='{2}', elevation='{3}', processIsElevated='{4}', willElevate='{5}'." -f $targetKind, $installerKind, $uiMode, $elevationPlan.Mode, $elevationPlan.ProcessIsElevated, $elevationPlan.ShouldElevate)

    $startProcessParameters = @{
        FilePath         = $commandPath
        ArgumentList     = $commandArguments
        WorkingDirectory = $workingDirectory
        PassThru         = $true
    }
    if ($elevationPlan.ShouldElevate) {
        $startProcessParameters['Verb'] = 'RunAs'
    }

    $process = Start-Process @startProcessParameters
    if (-not $process.WaitForExit($timeoutSec * 1000)) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
        }

        throw "Package installer command exceeded the timeout of $timeoutSec seconds."
    }

    $process.Refresh()
    $exitCode = [int]$process.ExitCode
    $acceptedExitCodes = @($successExitCodes) + @($restartExitCodes)
    if ($exitCode -notin $acceptedExitCodes) {
        throw "Package installer command failed with exit code $exitCode."
    }

    return [pscustomobject]@{
        ExitCode         = $exitCode
        RestartRequired  = ($exitCode -in $restartExitCodes)
        LogPath          = $logPath
        CommandPath      = $commandPath
        CommandArguments = @($commandArguments)
        TargetKind       = $targetKind
        InstallerKind    = $installerKind
        UiMode           = $uiMode
        Elevation        = $elevationPlan
    }
}

function Install-PackagePackage {
<#
.SYNOPSIS
Installs or reuses the selected package.

.DESCRIPTION
Reuses or adopts a valid existing install when the earlier ownership/policy
decision allows it, otherwise executes the configured install kind and attaches
the install result to the Package result object.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Install-PackagePackage -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $package = $PackageResult.Package
    $install = $package.install
    if (-not $install -or -not $install.PSObject.Properties['kind']) {
        throw "Package release '$($package.id)' does not define install.kind."
    }

    if ([string]::Equals([string]$PackageResult.InstallOrigin, 'AlreadySatisfied', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-PackageExecutionMessage -Message "[ACTION] Skipped installer because machine prerequisite is already satisfied."
        return $PackageResult
    }

    if ($PackageResult.ExistingPackage -and $PackageResult.ExistingPackage.Decision -eq 'ReusePackageOwned') {
        $PackageResult.InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
        $PackageResult.InstallOrigin = 'PackageReused'
        $PackageResult.Install = [pscustomobject]@{
            Status           = 'ReusedPackageOwned'
            InstallKind      = 'existingInstall'
            InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
            ReusedExisting   = $true
            CandidatePath    = $PackageResult.ExistingPackage.CandidatePath
        }
        $PackageResult.Validation = $PackageResult.ExistingPackage.Validation
        Write-PackageExecutionMessage -Message ("[ACTION] Reused Package-owned install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
        return $PackageResult
    }

    if ($PackageResult.ExistingPackage -and $PackageResult.ExistingPackage.Decision -eq 'AdoptExternal') {
        $PackageResult.InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
        $PackageResult.InstallOrigin = 'AdoptedExternal'
        $PackageResult.Install = [pscustomobject]@{
            Status           = 'AdoptedExternal'
            InstallKind      = 'existingInstall'
            InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
            ReusedExisting   = $true
            CandidatePath    = $PackageResult.ExistingPackage.CandidatePath
        }
        $PackageResult.Validation = $PackageResult.ExistingPackage.Validation
        Write-PackageExecutionMessage -Message ("[ACTION] Adopted external install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
        return $PackageResult
    }

    if ([string]::Equals([string]$install.kind, 'reuseExisting', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package release '$($package.id)' requires an existing install, but no reusable install passed validation."
    }

    if ($PackageResult.PackageFileSave -and -not $PackageResult.PackageFileSave.Success) {
        throw $PackageResult.PackageFileSave.ErrorMessage
    }

    switch -Exact ([string]$install.kind) {
        'expandArchive' {
            Write-PackageExecutionMessage -Message ("[ACTION] Installing package archive into '{0}'." -f $PackageResult.InstallDirectory)
            $PackageResult.Install = Install-PackageArchive -PackageResult $PackageResult
        }
        'placePackageFile' {
            Write-PackageExecutionMessage -Message ("[ACTION] Placing package file into '{0}'." -f $PackageResult.InstallDirectory)
            $PackageResult.Install = Install-PackagePackageFile -PackageResult $PackageResult
        }
        'runInstaller' {
            $targetKind = Get-PackageInstallTargetKind -Package $package
            $targetText = if ([string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory)) { '<machine prerequisite>' } else { [string]$PackageResult.InstallDirectory }
            Write-PackageExecutionMessage -Message ("[ACTION] Running installer for target '{0}'." -f $targetText)
            $installerResult = Invoke-PackageInstallerProcess -PackageResult $PackageResult
            $PackageResult.Install = [pscustomobject]@{
                Status           = Get-PackageOwnedInstallStatus -PackageResult $PackageResult
                InstallKind      = 'runInstaller'
                TargetKind       = $targetKind
                InstallDirectory = $PackageResult.InstallDirectory
                ReusedExisting   = $false
                Installer        = $installerResult
            }
        }
        'npmGlobalPackage' {
            Write-PackageExecutionMessage -Message ("[ACTION] Installing npm global package into '{0}'." -f $PackageResult.InstallDirectory)
            $PackageResult.Install = Install-PackageNpmPackage -PackageResult $PackageResult
        }
        default {
            throw "Unsupported Package install kind '$($install.kind)'."
        }
    }

    $PackageResult.InstallOrigin = if ([string]::Equals((Get-PackageInstallTargetKind -Package $package), 'machinePrerequisite', [System.StringComparison]::OrdinalIgnoreCase)) {
        'PackageApplied'
    }
    else {
        'PackageInstalled'
    }
    Write-PackageExecutionMessage -Message ("[ACTION] Completed Package-owned install with status '{0}'." -f $PackageResult.Install.Status)
    return $PackageResult
}

