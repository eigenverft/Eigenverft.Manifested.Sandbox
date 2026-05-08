<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionSchema.ReleaseMerge
    Merges shared lifecycle defaults from baseline wire definitions (schemaVersion 1.1) into one effective release (runtime model).

    Wire vs effective (read this before changing validators, JSON schema, or lifecycle code):

    - On disk and in Assert-PackageDefinitionSchema* / eigenverft-module-package-definition-1.1.schema.json,
      the definition uses legacy shared.* or packageOperations.shared.* plus assigned/removed (optional release overrides):
        shared.discovery / packageOperations.shared.discovery -> effective release: existingInstallDiscovery
        shared.ownershipPolicy / packageOperations.shared.ownershipPolicy -> effective release: existingInstallPolicy
      Release rows may also carry discovery / ownershipPolicy before merge; those are renamed the same way.

    - After Resolve-PackageEffectiveRelease, Package subsystem code (Selection, lifecycle, Validation, etc.)
      MUST use assigned / removed (not legacy install / remove on the effective release), and
      existingInstallDiscovery / existingInstallPolicy only. Do not read .discovery or .ownershipPolicy on the merged release object.

    - JSON schema "releaseNarrow" lists only wire-shaped release fields; the effective names above are
      runtime-only. If you extend discovery/policy, update wire schema + Wire1_1 validators + this merge in lockstep.

    - Definitions may use legacy top-level 'shared' (sharedLifecycle) or 'packageOperations'
      (packageOperations.shared + assigned + removed). Get-PackageDefinitionNormalizedSharedView
      maps the new shape into a normalized view with wire keys install/remove for merge consumption only.
#>

function Get-PackageDefinitionNormalizedSharedView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition
    )

    $hasShared = $Definition.PSObject.Properties['shared'] -and $null -ne $Definition.shared
    $hasPackageOperations = $Definition.PSObject.Properties['packageOperations'] -and $null -ne $Definition.packageOperations

    if ($hasShared -and $hasPackageOperations) {
        throw "Package definition '$($Definition.id)' defines both 'shared' and 'packageOperations'; use only one wire shape."
    }
    if (-not $hasShared -and -not $hasPackageOperations) {
        throw "Package definition '$($Definition.id)' is missing required lifecycle block: provide either 'shared' or 'packageOperations'."
    }

    if ($hasPackageOperations) {
        $po = $Definition.packageOperations
        foreach ($req in @('shared', 'assigned', 'removed')) {
            if (-not $po.PSObject.Properties[$req] -or $null -eq $po.$req) {
                throw "Package definition '$($Definition.id)' packageOperations is missing required property '$req'."
            }
        }
        $innerShared = $po.shared
        return [pscustomobject]@{
            compatibility   = $innerShared.compatibility
            discovery       = $innerShared.discovery
            ownershipPolicy = $innerShared.ownershipPolicy
            validation      = $innerShared.validation
            install         = $po.assigned
            remove          = $po.removed
        }
    }

    return $Definition.shared
}

function Resolve-PackageEffectiveRelease {
<#
.SYNOPSIS
Builds the effective Package release by applying definition shared defaults.

.DESCRIPTION
Applies whole-block fallback from the definition shared block to a single release
entry. When a release defines one of the known lifecycle blocks, that block fully
replaces the default block for that key. Wire properties discovery and ownershipPolicy
(v4 JSON names on disk) are copied or renamed to existingInstallDiscovery and
existingInstallPolicy on the effective release for all downstream Package code.

.PARAMETER Definition
The Package definition object.

.PARAMETER Release
The raw release object from the definition.

.EXAMPLE
Resolve-PackageEffectiveRelease -Definition $definition -Release $release
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [psobject]$Release
    )

    $effectiveRelease = ConvertTo-PackageObject -InputObject $Release

    if ($effectiveRelease.PSObject.Properties['discovery'] -and
        -not $effectiveRelease.PSObject.Properties['existingInstallDiscovery']) {
        $effectiveRelease | Add-Member -MemberType NoteProperty -Name 'existingInstallDiscovery' -Value (ConvertTo-PackageObject -InputObject $effectiveRelease.discovery)
        $null = $effectiveRelease.PSObject.Properties.Remove('discovery')
    }
    if ($effectiveRelease.PSObject.Properties['ownershipPolicy'] -and
        -not $effectiveRelease.PSObject.Properties['existingInstallPolicy']) {
        $effectiveRelease | Add-Member -MemberType NoteProperty -Name 'existingInstallPolicy' -Value (ConvertTo-PackageObject -InputObject $effectiveRelease.ownershipPolicy)
        $null = $effectiveRelease.PSObject.Properties.Remove('ownershipPolicy')
    }

    if ($effectiveRelease.PSObject.Properties['install'] -and
        -not $effectiveRelease.PSObject.Properties['assigned']) {
        $effectiveRelease | Add-Member -MemberType NoteProperty -Name 'assigned' -Value (ConvertTo-PackageObject -InputObject $effectiveRelease.install)
        $null = $effectiveRelease.PSObject.Properties.Remove('install')
    }
    if ($effectiveRelease.PSObject.Properties['remove'] -and
        -not $effectiveRelease.PSObject.Properties['removed']) {
        $effectiveRelease | Add-Member -MemberType NoteProperty -Name 'removed' -Value (ConvertTo-PackageObject -InputObject $effectiveRelease.remove)
        $null = $effectiveRelease.PSObject.Properties.Remove('remove')
    }

    $shared = Get-PackageDefinitionNormalizedSharedView -Definition $Definition
    foreach ($propertyName in @('compatibility', 'assigned', 'validation', 'existingInstallDiscovery', 'existingInstallPolicy')) {
        $sharedValue = $null
        switch ($propertyName) {
            'existingInstallDiscovery' {
                if ($shared.PSObject.Properties['discovery']) {
                    $sharedValue = $shared.discovery
                }
            }
            'existingInstallPolicy' {
                if ($shared.PSObject.Properties['ownershipPolicy']) {
                    $sharedValue = $shared.ownershipPolicy
                }
            }
            'assigned' {
                if ($shared.PSObject.Properties['install'] -and $null -ne $shared.install) {
                    $sharedValue = $shared.install
                }
            }
            default {
                if ($shared.PSObject.Properties[$propertyName]) {
                    $sharedValue = $shared.$propertyName
                }
            }
        }

        if (-not $effectiveRelease.PSObject.Properties[$propertyName] -and $null -ne $sharedValue) {
            $effectiveRelease | Add-Member -MemberType NoteProperty -Name $propertyName -Value (ConvertTo-PackageObject -InputObject $sharedValue)
        }
    }

    if ($shared.PSObject.Properties['remove'] -and $null -ne $shared.remove) {
        if ($effectiveRelease.PSObject.Properties['removed']) {
            $null = $effectiveRelease.PSObject.Properties.Remove('removed')
        }
        $effectiveRelease | Add-Member -MemberType NoteProperty -Name 'removed' -Value (ConvertTo-PackageObject -InputObject $shared.remove)
    }

    return $effectiveRelease
}
