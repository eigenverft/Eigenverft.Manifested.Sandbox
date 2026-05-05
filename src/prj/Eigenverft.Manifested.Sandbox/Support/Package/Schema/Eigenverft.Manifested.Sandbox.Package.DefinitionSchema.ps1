<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionSchema
    Package definition JSON validation for the mandatory baseline wire model (schemaVersion 1.1).

    Runtime validation is PowerShell-only (this module + DefinitionSchema.Wire1_1.ps1). The JSON schema file
    is the editor/contract; keep it aligned with these asserts. Wire field names use shared.discovery and
    shared.ownershipPolicy; Resolve-PackageEffectiveRelease produces existingInstallDiscovery /
    existingInstallPolicy on the merged release — see DefinitionSchema.ReleaseMerge.ps1.
#>

# Mandatory baseline schemaVersion for package definitions (wire format; successor to retired 1.0).
$script:PackageDefinitionSupportedSchemaVersions = @(
    '1.1'
)

function Assert-PackageDefinitionSchemaVersionSupported {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SchemaVersionText,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionDocumentPath
    )

    foreach ($supported in $script:PackageDefinitionSupportedSchemaVersions) {
        if ([string]::Equals($SchemaVersionText, $supported, [System.StringComparison]::Ordinal)) {
            return
        }
    }

    $supportedList = ($script:PackageDefinitionSupportedSchemaVersions | ForEach-Object { "'$_'" }) -join ', '
    throw "Package definition '$DefinitionDocumentPath' uses unsupported schemaVersion '$SchemaVersionText'. The mandatory baseline is schemaVersion '1.1'. Supported schemaVersion values are $supportedList."
}

function Assert-PackageDefinitionSchema {
<#
.SYNOPSIS
Validates the Package definition schema for this package pass.

.DESCRIPTION
Rejects retired top-level names, requires baseline fields, then validates the
only supported shape: mandatory wire schemaVersion '1.1' (upstreamSources,
providedTools, shared, releases). Older definition-schema files are not used.

.PARAMETER DefinitionDocumentInfo
The loaded Package definition document info.

.PARAMETER DefinitionId
The expected definition id.

.EXAMPLE
Assert-PackageDefinitionSchema -DefinitionDocumentInfo $definitionInfo -DefinitionId VSCodeRuntime
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$DefinitionDocumentInfo,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [string]$DefinitionRepositoryId = (Get-PackageDefaultRepositoryId)
    )

    $definition = $DefinitionDocumentInfo.Document
    foreach ($retiredProperty in @('classification', 'target', 'origins', 'interfaces', 'packageType', 'paths', 'sources', 'packages', 'entryPoints', 'packageFamily', 'managedPaths')) {
        if ($definition.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' still uses retired property '$retiredProperty'."
        }
    }

    foreach ($requiredProperty in @('schemaVersion', 'id', 'display', 'upstreamSources', 'providedTools', 'shared', 'releases')) {
        if (-not $definition.PSObject.Properties[$requiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' is missing required property '$requiredProperty'."
        }
    }
    if ($definition.PSObject.Properties['releaseDefaults']) {
        throw "Package definition '$($DefinitionDocumentInfo.Path)' still uses retired property 'releaseDefaults'. Use 'shared' (mandatory baseline wire / schemaVersion 1.1)."
    }
    $schemaVersionText = [string]$definition.schemaVersion
    if ([string]::IsNullOrWhiteSpace($schemaVersionText)) {
        throw "Package definition '$($DefinitionDocumentInfo.Path)' defines schemaVersion, but it is empty."
    }
    Assert-PackageDefinitionSchemaVersionSupported -SchemaVersionText $schemaVersionText -DefinitionDocumentPath $DefinitionDocumentInfo.Path

    switch -Exact ($schemaVersionText) {
        '1.1' {
            Assert-PackageDefinitionSchema_1_1 -DefinitionDocumentInfo $DefinitionDocumentInfo -DefinitionId $DefinitionId -DefinitionRepositoryId $DefinitionRepositoryId
            return
        }
        default {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' encountered unsupported schemaVersion '$schemaVersionText' after validation gate."
        }
    }
}
