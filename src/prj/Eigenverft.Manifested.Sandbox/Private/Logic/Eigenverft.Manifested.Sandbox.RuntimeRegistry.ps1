<#
    Eigenverft.Manifested.Sandbox.RuntimeRegistry
#>

function Get-ManifestedRuntimeRegistry {
    [CmdletBinding()]
    param()

    if ($script:ManifestedRuntimeRegistry) {
        return @($script:ManifestedRuntimeRegistry)
    }

    $script:ManifestedRuntimeRegistry = @(
        Get-ManifestedPythonRuntimeRegistryDescriptor
        Get-ManifestedNodeRuntimeRegistryDescriptor
        Get-ManifestedOpenCodeRuntimeRegistryDescriptor
        Get-ManifestedGeminiRuntimeRegistryDescriptor
        Get-ManifestedQwenRuntimeRegistryDescriptor
        Get-ManifestedCodexRuntimeRegistryDescriptor
        Get-ManifestedGHCliRuntimeRegistryDescriptor
        [pscustomobject]@{
            Name                    = 'Ps7Runtime'
            RuntimeFamily           = 'GitHubPortable'
            RuntimePack             = 'GitHubPortable'
            SnapshotName            = 'Ps7Runtime'
            SnapshotPathProperty    = 'RuntimeHome'
            StateFunctionName       = 'Get-Ps7RuntimeState'
            InitializeCommandName   = 'Initialize-Ps7Runtime'
            DisplayName             = 'PowerShell'
            DependencyCommandNames  = @()
            ToolsRootPropertyName   = 'Ps7ToolsRoot'
            CacheRootPropertyName   = 'Ps7CacheRoot'
            RefreshParameterName    = 'RefreshPs7'
            SavePackageFunctionName = 'Save-Ps7RuntimePackage'
            TestPackageFunctionName = 'Test-Ps7RuntimePackage'
            InstallFunctionName     = 'Install-Ps7Runtime'
            RepairFunctionName      = 'Repair-Ps7Runtime'
            RuntimeTestFunctionName = 'Test-Ps7Runtime'
            PersistedExtraStateProperties = @()
            ResolveCommandEnvironment = {
                param([pscustomobject]$RuntimeState)

                $executablePath = if ($RuntimeState -and $RuntimeState.PSObject.Properties['ExecutablePath']) { $RuntimeState.ExecutablePath } else { $null }
                $desiredCommandDirectory = $null
                $expectedCommandPaths = [ordered]@{}

                if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                    $desiredCommandDirectory = Split-Path -Parent $executablePath
                    $expectedCommandPaths['pwsh.exe'] = (Get-ManifestedFullPath -Path $executablePath)
                }

                [pscustomobject]@{
                    DesiredCommandDirectory = $desiredCommandDirectory
                    ExpectedCommandPaths    = $expectedCommandPaths
                }
            }
        }
        Get-ManifestedGitRuntimeRegistryDescriptor
        Get-ManifestedVSCodeRuntimeRegistryDescriptor
        [pscustomobject]@{
            Name                    = 'VCRuntime'
            RuntimeFamily           = 'MachinePrerequisite'
            RuntimePack             = 'VCRuntime'
            SnapshotName            = 'VCRuntime'
            SnapshotPathProperty    = 'InstallerPath'
            StateFunctionName       = 'Get-VCRuntimeState'
            InitializeCommandName   = 'Initialize-VCRuntime'
            DisplayName             = 'VC Runtime'
            DependencyCommandNames  = @()
            CacheRootPropertyName   = 'VCRuntimeCacheRoot'
            RefreshParameterName    = 'RefreshVCRuntime'
            SavePackageFunctionName = 'Save-VCRuntimeInstaller'
            TestPackageFunctionName = 'Test-VCRuntimeInstaller'
            InstallFunctionName     = 'Install-VCRuntime'
            RepairFunctionName      = 'Repair-VCRuntime'
            RuntimeTestFunctionName = 'Test-VCRuntime'
            RuntimeTestParameterResolver = {
                param([pscustomobject]$RuntimeState)

                @{
                    InstalledRuntime = if ($RuntimeState -and $RuntimeState.PSObject.Properties['InstalledRuntime']) { $RuntimeState.InstalledRuntime } else { $null }
                }
            }
            PersistedDetailsFunctionName = 'Get-ManifestedMachinePrerequisitePersistedDetails'
            InstallTimeoutParameterName  = 'InstallTimeoutSec'
            ResolveCommandEnvironment = {
                param([pscustomobject]$RuntimeState)
                [pscustomobject]@{
                    DesiredCommandDirectory = $null
                    ExpectedCommandPaths    = [ordered]@{}
                }
            }
        }
    )

    return @($script:ManifestedRuntimeRegistry)
}

function Get-ManifestedRuntimeDescriptor {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByCommand')]
        [string]$CommandName
    )

    $registry = @(Get-ManifestedRuntimeRegistry)

    switch ($PSCmdlet.ParameterSetName) {
        'ByCommand' {
            return ($registry | Where-Object { $_.InitializeCommandName -eq $CommandName } | Select-Object -First 1)
        }
        default {
            return ($registry | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
        }
    }
}

function Get-ManifestedRuntimeSnapshotDescriptors {
    [CmdletBinding()]
    param()

    return @(
        Get-ManifestedRuntimeRegistry |
            Where-Object { $_.SnapshotName -and $_.StateFunctionName -and $_.SnapshotPathProperty }
    )
}
