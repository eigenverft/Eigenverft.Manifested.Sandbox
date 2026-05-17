<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionSchema.Wire1_5
    Validators and runtime projection for package definition schemaVersion 1.5.
#>

function Get-PackageObjectPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $InputObject -or -not $InputObject.PSObject.Properties[$Name]) {
        return $null
    }

    return $InputObject.$Name
}

function Test-PackageObjectHasProperty {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [psobject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return ($InputObject -and $InputObject.PSObject.Properties[$Name])
}

function Get-PackagePresenceDiscoveryEntryPoints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('commands', 'apps')]
        [string]$ToolKind,

        [switch]$ExposedOnly
    )

    if (-not (Test-PackageObjectHasProperty -InputObject $Definition -Name 'presenceDiscovery') -or
        -not (Test-PackageObjectHasProperty -InputObject $Definition.presenceDiscovery -Name $ToolKind)) {
        return @()
    }

    $exposedPropertyName = if ([string]::Equals($ToolKind, 'commands', [System.StringComparison]::Ordinal)) {
        'exposeCommand'
    }
    else {
        'exposeApp'
    }

    return @(
        foreach ($entryPoint in @($Definition.presenceDiscovery.$ToolKind)) {
            if ($null -eq $entryPoint) {
                continue
            }
            if ($ExposedOnly -and (
                    -not $entryPoint.PSObject.Properties[$exposedPropertyName] -or
                    -not [bool]$entryPoint.$exposedPropertyName)) {
                continue
            }
            $entryPoint
        }
    )
}

function Get-PackagePresenceDiscoveryEntryPoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('commands', 'apps')]
        [string]$ToolKind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [switch]$ExposedOnly
    )

    foreach ($entryPoint in @(Get-PackagePresenceDiscoveryEntryPoints -Definition $Definition -ToolKind $ToolKind -ExposedOnly:$ExposedOnly)) {
        if ([string]::Equals([string]$entryPoint.name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entryPoint
        }
    }

    return $null
}

function Resolve-PackagePresenceEntryPointPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EntryPoint,

        [Parameter(Mandatory = $true)]
        [string]$InstallDirectory
    )

    return (Join-Path $InstallDirectory (([string]$EntryPoint.relativePath) -replace '/', '\'))
}

function Resolve-PackagePresenceToolPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('commands', 'apps')]
        [string]$ToolKind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$InstallDirectory
    )

    $entryPoint = Get-PackagePresenceDiscoveryEntryPoint -Definition $Definition -ToolKind $ToolKind -Name $Name
    if (-not $entryPoint) {
        return $null
    }

    return (Resolve-PackagePresenceEntryPointPath -EntryPoint $entryPoint -InstallDirectory $InstallDirectory)
}

function Assert-PackageDefinitionNoRetiredNestedProperty_1_5 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [AllowNull()]
        [psobject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $true)]
        [string]$PropertyPath,

        [Parameter(Mandatory = $true)]
        [string]$ReplacementPath
    )

    if ($InputObject -and $InputObject.PSObject.Properties[$PropertyName]) {
        throw "Package definition '$DefinitionId' still uses retired property '$PropertyPath'. Use '$ReplacementPath'."
    }
}

function Assert-PackageArtifactTrustMetadata_1_5 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$TargetId,

        [AllowNull()]
        [psobject]$Artifact
    )

    if (-not $Artifact) {
        return
    }

    foreach ($retiredProperty in @('autoUpdateSupported', 'integrity', 'authenticode')) {
        if ($Artifact.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' still uses retired packageFile.$retiredProperty. Use artifact contentHash or publisherSignature metadata."
        }
    }

    if ($Artifact.PSObject.Properties['contentHash']) {
        $contentHash = $Artifact.contentHash
        if (-not $contentHash -or
            -not $contentHash.PSObject.Properties['algorithm'] -or
            [string]::IsNullOrWhiteSpace([string]$contentHash.algorithm)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.contentHash without algorithm."
        }
        if (-not [string]::Equals([string]$contentHash.algorithm, 'sha256', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' uses unsupported packageFile.contentHash algorithm '$($contentHash.algorithm)'. Use sha256."
        }
        if (-not $contentHash.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$contentHash.value)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.contentHash without value."
        }
    }

    if ($Artifact.PSObject.Properties['publisherSignature']) {
        $publisherSignature = $Artifact.publisherSignature
        if (-not $publisherSignature -or
            -not $publisherSignature.PSObject.Properties['kind'] -or
            [string]::IsNullOrWhiteSpace([string]$publisherSignature.kind)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.publisherSignature without kind."
        }
        if (-not [string]::Equals([string]$publisherSignature.kind, 'authenticode', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' uses unsupported packageFile.publisherSignature kind '$($publisherSignature.kind)'. Use authenticode."
        }
        if (-not $publisherSignature.PSObject.Properties['requireValid']) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.publisherSignature without requireValid."
        }
        if (-not $publisherSignature.PSObject.Properties['subjectContains'] -or [string]::IsNullOrWhiteSpace([string]$publisherSignature.subjectContains)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.publisherSignature without subjectContains."
        }
    }
}

function Assert-PackagePresenceRequirementFlags_1_5 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [string]$PropertyPath,

        [Parameter(Mandatory = $true)]
        [psobject]$Require
    )

    $requiredRequirements = @('files', 'directories', 'commands', 'apps', 'metadataFiles', 'signatures', 'fileDetails', 'registry', 'powerShellModules')
    foreach ($required in @($requiredRequirements)) {
        if (-not $Require.PSObject.Properties[$required]) {
            throw "Package definition '$DefinitionId' requires '$PropertyPath.require.$required'."
        }
        if ($Require.$required -isnot [bool]) {
            throw "Package definition '$DefinitionId' field '$PropertyPath.require.$required' must be boolean."
        }
    }
}

function Test-PackageDefinitionTextPropertyPresent_1_5 {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [psobject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    return ($InputObject -and
        $InputObject.PSObject.Properties[$PropertyName] -and
        -not [string]::IsNullOrWhiteSpace([string]$InputObject.$PropertyName))
}

function Assert-PackageExistingInstallDiscovery_1_5 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [psobject]$ExistingInstallDiscovery
    )

    foreach ($required in @('enabled', 'searchLocations', 'installRootRules')) {
        if (-not $ExistingInstallDiscovery.PSObject.Properties[$required]) {
            throw "Package definition '$DefinitionId' is missing existingInstallDiscovery.$required."
        }
    }

    $searchLocationIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($location in @($ExistingInstallDiscovery.searchLocations)) {
        foreach ($required in @('id', 'kind', 'searchOrder')) {
            if (-not $location.PSObject.Properties[$required] -or [string]::IsNullOrWhiteSpace([string]$location.$required)) {
                throw "Package definition '$DefinitionId' existingInstallDiscovery.searchLocations entry is missing '$required'."
            }
        }
        if (-not $searchLocationIds.Add([string]$location.id)) {
            throw "Package definition '$DefinitionId' has duplicate existingInstallDiscovery.searchLocations id '$($location.id)'."
        }
        switch -Exact ([string]$location.kind) {
            'command' {
                if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $location -PropertyName 'name')) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' kind command requires name."
                }
            }
            'path' {
                if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $location -PropertyName 'path')) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' kind path requires path."
                }
            }
            'directory' {
                if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $location -PropertyName 'path')) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' kind directory requires path."
                }
            }
            'windowsUninstallRegistryKey' {
                if (-not $location.PSObject.Properties['paths'] -or @($location.paths).Count -eq 0) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' kind windowsUninstallRegistryKey requires paths."
                }
                foreach ($path in @($location.paths)) {
                    if ([string]::IsNullOrWhiteSpace([string]$path)) {
                        throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' has an empty registry path."
                    }
                }
                if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $location -PropertyName 'installDirectorySource')) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' kind windowsUninstallRegistryKey requires installDirectorySource."
                }
                if ([string]$location.installDirectorySource -notin @('installLocation', 'displayIcon', 'displayIconDirectory', 'uninstallString', 'uninstallStringDirectory')) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' uses unsupported installDirectorySource '$($location.installDirectorySource)'."
                }
            }
            'powershellModule' {
                if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $location -PropertyName 'name')) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' kind powershellModule requires name."
                }
                if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $location -PropertyName 'requiredVersion')) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' kind powershellModule requires requiredVersion."
                }
                if ($location.PSObject.Properties['scope'] -and
                    -not [string]::Equals([string]$location.scope, 'CurrentUser', [System.StringComparison]::OrdinalIgnoreCase) -and
                    -not [string]::Equals([string]$location.scope, 'AllUsers', [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' kind powershellModule uses unsupported scope '$($location.scope)'. Use CurrentUser or AllUsers."
                }
                if ($location.PSObject.Properties['requireNuGetProvider'] -and $location.requireNuGetProvider -isnot [bool]) {
                    throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' kind powershellModule requireNuGetProvider must be boolean."
                }
            }
            default {
                throw "Package definition '$DefinitionId' existingInstallDiscovery search '$($location.id)' uses unsupported kind '$($location.kind)'."
            }
        }
    }

    foreach ($rule in @($ExistingInstallDiscovery.installRootRules)) {
        if (-not $rule.PSObject.Properties['match'] -or -not $rule.match) {
            throw "Package definition '$DefinitionId' installRootRules entry requires match."
        }
        if (-not $rule.match.PSObject.Properties['kind'] -or -not [string]::Equals([string]$rule.match.kind, 'fileName', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package definition '$DefinitionId' installRootRules.match currently supports only kind 'fileName'."
        }
        if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $rule.match -PropertyName 'value')) {
            throw "Package definition '$DefinitionId' installRootRules.match kind fileName requires value."
        }
        if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $rule -PropertyName 'installRootRelativePath')) {
            throw "Package definition '$DefinitionId' installRootRules entry requires installRootRelativePath."
        }
    }
}

function Assert-PackageAssignedInstallOperation_1_5 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [psobject]$AssignedInstall
    )

    if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $AssignedInstall -PropertyName 'kind')) {
        throw "Package definition '$DefinitionId' is missing packageOperations.assigned.install.kind."
    }

    switch -Exact ([string]$AssignedInstall.kind) {
        'nsisInstaller' {
            if ($AssignedInstall.PSObject.Properties['installerKind'] -and
                -not [string]::Equals([string]$AssignedInstall.installerKind, 'nsis', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Package definition '$DefinitionId' nsisInstaller cannot use installerKind '$($AssignedInstall.installerKind)'. Use innoSetupInstaller for Inno Setup packages."
            }
            if (-not $AssignedInstall.PSObject.Properties['targetDirectoryArgument'] -or -not $AssignedInstall.targetDirectoryArgument) {
                throw "Package definition '$DefinitionId' nsisInstaller requires targetDirectoryArgument."
            }
            $targetArgument = $AssignedInstall.targetDirectoryArgument
            if (-not $targetArgument.PSObject.Properties['enabled'] -or $targetArgument.enabled -isnot [bool]) {
                throw "Package definition '$DefinitionId' nsisInstaller targetDirectoryArgument.enabled must be boolean."
            }
            if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $targetArgument -PropertyName 'prefix')) {
                throw "Package definition '$DefinitionId' nsisInstaller targetDirectoryArgument.prefix must not be empty."
            }
        }
        'innoSetupInstaller' {
            foreach ($required in @('installDirectory', 'commandArguments', 'targetDirectoryArgument')) {
                if (-not $AssignedInstall.PSObject.Properties[$required]) {
                    throw "Package definition '$DefinitionId' innoSetupInstaller requires $required."
                }
            }
            $targetArgument = $AssignedInstall.targetDirectoryArgument
            if (-not $targetArgument.PSObject.Properties['enabled'] -or $targetArgument.enabled -isnot [bool]) {
                throw "Package definition '$DefinitionId' innoSetupInstaller targetDirectoryArgument.enabled must be boolean."
            }
            if ($targetArgument.enabled) {
                if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $targetArgument -PropertyName 'prefix')) {
                    throw "Package definition '$DefinitionId' innoSetupInstaller targetDirectoryArgument.prefix is required when enabled."
                }
                if (-not $targetArgument.PSObject.Properties['quoteValue'] -or $targetArgument.quoteValue -isnot [bool]) {
                    throw "Package definition '$DefinitionId' innoSetupInstaller targetDirectoryArgument.quoteValue must be boolean."
                }
            }
        }
        'powershellModuleInstaller' {
            foreach ($required in @('moduleName', 'requiredVersion')) {
                if (-not (Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $AssignedInstall -PropertyName $required)) {
                    throw "Package definition '$DefinitionId' powershellModuleInstaller requires $required."
                }
            }
            if ($AssignedInstall.PSObject.Properties['scope'] -and
                -not [string]::Equals([string]$AssignedInstall.scope, 'CurrentUser', [System.StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::Equals([string]$AssignedInstall.scope, 'AllUsers', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Package definition '$DefinitionId' powershellModuleInstaller uses unsupported scope '$($AssignedInstall.scope)'. Use CurrentUser or AllUsers."
            }
            if ($AssignedInstall.PSObject.Properties['timeoutSec'] -and [int]$AssignedInstall.timeoutSec -lt 1) {
                throw "Package definition '$DefinitionId' powershellModuleInstaller timeoutSec must be greater than zero."
            }
        }
    }
}

function Assert-PackageRemovedOperation_1_5 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [psobject]$RemovedOperation
    )

    if (-not $RemovedOperation.PSObject.Properties['policy']) {
        throw "Package definition '$DefinitionId' is missing packageOperations.removed.policy."
    }
    if (-not $RemovedOperation.PSObject.Properties['operation']) {
        throw "Package definition '$DefinitionId' is missing packageOperations.removed.operation."
    }
    if (-not $RemovedOperation.PSObject.Properties['absenceVerification']) {
        throw "Package definition '$DefinitionId' is missing packageOperations.removed.absenceVerification."
    }
    if (-not $RemovedOperation.PSObject.Properties['postRemoveCleanup']) {
        throw "Package definition '$DefinitionId' is missing packageOperations.removed.postRemoveCleanup."
    }

    $policy = $RemovedOperation.policy
    foreach ($requiredPolicyProperty in @('whenNotInInventory', 'allowedInventoryOwnershipKinds', 'allowUntrackedExternalRemoval', 'removeDependencies')) {
        if (-not $policy.PSObject.Properties[$requiredPolicyProperty]) {
            throw "Package definition '$DefinitionId' is missing packageOperations.removed.policy.$requiredPolicyProperty."
        }
    }
    if (-not [string]::Equals([string]$policy.whenNotInInventory, 'succeed', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals([string]$policy.whenNotInInventory, 'fail', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package definition '$DefinitionId' uses unsupported packageOperations.removed.policy.whenNotInInventory value '$($policy.whenNotInInventory)'."
    }
    foreach ($kind in @($policy.allowedInventoryOwnershipKinds)) {
        if ([string]::IsNullOrWhiteSpace([string]$kind)) {
            throw "Package definition '$DefinitionId' has empty packageOperations.removed.policy.allowedInventoryOwnershipKinds entry."
        }
        if (-not [string]::Equals([string]$kind, 'PackageInstalled', [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::Equals([string]$kind, 'PackageApplied', [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::Equals([string]$kind, 'AdoptedExternal', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package definition '$DefinitionId' uses unsupported packageOperations.removed.policy.allowedInventoryOwnershipKinds value '$kind'."
        }
    }
    if ($policy.allowUntrackedExternalRemoval -isnot [bool]) {
        throw "Package definition '$DefinitionId' requires packageOperations.removed.policy.allowUntrackedExternalRemoval to be boolean."
    }
    if ($policy.removeDependencies -isnot [bool]) {
        throw "Package definition '$DefinitionId' requires packageOperations.removed.policy.removeDependencies to be boolean."
    }

    $operation = $RemovedOperation.operation
    if (-not $operation.PSObject.Properties['kind']) {
        throw "Package definition '$DefinitionId' is missing packageOperations.removed.operation.kind."
    }
    $operationKind = [string]$operation.kind
    switch ($operationKind) {
        'deleteInstallDirectory' {
            if (-not $operation.PSObject.Properties['pathSource'] -or
                -not [string]::Equals([string]$operation.pathSource, 'inventory.installDirectory', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Package definition '$DefinitionId' removed.operation.kind 'deleteInstallDirectory' requires pathSource = 'inventory.installDirectory'."
            }
        }
        { $_ -in @('nsisUninstaller', 'innoSetupUninstaller') } {
            foreach ($required in @('commandSource', 'commandArguments', 'elevation', 'timeoutSec', 'successExitCodes', 'restartExitCodes', 'uiMode')) {
                if (-not $operation.PSObject.Properties[$required]) {
                    throw "Package definition '$DefinitionId' missing packageOperations.removed.operation.$required."
                }
            }
            if (-not $operation.commandSource.PSObject.Properties['use'] -or -not [string]::Equals([string]$operation.commandSource.use, 'existingInstallDiscovery', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Package definition '$DefinitionId' packageOperations.removed.operation.commandSource.use must be 'existingInstallDiscovery'."
            }
            if (-not $operation.commandSource.PSObject.Properties['searchLocationId'] -or [string]::IsNullOrWhiteSpace([string]$operation.commandSource.searchLocationId)) {
                throw "Package definition '$DefinitionId' packageOperations.removed.operation.commandSource.searchLocationId is missing."
            }
            if (-not $operation.commandSource.PSObject.Properties['registryValueOrder'] -or @($operation.commandSource.registryValueOrder).Count -eq 0) {
                throw "Package definition '$DefinitionId' packageOperations.removed.operation.commandSource.registryValueOrder is missing."
            }
            foreach ($registryValue in @($operation.commandSource.registryValueOrder)) {
                if (-not [string]::Equals([string]$registryValue, 'QuietUninstallString', [System.StringComparison]::OrdinalIgnoreCase) -and
                    -not [string]::Equals([string]$registryValue, 'UninstallString', [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Package definition '$DefinitionId' packageOperations.removed.operation.commandSource.registryValueOrder contains unsupported value '$registryValue'."
                }
            }
            if (($operation.timeoutSec -isnot [int] -and $operation.timeoutSec -isnot [long]) -or $operation.timeoutSec -le 0) {
                throw "Package definition '$DefinitionId' packageOperations.removed.operation.timeoutSec must be a positive integer."
            }
            if (-not ($operation.successExitCodes -is [array])) {
                throw "Package definition '$DefinitionId' packageOperations.removed.operation.successExitCodes must be an array."
            }
            if (-not ($operation.restartExitCodes -is [array])) {
                throw "Package definition '$DefinitionId' packageOperations.removed.operation.restartExitCodes must be an array."
            }
        }
        'none' {
            # no operation-specific fields required.
        }
        default {
            throw "Package definition '$DefinitionId' uses unsupported packageOperations.removed.operation.kind '$operationKind'."
        }
    }

    $absence = $RemovedOperation.absenceVerification
    if (-not $absence.PSObject.Properties['use'] -or -not [string]::Equals([string]$absence.use, 'presenceDiscovery', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package definition '$DefinitionId' requires packageOperations.removed.absenceVerification.use = 'presenceDiscovery'."
    }
    if (-not $absence.PSObject.Properties['require']) {
        throw "Package definition '$DefinitionId' is missing packageOperations.removed.absenceVerification.require."
    }
    Assert-PackagePresenceRequirementFlags_1_5 -DefinitionId $DefinitionId -PropertyPath 'packageOperations.removed.absenceVerification' -Require $absence.require

    $postRemoveCleanup = $RemovedOperation.postRemoveCleanup
    foreach ($requiredPost in @('packageInventoryRecord', 'generatedShims', 'pathEntries', 'workDirectories')) {
        if (-not $postRemoveCleanup.PSObject.Properties[$requiredPost]) {
            throw "Package definition '$DefinitionId' requires packageOperations.removed.postRemoveCleanup.$requiredPost."
        }
        if ($postRemoveCleanup.$requiredPost -isnot [bool]) {
            throw "Package definition '$DefinitionId' packageOperations.removed.postRemoveCleanup.$requiredPost must be boolean."
        }
    }
}

function Assert-PackageDefinitionSchema_1_5 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$DefinitionDocumentInfo,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [AllowNull()]
        [string]$PublisherId = $null
    )

    $definition = $DefinitionDocumentInfo.Document
    foreach ($retiredProperty in @('releases', 'providedTools', 'shared', 'releaseDefaults', 'installedStateDiscovery', 'installedStateCheck', 'existingInstallPolicy')) {
        if ($definition.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' still uses retired property '$retiredProperty'."
        }
    }

    foreach ($retiredProperty in @('id')) {
        if ($definition.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' still uses retired top-level property 'id'. Use definitionPublication.definitionId instead."
        }
    }

    foreach ($requiredProperty in @('schemaVersion', 'definitionPublication', 'display', 'dependencies', 'artifacts', 'presenceDiscovery', 'existingInstallDiscovery', 'packageOperations')) {
        if (-not $definition.PSObject.Properties[$requiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' is missing required schemaVersion 1.5 property '$requiredProperty'."
        }
    }
    foreach ($retiredProperty in @('definitionId', 'repositoryId')) {
        if ($definition.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' still uses retired schema 1.4 root property '$retiredProperty'. Move definition identity to definitionPublication."
        }
    }

    foreach ($requiredPublicationProperty in @('publisherId', 'publisherName', 'definitionId', 'definitionRevision', 'publishedAtUtc')) {
        if (-not $definition.definitionPublication.PSObject.Properties[$requiredPublicationProperty]) {
            throw "Package definition '$DefinitionId' is missing definitionPublication.$requiredPublicationProperty."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$definition.definitionPublication.publisherId)) {
        throw "Package definition '$DefinitionId' definitionPublication.publisherId must not be empty."
    }
    Assert-PackagePublisherId -PublisherId ([string]$definition.definitionPublication.publisherId)
    if ([string]::IsNullOrWhiteSpace([string]$definition.definitionPublication.publisherName)) {
        throw "Package definition '$DefinitionId' definitionPublication.publisherName must not be empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$definition.definitionPublication.definitionId)) {
        throw "Package definition '$DefinitionId' definitionPublication.definitionId must not be empty."
    }
    if (-not [string]::Equals([string]$definition.definitionPublication.definitionId, $DefinitionId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package definition definitionPublication.definitionId '$($definition.definitionPublication.definitionId)' does not match expected id '$DefinitionId'."
    }
    if (-not [string]::IsNullOrWhiteSpace($PublisherId) -and
        -not [string]::Equals([string]$definition.definitionPublication.publisherId, [string]$PublisherId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package definition '$DefinitionId' publisher '$($definition.definitionPublication.publisherId)' does not match expected publisher '$PublisherId'."
    }
    $revision = 0
    if (-not [int]::TryParse([string]$definition.definitionPublication.definitionRevision, [ref]$revision) -or $revision -lt 1) {
        throw "Package definition '$DefinitionId' definitionPublication.definitionRevision must be a positive integer."
    }
    $pubRaw = $definition.definitionPublication.publishedAtUtc
    $publishedAtUtc = [DateTime]::MinValue
    if ($pubRaw -is [datetime]) {
        $publishedAtUtc = [datetime]$pubRaw
    }
    elseif (-not [DateTime]::TryParse([string]$pubRaw, [CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$publishedAtUtc) -and
        -not [DateTime]::TryParse([string]$pubRaw, [ref]$publishedAtUtc)) {
        throw "Package definition '$DefinitionId' definitionPublication.publishedAtUtc must be a valid UTC timestamp."
    }

    if (-not $definition.artifacts.PSObject.Properties['targets']) {
        throw "Package definition '$DefinitionId' is missing required artifacts.targets array."
    }
    if (-not $definition.artifacts.PSObject.Properties['releases']) {
        throw "Package definition '$DefinitionId' is missing required artifacts.releases array."
    }
    Assert-PackageExistingInstallDiscovery_1_5 -DefinitionId $DefinitionId -ExistingInstallDiscovery $definition.existingInstallDiscovery

    $targetIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $targetsById = @{}
    foreach ($target in @($definition.artifacts.targets)) {
        if (-not $target.PSObject.Properties['id'] -or [string]::IsNullOrWhiteSpace([string]$target.id)) {
            throw "Package definition '$DefinitionId' has artifact target without id."
        }
        if (-not $targetIds.Add([string]$target.id)) {
            throw "Package definition '$DefinitionId' has duplicate artifact target id '$($target.id)'."
        }
        $targetsById[[string]$target.id] = $target
        foreach ($requiredTargetProperty in @('releaseTrack', 'artifactDistributionVariant', 'constraints', 'versionSelection')) {
            if (-not $target.PSObject.Properties[$requiredTargetProperty]) {
                throw "Package definition '$DefinitionId' artifact target '$($target.id)' is missing '$requiredTargetProperty'."
            }
        }
        if (-not [string]::Equals([string]$target.versionSelection.strategy, 'latestByVersion', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package definition '$DefinitionId' artifact target '$($target.id)' uses unsupported versionSelection.strategy '$($target.versionSelection.strategy)'. Use latestByVersion."
        }
    }

    $dependencies = if (Test-PackageObjectHasProperty -InputObject $definition -Name 'dependencies') { @($definition.dependencies) } else { @() }
    foreach ($dependency in @($dependencies)) {
        if ($null -eq $dependency) {
            continue
        }
        if ($dependency.PSObject.Properties['repositoryId']) {
            throw "Package definition '$DefinitionId' dependency still uses retired property 'repositoryId'. Use dependency.publisherId or omit it."
        }
        if ($dependency.PSObject.Properties['repositorySourceId']) {
            throw "Package definition '$DefinitionId' dependency still uses retired property 'repositorySourceId'. Use dependency.publisherId or omit it."
        }
        if ($dependency.PSObject.Properties['publisherId'] -and [string]::IsNullOrWhiteSpace([string]$dependency.publisherId)) {
            throw "Package definition '$DefinitionId' has dependency with empty publisherId."
        }
        if ($dependency.PSObject.Properties['publisherId']) {
            Assert-PackagePublisherId -PublisherId ([string]$dependency.publisherId)
        }
        if (-not $dependency.PSObject.Properties['definitionId'] -or [string]::IsNullOrWhiteSpace([string]$dependency.definitionId)) {
            throw "Package definition '$DefinitionId' has dependency without definitionId."
        }
    }

    $sharedOperation = if ($definition.packageOperations.PSObject.Properties['policy']) { $definition.packageOperations.policy } else { $null }
    $ownershipPolicy = if ($sharedOperation -and $sharedOperation.PSObject.Properties['ownershipPolicy']) { $sharedOperation.ownershipPolicy } else { $null }
    Assert-PackageDefinitionNoRetiredNestedProperty_1_5 -DefinitionId $DefinitionId -InputObject $ownershipPolicy -PropertyName 'requireManagedOwnership' -PropertyPath 'packageOperations.policy.ownershipPolicy.requireManagedOwnership' -ReplacementPath 'packageOperations.policy.ownershipPolicy.requirePackageOwnership'

    $assignedOperation = if ($definition.packageOperations.PSObject.Properties['assigned']) { $definition.packageOperations.assigned } else { $null }
    $assignedInstall = if ($assignedOperation -and $assignedOperation.PSObject.Properties['install']) { $assignedOperation.install } else { $null }
    Assert-PackageDefinitionNoRetiredNestedProperty_1_5 -DefinitionId $DefinitionId -InputObject $assignedOperation -PropertyName 'managerDependency' -PropertyPath 'packageOperations.assigned.managerDependency' -ReplacementPath 'dependencies plus packageOperations.assigned.install.installerCommand'
    Assert-PackageDefinitionNoRetiredNestedProperty_1_5 -DefinitionId $DefinitionId -InputObject $assignedInstall -PropertyName 'managerDependency' -PropertyPath 'packageOperations.assigned.install.managerDependency' -ReplacementPath 'dependencies plus packageOperations.assigned.install.installerCommand'
    Assert-PackageDefinitionNoRetiredNestedProperty_1_5 -DefinitionId $DefinitionId -InputObject $assignedOperation -PropertyName 'managerKind' -PropertyPath 'packageOperations.assigned.managerKind' -ReplacementPath 'packageOperations.assigned.install.kind = npmGlobalPackage'
    Assert-PackageDefinitionNoRetiredNestedProperty_1_5 -DefinitionId $DefinitionId -InputObject $assignedInstall -PropertyName 'managerKind' -PropertyPath 'packageOperations.assigned.install.managerKind' -ReplacementPath 'packageOperations.assigned.install.kind = npmGlobalPackage'
    if (-not $assignedInstall) {
        throw "Package definition '$DefinitionId' is missing packageOperations.assigned.install."
    }
    Assert-PackageAssignedInstallOperation_1_5 -DefinitionId $DefinitionId -AssignedInstall $assignedInstall
    if (-not $definition.packageOperations.PSObject.Properties['removed']) {
        throw "Package definition '$DefinitionId' is missing required packageOperations.removed."
    }
    Assert-PackageRemovedOperation_1_5 -DefinitionId $DefinitionId -RemovedOperation $definition.packageOperations.removed

    if (-not $definition.artifacts.sources) {
        throw "Package definition '$DefinitionId' is missing artifacts.sources map."
    }

    foreach ($sourceProperty in @($definition.artifacts.sources.PSObject.Properties)) {
        $source = $sourceProperty.Value
        if (-not $source.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$source.kind)) {
            throw "Package definition '$DefinitionId' artifacts source '$($sourceProperty.Name)' is missing kind."
        }
    }

    foreach ($versionEntry in @($definition.artifacts.releases)) {
        if ($versionEntry.PSObject.Properties['artifactsByTarget']) {
            throw "Package definition '$DefinitionId' release '$($versionEntry.version)' still uses retired property 'artifactsByTarget'."
        }
        Assert-PackageDefinitionNoRetiredNestedProperty_1_5 -DefinitionId $DefinitionId -InputObject $versionEntry -PropertyName 'artifactsByTarget' -PropertyPath 'artifacts.releases[].artifactsByTarget' -ReplacementPath 'targetArtifacts'
        if (-not $versionEntry.PSObject.Properties['version'] -or [string]::IsNullOrWhiteSpace([string]$versionEntry.version)) {
            throw "Package definition '$DefinitionId' has release entry without version."
        }
        if (-not $versionEntry.PSObject.Properties['releaseTracks'] -or $null -eq $versionEntry.releaseTracks) {
            throw "Package definition '$DefinitionId' release '$($versionEntry.version)' is missing releaseTracks."
        }
        if (-not $versionEntry.PSObject.Properties['targetArtifacts'] -or $null -eq $versionEntry.targetArtifacts) {
            throw "Package definition '$DefinitionId' release '$($versionEntry.version)' is missing targetArtifacts."
        }

        $releaseUpstream = if ($versionEntry.PSObject.Properties['upstreamRelease']) { $versionEntry.upstreamRelease } else { $null }

        foreach ($artifactProperty in @($versionEntry.targetArtifacts.PSObject.Properties)) {
            if (-not $targetIds.Contains([string]$artifactProperty.Name)) {
                throw "Package definition '$DefinitionId' release '$($versionEntry.version)' references unknown artifact target '$($artifactProperty.Name)'."
            }

            $artifact = $artifactProperty.Value
            if (-not $artifact -or -not $artifact.PSObject.Properties['artifactId'] -or [string]::IsNullOrWhiteSpace([string]$artifact.artifactId)) {
                throw "Package definition '$DefinitionId' release '$($versionEntry.version)' artifact '$($artifactProperty.Name)' is missing artifactId."
            }

            Assert-PackageArtifactTrustMetadata_1_5 -DefinitionId $DefinitionId -Version ([string]$versionEntry.version) -TargetId ([string]$artifactProperty.Name) -Artifact $artifact

            $artifactAcquisitionCandidates = if ($artifact.PSObject.Properties['acquisitionCandidates']) { @($artifact.acquisitionCandidates) } else { @() }
            if (-not $artifactAcquisitionCandidates -and $targetsById[[string]$artifactProperty.Name] -and $targetsById[[string]$artifactProperty.Name].PSObject.Properties['acquisitionCandidates']) {
                $artifactAcquisitionCandidates = @($targetsById[[string]$artifactProperty.Name].acquisitionCandidates)
            }

            foreach ($candidate in @($artifactAcquisitionCandidates)) {
                if ($candidate.PSObject.Properties['priority']) {
                    throw "Package definition '$DefinitionId' release '$($versionEntry.version)' artifact '$($artifactProperty.Name)' still uses retired acquisitionCandidate property 'priority'. Use searchOrder."
                }
                if (-not [string]::Equals([string]$candidate.kind, 'download', [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                $hasSourceId = Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $candidate -PropertyName 'sourceId'
                $hasCandidateSourcePath = Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $candidate -PropertyName 'sourcePath'
                $hasArtifactSourcePath = Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $artifact -PropertyName 'sourcePath'
                $hasCandidateUrl = Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $candidate -PropertyName 'url'
                $hasCandidateUrlTemplate = Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $candidate -PropertyName 'urlTemplate'
                $hasArtifactUrl = Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $artifact -PropertyName 'url'
                $hasArtifactUrlTemplate = Test-PackageDefinitionTextPropertyPresent_1_5 -InputObject $artifact -PropertyName 'urlTemplate'
                $directDownloadCount = 0
                foreach ($hasDirectDownload in @($hasCandidateUrl, $hasCandidateUrlTemplate, $hasArtifactUrl, $hasArtifactUrlTemplate)) {
                    if ($hasDirectDownload) {
                        $directDownloadCount++
                    }
                }

                if ($directDownloadCount -gt 1) {
                    throw "Package definition '$DefinitionId' release '$($versionEntry.version)' artifact '$($artifactProperty.Name)' download candidate must define only one direct url/urlTemplate location."
                }
                if ($directDownloadCount -gt 0 -and ($hasSourceId -or $hasCandidateSourcePath -or $hasArtifactSourcePath)) {
                    throw "Package definition '$DefinitionId' release '$($versionEntry.version)' artifact '$($artifactProperty.Name)' download candidate must use either direct url/urlTemplate or sourceId with sourcePath, not both."
                }
                if ($directDownloadCount -gt 0) {
                    continue
                }
                if (-not $hasSourceId) {
                    throw "Package definition '$DefinitionId' release '$($versionEntry.version)' artifact '$($artifactProperty.Name)' download candidate requires sourceId, direct url, or urlTemplate."
                }
                if (-not (Test-PackageObjectHasProperty -InputObject $definition.artifacts.sources -Name ([string]$candidate.sourceId))) {
                    throw "Package definition '$DefinitionId' release '$($versionEntry.version)' artifact '$($artifactProperty.Name)' references unknown artifacts source '$($candidate.sourceId)'."
                }

                $candidateSource = Get-PackageObjectPropertyValue -InputObject $definition.artifacts.sources -Name ([string]$candidate.sourceId)
                if ($candidateSource -and [string]::Equals([string]$candidateSource.kind, 'githubRelease', [System.StringComparison]::OrdinalIgnoreCase)) {
                    if (-not $releaseUpstream -or -not $releaseUpstream.PSObject.Properties['sourceId'] -or [string]::IsNullOrWhiteSpace([string]$releaseUpstream.sourceId) -or
                        -not [string]::Equals([string]$releaseUpstream.sourceId, [string]$candidate.sourceId, [System.StringComparison]::OrdinalIgnoreCase) -or
                        -not $releaseUpstream.PSObject.Properties['releaseTag'] -or [string]::IsNullOrWhiteSpace([string]$releaseUpstream.releaseTag)) {
                        throw "Package definition '$DefinitionId' release '$($versionEntry.version)' artifact '$($artifactProperty.Name)' requires releaseTag because candidate '$($candidate.sourceId)' uses GitHub release."
                    }
                    continue
                }

                if (-not ($hasCandidateSourcePath -or $hasArtifactSourcePath)) {
                    throw "Package definition '$DefinitionId' release '$($versionEntry.version)' artifact '$($artifactProperty.Name)' download candidate requires sourcePath, artifact sourcePath, url, or urlTemplate."
                }
            }
        }
    }

    $exposedCommands = @(Get-PackagePresenceDiscoveryEntryPoints -Definition $definition -ToolKind 'commands' -ExposedOnly)
    $assigned = $definition.packageOperations.assigned
    if ($assigned.PSObject.Properties['pathRegistration'] -and
        $assigned.pathRegistration.PSObject.Properties['source'] -and
        [string]::Equals([string]$assigned.pathRegistration.source.kind, 'shim', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not [string]::Equals([string]$assigned.pathRegistration.source.use, 'presenceDiscovery.commands', [System.StringComparison]::Ordinal)) {
            throw "Package definition '$DefinitionId' pathRegistration.source kind 'shim' requires use='presenceDiscovery.commands'."
        }
        if ($exposedCommands.Count -eq 0) {
            throw "Package definition '$DefinitionId' uses shim PATH registration but has no exposed presenceDiscovery.commands."
        }
    }
}
function Get-PackageArtifactForTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$VersionEntry,

        [Parameter(Mandatory = $true)]
        [string]$TargetId
    )

    foreach ($property in @($VersionEntry.targetArtifacts.PSObject.Properties)) {
        if ([string]::Equals([string]$property.Name, $TargetId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $property.Value
        }
    }

    return $null
}

function Resolve-PackageTargetArtifactText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [psobject]$ArtifactTarget,

        [Parameter(Mandatory = $true)]
        [psobject]$VersionEntry,

        [AllowNull()]
        [psobject]$UpstreamRelease
    )

    if ($null -eq $Text) {
        return $null
    }

    return Resolve-TemplateText -Text $Text -Tokens @{
        version                 = [string]$VersionEntry.version
        releaseTag              = if ($UpstreamRelease -and $UpstreamRelease.PSObject.Properties['releaseTag']) { [string]$UpstreamRelease.releaseTag } else { $null }
        releaseTrack            = [string]$ArtifactTarget.releaseTrack
        artifactDistributionVariant = [string]$ArtifactTarget.artifactDistributionVariant
    }
}

function New-PackageReadinessFromPresenceDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [psobject]$Assigned
    )

    $require = if ($Assigned.PSObject.Properties['readyStateCheck'] -and $Assigned.readyStateCheck.PSObject.Properties['require']) {
        $Assigned.readyStateCheck.require
    }
    else {
        [pscustomobject]@{}
    }
    $presenceDiscovery = $Definition.presenceDiscovery

    $commandChecks = New-Object System.Collections.Generic.List[object]
    if ($require.PSObject.Properties['commands'] -and [bool]$require.commands) {
        foreach ($command in @($presenceDiscovery.commands)) {
            foreach ($stateCheck in @($command.stateChecks)) {
                if ($null -eq $stateCheck) {
                    continue
                }
                $check = ConvertTo-PackageObject -InputObject $stateCheck
                $check | Add-Member -MemberType NoteProperty -Name 'entryPoint' -Value ([string]$command.name) -Force
                $commandChecks.Add($check) | Out-Null
            }
        }
    }

    return [pscustomobject]@{
        files          = if ($require.PSObject.Properties['files'] -and [bool]$require.files) { @($presenceDiscovery.files) } else { @() }
        directories    = if ($require.PSObject.Properties['directories'] -and [bool]$require.directories) { @($presenceDiscovery.directories) } else { @() }
        commandChecks  = @($commandChecks.ToArray())
        metadataFiles  = if ($require.PSObject.Properties['metadataFiles'] -and [bool]$require.metadataFiles) { @($presenceDiscovery.metadataFiles) } else { @() }
        signatures     = if ($require.PSObject.Properties['signatures'] -and [bool]$require.signatures) { @($presenceDiscovery.signatures) } else { @() }
        fileDetails    = if ($require.PSObject.Properties['fileDetails'] -and [bool]$require.fileDetails) { @($presenceDiscovery.fileDetails) } else { @() }
        registryChecks = if ($require.PSObject.Properties['registry'] -and [bool]$require.registry) { @($presenceDiscovery.registry) } else { @() }
        powerShellModules = if ($require.PSObject.Properties['powerShellModules'] -and [bool]$require.powerShellModules) { @($presenceDiscovery.powerShellModules) } else { @() }
    }
}

function Resolve-PackageEffectivePackage_1_5 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageConfig
    )

    $definition = $PackageConfig.Definition
    $releaseTrack = if ([string]::IsNullOrWhiteSpace([string]$PackageConfig.ReleaseTrack)) { 'none' } else { [string]$PackageConfig.ReleaseTrack }
    $matchState = New-Object System.Collections.Generic.List[object]

    foreach ($target in @($definition.artifacts.targets)) {
        $constraints = $target.constraints
        $osConstraints = if ($constraints.PSObject.Properties['os']) { @($constraints.os) } else { @() }
        $cpuConstraints = if ($constraints.PSObject.Properties['cpu']) { @($constraints.cpu) } else { @() }
        if (-not [string]::Equals([string]$target.releaseTrack, $releaseTrack, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-PackageConstraintSetMatch -Values $osConstraints -ActualValue $PackageConfig.Platform) -or
            -not (Test-PackageConstraintSetMatch -Values $cpuConstraints -ActualValue $PackageConfig.Architecture)) {
            continue
        }

        foreach ($versionEntry in @($definition.artifacts.releases)) {
            $releaseTracks = if ($versionEntry.PSObject.Properties['releaseTracks']) { @($versionEntry.releaseTracks) } else { @() }
            $versionIsInTrack = $false
            foreach ($releaseTrackName in @($releaseTracks)) {
                if ([string]::Equals([string]$releaseTrackName, [string]$target.releaseTrack, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $versionIsInTrack = $true
                    break
                }
            }
            if (-not $versionIsInTrack) {
                continue
            }

            $artifact = Get-PackageArtifactForTarget -VersionEntry $versionEntry -TargetId ([string]$target.id)
            if ($artifact) {
                $matchState.Add([pscustomobject]@{
                    ArtifactTarget  = $target
                    VersionEntry   = $versionEntry
                    Artifact      = $artifact
                    SortVersion    = ConvertTo-PackageVersion -VersionText ([string]$versionEntry.version)
                }) | Out-Null
            }
        }
    }

    if ($matchState.Count -eq 0) {
        throw "No Package target/release entry matched platform '$($PackageConfig.Platform)', architecture '$($PackageConfig.Architecture)', and releaseTrack '$releaseTrack'."
    }

    $selected = @($matchState.ToArray()) | Sort-Object -Descending -Property SortVersion | Select-Object -First 1
    $target = $selected.ArtifactTarget
    $versionEntry = $selected.VersionEntry
    $artifact = $selected.Artifact
    $assigned = ConvertTo-PackageObject -InputObject $definition.packageOperations.assigned
    $upstreamRelease = if ($versionEntry.PSObject.Properties['upstreamRelease']) { $versionEntry.upstreamRelease } else { $null }

    $fileName = if ($artifact.PSObject.Properties['fileName'] -and -not [string]::IsNullOrWhiteSpace([string]$artifact.fileName)) {
        [string]$artifact.fileName
    }
    elseif ($target.PSObject.Properties['fileNameTemplate']) {
        Resolve-PackageTargetArtifactText -Text ([string]$target.fileNameTemplate) -ArtifactTarget $target -VersionEntry $versionEntry -UpstreamRelease $upstreamRelease
    }
    else {
        $null
    }

    $packageFile = $null
    if (-not [string]::IsNullOrWhiteSpace($fileName) -or
        $artifact.PSObject.Properties['contentHash'] -or
        $artifact.PSObject.Properties['publisherSignature']) {
        $packageFile = [ordered]@{}
        if (-not [string]::IsNullOrWhiteSpace($fileName)) { $packageFile.fileName = $fileName }
        if ($artifact.PSObject.Properties['contentHash']) { $packageFile.contentHash = ConvertTo-PackageObject -InputObject $artifact.contentHash }
        if ($artifact.PSObject.Properties['publisherSignature']) { $packageFile.publisherSignature = ConvertTo-PackageObject -InputObject $artifact.publisherSignature }
    }

    $artifactAcquisitionCandidates = if ($artifact.PSObject.Properties['acquisitionCandidates']) { @($artifact.acquisitionCandidates) } else { @() }
    if (-not $artifactAcquisitionCandidates -and $target.PSObject.Properties['acquisitionCandidates']) {
        $artifactAcquisitionCandidates = @($target.acquisitionCandidates)
    }
    $artifactSourcePath = if ($artifact.PSObject.Properties['sourcePath']) {
        Resolve-PackageTargetArtifactText -Text ([string]$artifact.sourcePath) -ArtifactTarget $target -VersionEntry $versionEntry -UpstreamRelease $upstreamRelease
    }
    else {
        $null
    }
    $artifactUrl = if ($artifact.PSObject.Properties['urlTemplate'] -and -not [string]::IsNullOrWhiteSpace([string]$artifact.urlTemplate)) {
        Resolve-PackageTargetArtifactText -Text ([string]$artifact.urlTemplate) -ArtifactTarget $target -VersionEntry $versionEntry -UpstreamRelease $upstreamRelease
    }
    elseif ($artifact.PSObject.Properties['url'] -and -not [string]::IsNullOrWhiteSpace([string]$artifact.url)) {
        Resolve-PackageTargetArtifactText -Text ([string]$artifact.url) -ArtifactTarget $target -VersionEntry $versionEntry -UpstreamRelease $upstreamRelease
    }
    else {
        $null
    }
    $acquisitionCandidates = @(
        foreach ($source in @($artifactAcquisitionCandidates)) {
            $candidate = ConvertTo-PackageObject -InputObject $source
            if ([string]::Equals([string]$candidate.kind, 'download', [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($candidate.PSObject.Properties['urlTemplate'] -and -not [string]::IsNullOrWhiteSpace([string]$candidate.urlTemplate)) {
                    $candidate | Add-Member -MemberType NoteProperty -Name 'url' -Value (Resolve-PackageTargetArtifactText -Text ([string]$candidate.urlTemplate) -ArtifactTarget $target -VersionEntry $versionEntry -UpstreamRelease $upstreamRelease) -Force
                }
                elseif ($candidate.PSObject.Properties['url'] -and -not [string]::IsNullOrWhiteSpace([string]$candidate.url)) {
                    $candidate.url = Resolve-PackageTargetArtifactText -Text ([string]$candidate.url) -ArtifactTarget $target -VersionEntry $versionEntry -UpstreamRelease $upstreamRelease
                }
                elseif (-not [string]::IsNullOrWhiteSpace($artifactUrl)) {
                    $candidate | Add-Member -MemberType NoteProperty -Name 'url' -Value $artifactUrl -Force
                }
                elseif ($candidate.PSObject.Properties['sourcePath'] -and -not [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                    $candidate.sourcePath = Resolve-PackageTargetArtifactText -Text ([string]$candidate.sourcePath) -ArtifactTarget $target -VersionEntry $versionEntry -UpstreamRelease $upstreamRelease
                }
                elseif (-not [string]::IsNullOrWhiteSpace($artifactSourcePath)) {
                    $candidate | Add-Member -MemberType NoteProperty -Name 'sourcePath' -Value $artifactSourcePath -Force
                }
            }
            $candidate
        }
    )

    $packageId = if ($artifact.PSObject.Properties['artifactId'] -and -not [string]::IsNullOrWhiteSpace([string]$artifact.artifactId)) {
        [string]$artifact.artifactId
    }
    else {
        '{0}-{1}-{2}' -f [string]$definition.definitionPublication.definitionId, [string]$target.id, [string]$versionEntry.version
    }

    return [pscustomobject]@{
        id                      = $packageId
        artifactId              = [string]$artifact.artifactId
        version                 = [string]$versionEntry.version
        releaseTag              = if ($upstreamRelease -and $upstreamRelease.PSObject.Properties['releaseTag']) { [string]$upstreamRelease.releaseTag } else { $null }
        releaseTrack            = [string]$target.releaseTrack
        artifactDistributionVariant = [string]$target.artifactDistributionVariant
        artifactTargetId        = [string]$target.id
        constraints             = ConvertTo-PackageObject -InputObject $target.constraints
        packageFile             = if ($packageFile) { [pscustomobject]$packageFile } else { $null }
        upstreamRelease         = ConvertTo-PackageObject -InputObject $upstreamRelease
        acquisitionCandidates   = @($acquisitionCandidates | Sort-Object -Property @{ Expression = { if ($_.PSObject.Properties['searchOrder']) { [int]$_.searchOrder } else { [int]::MaxValue } } })
        compatibility           = ConvertTo-PackageObject -InputObject $definition.packageOperations.policy.compatibility
        presenceDiscovery       = ConvertTo-PackageObject -InputObject $definition.presenceDiscovery
        existingInstallDiscovery = ConvertTo-PackageObject -InputObject $definition.existingInstallDiscovery
        ownershipPolicy         = ConvertTo-PackageObject -InputObject $definition.packageOperations.policy.ownershipPolicy
        assigned                = $assigned
        removed                 = ConvertTo-PackageObject -InputObject $definition.packageOperations.removed
        readiness               = New-PackageReadinessFromPresenceDiscovery -Definition $definition -Assigned $assigned
    }
}


