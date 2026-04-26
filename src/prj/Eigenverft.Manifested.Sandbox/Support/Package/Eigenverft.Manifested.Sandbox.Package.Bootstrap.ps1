<#
    Eigenverft.Manifested.Sandbox.Package.Bootstrap
#>

$script:ManifestedPackageModelRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ManifestedPackageModelConfigurationRoot = Join-Path $script:ManifestedPackageModelRoot 'Configuration'
$script:ManifestedPackageModelRepositoriesRoot = Join-Path $script:ManifestedPackageModelRoot 'Repositories'
$script:ManifestedPackageModelDefaultRepositoryId = 'EigenverftModule'
$script:ManifestedPackageModelSourceInventoryPathEnvironmentVariableName = 'EIGENVERFT_MANIFESTED_PACKAGE_MODEL_SOURCE_INVENTORY_PATH'
$script:ManifestedPackageModelSiteCodeEnvironmentVariableName = 'EIGENVERFT_MANIFESTED_PACKAGE_MODEL_SITE_CODE'

function Get-PackageModelConfigurationRoot {
<#
.SYNOPSIS
Returns the shipped PackageModel configuration directory.

.DESCRIPTION
Resolves the module-relative directory that contains shipped PackageModel
configuration JSON documents.

.EXAMPLE
Get-PackageModelConfigurationRoot
#>
    [CmdletBinding()]
    param()

    return $script:ManifestedPackageModelConfigurationRoot
}

function Get-PackageModelRepositoriesRoot {
<#
.SYNOPSIS
Returns the shipped PackageModel repositories directory.

.DESCRIPTION
Resolves the module-relative directory that contains shipped PackageModel
definition repositories.

.EXAMPLE
Get-PackageModelRepositoriesRoot
#>
    [CmdletBinding()]
    param()

    return $script:ManifestedPackageModelRepositoriesRoot
}

function Get-PackageModelDefaultRepositoryId {
<#
.SYNOPSIS
Returns the shipped PackageModel base repository id.

.DESCRIPTION
Returns the repository id used for the definitions shipped with this module.

.EXAMPLE
Get-PackageModelDefaultRepositoryId
#>
    [CmdletBinding()]
    param()

    return $script:ManifestedPackageModelDefaultRepositoryId
}

function Get-PackageModelShippedGlobalConfigPath {
<#
.SYNOPSIS
Returns the shipped PackageModel config path.

.DESCRIPTION
Builds the module-relative path to the JSON document that defines PackageModel
defaults.

.EXAMPLE
Get-PackageModelShippedGlobalConfigPath
#>
    [CmdletBinding()]
    param()

    return (Join-Path (Join-Path (Get-PackageModelConfigurationRoot) 'Internal') 'Config.json')
}

function Get-PackageModelLocalRoot {
<#
.SYNOPSIS
Returns the PackageModel local application-data root.

.DESCRIPTION
Builds the local application-data directory used for PackageModel state,
configuration, repositories, workspaces, depots, and installs.

.EXAMPLE
Get-PackageModelLocalRoot
#>
    [CmdletBinding()]
    param()

    $localApplicationData = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        $localApplicationData = [Environment]::GetFolderPath('LocalApplicationData')
    }
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        throw 'Could not resolve the LocalApplicationData directory for PackageModel.'
    }

    return [System.IO.Path]::GetFullPath((Join-Path $localApplicationData 'Eigenverft.Manifested.Sandbox'))
}

function Get-PackageModelLocalGlobalConfigPath {
<#
.SYNOPSIS
Returns the local PackageModel config path.

.DESCRIPTION
Builds the local copy path for Config.json. The local file can later be edited
or refreshed independently of the module installation.

.EXAMPLE
Get-PackageModelLocalGlobalConfigPath
#>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path (Join-Path (Get-PackageModelLocalRoot) 'Configuration\Internal') 'Config.json'))
}

function Get-PackageModelGlobalConfigPath {
<#
.SYNOPSIS
Returns the active PackageModel config path.

.DESCRIPTION
Returns the local Config.json path, creating it from the shipped module
configuration when the local copy does not exist yet.

.EXAMPLE
Get-PackageModelGlobalConfigPath
#>
    [CmdletBinding()]
    param()

    $localConfigPath = Get-PackageModelLocalGlobalConfigPath
    if (-not (Test-Path -LiteralPath $localConfigPath -PathType Leaf)) {
        $localConfigDirectory = Split-Path -Parent $localConfigPath
        if (-not [string]::IsNullOrWhiteSpace($localConfigDirectory)) {
            $null = New-Item -ItemType Directory -Path $localConfigDirectory -Force
        }

        Copy-FileToPath -SourcePath (Get-PackageModelShippedGlobalConfigPath) -TargetPath $localConfigPath -Overwrite | Out-Null
    }

    return $localConfigPath
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
Builds the module-relative path to a PackageModel definition JSON file in the
shipped EigenverftModule repository by using the definition id as the filename
stem.

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

    return (Join-Path (Join-Path (Get-PackageModelRepositoriesRoot) (Get-PackageModelDefaultRepositoryId)) ($DefinitionId + '.json'))
}

