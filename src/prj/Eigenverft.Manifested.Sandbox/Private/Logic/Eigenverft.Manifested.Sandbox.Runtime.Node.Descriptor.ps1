<#
    Eigenverft.Manifested.Sandbox.Runtime.Node.Descriptor
#>

function Get-ManifestedNodeRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Name                    = 'NodeRuntime'
        RuntimeFamily           = 'Node'
        RuntimePack             = 'Node'
        SnapshotName            = 'NodeRuntime'
        SnapshotPathProperty    = 'RuntimeHome'
        StateFunctionName       = 'Get-NodeRuntimeState'
        InitializeCommandName   = 'Initialize-NodeRuntime'
        DisplayName             = 'Node'
        DependencyCommandNames  = @()
        ToolsRootPropertyName   = 'NodeToolsRoot'
        CacheRootPropertyName   = 'NodeCacheRoot'
        RefreshParameterName    = 'RefreshNode'
        SavePackageFunctionName = 'Save-NodeRuntimePackage'
        TestPackageFunctionName = 'Test-NodeRuntimePackage'
        InstallFunctionName     = 'Install-NodeRuntime'
        RepairFunctionName      = 'Repair-NodeRuntime'
        RuntimeTestFunctionName = 'Test-NodeRuntime'
        RuntimeTestParameterResolver = {
            param([pscustomobject]$RuntimeState)

            @{
                NodeHome = if ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeHome']) { $RuntimeState.RuntimeHome } else { $null }
            }
        }
        ManagedFinalizerStatusFunctionName = 'Get-ManifestedNodeManagedFinalizerStatus'
        ManagedFinalizerFunctionName       = 'Invoke-ManifestedNodeManagedFinalization'
        PersistedDetailsFunctionName       = 'Get-ManifestedNodePersistedDetails'
        ResolveCommandEnvironment = {
            param([pscustomobject]$RuntimeState)

            $runtimeHome = if ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeHome']) { $RuntimeState.RuntimeHome } else { $null }
            $executablePath = if ($RuntimeState -and $RuntimeState.PSObject.Properties['ExecutablePath']) { $RuntimeState.ExecutablePath } else { $null }
            $desiredCommandDirectory = $null
            $expectedCommandPaths = [ordered]@{}

            if (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $desiredCommandDirectory = $runtimeHome
            }
            elseif (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $desiredCommandDirectory = Split-Path -Parent $executablePath
            }

            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $expectedCommandPaths['node.exe'] = (Get-ManifestedFullPath -Path $executablePath)
            }
            if (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $expectedCommandPaths['npm.cmd'] = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'npm.cmd'))
            }

            [pscustomobject]@{
                DesiredCommandDirectory = $desiredCommandDirectory
                ExpectedCommandPaths    = $expectedCommandPaths
            }
        }
    }
}
