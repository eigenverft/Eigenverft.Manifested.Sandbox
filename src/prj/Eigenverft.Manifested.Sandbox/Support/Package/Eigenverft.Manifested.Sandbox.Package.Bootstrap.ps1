<#
    Eigenverft.Manifested.Sandbox.Package.Bootstrap
#>

$script:ManifestedPackageModelRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ManifestedPackageModelDefinitionsRoot = Join-Path $script:ManifestedPackageModelRoot 'Definitions'
$script:ManifestedPackageModelSourceInventoryPathEnvironmentVariableName = 'EIGENVERFT_MANIFESTED_PACKAGE_MODEL_SOURCE_INVENTORY_PATH'
$script:ManifestedPackageModelSiteCodeEnvironmentVariableName = 'EIGENVERFT_MANIFESTED_PACKAGE_MODEL_SITE_CODE'

function Get-PackageModelDefinitionsRoot {
<#
.SYNOPSIS
Returns the shipped PackageModel definitions directory.

.DESCRIPTION
Resolves the module-relative directory that contains the shipped PackageModel
JSON documents.

.EXAMPLE
Get-PackageModelDefinitionsRoot
#>
    [CmdletBinding()]
    param()

    return $script:ManifestedPackageModelDefinitionsRoot
}

function Get-PackageModelGlobalConfigPath {
<#
.SYNOPSIS
Returns the shipped PackageModel global config path.

.DESCRIPTION
Builds the module-relative path to the JSON document that defines PackageModel
global defaults.

.EXAMPLE
Get-PackageModelGlobalConfigPath
#>
    [CmdletBinding()]
    param()

    return (Join-Path (Get-PackageModelDefinitionsRoot) 'Global.json')
}

function Get-PackageModelSourceInventoryPathEnvironmentVariableName {
<#
.SYNOPSIS
Returns the PackageModel source-inventory path environment-variable name.

.DESCRIPTION
Provides the environment-variable name that can point PackageModel to an
external source-inventory document.

.EXAMPLE
Get-PackageModelSourceInventoryPathEnvironmentVariableName
#>
    [CmdletBinding()]
    param()

    return $script:ManifestedPackageModelSourceInventoryPathEnvironmentVariableName
}

function Get-PackageModelSiteCodeEnvironmentVariableName {
<#
.SYNOPSIS
Returns the PackageModel site-code environment-variable name.

.DESCRIPTION
Provides the environment-variable name used to select a site-specific overlay
from the external PackageModel source inventory.

.EXAMPLE
Get-PackageModelSiteCodeEnvironmentVariableName
#>
    [CmdletBinding()]
    param()

    return $script:ManifestedPackageModelSiteCodeEnvironmentVariableName
}

function Get-PackageModelDefinitionPath {
<#
.SYNOPSIS
Returns the shipped PackageModel definition path for an id.

.DESCRIPTION
Builds the module-relative path to a PackageModel definition JSON file by using
the definition id as the filename stem.

.PARAMETER DefinitionId
The PackageModel definition id.

.EXAMPLE
Get-PackageModelDefinitionPath -DefinitionId VSCodeRuntime
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId
    )

    return (Join-Path (Get-PackageModelDefinitionsRoot) ($DefinitionId + '.json'))
}

