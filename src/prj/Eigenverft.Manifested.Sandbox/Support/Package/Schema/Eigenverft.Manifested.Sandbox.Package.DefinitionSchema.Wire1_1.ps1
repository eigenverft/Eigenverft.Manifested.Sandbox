<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionSchema.Wire1_1
    Validators for the mandatory baseline wire model (schemaVersion 1.1).
    Isolated from dispatch (DefinitionSchema.ps1) and release merge (ReleaseMerge.ps1).

    Validators here run on wire documents only: use shared.discovery / shared.ownershipPolicy (and the
    same names on a release row if present). Never require existingInstallDiscovery / existingInstallPolicy
    in definition JSON — those names exist only on the effective release after Resolve-PackageEffectiveRelease.
#>

function Assert-PackageDefinitionWire_DefinitionCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionRepositoryId
    )

    if (-not [string]::Equals([string]$definition.id, [string]$DefinitionId, [System.StringComparison]::Ordinal)) {
        throw "Package definition id '$($definition.id)' does not match requested definition id '$DefinitionId'."
    }

    if ($definition.PSObject.Properties['dependencies']) {
        foreach ($dependency in @($definition.dependencies)) {
            if (-not $dependency.PSObject.Properties['definitionId'] -or [string]::IsNullOrWhiteSpace([string]$dependency.definitionId)) {
                throw "Package definition '$($definition.id)' has dependency without definitionId."
            }
            $dependencyRepositoryId = $DefinitionRepositoryId
            if ($dependency.PSObject.Properties['repositoryId']) {
                if ([string]::IsNullOrWhiteSpace([string]$dependency.repositoryId)) {
                    throw "Package definition '$($definition.id)' has dependency '$($dependency.definitionId)' with empty repositoryId."
                }
                $dependencyRepositoryId = [string]$dependency.repositoryId
            }
            if ([string]::Equals([string]$dependency.definitionId, [string]$definition.id, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals($dependencyRepositoryId, $DefinitionRepositoryId, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Package definition '$($definition.id)' cannot depend on itself."
            }
        }
    }

    foreach ($upstreamSourceProperty in @($definition.upstreamSources.PSObject.Properties)) {
        $upstreamSource = $upstreamSourceProperty.Value
        if (-not $upstreamSource.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$upstreamSource.kind)) {
            throw "Package definition '$($definition.id)' has upstream source '$($upstreamSourceProperty.Name)' without kind."
        }

        switch -Exact ([string]$upstreamSource.kind) {
            'download' {
                if (-not $upstreamSource.PSObject.Properties['baseUri'] -or [string]::IsNullOrWhiteSpace([string]$upstreamSource.baseUri)) {
                    throw "Package definition '$($definition.id)' has download upstream source '$($upstreamSourceProperty.Name)' without baseUri."
                }
            }
            'githubRelease' {
                if (-not $upstreamSource.PSObject.Properties['repositoryOwner'] -or [string]::IsNullOrWhiteSpace([string]$upstreamSource.repositoryOwner)) {
                    throw "Package definition '$($definition.id)' has GitHub release upstream source '$($upstreamSourceProperty.Name)' without repositoryOwner."
                }
                if (-not $upstreamSource.PSObject.Properties['repositoryName'] -or [string]::IsNullOrWhiteSpace([string]$upstreamSource.repositoryName)) {
                    throw "Package definition '$($definition.id)' has GitHub release upstream source '$($upstreamSourceProperty.Name)' without repositoryName."
                }
            }
            default {
                throw "Package definition '$($definition.id)' uses unsupported upstream source kind '$($upstreamSource.kind)' for '$($upstreamSourceProperty.Name)'."
            }
        }
    }

    if ($definition.PSObject.Properties['releaseDefaults']) {
        throw "Package definition '$($definition.id)' still uses retired property 'releaseDefaults'. Use 'shared' (mandatory baseline wire / schemaVersion 1.1)."
    }
    if (-not $definition.PSObject.Properties['shared'] -or $null -eq $definition.shared) {
        throw "Package definition '$($definition.id)' is missing required property 'shared'."
    }

    $shared = $definition.shared
    if ($shared.PSObject.Properties['requirements']) {
        throw "Package definition '$($definition.id)' still uses retired property 'shared.requirements'. Use 'shared.compatibility.checks'."
    }

    foreach ($requiredSharedProperty in @('compatibility', 'discovery', 'ownershipPolicy', 'install', 'remove', 'validation')) {
        if (-not $shared.PSObject.Properties[$requiredSharedProperty]) {
            throw "Package definition '$($definition.id)' is missing shared.$requiredSharedProperty."
        }
    }
    foreach ($retiredSharedProperty in @('existingInstall', 'existingInstallDiscovery', 'existingInstallPolicy')) {
        if ($shared.PSObject.Properties[$retiredSharedProperty]) {
            throw "Package definition '$($definition.id)' still uses retired property 'shared.$retiredSharedProperty'. Use 'shared.discovery' and 'shared.ownershipPolicy'."
        }
    }

    $remove = $shared.remove
    foreach ($requiredRemoveProperty in @('keepInstallDirectory', 'keepInventoryRecord', 'keepShims', 'requireProcessExit')) {
        if (-not $remove.PSObject.Properties[$requiredRemoveProperty]) {
            throw "Package definition '$($definition.id)' is missing shared.remove.$requiredRemoveProperty."
        }
    }
}

function Assert-PackageDefinitionWire_OneRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [psobject]$Release,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionRepositoryId
    )

    foreach ($retiredProperty in @('artifact', 'acquisitions', 'sourceOptions', 'reuse', 'channel')) {
        if ($release.PSObject.Properties[$retiredProperty]) {
            throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property '$retiredProperty'."
        }
    }
    if ($release.PSObject.Properties['requirements']) {
        throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'requirements'. Use 'compatibility.checks'."
    }
    foreach ($retiredReleaseProperty in @('existingInstall')) {
        if ($release.PSObject.Properties[$retiredReleaseProperty]) {
            throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property '$retiredReleaseProperty'."
        }
    }

    foreach ($requiredProperty in @('id', 'version', 'releaseTrack', 'flavor', 'constraints')) {
        if (-not $release.PSObject.Properties[$requiredProperty]) {
            throw "Package release '$($release.id)' in '$($definition.id)' is missing required property '$requiredProperty'."
        }
    }

    $effectiveRelease = Resolve-PackageEffectiveRelease -Definition $definition -Release $release
    foreach ($requiredEffectiveProperty in @('install', 'validation', 'compatibility', 'existingInstallDiscovery', 'existingInstallPolicy')) {
        if (-not $effectiveRelease.PSObject.Properties[$requiredEffectiveProperty]) {
            throw "Package release '$($release.id)' in '$($definition.id)' is missing required effective property '$requiredEffectiveProperty'."
        }
    }
    if ($effectiveRelease.compatibility.PSObject.Properties['packages']) {
        throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'compatibility.packages'. Use 'compatibility.checks'."
    }
    if (-not $effectiveRelease.compatibility.PSObject.Properties['checks']) {
        throw "Package release '$($release.id)' in '$($definition.id)' is missing compatibility.checks."
    }
    foreach ($compatibilityCheck in @($effectiveRelease.compatibility.checks)) {
        if ($null -eq $compatibilityCheck) {
            continue
        }
        if (-not $compatibilityCheck.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.kind)) {
            throw "Package release '$($release.id)' in '$($definition.id)' has a compatibility check without kind."
        }
        $onFail = 'fail'
        if ($compatibilityCheck.PSObject.Properties['onFail'] -and -not [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.onFail)) {
            $onFail = ([string]$compatibilityCheck.onFail).ToLowerInvariant()
        }
        if ($onFail -notin @('fail', 'warn')) {
            throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported compatibility onFail '$($compatibilityCheck.onFail)'."
        }

        switch -Exact ([string]$compatibilityCheck.kind) {
            'osFamily' {
                $hasAllowed = $compatibilityCheck.PSObject.Properties['allowed'] -and @($compatibilityCheck.allowed).Count -gt 0
                $hasBlocked = $compatibilityCheck.PSObject.Properties['blocked'] -and @($compatibilityCheck.blocked).Count -gt 0
                if (-not $hasAllowed -and -not $hasBlocked) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has an osFamily compatibility check without allowed or blocked values."
                }
            }
            'cpuArchitecture' {
                $hasAllowed = $compatibilityCheck.PSObject.Properties['allowed'] -and @($compatibilityCheck.allowed).Count -gt 0
                $hasBlocked = $compatibilityCheck.PSObject.Properties['blocked'] -and @($compatibilityCheck.blocked).Count -gt 0
                if (-not $hasAllowed -and -not $hasBlocked) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a cpuArchitecture compatibility check without allowed or blocked values."
                }
            }
            'osVersion' {
                if (-not $compatibilityCheck.PSObject.Properties['operator'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.operator)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has an osVersion compatibility check without operator."
                }
                if (-not $compatibilityCheck.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.value)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has an osVersion compatibility check without value."
                }
            }
            'physicalMemoryGiB' {
                if (-not $compatibilityCheck.PSObject.Properties['operator'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.operator)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a physicalMemoryGiB compatibility check without operator."
                }
                if (-not $compatibilityCheck.PSObject.Properties['value']) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a physicalMemoryGiB compatibility check without value."
                }
                $parsedValue = 0.0
                if (-not [double]::TryParse(([string]$compatibilityCheck.value), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a physicalMemoryGiB compatibility check with non-numeric value '$($compatibilityCheck.value)'."
                }
            }
            'videoMemoryGiB' {
                if (-not $compatibilityCheck.PSObject.Properties['operator'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.operator)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a videoMemoryGiB compatibility check without operator."
                }
                if (-not $compatibilityCheck.PSObject.Properties['value']) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a videoMemoryGiB compatibility check without value."
                }
                $parsedValue = 0.0
                if (-not [double]::TryParse(([string]$compatibilityCheck.value), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a videoMemoryGiB compatibility check with non-numeric value '$($compatibilityCheck.value)'."
                }
            }
            'physicalOrVideoMemoryGiB' {
                if (-not $compatibilityCheck.PSObject.Properties['operator'] -or [string]::IsNullOrWhiteSpace([string]$compatibilityCheck.operator)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a physicalOrVideoMemoryGiB compatibility check without operator."
                }
                if (-not $compatibilityCheck.PSObject.Properties['value']) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a physicalOrVideoMemoryGiB compatibility check without value."
                }
                $parsedValue = 0.0
                if (-not [double]::TryParse(([string]$compatibilityCheck.value), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
                    throw "Package release '$($release.id)' in '$($definition.id)' has a physicalOrVideoMemoryGiB compatibility check with non-numeric value '$($compatibilityCheck.value)'."
                }
            }
            default {
                throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported compatibility kind '$($compatibilityCheck.kind)'."
            }
        }
    }
    if ($effectiveRelease.existingInstallPolicy -and $effectiveRelease.existingInstallPolicy.PSObject.Properties['requireManagedOwnership']) {
        throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'requireManagedOwnership'. Use 'requirePackageOwnership'."
    }

    $installKind = if ($effectiveRelease.install -and $effectiveRelease.install.PSObject.Properties['kind']) {
        [string]$effectiveRelease.install.kind
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($installKind)) {
        throw "Package release '$($release.id)' in '$($definition.id)' is missing install.kind."
    }

    if ($installKind -notin @('expandArchive', 'placePackageFile', 'runInstaller', 'nsisInstaller', 'npmGlobalPackage', 'reuseExisting')) {
        throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.kind '$installKind'."
    }

    foreach ($retiredInstallProperty in @('managerKind', 'managerDependency')) {
        if ($effectiveRelease.install.PSObject.Properties[$retiredInstallProperty]) {
            throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'install.$retiredInstallProperty'. Use install.kind 'npmGlobalPackage' with install.installerCommand."
        }
    }

    if ($effectiveRelease.install.PSObject.Properties['targetKind'] -and
        -not [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.targetKind) -and
        ([string]$effectiveRelease.install.targetKind) -notin @('directory', 'machinePrerequisite')) {
        throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.targetKind '$($effectiveRelease.install.targetKind)'."
    }

    if ($effectiveRelease.install.PSObject.Properties['elevation'] -and
        -not [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.elevation) -and
        ([string]$effectiveRelease.install.elevation) -notin @('none', 'required', 'auto')) {
        throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.elevation '$($effectiveRelease.install.elevation)'."
    }

    if ([string]::Equals($installKind, 'npmGlobalPackage', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not $effectiveRelease.install.PSObject.Properties['packageSpec'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.packageSpec)) {
            throw "Package release '$($release.id)' in '$($definition.id)' uses install.kind 'npmGlobalPackage' without install.packageSpec."
        }
        if (-not $effectiveRelease.install.PSObject.Properties['installerCommand'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.installerCommand)) {
            throw "Package release '$($release.id)' in '$($definition.id)' uses install.kind 'npmGlobalPackage' without install.installerCommand."
        }
    }

    if ([string]::Equals($installKind, 'nsisInstaller', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($effectiveRelease.install.PSObject.Properties['targetDirectoryArgument'] -and $null -ne $effectiveRelease.install.targetDirectoryArgument) {
            $targetDirectoryArgument = $effectiveRelease.install.targetDirectoryArgument
            if ($targetDirectoryArgument.PSObject.Properties['prefix'] -and [string]::IsNullOrWhiteSpace([string]$targetDirectoryArgument.prefix)) {
                throw "Package release '$($release.id)' in '$($definition.id)' defines install.targetDirectoryArgument.prefix without a value."
            }
        }
    }

    if ($effectiveRelease.install -and $effectiveRelease.install.PSObject.Properties['pathRegistration'] -and $null -ne $effectiveRelease.install.pathRegistration) {
        $pathRegistration = $effectiveRelease.install.pathRegistration
        if (-not $pathRegistration.PSObject.Properties['mode'] -or [string]::IsNullOrWhiteSpace([string]$pathRegistration.mode)) {
            throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration without mode."
        }

        $pathRegistrationMode = ([string]$pathRegistration.mode).ToLowerInvariant()
        if ($pathRegistrationMode -notin @('none', 'user', 'machine')) {
            throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.pathRegistration.mode '$($pathRegistration.mode)'."
        }

        if ($pathRegistrationMode -ne 'none') {
            if (-not $pathRegistration.PSObject.Properties['source'] -or $null -eq $pathRegistration.source) {
                throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration.mode '$($pathRegistration.mode)' without source."
            }
            if (-not $pathRegistration.source.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$pathRegistration.source.kind)) {
                throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration without source.kind."
            }

            switch -Exact ([string]$pathRegistration.source.kind) {
                'commandEntryPoint' {
                    if (-not $pathRegistration.source.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$pathRegistration.source.value)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration source kind 'commandEntryPoint' without source.value."
                    }
                    if ($pathRegistration.source.PSObject.Properties['values']) {
                        throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration source.values for source kind 'commandEntryPoint'."
                    }
                }
                'appEntryPoint' {
                    if (-not $pathRegistration.source.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$pathRegistration.source.value)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration source kind 'appEntryPoint' without source.value."
                    }
                    if ($pathRegistration.source.PSObject.Properties['values']) {
                        throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration source.values for source kind 'appEntryPoint'."
                    }
                }
                'installRelativeDirectory' {
                    if (-not $pathRegistration.source.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$pathRegistration.source.value)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration source kind 'installRelativeDirectory' without source.value."
                    }
                    if ($pathRegistration.source.PSObject.Properties['values']) {
                        throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration source.values for source kind 'installRelativeDirectory'."
                    }
                }
                'shim' {
                    $hasShimValue = $pathRegistration.source.PSObject.Properties['value'] -and -not [string]::IsNullOrWhiteSpace([string]$pathRegistration.source.value)
                    $hasShimValues = $false
                    if ($pathRegistration.source.PSObject.Properties['values'] -and $null -ne $pathRegistration.source.values) {
                        $hasShimValues = @($pathRegistration.source.values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0
                    }
                    if (-not $hasShimValue -and -not $hasShimValues) {
                        throw "Package release '$($release.id)' in '$($definition.id)' defines install.pathRegistration source kind 'shim' without source.value or source.values."
                    }
                }
                default {
                    throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported install.pathRegistration.source.kind '$($pathRegistration.source.kind)'."
                }
            }
        }
    }

    $requiresPackageFile = $false
    $requiresAcquisitionCandidates = $false
    switch -Exact ($installKind) {
        'expandArchive' {
            $requiresPackageFile = $true
            $requiresAcquisitionCandidates = $true
        }
        'placePackageFile' {
            $requiresPackageFile = $true
            $requiresAcquisitionCandidates = $true
            if ($effectiveRelease.install.PSObject.Properties['targetRelativePath'] -and
                [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.targetRelativePath)) {
                throw "Package release '$($release.id)' in '$($definition.id)' defines install.targetRelativePath without a value."
            }
        }
        'runInstaller' {
            if (-not $effectiveRelease.install.PSObject.Properties['commandPath'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.install.commandPath)) {
                $requiresPackageFile = $true
                $requiresAcquisitionCandidates = $true
            }
        }
        'nsisInstaller' {
            $requiresPackageFile = $true
            $requiresAcquisitionCandidates = $true
        }
    }

    if ($requiresPackageFile) {
        if (-not $effectiveRelease.PSObject.Properties['packageFile'] -or $null -eq $effectiveRelease.packageFile) {
            throw "Package release '$($release.id)' in '$($definition.id)' is missing required property 'packageFile'."
        }
        if (-not $effectiveRelease.packageFile.PSObject.Properties['fileName'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.packageFile.fileName)) {
            throw "Package release '$($release.id)' in '$($definition.id)' is missing packageFile.fileName."
        }
    }

    if ($effectiveRelease.PSObject.Properties['packageFile'] -and $effectiveRelease.packageFile -and
        (-not $effectiveRelease.packageFile.PSObject.Properties['fileName'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.packageFile.fileName))) {
        throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile without packageFile.fileName."
    }
    if ($effectiveRelease.PSObject.Properties['packageFile'] -and $effectiveRelease.packageFile) {
        if ($effectiveRelease.packageFile.PSObject.Properties['autoUpdateSupported']) {
            throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'packageFile.autoUpdateSupported'."
        }
        if ($effectiveRelease.packageFile.PSObject.Properties['integrity']) {
            throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'packageFile.integrity'. Use 'packageFile.contentHash'."
        }
        if ($effectiveRelease.packageFile.PSObject.Properties['authenticode']) {
            throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'packageFile.authenticode'. Use 'packageFile.publisherSignature'."
        }
    }

    if ($effectiveRelease.PSObject.Properties['packageFile'] -and
        $effectiveRelease.packageFile -and
        $effectiveRelease.packageFile.PSObject.Properties['contentHash'] -and
        $null -ne $effectiveRelease.packageFile.contentHash) {
        $contentHash = $effectiveRelease.packageFile.contentHash
        if (-not $contentHash.PSObject.Properties['algorithm'] -or [string]::IsNullOrWhiteSpace([string]$contentHash.algorithm)) {
            throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile.contentHash without algorithm."
        }
        if (-not $contentHash.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$contentHash.value)) {
            throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile.contentHash without value."
        }
        if (-not [string]::Equals([string]$contentHash.algorithm, 'sha256', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported packageFile.contentHash.algorithm '$($contentHash.algorithm)'."
        }
    }

    if ($effectiveRelease.PSObject.Properties['packageFile'] -and
        $effectiveRelease.packageFile -and
        $effectiveRelease.packageFile.PSObject.Properties['publisherSignature'] -and
        $null -ne $effectiveRelease.packageFile.publisherSignature) {
        $publisherSignature = $effectiveRelease.packageFile.publisherSignature
        if (-not $publisherSignature.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$publisherSignature.kind)) {
            throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile.publisherSignature without kind."
        }
        if (-not [string]::Equals([string]$publisherSignature.kind, 'authenticode', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported packageFile.publisherSignature.kind '$($publisherSignature.kind)'."
        }
        if ($publisherSignature.PSObject.Properties['requireValid'] -and
            $null -eq $publisherSignature.requireValid) {
            throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile.publisherSignature.requireValid without a value."
        }
        if ($publisherSignature.PSObject.Properties['subjectContains'] -and
            [string]::IsNullOrWhiteSpace([string]$publisherSignature.subjectContains)) {
            throw "Package release '$($release.id)' in '$($definition.id)' defines packageFile.publisherSignature.subjectContains without a value."
        }
    }

    if ($requiresAcquisitionCandidates) {
        if (-not $effectiveRelease.PSObject.Properties['acquisitionCandidates'] -or @($effectiveRelease.acquisitionCandidates).Count -eq 0) {
            throw "Package release '$($release.id)' in '$($definition.id)' is missing required property 'acquisitionCandidates'."
        }
    }

    if ($effectiveRelease.PSObject.Properties['acquisitionCandidates']) {
        foreach ($candidate in @($effectiveRelease.acquisitionCandidates)) {
            if ($null -eq $candidate) {
                continue
            }
            if ($candidate.PSObject.Properties['sourceBindingId']) {
                throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'sourceBindingId'."
            }
            if ($candidate.PSObject.Properties['sourceRef']) {
                throw "Package release '$($release.id)' in '$($definition.id)' still uses retired property 'sourceRef'."
            }
            if ($candidate.PSObject.Properties['priority']) {
                throw "Package release '$($release.id)' in '$($definition.id)' acquisition candidate still uses retired property 'priority'. Use 'searchOrder'."
            }
            if (-not $candidate.PSObject.Properties['searchOrder']) {
                throw "Package release '$($release.id)' in '$($definition.id)' has an acquisition candidate without searchOrder."
            }
            if (-not $candidate.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$candidate.kind)) {
                throw "Package release '$($release.id)' in '$($definition.id)' has an acquisition candidate without kind."
            }
            switch -Exact ([string]$candidate.kind) {
                'packageDepot' { }
                'download' {
                    if (-not $candidate.PSObject.Properties['sourceId'] -or [string]::IsNullOrWhiteSpace([string]$candidate.sourceId)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a download acquisition candidate without sourceId."
                    }

                    $downloadSource = $null
                    foreach ($upstreamSourceProperty in @($definition.upstreamSources.PSObject.Properties)) {
                        if ([string]::Equals([string]$upstreamSourceProperty.Name, [string]$candidate.sourceId, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $downloadSource = $upstreamSourceProperty.Value
                            break
                        }
                    }
                    if (-not $downloadSource) {
                        throw "Package release '$($release.id)' in '$($definition.id)' references unknown download sourceId '$($candidate.sourceId)'."
                    }

                    $downloadSourceKind = if ($downloadSource.PSObject.Properties['kind']) { [string]$downloadSource.kind } else { $null }
                    switch -Exact ($downloadSourceKind) {
                        'download' {
                            if (-not $candidate.PSObject.Properties['sourcePath'] -or [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                                throw "Package release '$($release.id)' in '$($definition.id)' has a download acquisition candidate without sourcePath."
                            }
                        }
                        'githubRelease' {
                            if ($candidate.PSObject.Properties['sourcePath'] -and -not [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                                throw "Package release '$($release.id)' in '$($definition.id)' must not define sourcePath for GitHub release source '$($candidate.sourceId)'."
                            }
                            if (-not $effectiveRelease.PSObject.Properties['releaseTag'] -or [string]::IsNullOrWhiteSpace([string]$effectiveRelease.releaseTag)) {
                                throw "Package release '$($release.id)' in '$($definition.id)' requires releaseTag when download source '$($candidate.sourceId)' is a GitHub release source."
                            }
                            if (-not $effectiveRelease.PSObject.Properties['packageFile'] -or
                                $null -eq $effectiveRelease.packageFile -or
                                -not $effectiveRelease.packageFile.PSObject.Properties['fileName'] -or
                                [string]::IsNullOrWhiteSpace([string]$effectiveRelease.packageFile.fileName)) {
                                throw "Package release '$($release.id)' in '$($definition.id)' requires packageFile.fileName when download source '$($candidate.sourceId)' is a GitHub release source."
                            }
                        }
                        default {
                            throw "Package release '$($release.id)' in '$($definition.id)' references unsupported download source kind '$downloadSourceKind' for sourceId '$($candidate.sourceId)'."
                        }
                    }
                }
                'filesystem' {
                    if (-not $candidate.PSObject.Properties['sourcePath'] -or [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a filesystem acquisition candidate without sourcePath."
                    }
                }
                default {
                    throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported acquisition kind '$($candidate.kind)'."
                }
            }
        }
    }

    $existingInstallDiscovery = $effectiveRelease.existingInstallDiscovery
    if ($existingInstallDiscovery.PSObject.Properties['enableDetection'] -and [bool]$existingInstallDiscovery.enableDetection) {
        if (-not $existingInstallDiscovery.PSObject.Properties['searchLocations']) {
            throw "Package release '$($release.id)' in '$($definition.id)' is missing existingInstallDiscovery.searchLocations."
        }
        if (-not $existingInstallDiscovery.PSObject.Properties['installRootRules']) {
            throw "Package release '$($release.id)' in '$($definition.id)' is missing existingInstallDiscovery.installRootRules."
        }
        foreach ($searchLocation in @($existingInstallDiscovery.searchLocations)) {
            if ($null -eq $searchLocation) {
                continue
            }
            if (-not $searchLocation.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.kind)) {
                throw "Package release '$($release.id)' in '$($definition.id)' has an existingInstallDiscovery.searchLocation without kind."
            }
            switch -Exact ([string]$searchLocation.kind) {
                'command' {
                    if (-not $searchLocation.PSObject.Properties['name'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.name)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a command searchLocation without name."
                    }
                }
                'path' {
                    if (-not $searchLocation.PSObject.Properties['path'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.path)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a path searchLocation without path."
                    }
                }
                'directory' {
                    if (-not $searchLocation.PSObject.Properties['path'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.path)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a directory searchLocation without path."
                    }
                }
                'windowsUninstallRegistryKey' {
                    if (-not $searchLocation.PSObject.Properties['paths'] -or @($searchLocation.paths).Count -eq 0) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a windowsUninstallRegistryKey searchLocation without paths."
                    }
                    if (-not $searchLocation.PSObject.Properties['installDirectorySource'] -or [string]::IsNullOrWhiteSpace([string]$searchLocation.installDirectorySource)) {
                        throw "Package release '$($release.id)' in '$($definition.id)' has a windowsUninstallRegistryKey searchLocation without installDirectorySource."
                    }
                    if ([string]$searchLocation.installDirectorySource -notin @('installLocation', 'displayIconDirectory', 'uninstallStringDirectory')) {
                        throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported windowsUninstallRegistryKey installDirectorySource '$($searchLocation.installDirectorySource)'."
                    }
                }
                default {
                    throw "Package release '$($release.id)' in '$($definition.id)' uses unsupported existingInstallDiscovery.searchLocation kind '$($searchLocation.kind)'."
                }
            }
        }
        foreach ($rule in @($existingInstallDiscovery.installRootRules)) {
            if ($null -eq $rule) {
                continue
            }
            if ($rule.PSObject.Properties['fileName'] -or $rule.PSObject.Properties['homePath']) {
                throw "Package release '$($release.id)' in '$($definition.id)' still uses retired installRootRules fields from installHomeRules."
            }
            if (-not $rule.PSObject.Properties['match'] -or $null -eq $rule.match) {
                throw "Package release '$($release.id)' in '$($definition.id)' has an installRootRule without match."
            }
            if (-not $rule.match.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$rule.match.kind)) {
                throw "Package release '$($release.id)' in '$($definition.id)' has an installRootRule without match.kind."
            }
            if (-not $rule.match.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$rule.match.value)) {
                throw "Package release '$($release.id)' in '$($definition.id)' has an installRootRule without match.value."
            }
            if (-not $rule.PSObject.Properties['installRootRelativePath']) {
                throw "Package release '$($release.id)' in '$($definition.id)' has an installRootRule without installRootRelativePath."
            }
        }
    }
}

# schemaVersion '1.1' is the mandatory baseline wire literal (see eigenverft-module-package-definition-1.1.schema.json).
function Assert-PackageDefinitionSchema_1_1 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$DefinitionDocumentInfo,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [string]$DefinitionRepositoryId = (Get-PackageDefaultRepositoryId)
    )

    $definition = $DefinitionDocumentInfo.Document
    Assert-PackageDefinitionWire_DefinitionCore -Definition $definition -DefinitionId $DefinitionId -DefinitionRepositoryId $DefinitionRepositoryId
    foreach ($release in @($definition.releases)) {
        Assert-PackageDefinitionWire_OneRelease -Definition $definition -Release $release -DefinitionRepositoryId $DefinitionRepositoryId
    }
}

