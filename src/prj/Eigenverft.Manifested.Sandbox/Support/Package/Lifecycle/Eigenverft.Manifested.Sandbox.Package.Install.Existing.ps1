<#
    Eigenverft.Manifested.Sandbox.Package.Install — existing-install discovery, registry probe, and reuse/adopt decisions.
    Dot-sourced from Eigenverft.Manifested.Sandbox.psm1 (mirrored in TestImports.ps1) before Package.Install.ps1.
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

function Resolve-PackageExistingUninstallRegistryCandidate {
<#
.SYNOPSIS
Resolves an existing-install candidate from Windows uninstall registry keys.

.DESCRIPTION
Keeps Package JSON mapping separate from the generic registry helpers. The
search location provides concrete registry paths and the path source that should
be interpreted as the install directory.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SearchLocation
    )

    if (-not $SearchLocation.PSObject.Properties['paths'] -or @($SearchLocation.paths).Count -eq 0) {
        throw "Package existingInstallDiscovery windowsUninstallRegistryKey search is missing paths."
    }
    if (-not $SearchLocation.PSObject.Properties['installDirectorySource'] -or [string]::IsNullOrWhiteSpace([string]$SearchLocation.installDirectorySource)) {
        throw "Package existingInstallDiscovery windowsUninstallRegistryKey search is missing installDirectorySource."
    }

    foreach ($registryPath in @($SearchLocation.paths | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $entry = Get-WindowsUninstallRegistryEntry -Path $registryPath
        if (-not $entry -or -not [string]::Equals([string]$entry.Status, 'Ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $pathResolution = Resolve-WindowsUninstallRegistryEntryPath -Entry $entry -Source ([string]$SearchLocation.installDirectorySource)
        if (-not $pathResolution -or -not [string]::Equals([string]$pathResolution.Status, 'Ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if (Test-Path -LiteralPath $pathResolution.ResolvedPath -PathType Container) {
            return [pscustomobject]@{
                CandidatePath     = $pathResolution.ResolvedPath
                RegistryEntry     = $entry
                PathResolution    = $pathResolution
            }
        }
    }

    return $null
}

function Get-PackageExistingInstallSearchLocations {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$SearchLocations
    )

    $indexedLocations = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($searchLocation in @($SearchLocations)) {
        if ($null -eq $searchLocation) {
            continue
        }
        $indexedLocations.Add([pscustomobject]@{
            SearchLocation = $searchLocation
            SearchOrder    = if ($searchLocation.PSObject.Properties['searchOrder']) { [int]$searchLocation.searchOrder } else { [int]::MaxValue }
            Index          = $index
        }) | Out-Null
        $index++
    }

    return @($indexedLocations.ToArray() | Sort-Object -Property SearchOrder, Index | ForEach-Object { $_.SearchLocation })
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

    foreach ($searchLocation in @(Get-PackageExistingInstallSearchLocations -SearchLocations @($existingInstallDiscovery.searchLocations))) {
        $candidatePath = $null
        $discoveryDetails = $null
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
            'windowsUninstallRegistryKey' {
                $registryCandidate = Resolve-PackageExistingUninstallRegistryCandidate -SearchLocation $searchLocation
                if ($registryCandidate) {
                    $candidatePath = $registryCandidate.CandidatePath
                    $discoveryDetails = $registryCandidate
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
            DiscoveryDetails = $discoveryDetails
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
    $PackageResult = Test-PackageAssignedReadiness -PackageResult $PackageResult
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

    if ([string]::Equals($classification, 'PackageTarget', [System.StringComparison]::OrdinalIgnoreCase) -and -not $ownershipRecord) {
        $PackageResult.ExistingPackage.Decision = 'ReusePackageOwned'
        $PackageResult.InstallOrigin = 'PackageReused'
        Write-PackageExecutionMessage -Message ("[DECISION] Reusing Package-owned target install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
        Write-PackageExecutionMessage -Message ("[STATE] Existing install decision resolved to '{0}' with installOrigin='{1}'." -f $PackageResult.ExistingPackage.Decision, $PackageResult.InstallOrigin)
        return $PackageResult
    }

    if ([string]::Equals($classification, 'PackageTarget', [System.StringComparison]::OrdinalIgnoreCase) -and $ownershipRecord) {
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
