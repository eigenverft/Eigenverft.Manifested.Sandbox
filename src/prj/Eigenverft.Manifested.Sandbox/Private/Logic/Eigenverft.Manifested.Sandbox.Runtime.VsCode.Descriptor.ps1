<#
    Eigenverft.Manifested.Sandbox.Runtime.VsCode.Descriptor
#>

function Get-ManifestedVSCodeRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Name                    = 'VSCodeRuntime'
        RuntimeFamily           = 'GitHubPortable'
        RuntimePack             = 'GitHubPortable'
        SnapshotName            = 'VSCodeRuntime'
        SnapshotPathProperty    = 'RuntimeHome'
        StateFunctionName       = 'Get-VSCodeRuntimeState'
        InitializeCommandName   = 'Initialize-VSCodeRuntime'
        DisplayName             = 'VS Code'
        DependencyCommandNames  = @()
        ToolsRootPropertyName   = 'VsCodeToolsRoot'
        CacheRootPropertyName   = 'VsCodeCacheRoot'
        RefreshParameterName    = 'RefreshVSCode'
        SavePackageFunctionName = 'Save-VSCodeRuntimePackage'
        TestPackageFunctionName = 'Test-VSCodeRuntimePackage'
        InstallFunctionName     = 'Install-VSCodeRuntime'
        RepairFunctionName      = 'Repair-VSCodeRuntime'
        RuntimeTestFunctionName = 'Test-VSCodeRuntime'
        PersistedExtraStateProperties = @('Channel', 'CliCommandPath', 'PortableMode')
        RuntimeTestParameterResolver = {
            param([pscustomobject]$RuntimeState)
            @{
                RequirePortableMode = ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeSource'] -and ($RuntimeState.RuntimeSource -eq 'Managed'))
            }
        }
        ResolveCommandEnvironment = {
            param([pscustomobject]$RuntimeState)

            $runtimeHome = if ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeHome']) { $RuntimeState.RuntimeHome } else { $null }
            $cliCommandPath = if ($RuntimeState -and $RuntimeState.PSObject.Properties['CliCommandPath']) { $RuntimeState.CliCommandPath } else { $null }
            $desiredCommandDirectory = $null
            $expectedCommandPaths = [ordered]@{}

            if (-not [string]::IsNullOrWhiteSpace($cliCommandPath)) {
                $desiredCommandDirectory = Split-Path -Parent $cliCommandPath
                $expectedCommandPaths['code'] = (Get-ManifestedFullPath -Path $cliCommandPath)
                $expectedCommandPaths['code.cmd'] = (Get-ManifestedFullPath -Path $cliCommandPath)
            }
            elseif (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $desiredCommandDirectory = Join-Path $runtimeHome 'bin'
                $expectedCommandPaths['code'] = (Get-ManifestedFullPath -Path (Join-Path $desiredCommandDirectory 'code.cmd'))
                $expectedCommandPaths['code.cmd'] = (Get-ManifestedFullPath -Path (Join-Path $desiredCommandDirectory 'code.cmd'))
            }

            [pscustomobject]@{
                DesiredCommandDirectory = $desiredCommandDirectory
                ExpectedCommandPaths    = $expectedCommandPaths
            }
        }
    }
}
