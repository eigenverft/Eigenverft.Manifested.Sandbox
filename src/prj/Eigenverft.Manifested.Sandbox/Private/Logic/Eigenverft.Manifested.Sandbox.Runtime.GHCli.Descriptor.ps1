<#
    Eigenverft.Manifested.Sandbox.Runtime.GHCli.Descriptor
#>

function Get-ManifestedGHCliRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Name                    = 'GHCliRuntime'
        RuntimeFamily           = 'GitHubPortable'
        RuntimePack             = 'GitHubPortable'
        SnapshotName            = 'GHCliRuntime'
        SnapshotPathProperty    = 'RuntimeHome'
        StateFunctionName       = 'Get-GHCliRuntimeState'
        InitializeCommandName   = 'Initialize-GHCliRuntime'
        DisplayName             = 'GitHub CLI'
        DependencyCommandNames  = @()
        ToolsRootPropertyName   = 'GHCliToolsRoot'
        CacheRootPropertyName   = 'GHCliCacheRoot'
        RefreshParameterName    = 'RefreshGHCli'
        SavePackageFunctionName = 'Save-GHCliRuntimePackage'
        TestPackageFunctionName = 'Test-GHCliRuntimePackage'
        InstallFunctionName     = 'Install-GHCliRuntime'
        RepairFunctionName      = 'Repair-GHCliRuntime'
        RuntimeTestFunctionName = 'Test-GHCliRuntime'
        PersistedExtraStateProperties = @()
        ResolveCommandEnvironment = {
            param([pscustomobject]$RuntimeState)

            $executablePath = if ($RuntimeState -and $RuntimeState.PSObject.Properties['ExecutablePath']) { $RuntimeState.ExecutablePath } else { $null }
            $desiredCommandDirectory = $null
            $expectedCommandPaths = [ordered]@{}

            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $desiredCommandDirectory = Split-Path -Parent $executablePath
                $expectedCommandPaths['gh'] = (Get-ManifestedFullPath -Path $executablePath)
                $expectedCommandPaths['gh.exe'] = (Get-ManifestedFullPath -Path $executablePath)
            }

            [pscustomobject]@{
                DesiredCommandDirectory = $desiredCommandDirectory
                ExpectedCommandPaths    = $expectedCommandPaths
            }
        }
    }
}
