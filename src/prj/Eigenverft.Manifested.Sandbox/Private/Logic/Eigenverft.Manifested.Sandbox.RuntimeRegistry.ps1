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
        [pscustomobject]@{
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
        [pscustomobject]@{
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
        [pscustomobject]@{
            Name                    = 'OpenCodeRuntime'
            RuntimeFamily           = 'NpmCli'
            RuntimePack             = 'NpmCli'
            SnapshotName            = 'OpenCodeRuntime'
            SnapshotPathProperty    = 'RuntimeHome'
            StateFunctionName       = 'Get-OpenCodeRuntimeState'
            InitializeCommandName   = 'Initialize-OpenCodeRuntime'
            DisplayName             = 'OpenCode'
            DependencyCommandNames  = @('Initialize-NodeRuntime')
            ToolsRootPropertyName   = 'OpenCodeToolsRoot'
            InstallFunctionName     = 'Install-OpenCodeRuntime'
            RepairFunctionName      = 'Repair-OpenCodeRuntime'
            RuntimeTestFunctionName = 'Test-OpenCodeRuntime'
            PackageJsonPropertyName = 'PackageJsonPath'
            NodeDependency          = [pscustomobject]@{
                Required       = $true
                MinimumVersion = $null
            }
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

                $commandPath = $null
                if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                    $commandPath = (Get-ManifestedFullPath -Path $executablePath)
                }
                elseif (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                    $commandPath = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'opencode.cmd'))
                }

                if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
                    $expectedCommandPaths['opencode'] = $commandPath
                    $expectedCommandPaths['opencode.cmd'] = $commandPath
                }

                [pscustomobject]@{
                    DesiredCommandDirectory = $desiredCommandDirectory
                    ExpectedCommandPaths    = $expectedCommandPaths
                }
            }
        }
        [pscustomobject]@{
            Name                    = 'GeminiRuntime'
            RuntimeFamily           = 'NpmCli'
            RuntimePack             = 'NpmCli'
            SnapshotName            = 'GeminiRuntime'
            SnapshotPathProperty    = 'RuntimeHome'
            StateFunctionName       = 'Get-GeminiRuntimeState'
            InitializeCommandName   = 'Initialize-GeminiRuntime'
            DisplayName             = 'Gemini'
            DependencyCommandNames  = @('Initialize-NodeRuntime')
            ToolsRootPropertyName   = 'GeminiToolsRoot'
            InstallFunctionName     = 'Install-GeminiRuntime'
            RepairFunctionName      = 'Repair-GeminiRuntime'
            RuntimeTestFunctionName = 'Test-GeminiRuntime'
            PackageJsonPropertyName = 'PackageJsonPath'
            NodeDependency          = [pscustomobject]@{
                Required       = $true
                MinimumVersion = [version]'20.0.0'
            }
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

                $commandPath = $null
                if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                    $commandPath = (Get-ManifestedFullPath -Path $executablePath)
                }
                elseif (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                    $commandPath = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'gemini.cmd'))
                }

                if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
                    $expectedCommandPaths['gemini'] = $commandPath
                    $expectedCommandPaths['gemini.cmd'] = $commandPath
                }

                [pscustomobject]@{
                    DesiredCommandDirectory = $desiredCommandDirectory
                    ExpectedCommandPaths    = $expectedCommandPaths
                }
            }
        }
        [pscustomobject]@{
            Name                    = 'QwenRuntime'
            RuntimeFamily           = 'NpmCli'
            RuntimePack             = 'NpmCli'
            SnapshotName            = 'QwenRuntime'
            SnapshotPathProperty    = 'RuntimeHome'
            StateFunctionName       = 'Get-QwenRuntimeState'
            InitializeCommandName   = 'Initialize-QwenRuntime'
            DisplayName             = 'Qwen'
            DependencyCommandNames  = @('Initialize-NodeRuntime')
            ToolsRootPropertyName   = 'QwenToolsRoot'
            InstallFunctionName     = 'Install-QwenRuntime'
            RepairFunctionName      = 'Repair-QwenRuntime'
            RuntimeTestFunctionName = 'Test-QwenRuntime'
            PackageJsonPropertyName = 'PackageJsonPath'
            NodeDependency          = [pscustomobject]@{
                Required       = $true
                MinimumVersion = [version]'20.0.0'
            }
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

                $commandPath = $null
                if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                    $commandPath = (Get-ManifestedFullPath -Path $executablePath)
                }
                elseif (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                    $commandPath = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'qwen.cmd'))
                }

                if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
                    $expectedCommandPaths['qwen'] = $commandPath
                    $expectedCommandPaths['qwen.cmd'] = $commandPath
                }

                [pscustomobject]@{
                    DesiredCommandDirectory = $desiredCommandDirectory
                    ExpectedCommandPaths    = $expectedCommandPaths
                }
            }
        }
        [pscustomobject]@{
            Name                    = 'CodexRuntime'
            RuntimeFamily           = 'NpmCli'
            RuntimePack             = 'NpmCli'
            SnapshotName            = 'CodexRuntime'
            SnapshotPathProperty    = 'RuntimeHome'
            StateFunctionName       = 'Get-CodexRuntimeState'
            InitializeCommandName   = 'Initialize-CodexRuntime'
            DisplayName             = 'Codex'
            DependencyCommandNames  = @('Initialize-VCRuntime', 'Initialize-NodeRuntime')
            ToolsRootPropertyName   = 'CodexToolsRoot'
            InstallFunctionName     = 'Install-CodexRuntime'
            RepairFunctionName      = 'Repair-CodexRuntime'
            RuntimeTestFunctionName = 'Test-CodexRuntime'
            PackageJsonPropertyName = 'PackageJsonPath'
            NodeDependency          = [pscustomobject]@{
                Required       = $true
                MinimumVersion = $null
            }
            DirectInstallDependencies = @(
                [pscustomobject]@{
                    CommandName = 'Initialize-VCRuntime'
                }
            )
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

                $commandPath = $null
                if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                    $commandPath = (Get-ManifestedFullPath -Path $executablePath)
                }
                elseif (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                    $commandPath = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'codex.cmd'))
                }

                if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
                    $expectedCommandPaths['codex'] = $commandPath
                    $expectedCommandPaths['codex.cmd'] = $commandPath
                }

                [pscustomobject]@{
                    DesiredCommandDirectory = $desiredCommandDirectory
                    ExpectedCommandPaths    = $expectedCommandPaths
                }
            }
        }
        [pscustomobject]@{
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
        [pscustomobject]@{
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
        [pscustomobject]@{
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
