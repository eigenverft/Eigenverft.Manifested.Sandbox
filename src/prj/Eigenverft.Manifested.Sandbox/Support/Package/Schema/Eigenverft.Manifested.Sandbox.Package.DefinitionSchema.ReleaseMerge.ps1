<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionSchema.ReleaseMerge
    Merges shared lifecycle defaults from baseline wire definitions (schemaVersion 1.1) into one effective release (runtime model).

    Wire vs effective (read this before changing validators, JSON schema, or lifecycle code):

    - On disk and in Assert-PackageDefinitionSchema* / eigenverft-module-package-definition-1.1.schema.json,
      the definition uses short wire names under shared and optional release overrides:
        shared.discovery          -> effective release: existingInstallDiscovery
        shared.ownershipPolicy    -> effective release: existingInstallPolicy
      Release rows may also carry discovery / ownershipPolicy before merge; those are renamed the same way.

    - After Resolve-PackageEffectiveRelease, Package subsystem code (Selection, Install, Validation, etc.)
      MUST use existingInstallDiscovery / existingInstallPolicy only. Do not add new code paths that read
      .discovery or .ownershipPolicy on the merged release object.

    - JSON schema "releaseNarrow" lists only wire-shaped release fields; the effective names above are
      runtime-only. If you extend discovery/policy, update wire schema + Wire1_1 validators + this merge in lockstep.
#>

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

    if (-not ($Definition.PSObject.Properties['shared']) -or $null -eq $Definition.shared) {
        throw "Package definition '$($Definition.id)' is missing required 'shared' lifecycle block."
    }

    $shared = $Definition.shared
    foreach ($propertyName in @('compatibility', 'install', 'validation', 'existingInstallDiscovery', 'existingInstallPolicy')) {
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
        if ($effectiveRelease.PSObject.Properties['remove']) {
            $null = $effectiveRelease.PSObject.Properties.Remove('remove')
        }
        $effectiveRelease | Add-Member -MemberType NoteProperty -Name 'remove' -Value (ConvertTo-PackageObject -InputObject $shared.remove)
    }

    return $effectiveRelease
}
