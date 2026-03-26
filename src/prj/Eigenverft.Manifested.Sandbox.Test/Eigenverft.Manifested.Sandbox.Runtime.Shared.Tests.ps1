<#
    Shared helper coverage for runtime-family refactors.
#>

Describe 'Eigenverft.Manifested.Sandbox shared runtime helpers' {
    BeforeAll {
        $testProjectRoot = if ($PSCommandPath) {
            Split-Path -Parent $PSCommandPath
        }
        else {
            $PSScriptRoot
        }

        $moduleProjectRoot = Join-Path (Split-Path -Parent $testProjectRoot) 'Eigenverft.Manifested.Sandbox'
        $script:ModuleManifestPath = Join-Path $moduleProjectRoot 'Eigenverft.Manifested.Sandbox.psd1'
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

    It 'exposes shared npm CLI definitions for all managed CLI runtimes' {
        $definitions = @(& $script:SandboxModule {
            @(
                Get-ManifestedCodexNpmCliRuntimeDefinition
                Get-ManifestedOpenCodeNpmCliRuntimeDefinition
                Get-ManifestedGeminiNpmCliRuntimeDefinition
                Get-ManifestedQwenNpmCliRuntimeDefinition
            )
        })

        ($definitions | Select-Object -ExpandProperty Name) | Should -Be @(
            'CodexRuntime',
            'OpenCodeRuntime',
            'GeminiRuntime',
            'QwenRuntime'
        )

        ($definitions | Where-Object Name -eq 'CodexRuntime').PackageId | Should -Be '@openai/codex@latest'
        ($definitions | Where-Object Name -eq 'OpenCodeRuntime').ExecutableFileName | Should -Be 'opencode.cmd'
        ($definitions | Where-Object Name -eq 'GeminiRuntime').NodeDependency.MinimumVersion | Should -Be ([version]'20.0.0')
        ($definitions | Where-Object Name -eq 'QwenRuntime').CommandEnvironmentNames | Should -Be @('qwen', 'qwen.cmd')
    }

    It 'builds npm CLI runtime states through the shared helper for Codex OpenCode Gemini and Qwen' {
        $states = @(& $script:SandboxModule {
            function Get-ManifestedLayout {
                param([string]$LocalRoot)

                [pscustomobject]@{
                    LocalRoot         = 'C:\Sandbox'
                    CodexToolsRoot    = 'C:\Sandbox\tools\codex'
                    OpenCodeToolsRoot = 'C:\Sandbox\tools\opencode'
                    GeminiToolsRoot   = 'C:\Sandbox\tools\gemini'
                    QwenToolsRoot     = 'C:\Sandbox\tools\qwen'
                }
            }

            function Get-ManifestedStageDirectories {
                param(
                    [string]$Prefix,
                    [string]$Mode,
                    [string[]]$LegacyRootPaths
                )

                return @()
            }

            function Get-InstalledManifestedNpmCliRuntime {
                param(
                    [pscustomobject]$Definition,
                    [string]$LocalRoot
                )

                $runtime = [ordered]@{
                    Version         = '1.2.3'
                    RuntimeHome     = ('C:\Sandbox\tools\' + $Definition.StagePrefix + '\1.2.3')
                }
                $runtime[$Definition.ExecutablePropertyName] = ('C:\Sandbox\tools\' + $Definition.StagePrefix + '\1.2.3\' + $Definition.ExecutableFileName)
                $runtime['PackageJsonPath'] = ('C:\Sandbox\tools\' + $Definition.StagePrefix + '\1.2.3\package.json')
                $runtime['Validation'] = [pscustomobject]@{
                    Status  = 'Ready'
                    IsReady = $true
                }
                $runtime['VersionMatches'] = $true
                $runtime['IsReady'] = $true
                $runtime['Source'] = 'Managed'

                $runtimeEntry = [pscustomobject]$runtime
                [pscustomobject]@{
                    Current = $runtimeEntry
                    Valid   = @($runtimeEntry)
                    Invalid = @()
                }
            }

            function Get-SystemManifestedNpmCliRuntime {
                throw 'External npm CLI discovery should not run when a managed runtime is already present.'
            }

            @(
                [pscustomobject]@{ Name = 'Codex'; State = (Get-ManifestedNpmCliRuntimeState -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -LocalRoot 'C:\Sandbox') }
                [pscustomobject]@{ Name = 'OpenCode'; State = (Get-ManifestedNpmCliRuntimeState -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -LocalRoot 'C:\Sandbox') }
                [pscustomobject]@{ Name = 'Gemini'; State = (Get-ManifestedNpmCliRuntimeState -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -LocalRoot 'C:\Sandbox') }
                [pscustomobject]@{ Name = 'Qwen'; State = (Get-ManifestedNpmCliRuntimeState -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -LocalRoot 'C:\Sandbox') }
            )
        })

        foreach ($stateEntry in $states) {
            $stateEntry.State.Status | Should -Be 'Ready'
            $stateEntry.State.RuntimeSource | Should -Be 'Managed'
            $stateEntry.State.PackageJsonPath | Should -Match '\\package\.json$'
            $stateEntry.State.ExecutablePath | Should -Match '\.cmd$'
        }
    }

    It 'reuses shared archive state assembly for Git GHCli and VS Code leaves' {
        $states = @(& $script:SandboxModule {
            function Get-GitFlavor { '64-bit' }
            function Get-GHCliFlavor { 'windows_amd64' }
            function Get-VSCodeFlavor { 'win32-x64' }

            function Get-ManifestedLayout {
                param([string]$LocalRoot)

                [pscustomobject]@{
                    LocalRoot      = 'C:\Sandbox'
                    ToolsRoot      = 'C:\Sandbox\tools'
                    GitCacheRoot   = 'C:\Sandbox\cache\git'
                    GitToolsRoot   = 'C:\Sandbox\tools\git'
                    GHCliCacheRoot = 'C:\Sandbox\cache\gh'
                    GHCliToolsRoot = 'C:\Sandbox\tools\gh'
                    VsCodeCacheRoot = 'C:\Sandbox\cache\vscode'
                    VsCodeToolsRoot = 'C:\Sandbox\tools\vscode'
                }
            }

            function Get-ManifestedStageDirectories {
                param(
                    [string]$Prefix,
                    [string]$Mode,
                    [string[]]$LegacyRootPaths
                )

                return @()
            }

            function Get-InstalledGitRuntime {
                param([string]$Flavor, [string]$LocalRoot)
                $runtime = [pscustomobject]@{
                    Version        = '2.48.1.2'
                    RuntimeHome    = 'C:\Sandbox\tools\git\2.48.1.2\64-bit'
                    GitCmd         = 'C:\Sandbox\tools\git\2.48.1.2\64-bit\cmd\git.exe'
                    Validation     = [pscustomobject]@{ Status = 'Ready'; IsReady = $true }
                    VersionMatches = $true
                    IsReady        = $true
                }
                [pscustomobject]@{
                    Current = $runtime
                    Valid   = @($runtime)
                    Invalid = @()
                }
            }

            function Get-SystemGitRuntime { $null }
            function Get-LatestCachedGitRuntimePackage { $null }

            function Get-InstalledGHCliRuntime {
                param([string]$Flavor, [string]$LocalRoot)
                [pscustomobject]@{
                    Current = $null
                    Valid   = @()
                    Invalid = @()
                }
            }

            function Get-SystemGHCliRuntime { $null }

            function Get-LatestCachedGHCliRuntimePackage {
                param([string]$Flavor, [string]$LocalRoot)
                [pscustomobject]@{
                    Version = '2.68.1'
                    Path    = 'C:\Sandbox\cache\gh\gh_2.68.1_windows_amd64.zip'
                }
            }

            function Get-InstalledVSCodeRuntime {
                param([string]$Flavor, [string]$LocalRoot)
                [pscustomobject]@{
                    Current = $null
                    Valid   = @()
                    Invalid = @(
                        [pscustomobject]@{
                            RuntimeHome = 'C:\Sandbox\tools\vscode\broken'
                        }
                    )
                }
            }

            function Get-SystemVSCodeRuntime { $null }

            function Get-LatestCachedVSCodeRuntimePackage {
                param([string]$Flavor, [string]$LocalRoot)
                [pscustomobject]@{
                    Version = '1.99.0'
                    Path    = 'C:\Sandbox\cache\vscode\VSCode-win32-x64-1.99.0.zip'
                    Channel = 'stable'
                }
            }

            @(
                [pscustomobject]@{ Name = 'Git'; State = (Get-GitRuntimeState -LocalRoot 'C:\Sandbox') }
                [pscustomobject]@{ Name = 'GHCli'; State = (Get-GHCliRuntimeState -LocalRoot 'C:\Sandbox') }
                [pscustomobject]@{ Name = 'VSCode'; State = (Get-VSCodeRuntimeState -LocalRoot 'C:\Sandbox') }
            )
        })

        ($states | Where-Object Name -eq 'Git').State.Status | Should -Be 'Ready'
        ($states | Where-Object Name -eq 'Git').State.RuntimeSource | Should -Be 'Managed'

        ($states | Where-Object Name -eq 'GHCli').State.Status | Should -Be 'NeedsInstall'
        ($states | Where-Object Name -eq 'GHCli').State.PackagePath | Should -Match 'gh_2\.68\.1_windows_amd64\.zip$'

        ($states | Where-Object Name -eq 'VSCode').State.Status | Should -Be 'NeedsRepair'
        ($states | Where-Object Name -eq 'VSCode').State.InvalidRuntimeHomes | Should -Contain 'C:\Sandbox\tools\vscode\broken'
    }

    It 'prefers trusted archive caches when choosing the latest cached package' {
        $selectedPackage = & $script:SandboxModule {
            Get-LatestManifestedArchiveRuntimePackage -CachedPackages @(
                [pscustomobject]@{ Version = '2.0.0'; Sha256 = $null; FileName = 'a.zip' }
                [pscustomobject]@{ Version = '1.9.0'; Sha256 = 'deadbeef'; FileName = 'b.zip' }
            )
        }

        $selectedPackage.FileName | Should -Be 'b.zip'
    }

    It 'promotes archive installs through the shared helper and runs the VS Code portable data hook' {
        $testRoot = Join-Path $env:TEMP ('ManifestedArchiveSharedTests-' + [guid]::NewGuid().ToString('N'))
        $expandedRoot = Join-Path $testRoot 'expanded'
        $stagePath = Join-Path $testRoot 'stage'
        $runtimeHome = Join-Path $testRoot 'runtime'
        $packagePath = Join-Path $testRoot 'package.zip'

        try {
            New-Item -ItemType Directory -Path (Join-Path $expandedRoot 'bin') -Force | Out-Null
            New-Item -ItemType Directory -Path $stagePath -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $expandedRoot 'Code.exe') -Value 'exe' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $expandedRoot 'bin\code.cmd') -Value 'cmd' -Encoding ASCII
            Set-Content -LiteralPath $packagePath -Value 'zip' -Encoding ASCII

            $result = & $script:SandboxModule {
                param($paths)

                function Expand-ManifestedArchiveToStage {
                    param(
                        [string]$PackagePath,
                        [string]$Prefix
                    )

                    [pscustomobject]@{
                        StagePath     = $paths.StagePath
                        ExpandedRoot  = $paths.ExpandedRoot
                    }
                }

                function New-ManifestedDirectory {
                    param([string]$Path)

                    New-Item -ItemType Directory -Path $Path -Force | Out-Null
                    return $Path
                }

                function Remove-ManifestedPath {
                    param([string]$Path)

                    if (Test-Path -LiteralPath $Path) {
                        Remove-Item -LiteralPath $Path -Recurse -Force
                    }

                    return $true
                }

                Install-ManifestedArchiveRuntimeFromPackage -PackageInfo ([pscustomobject]@{ Path = $paths.PackagePath }) -RuntimeHome $paths.RuntimeHome -StagePrefix 'vscode' -DisplayName 'VS Code' -TestRuntime {
                    param($candidateRuntimeHome)

                    $isReady = (Test-Path -LiteralPath (Join-Path $candidateRuntimeHome 'Code.exe')) -and
                        (Test-Path -LiteralPath (Join-Path $candidateRuntimeHome 'bin\code.cmd')) -and
                        (Test-Path -LiteralPath (Join-Path $candidateRuntimeHome 'data'))

                    [pscustomobject]@{
                        Status = if ($isReady) { 'Ready' } else { 'Missing' }
                    }
                } -PostInstall {
                    param($candidateRuntimeHome)

                    New-Item -ItemType Directory -Path (Join-Path $candidateRuntimeHome 'data') -Force | Out-Null
                }
            } ([pscustomobject]@{
                ExpandedRoot = $expandedRoot
                StagePath    = $stagePath
                RuntimeHome  = $runtimeHome
                PackagePath  = $packagePath
            })

            $result.Action | Should -Be 'Installed'
            $result.Validation.Status | Should -Be 'Ready'
            (Test-Path -LiteralPath (Join-Path $runtimeHome 'data')) | Should -BeTrue
            (Test-Path -LiteralPath $stagePath) | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $testRoot) {
                Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'calculates shared proxy actions for external direct reused and needs-config cases' {
        $actions = & $script:SandboxModule {
            [pscustomobject]@{
                External = Get-ManifestedManagedProxyAction -IsManagedTarget:$false -Route 'Proxy' -DesiredProxyUri 'http://proxy:8080' -CurrentValues @() -ExternalAction 'SkippedExternal' -DirectAction 'DirectNoChange' -ReusedAction 'ReusedManaged' -NeedsAction 'NeedsManaged'
                Direct   = Get-ManifestedManagedProxyAction -IsManagedTarget:$true -Route 'Direct' -DesiredProxyUri $null -CurrentValues @() -ExternalAction 'SkippedExternal' -DirectAction 'DirectNoChange' -ReusedAction 'ReusedManaged' -NeedsAction 'NeedsManaged'
                Reused   = Get-ManifestedManagedProxyAction -IsManagedTarget:$true -Route 'Proxy' -DesiredProxyUri 'http://proxy:8080' -CurrentValues @('http://proxy:8080', 'http://proxy:8080') -ExternalAction 'SkippedExternal' -DirectAction 'DirectNoChange' -ReusedAction 'ReusedManaged' -NeedsAction 'NeedsManaged'
                Needs    = Get-ManifestedManagedProxyAction -IsManagedTarget:$true -Route 'Proxy' -DesiredProxyUri 'http://proxy:8080' -CurrentValues @('http://old-proxy:8080') -ExternalAction 'SkippedExternal' -DirectAction 'DirectNoChange' -ReusedAction 'ReusedManaged' -NeedsAction 'NeedsManaged'
            }
        }

        $actions.External | Should -Be 'SkippedExternal'
        $actions.Direct | Should -Be 'DirectNoChange'
        $actions.Reused | Should -Be 'ReusedManaged'
        $actions.Needs | Should -Be 'NeedsManaged'
    }
}
