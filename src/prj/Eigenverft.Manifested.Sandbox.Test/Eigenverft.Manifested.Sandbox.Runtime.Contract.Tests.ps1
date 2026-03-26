<#
    Registry and facade contract coverage for the module refactor.
#>

Describe 'Eigenverft.Manifested.Sandbox runtime contracts' {
    BeforeAll {
        $testProjectRoot = if ($PSCommandPath) {
            Split-Path -Parent $PSCommandPath
        }
        else {
            $PSScriptRoot
        }

        $moduleProjectRoot = Join-Path (Split-Path -Parent $testProjectRoot) 'Eigenverft.Manifested.Sandbox'
        $script:ModuleProjectRoot = $moduleProjectRoot
        $script:ModuleManifestPath = Join-Path $moduleProjectRoot 'Eigenverft.Manifested.Sandbox.psd1'
        $script:ManifestData = Import-PowerShellDataFile -Path $script:ModuleManifestPath
        $script:SandboxModule = $null

        function Reset-SandboxModule {
            $existingSandboxModule = Get-Variable -Name SandboxModule -Scope Script -ErrorAction SilentlyContinue
            if ($existingSandboxModule -and $existingSandboxModule.Value) {
                Remove-Module $existingSandboxModule.Value.Name -Force -ErrorAction SilentlyContinue
            }

            $script:SandboxModule = Import-Module $script:ModuleManifestPath -Force -PassThru
        }

        Reset-SandboxModule
    }

    BeforeEach {
        Reset-SandboxModule
    }

    AfterAll {
        $existingSandboxModule = Get-Variable -Name SandboxModule -Scope Script -ErrorAction SilentlyContinue
        if ($existingSandboxModule -and $existingSandboxModule.Value) {
            Remove-Module $existingSandboxModule.Value.Name -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps the runtime registry aligned with the supported runtime set' {
        $registry = @(& $script:SandboxModule { Get-ManifestedRuntimeRegistry })
        $registryNames = @($registry | Select-Object -ExpandProperty Name)

        $registry.Count | Should -Be 11
        $registryNames | Should -Contain 'PythonRuntime'
        $registryNames | Should -Contain 'NodeRuntime'
        $registryNames | Should -Contain 'OpenCodeRuntime'
        $registryNames | Should -Contain 'GeminiRuntime'
        $registryNames | Should -Contain 'QwenRuntime'
        $registryNames | Should -Contain 'CodexRuntime'
        $registryNames | Should -Contain 'GHCliRuntime'
        $registryNames | Should -Contain 'Ps7Runtime'
        $registryNames | Should -Contain 'GitRuntime'
        $registryNames | Should -Contain 'VSCodeRuntime'
        $registryNames | Should -Contain 'VCRuntime'
    }

    It 'derives runtime snapshot metadata directly from registry descriptors' {
        $expectedNames = @(& $script:SandboxModule {
            Get-ManifestedRuntimeRegistry |
                Where-Object { $_.SnapshotName -and $_.StateFunctionName -and $_.SnapshotPathProperty } |
                Select-Object -ExpandProperty SnapshotName
        })
        $actualNames = @(& $script:SandboxModule { Get-ManifestedRuntimeSnapshotDescriptors | Select-Object -ExpandProperty SnapshotName })

        @(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames).Count | Should -Be 0
    }

    It 'exposes descriptor-driven family metadata for Node, Python, and VC runtime orchestration' {
        $descriptors = & $script:SandboxModule {
            @(
                Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-NodeRuntime'
                Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-PythonRuntime'
                Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-VCRuntime'
            )
        }

        $nodeDescriptor = $descriptors | Where-Object Name -eq 'NodeRuntime'
        $pythonDescriptor = $descriptors | Where-Object Name -eq 'PythonRuntime'
        $vcDescriptor = $descriptors | Where-Object Name -eq 'VCRuntime'

        $nodeDescriptor.RuntimeFamily | Should -Be 'Node'
        $nodeDescriptor.ToolsRootPropertyName | Should -Be 'NodeToolsRoot'
        $nodeDescriptor.CacheRootPropertyName | Should -Be 'NodeCacheRoot'
        $nodeDescriptor.ManagedFinalizerFunctionName | Should -Be 'Invoke-ManifestedNodeManagedFinalization'
        $nodeDescriptor.PersistedDetailsFunctionName | Should -Be 'Get-ManifestedNodePersistedDetails'

        $pythonDescriptor.RuntimeFamily | Should -Be 'Python'
        $pythonDescriptor.ToolsRootPropertyName | Should -Be 'PythonToolsRoot'
        $pythonDescriptor.CacheRootPropertyName | Should -Be 'PythonCacheRoot'
        $pythonDescriptor.ManagedFinalizerFunctionName | Should -Be 'Invoke-ManifestedPythonManagedFinalization'
        $pythonDescriptor.PersistedDetailsFunctionName | Should -Be 'Get-ManifestedPythonPersistedDetails'

        $vcDescriptor.RuntimeFamily | Should -Be 'MachinePrerequisite'
        $vcDescriptor.CacheRootPropertyName | Should -Be 'VCRuntimeCacheRoot'
        $vcDescriptor.InstallFunctionName | Should -Be 'Install-VCRuntime'
        $vcDescriptor.PersistedDetailsFunctionName | Should -Be 'Get-ManifestedMachinePrerequisitePersistedDetails'
    }

    It 'delegates the Node, Python, and VC runtime facades through private family helpers' {
        $definitions = & $script:SandboxModule {
            @{
                Node   = (Get-Command Initialize-NodeRuntime).ScriptBlock.ToString()
                Python = (Get-Command Initialize-PythonRuntime).ScriptBlock.ToString()
                VC     = (Get-Command Initialize-VCRuntime).ScriptBlock.ToString()
            }
        }

        $definitions.Node | Should -Match 'Invoke-ManifestedNodeRuntimeInitialization'
        $definitions.Node | Should -Not -Match 'Get-NodeRuntimeState'

        $definitions.Python | Should -Match 'Invoke-ManifestedPythonRuntimeInitialization'
        $definitions.Python | Should -Not -Match 'Get-PythonRuntimeState'

        $definitions.VC | Should -Match 'Invoke-ManifestedMachinePrerequisiteRuntimeInitialization'
        $definitions.VC | Should -Not -Match 'Get-VCRuntimeState'
    }

    It 'keeps every exported runtime initializer as a thin facade over the correct family helper' {
        $facadeChecks = @(& $script:SandboxModule {
            $commandToHelper = [ordered]@{
                'Initialize-NodeRuntime'     = 'Invoke-ManifestedNodeRuntimeInitialization'
                'Initialize-PythonRuntime'   = 'Invoke-ManifestedPythonRuntimeInitialization'
                'Initialize-VCRuntime'       = 'Invoke-ManifestedMachinePrerequisiteRuntimeInitialization'
                'Initialize-Ps7Runtime'      = 'Invoke-ManifestedGitHubPortableRuntimeInitialization'
                'Initialize-GitRuntime'      = 'Invoke-ManifestedGitHubPortableRuntimeInitialization'
                'Initialize-GHCliRuntime'    = 'Invoke-ManifestedGitHubPortableRuntimeInitialization'
                'Initialize-VSCodeRuntime'   = 'Invoke-ManifestedGitHubPortableRuntimeInitialization'
                'Initialize-OpenCodeRuntime' = 'Invoke-ManifestedNpmCliRuntimeInitialization'
                'Initialize-GeminiRuntime'   = 'Invoke-ManifestedNpmCliRuntimeInitialization'
                'Initialize-QwenRuntime'     = 'Invoke-ManifestedNpmCliRuntimeInitialization'
                'Initialize-CodexRuntime'    = 'Invoke-ManifestedNpmCliRuntimeInitialization'
            }

            foreach ($entry in $commandToHelper.GetEnumerator()) {
                $descriptor = Get-ManifestedRuntimeDescriptor -CommandName $entry.Key
                [pscustomobject]@{
                    CommandName      = $entry.Key
                    ExpectedHelper   = $entry.Value
                    StateFunction    = $descriptor.StateFunctionName
                    Definition       = (Get-Command $entry.Key).ScriptBlock.ToString()
                }
            }
        })

        foreach ($facadeCheck in $facadeChecks) {
            $facadeCheck.Definition | Should -Match $facadeCheck.ExpectedHelper
            $facadeCheck.Definition | Should -Not -Match [regex]::Escape($facadeCheck.StateFunction)
        }
    }

    It 'routes VS Code command-environment expectations through descriptor metadata' {
        $state = [pscustomobject]@{
            RuntimeHome    = 'C:\Tools\VSCode'
            RuntimeSource  = 'Managed'
            ExecutablePath = 'C:\Tools\VSCode\Code.exe'
            CliCommandPath = 'C:\Tools\VSCode\bin\code.cmd'
        }

        $specification = & $script:SandboxModule {
            param($runtimeState)
            Get-ManifestedCommandEnvironmentSpec -CommandName 'Initialize-VSCodeRuntime' -RuntimeState $runtimeState
        } $state

        $specification.Applicable | Should -BeTrue
        $specification.CommandNames | Should -Contain 'code'
        $specification.CommandNames | Should -Contain 'code.cmd'
        $specification.DesiredCommandDirectory | Should -Be 'C:\Tools\VSCode\bin'
        $specification.ExpectedCommandPaths['code.cmd'] | Should -Be 'C:\Tools\VSCode\bin\code.cmd'
    }

    It 'plans Codex dependencies through registry metadata instead of hard-coded orchestration' {
        $plannedActions = @(& $script:SandboxModule {
            function Get-NodeRuntimeState {
                [pscustomobject]@{
                    Status      = 'Missing'
                    Runtime     = $null
                    RuntimeHome = $null
                }
            }

            $descriptor = Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-CodexRuntime'
            Get-ManifestedNpmCliPlannedActions -Descriptor $descriptor -NeedsRepair:$false -NeedsInstall:$true -LocalRoot 'C:\Sandbox'
        })

        $plannedActions | Should -Contain 'Initialize-VCRuntime'
        $plannedActions | Should -Contain 'Initialize-NodeRuntime'
        $plannedActions | Should -Contain 'Install-CodexRuntime'
    }

    It 'keeps GitHub-portable runtime facades free of unreachable legacy bodies' {
        $definitions = & $script:SandboxModule {
            @{
                Git    = (Get-Command Initialize-GitRuntime).ScriptBlock.ToString()
                GHCli  = (Get-Command Initialize-GHCliRuntime).ScriptBlock.ToString()
                VSCode = (Get-Command Initialize-VSCodeRuntime).ScriptBlock.ToString()
            }
        }

        $definitions.Git | Should -Match 'Invoke-ManifestedGitHubPortableRuntimeInitialization'
        $definitions.Git | Should -Not -Match 'Get-GitRuntimeState'

        $definitions.GHCli | Should -Match 'Invoke-ManifestedGitHubPortableRuntimeInitialization'
        $definitions.GHCli | Should -Not -Match 'Get-GHCliRuntimeState'

        $definitions.VSCode | Should -Match 'Invoke-ManifestedGitHubPortableRuntimeInitialization'
        $definitions.VSCode | Should -Not -Match 'Get-VSCodeRuntimeState'
    }

    It 'loads private implementation files before public facades in every runtime pack loader' {
        $loaderChecks = @(
            @{
                Path = Join-Path $script:ModuleProjectRoot 'RuntimePacks\Node\Eigenverft.Manifested.Sandbox.RuntimePack.Node.ps1'
                Pairs = @(
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.Node.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache.ps1'
                    }
                )
            }
            @{
                Path = Join-Path $script:ModuleProjectRoot 'RuntimePacks\Python\Eigenverft.Manifested.Sandbox.RuntimePack.Python.ps1'
                Pairs = @(
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.Python.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.PythonRuntimeAndCache.ps1'
                    }
                )
            }
            @{
                Path = Join-Path $script:ModuleProjectRoot 'RuntimePacks\GitHubPortable\Eigenverft.Manifested.Sandbox.RuntimePack.GitHubPortable.ps1'
                Pairs = @(
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.Ps7.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache.ps1'
                    }
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.GHCli.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntimeAndCache.ps1'
                    }
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.Git.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache.ps1'
                    }
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.VsCode.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.VsCodeRuntimeAndCache.ps1'
                    }
                )
            }
            @{
                Path = Join-Path $script:ModuleProjectRoot 'RuntimePacks\NpmCli\Eigenverft.Manifested.Sandbox.RuntimePack.NpmCli.ps1'
                Pairs = @(
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.OpenCode.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache.ps1'
                    }
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.Gemini.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache.ps1'
                    }
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.Qwen.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache.ps1'
                    }
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.Codex.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache.ps1'
                    }
                )
            }
            @{
                Path = Join-Path $script:ModuleProjectRoot 'RuntimePacks\VCRuntime\Eigenverft.Manifested.Sandbox.RuntimePack.VCRuntime.ps1'
                Pairs = @(
                    @{
                        PrivatePath = 'Private\Logic\Eigenverft.Manifested.Sandbox.Runtime.VCRuntime.ps1'
                        PublicPath  = 'Public\Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache.ps1'
                    }
                )
            }
        )

        foreach ($loaderCheck in $loaderChecks) {
            $content = Get-Content -LiteralPath $loaderCheck.Path -Raw
            foreach ($pair in $loaderCheck.Pairs) {
                $privateIndex = $content.IndexOf($pair.PrivatePath, [System.StringComparison]::OrdinalIgnoreCase)
                $publicIndex = $content.IndexOf($pair.PublicPath, [System.StringComparison]::OrdinalIgnoreCase)

                $privateIndex | Should -BeGreaterThan -1
                $publicIndex | Should -BeGreaterThan -1
                $privateIndex | Should -BeLessThan $publicIndex
            }
        }
    }

    It 'plans Node runtime follow-up actions through family metadata' {
        $plannedActions = @(& $script:SandboxModule {
            $descriptor = Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-NodeRuntime'
            Get-ManifestedNodePlannedActions -Descriptor $descriptor -NeedsRepair:$false -NeedsInstall:$true -NeedsAcquire:$true -RuntimeState ([pscustomobject]@{ RuntimeSource = 'Managed' })
        })

        $plannedActions | Should -Be @(
            'Save-NodeRuntimePackage',
            'Test-NodeRuntimePackage',
            'Install-NodeRuntime',
            'Sync-ManifestedNpmProxyConfiguration',
            'Sync-ManifestedCommandLineEnvironment'
        )
    }

    It 'plans Python managed follow-up actions through family metadata' {
        $plannedActions = @(& $script:SandboxModule {
            $descriptor = Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-PythonRuntime'
            Get-ManifestedPythonPlannedActions -Descriptor $descriptor -NeedsRepair:$false -NeedsInstall:$false -NeedsAcquire:$false -RuntimeState ([pscustomobject]@{ RuntimeSource = 'Managed' })
        })

        $plannedActions | Should -Be @(
            'Ensure-PythonPip',
            'Sync-ManifestedCommandLineEnvironment'
        )
    }

    It 'keeps machine prerequisite planning free of command-environment synchronization' {
        $plannedActions = @(& $script:SandboxModule {
            $descriptor = Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-VCRuntime'
            Get-ManifestedMachinePrerequisitePlannedActions -Descriptor $descriptor -NeedsRepair:$false -NeedsInstall:$true -NeedsAcquire:$true
        })

        $plannedActions | Should -Be @(
            'Save-VCRuntimeInstaller',
            'Test-VCRuntimeInstaller',
            'Install-VCRuntime'
        )
        $plannedActions | Should -Not -Contain 'Sync-ManifestedCommandLineEnvironment'
    }

    It 'preserves VS Code persisted detail extras in the shared GitHub-portable helper' {
        $finalState = [pscustomobject]@{
            CurrentVersion = '1.112.0'
            Flavor         = 'win32-x64'
            Channel        = 'stable'
            RuntimeHome    = 'C:\Tools\VSCode'
            RuntimeSource  = 'Managed'
            ExecutablePath = 'C:\Tools\VSCode\Code.exe'
            CliCommandPath = 'C:\Tools\VSCode\bin\code.cmd'
            PortableMode   = $true
            PackagePath    = 'C:\Cache\code.zip'
        }
        $packageInfo = [pscustomobject]@{
            TagName     = '1.112.0'
            FileName    = 'code.zip'
            Path        = 'C:\Cache\code.zip'
            DownloadUrl = 'https://example.invalid/code.zip'
            Sha256      = 'abc123'
            ShaSource   = 'release'
        }

        $details = & $script:SandboxModule {
            param($state, $package)
            $descriptor = Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-VSCodeRuntime'
            Get-ManifestedGitHubPortablePersistedDetails -Descriptor $descriptor -FinalState $state -PackageInfo $package
        } $finalState $packageInfo

        $details.Channel | Should -Be 'stable'
        $details.CliCommandPath | Should -Be 'C:\Tools\VSCode\bin\code.cmd'
        $details.PortableMode | Should -BeTrue
        $details.PackagePath | Should -Be 'C:\Cache\code.zip'
    }

    It 'preserves Node persisted details in the family helper' {
        $details = & $script:SandboxModule {
            $descriptor = Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-NodeRuntime'
            $finalState = [pscustomobject]@{
                CurrentVersion = '24.8.0'
                PackagePath    = 'C:\Cache\node.zip'
                RuntimeHome    = 'C:\Tools\Node'
                RuntimeSource  = 'Managed'
                ExecutablePath = 'C:\Tools\Node\node.exe'
            }

            Get-ManifestedNodePersistedDetails -Descriptor $descriptor -FinalState $finalState
        }

        $details.Version | Should -Be '24.8.0'
        $details.PackagePath | Should -Be 'C:\Cache\node.zip'
        $details.RuntimeHome | Should -Be 'C:\Tools\Node'
        $details.RuntimeSource | Should -Be 'Managed'
        $details.ExecutablePath | Should -Be 'C:\Tools\Node\node.exe'
    }

    It 'preserves Python persisted details in the family helper' {
        $details = & $script:SandboxModule {
            $descriptor = Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-PythonRuntime'
            $finalState = [pscustomobject]@{
                CurrentVersion = '3.13.2'
                Flavor         = 'embed-amd64'
                RuntimeHome    = 'C:\Tools\Python'
                RuntimeSource  = 'Managed'
                ExecutablePath = 'C:\Tools\Python\python.exe'
            }
            $packageInfo = [pscustomobject]@{
                FileName    = 'python-3.13.2-embed-amd64.zip'
                Sha256      = 'abc123'
                ShaSource   = 'release'
                DownloadUrl = 'https://example.invalid/python.zip'
                ReleaseUrl  = 'https://example.invalid/release'
                ReleaseId   = 42
            }
            $runtimeTest = [pscustomobject]@{
                PipVersion = '25.0'
            }
            $pipSetupResult = [pscustomobject]@{
                PipProxyConfiguration = [pscustomobject]@{
                    PipConfigPath = 'C:\Tools\Python\pip.ini'
                }
            }

            Get-ManifestedPythonPersistedDetails -Descriptor $descriptor -FinalState $finalState -PackageInfo $packageInfo -RuntimeTest $runtimeTest -PipSetupResult $pipSetupResult
        }

        $details.Version | Should -Be '3.13.2'
        $details.Flavor | Should -Be 'embed-amd64'
        $details.RuntimeHome | Should -Be 'C:\Tools\Python'
        $details.RuntimeSource | Should -Be 'Managed'
        $details.ExecutablePath | Should -Be 'C:\Tools\Python\python.exe'
        $details.PipVersion | Should -Be '25.0'
        $details.PipConfigPath | Should -Be 'C:\Tools\Python\pip.ini'
        $details.AssetName | Should -Be 'python-3.13.2-embed-amd64.zip'
        $details.Sha256 | Should -Be 'abc123'
        $details.ShaSource | Should -Be 'release'
        $details.DownloadUrl | Should -Be 'https://example.invalid/python.zip'
        $details.ReleaseUrl | Should -Be 'https://example.invalid/release'
        $details.ReleaseId | Should -Be 42
    }

    It 'preserves machine prerequisite persisted details in the family helper' {
        $details = & $script:SandboxModule {
            $descriptor = Get-ManifestedRuntimeDescriptor -CommandName 'Initialize-VCRuntime'
            $finalState = [pscustomobject]@{
                CurrentVersion = '14.42.34433.0'
                InstallerPath  = 'C:\Cache\vc_redist.x64.exe'
            }

            Get-ManifestedMachinePrerequisitePersistedDetails -Descriptor $descriptor -FinalState $finalState
        }

        $details.Version | Should -Be '14.42.34433.0'
        $details.InstallerPath | Should -Be 'C:\Cache\vc_redist.x64.exe'
    }

    It 'constructs lifecycle results with shared and family-specific properties intact' {
        $result = & $script:SandboxModule {
            New-ManifestedRuntimeResult -LocalRoot 'C:\Sandbox' -Layout ([pscustomobject]@{ LocalRoot = 'C:\Sandbox' }) -InitialState ([pscustomobject]@{ Status = 'Missing' }) -FinalState ([pscustomobject]@{ Status = 'Blocked' }) -ActionTaken @('None') -PlannedActions @('Repair-NodeRuntime') -RestartRequired:$false -AdditionalProperties ([ordered]@{
                Package               = $null
                PackageTest           = $null
                RuntimeTest           = $null
                RepairResult          = $null
                InstallResult         = $null
                NpmProxyConfiguration = [pscustomobject]@{ Action = 'Reused' }
                CommandEnvironment    = [pscustomobject]@{ Applicable = $false; Status = 'NotApplicable' }
                Elevation             = [pscustomobject]@{ RequiresElevation = $false }
            })
        }

        $result.LocalRoot | Should -Be 'C:\Sandbox'
        $result.PlannedActions | Should -Be @('Repair-NodeRuntime')
        $result.NpmProxyConfiguration.Action | Should -Be 'Reused'
        $result.CommandEnvironment.Status | Should -Be 'NotApplicable'
        $result.Elevation.RequiresElevation | Should -BeFalse
    }

    It 'completes WhatIf lifecycle results without persisting state' {
        $result = & $script:SandboxModule {
            function Save-ManifestedInvokeState {
                throw 'Save-ManifestedInvokeState should not be called for non-persisted lifecycle results.'
            }

            $runtimeResult = New-ManifestedRuntimeResult -LocalRoot 'C:\Sandbox' -Layout ([pscustomobject]@{ LocalRoot = 'C:\Sandbox' }) -InitialState $null -FinalState ([pscustomobject]@{ Status = 'Missing' }) -ActionTaken @('WhatIf') -PlannedActions @('Save-NodeRuntimePackage') -RestartRequired:$false -AdditionalProperties ([ordered]@{
                Package            = $null
                PackageTest        = $null
                RuntimeTest        = $null
                RepairResult       = $null
                InstallResult      = $null
                CommandEnvironment = [pscustomobject]@{ Applicable = $false; Status = 'NotApplicable' }
                Elevation          = [pscustomobject]@{ RequiresElevation = $false }
            })

            Complete-ManifestedRuntimeResult -CommandName 'Initialize-NodeRuntime' -Result $runtimeResult -LocalRoot 'C:\Sandbox' -PersistState:$false
        }

        $result.ActionTaken | Should -Be @('WhatIf')
        $result.PersistedStatePath | Should -Be $null
    }

    It 'skips runtime command-environment synchronization cleanly when not applicable' {
        $syncResult = & $script:SandboxModule {
            function Invoke-TestCommandEnvironmentSync {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param()

                function Get-ManifestedCommandEnvironmentResult {
                    param(
                        [string]$CommandName,
                        [pscustomobject]$RuntimeState
                    )

                    [pscustomobject]@{
                        Applicable = $false
                        Status     = 'NotApplicable'
                    }
                }

                $actionsTaken = New-Object System.Collections.Generic.List[string]
                $result = Invoke-ManifestedRuntimeCommandEnvironmentSync -Cmdlet $PSCmdlet -CommandName 'Initialize-NodeRuntime' -DisplayName 'Node' -RuntimeState ([pscustomobject]@{ RuntimeHome = 'C:\Sandbox\tools\node' }) -ActionsTaken $actionsTaken -UseShouldProcess:$true

                [pscustomobject]@{
                    Result      = $result
                    ActionsTaken = @($actionsTaken)
                }
            }

            Invoke-TestCommandEnvironmentSync
        }

        $syncResult.Result.StopProcessing | Should -BeFalse
        $syncResult.Result.CommandEnvironment.Status | Should -Be 'NotApplicable'
        $syncResult.ActionsTaken | Should -Be @()
    }

    It 'tracks command-environment sync updates through the lifecycle helper' {
        $syncResult = & $script:SandboxModule {
            function Invoke-TestCommandEnvironmentSync {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param()

                function Get-ManifestedCommandEnvironmentResult {
                    param(
                        [string]$CommandName,
                        [pscustomobject]$RuntimeState
                    )

                    [pscustomobject]@{
                        Applicable              = $true
                        Status                  = 'NeedsSync'
                        DesiredCommandDirectory = 'C:\Sandbox\tools\node'
                    }
                }

                function Get-ManifestedCommandEnvironmentSpec {
                    param(
                        [string]$CommandName,
                        [pscustomobject]$RuntimeState
                    )

                    [pscustomobject]@{
                        Applicable              = $true
                        DesiredCommandDirectory = 'C:\Sandbox\tools\node'
                        CommandNames            = @('node.exe')
                        ExpectedCommandPaths    = [ordered]@{
                            'node.exe' = 'C:\Sandbox\tools\node\node.exe'
                        }
                    }
                }

                function Sync-ManifestedCommandLineEnvironment {
                    param([pscustomobject]$Specification)

                    [pscustomobject]@{
                        Applicable              = $true
                        Status                  = 'Updated'
                        DesiredCommandDirectory = $Specification.DesiredCommandDirectory
                    }
                }

                $actionsTaken = New-Object System.Collections.Generic.List[string]
                $result = Invoke-ManifestedRuntimeCommandEnvironmentSync -Cmdlet $PSCmdlet -CommandName 'Initialize-NodeRuntime' -DisplayName 'Node' -RuntimeState ([pscustomobject]@{ RuntimeHome = 'C:\Sandbox\tools\node' }) -ActionsTaken $actionsTaken -UseShouldProcess:$false -RequireNeedsSync:$true

                [pscustomobject]@{
                    Result      = $result
                    ActionsTaken = @($actionsTaken)
                }
            }

            Invoke-TestCommandEnvironmentSync
        }

        $syncResult.Result.StopProcessing | Should -BeFalse
        $syncResult.Result.CommandEnvironment.Status | Should -Be 'Updated'
        $syncResult.ActionsTaken | Should -Contain 'Sync-ManifestedCommandLineEnvironment'
    }

    It 'returns a WhatIf result shape for the Node facade without persisting state' {
        $result = & $script:SandboxModule {
            function Get-ManifestedLayout {
                [pscustomobject]@{
                    LocalRoot     = 'C:\Sandbox'
                    NodeCacheRoot = 'C:\Sandbox\cache\node'
                    NodeToolsRoot = 'C:\Sandbox\tools\node'
                }
            }

            function Get-ManifestedSelfElevationContext {
                [pscustomobject]@{
                    SkipSelfElevation = $true
                    WasSelfElevated   = $false
                }
            }

            function Get-ManifestedCommandElevationPlan {
                param(
                    [string]$CommandName,
                    [object[]]$PlannedActions,
                    [hashtable]$Context,
                    [string]$LocalRoot,
                    [bool]$SkipSelfElevation,
                    [bool]$WasSelfElevated,
                    [bool]$WhatIfMode
                )

                [pscustomobject]@{
                    CommandName       = $CommandName
                    PlannedActions    = @($PlannedActions)
                    RequiresElevation = $false
                    WhatIfMode        = $WhatIfMode
                }
            }

            function Get-ManifestedCommandEnvironmentResult {
                param(
                    [string]$CommandName,
                    [pscustomobject]$RuntimeState
                )

                [pscustomobject]@{
                    Applicable = $false
                    Status     = 'NotApplicable'
                }
            }

            function Get-NodeRuntimeState {
                param(
                    [string]$LocalRoot,
                    [string]$Flavor
                )

                [pscustomobject]@{
                    Status        = 'Missing'
                    LocalRoot     = 'C:\Sandbox'
                    Layout        = [pscustomobject]@{
                        LocalRoot     = 'C:\Sandbox'
                        NodeCacheRoot = 'C:\Sandbox\cache\node'
                        NodeToolsRoot = 'C:\Sandbox\tools\node'
                    }
                    Flavor        = 'win-x64'
                    PackagePath   = $null
                    RuntimeHome   = $null
                    Runtime       = $null
                    RuntimeSource = $null
                }
            }

            Initialize-NodeRuntime -WhatIf
        }

        $result.ActionTaken | Should -Be @('WhatIf')
        $result.PlannedActions | Should -Contain 'Save-NodeRuntimePackage'
        $result.PlannedActions | Should -Contain 'Sync-ManifestedCommandLineEnvironment'
        $result.PersistedStatePath | Should -Be $null
        $result.PSObject.Properties.Name | Should -Contain 'CommandEnvironment'
    }

    It 'returns a WhatIf result shape for the Python facade without persisting state' {
        $result = & $script:SandboxModule {
            function Get-ManifestedLayout {
                [pscustomobject]@{
                    LocalRoot       = 'C:\Sandbox'
                    PythonCacheRoot = 'C:\Sandbox\cache\python'
                    PythonToolsRoot = 'C:\Sandbox\tools\python'
                }
            }

            function Get-ManifestedSelfElevationContext {
                [pscustomobject]@{
                    SkipSelfElevation = $true
                    WasSelfElevated   = $false
                }
            }

            function Get-ManifestedCommandElevationPlan {
                param(
                    [string]$CommandName,
                    [object[]]$PlannedActions,
                    [hashtable]$Context,
                    [string]$LocalRoot,
                    [bool]$SkipSelfElevation,
                    [bool]$WasSelfElevated,
                    [bool]$WhatIfMode
                )

                [pscustomobject]@{
                    CommandName       = $CommandName
                    PlannedActions    = @($PlannedActions)
                    RequiresElevation = $false
                    WhatIfMode        = $WhatIfMode
                }
            }

            function Get-ManifestedCommandEnvironmentResult {
                param(
                    [string]$CommandName,
                    [pscustomobject]$RuntimeState
                )

                [pscustomobject]@{
                    Applicable = $true
                    Status     = 'NeedsSync'
                }
            }

            function Get-PythonRuntimeState {
                param(
                    [string]$LocalRoot,
                    [string]$Flavor
                )

                [pscustomobject]@{
                    Status        = 'Ready'
                    LocalRoot     = 'C:\Sandbox'
                    Layout        = [pscustomobject]@{
                        LocalRoot       = 'C:\Sandbox'
                        PythonCacheRoot = 'C:\Sandbox\cache\python'
                        PythonToolsRoot = 'C:\Sandbox\tools\python'
                    }
                    Flavor        = 'embed-amd64'
                    PackagePath   = 'C:\Sandbox\cache\python\python.zip'
                    Package       = [pscustomobject]@{
                        Path = 'C:\Sandbox\cache\python\python.zip'
                    }
                    RuntimeHome   = 'C:\Sandbox\tools\python'
                    Runtime       = [pscustomobject]@{
                        IsReady = $true
                    }
                    RuntimeSource = 'Managed'
                    ExecutablePath = 'C:\Sandbox\tools\python\python.exe'
                }
            }

            function Test-PythonRuntimePackageHasTrustedHash {
                param([pscustomobject]$PackageInfo)
                return $true
            }

            Initialize-PythonRuntime -WhatIf
        }

        $result.ActionTaken | Should -Be @('WhatIf')
        $result.PlannedActions | Should -Be @(
            'Ensure-PythonPip',
            'Sync-ManifestedCommandLineEnvironment'
        )
        $result.PersistedStatePath | Should -Be $null
        $result.PSObject.Properties.Name | Should -Contain 'PipSetupResult'
        $result.PSObject.Properties.Name | Should -Contain 'PipProxyConfiguration'
    }

    It 'returns a WhatIf result shape for the VC runtime facade without persisting state' {
        $result = & $script:SandboxModule {
            function Get-ManifestedLayout {
                [pscustomobject]@{
                    LocalRoot        = 'C:\Sandbox'
                    VCRuntimeCacheRoot = 'C:\Sandbox\cache\vc'
                }
            }

            function Get-ManifestedSelfElevationContext {
                [pscustomobject]@{
                    SkipSelfElevation = $true
                    WasSelfElevated   = $false
                }
            }

            function Get-ManifestedCommandElevationPlan {
                param(
                    [string]$CommandName,
                    [object[]]$PlannedActions,
                    [hashtable]$Context,
                    [string]$LocalRoot,
                    [bool]$SkipSelfElevation,
                    [bool]$WasSelfElevated,
                    [bool]$WhatIfMode
                )

                [pscustomobject]@{
                    CommandName       = $CommandName
                    PlannedActions    = @($PlannedActions)
                    RequiresElevation = $false
                    WhatIfMode        = $WhatIfMode
                }
            }

            function Get-VCRuntimeState {
                param([string]$LocalRoot)

                [pscustomobject]@{
                    Status           = 'Missing'
                    LocalRoot        = 'C:\Sandbox'
                    Layout           = [pscustomobject]@{
                        LocalRoot          = 'C:\Sandbox'
                        VCRuntimeCacheRoot = 'C:\Sandbox\cache\vc'
                    }
                    CurrentVersion   = $null
                    InstalledRuntime = [pscustomobject]@{
                        Installed = $false
                    }
                    Runtime          = [pscustomobject]@{
                        Status    = 'Missing'
                        Installed = $false
                    }
                    Installer        = $null
                    InstallerPath    = 'C:\Sandbox\cache\vc\vc_redist.x64.exe'
                    PartialPaths     = @()
                    BlockedReason    = $null
                }
            }

            Initialize-VCRuntime -WhatIf
        }

        $result.ActionTaken | Should -Be @('WhatIf')
        $result.PlannedActions | Should -Be @(
            'Save-VCRuntimeInstaller',
            'Test-VCRuntimeInstaller',
            'Install-VCRuntime'
        )
        $result.PersistedStatePath | Should -Be $null
        $result.RestartRequired | Should -BeFalse
    }

    It 'keeps exported commands aligned with the manifest contract' {
        $expectedExports = @($script:ManifestData.FunctionsToExport | Sort-Object)
        $actualExports = @($script:SandboxModule.ExportedCommands.Keys | Sort-Object)

        @(Compare-Object -ReferenceObject $expectedExports -DifferenceObject $actualExports).Count | Should -Be 0
    }
}
