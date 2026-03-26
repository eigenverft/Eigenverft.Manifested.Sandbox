<#
    Eigenverft.Manifested.Sandbox.Runtime.Git.Descriptor
#>

function Get-ManifestedGitRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Name                    = 'GitRuntime'
        RuntimeFamily           = 'GitHubPortable'
        RuntimePack             = 'GitHubPortable'
        SnapshotName            = 'GitRuntime'
        SnapshotPathProperty    = 'RuntimeHome'
        StateFunctionName       = 'Get-GitRuntimeState'
        InitializeCommandName   = 'Initialize-GitRuntime'
        DisplayName             = 'Git'
        DependencyCommandNames  = @()
        ToolsRootPropertyName   = 'GitToolsRoot'
        CacheRootPropertyName   = 'GitCacheRoot'
        RefreshParameterName    = 'RefreshGit'
        SavePackageFunctionName = 'Save-GitRuntimePackage'
        TestPackageFunctionName = 'Test-GitRuntimePackage'
        InstallFunctionName     = 'Install-GitRuntime'
        RepairFunctionName      = 'Repair-GitRuntime'
        RuntimeTestFunctionName = 'Test-GitRuntime'
        PersistedExtraStateProperties = @()
        ResolveCommandEnvironment = {
            param([pscustomobject]$RuntimeState)

            $executablePath = if ($RuntimeState -and $RuntimeState.PSObject.Properties['ExecutablePath']) { $RuntimeState.ExecutablePath } else { $null }
            $desiredCommandDirectory = $null
            $expectedCommandPaths = [ordered]@{}

            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $desiredCommandDirectory = Split-Path -Parent $executablePath
                $expectedCommandPaths['git.exe'] = (Get-ManifestedFullPath -Path $executablePath)
            }

            [pscustomobject]@{
                DesiredCommandDirectory = $desiredCommandDirectory
                ExpectedCommandPaths    = $expectedCommandPaths
            }
        }
    }
}
