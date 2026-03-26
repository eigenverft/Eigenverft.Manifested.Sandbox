<#
    Eigenverft.Manifested.Sandbox.Runtime.Python.Descriptor
#>

function Get-ManifestedPythonRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Name                    = 'PythonRuntime'
        RuntimeFamily           = 'Python'
        RuntimePack             = 'Python'
        SnapshotName            = 'PythonRuntime'
        SnapshotPathProperty    = 'RuntimeHome'
        StateFunctionName       = 'Get-PythonRuntimeState'
        InitializeCommandName   = 'Initialize-PythonRuntime'
        DisplayName             = 'Python'
        DependencyCommandNames  = @()
        ToolsRootPropertyName   = 'PythonToolsRoot'
        CacheRootPropertyName   = 'PythonCacheRoot'
        RefreshParameterName    = 'RefreshPython'
        SavePackageFunctionName = 'Save-PythonRuntimePackage'
        TestPackageFunctionName = 'Test-PythonRuntimePackage'
        InstallFunctionName     = 'Install-PythonRuntime'
        RepairFunctionName      = 'Repair-PythonRuntime'
        RuntimeTestFunctionName = 'Test-PythonRuntimeFromState'
        RuntimeTestParameterResolver = {
            param([pscustomobject]$RuntimeState)

            @{
                State     = $RuntimeState
                LocalRoot = if ($RuntimeState -and $RuntimeState.PSObject.Properties['LocalRoot']) { $RuntimeState.LocalRoot } else { (Get-ManifestedLocalRoot) }
            }
        }
        ManagedFinalizerStatusFunctionName = 'Get-ManifestedPythonManagedFinalizerStatus'
        ManagedFinalizerFunctionName       = 'Invoke-ManifestedPythonManagedFinalization'
        PersistedDetailsFunctionName       = 'Get-ManifestedPythonPersistedDetails'
        ResolveCommandEnvironment = {
            param([pscustomobject]$RuntimeState)

            $runtimeHome = if ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeHome']) { $RuntimeState.RuntimeHome } else { $null }
            $executablePath = if ($RuntimeState -and $RuntimeState.PSObject.Properties['ExecutablePath']) { $RuntimeState.ExecutablePath } else { $null }
            $runtimeSource = if ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeSource']) { $RuntimeState.RuntimeSource } else { $null }

            $desiredCommandDirectory = $null
            $expectedCommandPaths = [ordered]@{}

            if (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $desiredCommandDirectory = $runtimeHome
            }
            elseif (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $desiredCommandDirectory = Split-Path -Parent $executablePath
            }

            $pythonCommandPath = $null
            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $pythonCommandPath = (Get-ManifestedFullPath -Path $executablePath)
            }
            elseif (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $pythonCommandPath = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'python.exe'))
            }

            if (-not [string]::IsNullOrWhiteSpace($pythonCommandPath)) {
                $expectedCommandPaths['python'] = $pythonCommandPath
                $expectedCommandPaths['python.exe'] = $pythonCommandPath
            }

            if ($runtimeSource -eq 'Managed' -and -not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $expectedCommandPaths['pip.cmd'] = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'pip.cmd'))
                $expectedCommandPaths['pip3.cmd'] = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'pip3.cmd'))
            }

            [pscustomobject]@{
                DesiredCommandDirectory = $desiredCommandDirectory
                ExpectedCommandPaths    = $expectedCommandPaths
            }
        }
    }
}
