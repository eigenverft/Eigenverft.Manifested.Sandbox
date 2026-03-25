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
        $moduleManifestPath = Join-Path $moduleProjectRoot 'Eigenverft.Manifested.Sandbox.psd1'
        $manifestData = Import-PowerShellDataFile -Path $moduleManifestPath

        $script:SandboxModule = Import-Module $moduleManifestPath -Force -PassThru
    }

    AfterAll {
        if ($script:SandboxModule) {
            Remove-Module $script:SandboxModule.Name -Force -ErrorAction SilentlyContinue
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

    It 'keeps exported commands aligned with the manifest contract' {
        $expectedExports = @($manifestData.FunctionsToExport | Sort-Object)
        $actualExports = @($script:SandboxModule.ExportedCommands.Keys | Sort-Object)

        @(Compare-Object -ReferenceObject $expectedExports -DifferenceObject $actualExports).Count | Should -Be 0
    }
}
