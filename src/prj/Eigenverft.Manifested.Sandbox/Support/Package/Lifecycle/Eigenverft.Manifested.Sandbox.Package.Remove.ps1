<#
    Eigenverft.Manifested.Sandbox.Package.Remove — DesiredState Removed orchestration.
    Dot-sourced from Eigenverft.Manifested.Sandbox.psm1 after Package.CommandFlow.ps1.

    Removal safety: other inventory rows are scanned by loading each row's definition and
    matching dependencies against the target definition (repositoryId + definitionId).
    Persisted dependencyInstallSlotIds on inventory rows (see Update-PackageInventoryRecord)
    documents direct dependency slots for operators; blocking is driven by definition
    metadata so stale slot lists cannot bypass the check.
#>

function Get-PackageInventoryDependentBlockingRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageConfig,

        [Parameter(Mandatory = $true)]
        [string]$ExcludeInstallSlotId,

        [Parameter(Mandatory = $true)]
        [string]$TargetRepositoryId,

        [Parameter(Mandatory = $true)]
        [string]$TargetDefinitionId
    )

    $targetKey = Get-PackageDependencyReferenceKey -RepositoryId $TargetRepositoryId -DefinitionId $TargetDefinitionId
    $index = Get-PackageInventory -PackageConfig $PackageConfig
    $blockers = New-Object System.Collections.Generic.List[object]

    foreach ($record in @($index.Records)) {
        $slot = [string]$record.installSlotId
        if ([string]::Equals($slot, $ExcludeInstallSlotId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $parentRepositoryId = if ($record.PSObject.Properties['definitionRepositoryId'] -and -not [string]::IsNullOrWhiteSpace([string]$record.definitionRepositoryId)) {
            [string]$record.definitionRepositoryId
        }
        else {
            Get-PackageDefaultRepositoryId
        }
        $parentDefinitionId = [string]$record.definitionId

        try {
            $definitionReference = Resolve-PackageDefinitionReference -RepositoryId $parentRepositoryId -DefinitionId $parentDefinitionId
            $definitionDocumentInfo = Read-PackageJsonDocument -Path $definitionReference.DefinitionPath
            Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionDocumentInfo -DefinitionId $parentDefinitionId -DefinitionRepositoryId $parentRepositoryId
        }
        catch {
            throw "Package removal dependency scan failed while reading definition '$parentRepositoryId/$parentDefinitionId' for inventory installSlotId '$slot': $($_.Exception.Message)"
        }

        $definition = $definitionDocumentInfo.Document
        if (-not $definition.PSObject.Properties['dependencies'] -or $null -eq $definition.dependencies) {
            continue
        }

        foreach ($dependency in @($definition.dependencies)) {
            if ($null -eq $dependency) {
                continue
            }

            $depDefinitionId = if ($dependency.PSObject.Properties['definitionId']) { [string]$dependency.definitionId } else { $null }
            if ([string]::IsNullOrWhiteSpace($depDefinitionId)) {
                continue
            }

            $depRepositoryId = if ($dependency.PSObject.Properties['repositoryId'] -and -not [string]::IsNullOrWhiteSpace([string]$dependency.repositoryId)) {
                [string]$dependency.repositoryId
            }
            else {
                $parentRepositoryId
            }

            $depKey = Get-PackageDependencyReferenceKey -RepositoryId $depRepositoryId -DefinitionId $depDefinitionId
            if ([string]::Equals($depKey, $targetKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                $blockers.Add([pscustomobject]@{
                    DependentInstallSlotId = $slot
                    DependentDefinitionId  = $parentDefinitionId
                    DependentRepositoryId  = $parentRepositoryId
                }) | Out-Null
                break
            }
        }
    }

    return @($blockers.ToArray())
}

function Assert-PackageRemovalDependencyDependents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if ($PackageResult.PSObject.Properties['InventoryRemovalSkipped'] -and [bool]$PackageResult.InventoryRemovalSkipped) {
        return $PackageResult
    }

    $targetRepositoryId = Get-PackageResultRepositoryId -PackageResult $PackageResult
    $targetDefinitionId = [string]$PackageResult.DefinitionId
    $excludeSlotId = Get-PackageInstallSlotId -PackageResult $PackageResult
    $blockers = @(Get-PackageInventoryDependentBlockingRecords -PackageConfig $PackageResult.PackageConfig -ExcludeInstallSlotId $excludeSlotId -TargetRepositoryId $targetRepositoryId -TargetDefinitionId $targetDefinitionId)
    if ($blockers.Count -gt 0) {
        $summaries = @(
            foreach ($b in @($blockers)) {
                "'$($b.DependentRepositoryId)/$($b.DependentDefinitionId)' (installSlotId=$($b.DependentInstallSlotId))"
            }
        )
        throw ("Package removal blocked: '{0}/{1}' is still declared as a dependency by installed package(s): {2}. Remove those packages first (or implement removeDependencies)." -f $targetRepositoryId, $targetDefinitionId, ($summaries -join '; '))
    }

    return $PackageResult
}

function Get-PackageExistingInstallSearchLocationById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$SearchLocationId
    )

    $discovery = $Definition.existingInstallDiscovery
    if (-not $discovery -or -not $discovery.PSObject.Properties['searchLocations']) {
        throw "Package definition '$($Definition.id)' is missing existingInstallDiscovery.searchLocations required for removal uninstall discovery."
    }

    foreach ($searchLocation in @(Get-PackageExistingInstallSearchLocations -SearchLocations @($discovery.searchLocations))) {
        if ($searchLocation.PSObject.Properties['id'] -and
            [string]::Equals([string]$searchLocation.id, $SearchLocationId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $searchLocation
        }
    }

    throw "Package definition '$($Definition.id)' has no existingInstallDiscovery.searchLocations entry with id '$SearchLocationId'."
}

function Get-PackageUninstallExecutableAndArgumentTail {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RawText
    )

    if ([string]::IsNullOrWhiteSpace($RawText)) {
        return [pscustomobject]@{
            Executable     = $null
            ArgumentTokens = @()
        }
    }

    $expanded = [Environment]::ExpandEnvironmentVariables(([string]$RawText).Trim())
    $exe = Get-WindowsRegistryExecutablePathFromText -Text $expanded
    if ([string]::IsNullOrWhiteSpace($exe)) {
        return [pscustomobject]@{
            Executable     = $null
            ArgumentTokens = @()
        }
    }

    $idx = $expanded.IndexOf($exe, [System.StringComparison]::OrdinalIgnoreCase)
    $after = if ($idx -lt 0) { '' } else { $expanded.Substring($idx + $exe.Length).Trim() }
    $tokens = if ([string]::IsNullOrWhiteSpace($after)) {
        @()
    }
    else {
        @($after -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return [pscustomobject]@{
        Executable     = $exe
        ArgumentTokens = @($tokens)
    }
}

function ConvertFrom-PackageInventoryPathRegistrationRecord {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$PathRegistrationRecord
    )

    if ($null -eq $PathRegistrationRecord) {
        return $null
    }

    $sourceValues = if ($PathRegistrationRecord.PSObject.Properties['sourceValues'] -and $null -ne $PathRegistrationRecord.sourceValues) {
        @($PathRegistrationRecord.sourceValues | ForEach-Object { [string]$_ })
    }
    else {
        @()
    }

    $cleanupDirectories = if ($PathRegistrationRecord.PSObject.Properties['cleanupDirectories'] -and $null -ne $PathRegistrationRecord.cleanupDirectories) {
        @($PathRegistrationRecord.cleanupDirectories | ForEach-Object { [string]$_ })
    }
    else {
        @()
    }

    return [pscustomobject]@{
        Status             = if ($PathRegistrationRecord.PSObject.Properties['status']) { [string]$PathRegistrationRecord.status } else { $null }
        Mode               = if ($PathRegistrationRecord.PSObject.Properties['mode']) { [string]$PathRegistrationRecord.mode } else { $null }
        SourceKind         = if ($PathRegistrationRecord.PSObject.Properties['sourceKind']) { [string]$PathRegistrationRecord.sourceKind } else { $null }
        SourceValue        = if ($PathRegistrationRecord.PSObject.Properties['sourceValue']) { [string]$PathRegistrationRecord.sourceValue } else { $null }
        SourceValues       = @($sourceValues)
        SourcePath         = if ($PathRegistrationRecord.PSObject.Properties['sourcePath']) { [string]$PathRegistrationRecord.sourcePath } else { $null }
        RegisteredPath     = if ($PathRegistrationRecord.PSObject.Properties['registeredPath']) { [string]$PathRegistrationRecord.registeredPath } else { $null }
        CleanupDirectories = @($cleanupDirectories)
        CleanedTargets     = @()
        UpdatedTargets     = @()
    }
}

function Resolve-PackageRemovalInstallContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $definition = $PackageResult.PackageConfig.Definition
    $removed = $definition.packageOperations.removed
    $policy = $removed.policy
    $index = Get-PackageInventory -PackageConfig $PackageResult.PackageConfig
    $installSlotId = Get-PackageInstallSlotId -PackageResult $PackageResult

    $record = $null
    foreach ($candidate in @($index.Records)) {
        if ([string]::Equals([string]$candidate.installSlotId, $installSlotId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $record = $candidate
            break
        }
    }

    if ($null -eq $record) {
        if ([string]::Equals([string]$policy.whenNotInInventory, 'fail', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package removal failed for '$($PackageResult.DefinitionId)': no inventory record for install slot '$installSlotId' and policy.whenNotInInventory is 'fail'."
        }

        $PackageResult | Add-Member -Force -MemberType NoteProperty -Name 'InventoryRemovalSkipped' -Value $true
        Write-PackageExecutionMessage -Message ("[STATE] Removal skipped destructive work: no inventory record for install slot '{0}' (whenNotInInventory='succeed')." -f $installSlotId)
        return $PackageResult
    }

    $PackageResult | Add-Member -Force -MemberType NoteProperty -Name 'InventoryRemovalSkipped' -Value $false

    if ([string]::IsNullOrWhiteSpace([string]$record.installDirectory)) {
        throw "Package removal failed for '$($PackageResult.DefinitionId)': inventory record is missing installDirectory."
    }

    $normalizedInstallDirectory = [System.IO.Path]::GetFullPath([string]$record.installDirectory)
    $PackageResult.InstallDirectory = $normalizedInstallDirectory

    $ownershipKind = if ($record.PSObject.Properties['ownershipKind']) { [string]$record.ownershipKind } else { $null }
    $installOrigin = switch -Exact ($ownershipKind) {
        'PackageInstalled' { 'PackageInstalled'; break }
        'PackageApplied' { 'PackageApplied'; break }
        'AdoptedExternal' { 'AdoptedExternal'; break }
        default { $ownershipKind }
    }
    $PackageResult.InstallOrigin = $installOrigin

    $PackageResult.Ownership = [pscustomobject]@{
        InventoryPath   = $index.Path
        InstallSlotId   = $installSlotId
        Classification  = 'PackageTarget'
        OwnershipRecord = $record
    }

    $PackageResult.ExistingPackage = [pscustomobject]@{
        SearchKind       = 'packageTargetInstallPath'
        CandidatePath    = $normalizedInstallDirectory
        InstallDirectory = $normalizedInstallDirectory
        Decision         = 'Pending'
        Readiness       = $null
        Classification   = 'PackageTarget'
        OwnershipRecord  = $record
    }

    $pathRegistration = if ($record.PSObject.Properties['pathRegistration'] -and $null -ne $record.pathRegistration) {
        ConvertFrom-PackageInventoryPathRegistrationRecord -PathRegistrationRecord $record.pathRegistration
    }
    else {
        $null
    }

    if ($pathRegistration) {
        if ($PackageResult.PSObject.Properties['PathRegistration']) {
            $PackageResult.PathRegistration = $pathRegistration
        }
        else {
            $PackageResult | Add-Member -MemberType NoteProperty -Name PathRegistration -Value $pathRegistration
        }
    }

    Write-PackageExecutionMessage -Message ("[STATE] Removal inventory context: installSlotId='{0}', installDirectory='{1}', ownershipKind='{2}'." -f $installSlotId, $normalizedInstallDirectory, $ownershipKind)

    return $PackageResult
}

function Assert-PackageRemovalPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $definition = $PackageResult.PackageConfig.Definition
    $policy = $definition.packageOperations.removed.policy

    if ($policy.removeDependencies -is [bool] -and [bool]$policy.removeDependencies) {
        throw "Package removal for '$($PackageResult.DefinitionId)' requested policy.removeDependencies=true, which is not implemented yet. Set removeDependencies to false for v1 removal."
    }

    if ($PackageResult.PSObject.Properties['InventoryRemovalSkipped'] -and [bool]$PackageResult.InventoryRemovalSkipped) {
        return $PackageResult
    }

    $record = $PackageResult.Ownership.OwnershipRecord
    $allowedKinds = @($policy.allowedInventoryOwnershipKinds | ForEach-Object { [string]$_ })
    $kind = if ($record -and $record.PSObject.Properties['ownershipKind']) { [string]$record.ownershipKind } else { $null }
    if ([string]::IsNullOrWhiteSpace($kind)) {
        throw "Package removal failed for '$($PackageResult.DefinitionId)': inventory record is missing ownershipKind."
    }

    $allowed = $false
    foreach ($allowedKind in @($allowedKinds)) {
        if ([string]::Equals($allowedKind, $kind, [System.StringComparison]::OrdinalIgnoreCase)) {
            $allowed = $true
            break
        }
    }

    if (-not $allowed) {
        throw "Package removal failed for '$($PackageResult.DefinitionId)': inventory ownershipKind '$kind' is not allowed by removed.policy.allowedInventoryOwnershipKinds."
    }

    return $PackageResult
}

function Invoke-PackageRemovedOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $definition = $PackageResult.PackageConfig.Definition
    $operation = $definition.packageOperations.removed.operation
    $kind = [string]$operation.kind

    if ($PackageResult.PSObject.Properties['InventoryRemovalSkipped'] -and [bool]$PackageResult.InventoryRemovalSkipped) {
        Write-PackageExecutionMessage -Message '[STATE] Removed operation skipped because no inventory record was found.'
        return $PackageResult
    }

    switch -Exact ($kind) {
        'none' {
            Write-PackageExecutionMessage -Message '[STATE] Removed operation kind is none; nothing to execute.'
        }
        'deleteInstallDirectory' {
            $target = [string]$PackageResult.InstallDirectory
            if ([string]::IsNullOrWhiteSpace($target)) {
                throw "Package removed operation 'deleteInstallDirectory' requires a resolved inventory installDirectory."
            }
            if (Test-Path -LiteralPath $target) {
                Remove-PathIfExists -Path $target | Out-Null
                Write-PackageExecutionMessage -Message ("[ACTION] Deleted install directory '{0}' for removed operation." -f $target)
            }
            else {
                Write-PackageExecutionMessage -Message ("[STATE] deleteInstallDirectory skipped; path does not exist: '{0}'." -f $target)
            }
        }
        'nsisUninstaller' {
            $searchLocation = Get-PackageExistingInstallSearchLocationById -Definition $definition -SearchLocationId ([string]$operation.commandSource.searchLocationId)
            $resolved = Resolve-PackageExistingUninstallRegistryCandidate -SearchLocation $searchLocation
            if (-not $resolved -or -not $resolved.RegistryEntry) {
                throw "Package nsisUninstaller removal could not resolve a Windows uninstall registry entry for searchLocationId '$($operation.commandSource.searchLocationId)'."
            }

            $entry = $resolved.RegistryEntry
            $chosenText = $null
            foreach ($registryValueName in @($operation.commandSource.registryValueOrder)) {
                $prop = if ([string]::Equals([string]$registryValueName, 'QuietUninstallString', [System.StringComparison]::OrdinalIgnoreCase)) {
                    'QuietUninstallString'
                }
                else {
                    'UninstallString'
                }
                if (-not $entry.PSObject.Properties[$prop]) {
                    continue
                }
                $text = [string]$entry.$prop
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $chosenText = $text
                    break
                }
            }

            if ([string]::IsNullOrWhiteSpace($chosenText)) {
                throw 'Package nsisUninstaller removal did not find a usable QuietUninstallString or UninstallString in the resolved registry entry.'
            }

            $parsed = Get-PackageUninstallExecutableAndArgumentTail -RawText $chosenText
            if ([string]::IsNullOrWhiteSpace($parsed.Executable) -or -not (Test-Path -LiteralPath $parsed.Executable -PathType Leaf)) {
                throw "Package nsisUninstaller removal resolved uninstall executable '$($parsed.Executable)' but it does not exist."
            }

            $commandArguments = New-Object System.Collections.Generic.List[string]
            foreach ($token in @($parsed.ArgumentTokens)) {
                $commandArguments.Add((Format-PackageProcessArgument -Value $token)) | Out-Null
            }

            foreach ($argument in @($operation.commandArguments)) {
                $resolvedArgument = Resolve-PackageTemplateText -Text ([string]$argument) -PackageConfig $PackageResult.PackageConfig -Package $PackageResult.Package -ExtraTokens @{
                    packageFilePath                = $PackageResult.PackageFilePath
                    installDirectory               = $PackageResult.InstallDirectory
                    packageFileStagingDirectory    = $PackageResult.PackageFileStagingDirectory
                    packageInstallStageDirectory   = $PackageResult.PackageInstallStageDirectory
                    downloadDirectory              = $PackageResult.PackageFileStagingDirectory
                }
                $commandArguments.Add((Format-PackageProcessArgument -Value $resolvedArgument)) | Out-Null
            }

            $timeoutSec = [int]$operation.timeoutSec
            $successExitCodes = @($operation.successExitCodes | ForEach-Object { [int]$_ })
            $restartExitCodes = @($operation.restartExitCodes | ForEach-Object { [int]$_ })
            $uiMode = [string]$operation.uiMode
            $workingDirectory = if (-not [string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory) -and (Test-Path -LiteralPath $PackageResult.InstallDirectory -PathType Container)) {
                [string]$PackageResult.InstallDirectory
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$PackageResult.PackageInstallStageDirectory)) {
                [string]$PackageResult.PackageInstallStageDirectory
            }
            else {
                [System.IO.Path]::GetTempPath()
            }

            $elevationMode = if ($operation.PSObject.Properties['elevation'] -and -not [string]::IsNullOrWhiteSpace([string]$operation.elevation)) {
                [string]$operation.elevation
            }
            else {
                $null
            }

            $null = Invoke-PackageInstallerCommand -PackageResult $PackageResult -CommandPath $parsed.Executable -CommandArguments @($commandArguments.ToArray()) -WorkingDirectory $workingDirectory -TimeoutSec $timeoutSec -SuccessExitCodes @($successExitCodes) -RestartExitCodes @($restartExitCodes) -TargetKind 'directory' -InstallerKind 'nsis' -UiMode $uiMode -LogPath $null -ElevationMode $elevationMode
            Write-PackageExecutionMessage -Message '[ACTION] Completed nsisUninstaller removal operation.'
        }
        default {
            throw "Unsupported removed.operation.kind '$kind'."
        }
    }

    return $PackageResult
}

function Invoke-PackagePostRemoveCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $flags = $PackageResult.PackageConfig.Definition.packageOperations.removed.postRemoveCleanup

    if ($flags.generatedShims) {
        $null = Remove-PackageCommandShimsForDefinition -PackageResult $PackageResult
    }
    else {
        Write-PackageExecutionMessage -Message '[STATE] postRemoveCleanup.generatedShims is false; skipping shim removal.'
    }

    if ($flags.pathEntries) {
        $null = Unregister-PackagePathForRemoval -PackageResult $PackageResult
    }
    else {
        Write-PackageExecutionMessage -Message '[STATE] postRemoveCleanup.pathEntries is false; skipping PATH cleanup.'
    }

    if ($flags.packageInventoryRecord) {
        if ($PackageResult.PSObject.Properties['InventoryRemovalSkipped'] -and [bool]$PackageResult.InventoryRemovalSkipped) {
            Write-PackageExecutionMessage -Message '[STATE] postRemoveCleanup.packageInventoryRecord skipped because there was no inventory record.'
        }
        else {
            $null = Remove-PackageInventoryRecordForInstallSlot -PackageResult $PackageResult
        }
    }
    else {
        Write-PackageExecutionMessage -Message '[STATE] postRemoveCleanup.packageInventoryRecord is false; skipping inventory record removal.'
    }

    if ($flags.workDirectories) {
        $null = Clear-PackageWorkDirectories -PackageResult $PackageResult
    }
    else {
        Write-PackageExecutionMessage -Message '[STATE] postRemoveCleanup.workDirectories is false; skipping staging directory cleanup.'
    }

    return $PackageResult
}

function Invoke-PackageRemovedFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    try {
        Write-PackageExecutionMessage -Message ("[START] Invoke-PackageDefinitionCommand repository='{0}' definition='{1}' desiredState='{2}'." -f $PackageResult.RepositoryId, $PackageResult.DefinitionId, $PackageResult.DesiredState)

        $PackageResult.CurrentStep = 'InitializeLocalEnvironment'
        Write-PackageExecutionMessage -Message '[STEP] Initializing local package environment.'
        $PackageResult.LocalEnvironment = Initialize-PackageLocalEnvironment -PackageConfig $PackageResult.PackageConfig
        if ($PackageResult.LocalEnvironment.InitializedNow) {
            Write-PackageExecutionMessage -Message ("[STATE] Local package environment initialized: created={0}, existing={1}, skippedSources={2}." -f @($PackageResult.LocalEnvironment.CreatedDirectories).Count, @($PackageResult.LocalEnvironment.ExistingDirectories).Count, @($PackageResult.LocalEnvironment.SkippedSources).Count)
        }
        else {
            Write-PackageExecutionMessage -Message '[STATE] Local package environment already initialized.'
        }

        $PackageResult.CurrentStep = 'ResolvePackage'
        Write-PackageExecutionMessage -Message '[STEP] Resolving package selection.'
        $PackageResult = Resolve-PackagePackage -PackageResult $PackageResult

        $PackageResult.CurrentStep = 'ResolvePaths'
        Write-PackageExecutionMessage -Message '[STEP] Resolving package paths.'
        $PackageResult = Resolve-PackagePaths -PackageResult $PackageResult

        $PackageResult.CurrentStep = 'ResolveRemovalInstallContext'
        Write-PackageExecutionMessage -Message '[STEP] Resolving removal inventory context.'
        $PackageResult = Resolve-PackageRemovalInstallContext -PackageResult $PackageResult

        $PackageResult.CurrentStep = 'AssertRemovalPolicy'
        Write-PackageExecutionMessage -Message '[STEP] Evaluating removal policy.'
        $PackageResult = Assert-PackageRemovalPolicy -PackageResult $PackageResult

        $PackageResult.CurrentStep = 'AssertRemovalDependencyDependents'
        Write-PackageExecutionMessage -Message '[STEP] Checking for installed packages that still declare this package as a dependency.'
        $PackageResult = Assert-PackageRemovalDependencyDependents -PackageResult $PackageResult

        $PackageResult.CurrentStep = 'ExecuteRemovedOperation'
        Write-PackageExecutionMessage -Message '[STEP] Executing removed.operation.'
        $PackageResult = Invoke-PackageRemovedOperation -PackageResult $PackageResult

        $PackageResult.CurrentStep = 'PostRemoveCleanup'
        Write-PackageExecutionMessage -Message '[STEP] Running post-remove cleanup.'
        $PackageResult = Invoke-PackagePostRemoveCleanup -PackageResult $PackageResult

        $PackageResult.CurrentStep = 'VerifyRemovedAbsence'
        Write-PackageExecutionMessage -Message '[STEP] Verifying removed absence.'
        $PackageResult = Test-PackageRemovedAbsence -PackageResult $PackageResult

        Write-PackageExecutionMessage -Message ("[OK] Package removal completed for definition '{0}'." -f $PackageResult.DefinitionId)
    }
    catch {
        $PackageResult.Status = 'Failed'
        $PackageResult.ErrorMessage = $_.Exception.Message
        Write-PackageExecutionMessage -Level 'ERR' -Message ("[FAIL] Step '{0}' failed: {1}" -f $PackageResult.CurrentStep, $_.Exception.Message)
        $PackageResult.FailureReason = Get-PackageCommandFailureReason -CurrentStep ([string]$PackageResult.CurrentStep)
    }

    return $PackageResult
}
