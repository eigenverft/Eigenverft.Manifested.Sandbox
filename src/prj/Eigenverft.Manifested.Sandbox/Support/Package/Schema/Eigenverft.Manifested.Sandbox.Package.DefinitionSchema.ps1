<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionSchema
    Package definition JSON validation for the mandatory schemaVersion 1.4 wire model.

    Runtime validation is PowerShell-only (this module + DefinitionSchema.Wire1_4.ps1). The JSON schema file
    is the editor/human contract (canonical conforming examples live as *.json next to the schema); keep schema and asserts aligned. Schema root may include x-eigenverftAgentHint for LLM task disambiguation - runtime ignores it.
#>

# Mandatory schemaVersion for package definitions.
$script:PackageDefinitionSupportedSchemaVersions = @(
    '1.4'
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
    throw "Package definition '$DefinitionDocumentPath' uses unsupported schemaVersion '$SchemaVersionText'. The mandatory package definition schemaVersion is '1.4'. Supported schemaVersion values are $supportedList."
}

function Assert-PackageDefinitionSchema {
<#
.SYNOPSIS
Validates the Package definition schema for this package pass.

    .DESCRIPTION
Rejects retired top-level names, requires schemaVersion 1.4 fields, then
validates dependencies/artifacts/presenceDiscovery/existingInstallDiscovery/packageOperations references.

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
    foreach ($retiredProperty in @(
            'classification',
            'target',
            'origins',
            'interfaces',
            'packageType',
            'paths',
            'sources',
            'packages',
            'entryPoints',
            'packageFamily',
            'managedPaths'
        )) {
        if ($definition.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' still uses retired property '$retiredProperty'."
        }
    }

    $schemaVersionText = [string]$definition.schemaVersion
    if ([string]::IsNullOrWhiteSpace($schemaVersionText)) {
        throw "Package definition '$($DefinitionDocumentInfo.Path)' defines schemaVersion, but it is empty."
    }
    Assert-PackageDefinitionSchemaVersionSupported -SchemaVersionText $schemaVersionText -DefinitionDocumentPath $DefinitionDocumentInfo.Path

    foreach ($requiredProperty in @('schemaVersion', 'id', 'definitionPublication', 'display', 'dependencies', 'artifacts', 'presenceDiscovery', 'existingInstallDiscovery', 'packageOperations')) {
        if (-not $definition.PSObject.Properties[$requiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' is missing required property '$requiredProperty'."
        }
    }
    foreach ($retiredProperty in @(
            'packageTargets',
            'versionCatalog',
            'upstreamSources',
            'discovery',
            'stateDiscovery',
            'installedStateCheck',
            'providedTools',
            'releaseDefaults',
            'existingInstallPolicy'
        )) {
        if ($definition.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' still uses retired pre-1.3 property '$retiredProperty'."
        }
    }

    switch -Exact ($schemaVersionText) {
        '1.4' {
            Assert-PackageDefinitionSchema_1_4 -DefinitionDocumentInfo $DefinitionDocumentInfo -DefinitionId $DefinitionId -DefinitionRepositoryId $DefinitionRepositoryId
            return
        }
        default {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' encountered unsupported schemaVersion '$schemaVersionText' after validation gate."
        }
    }
}
