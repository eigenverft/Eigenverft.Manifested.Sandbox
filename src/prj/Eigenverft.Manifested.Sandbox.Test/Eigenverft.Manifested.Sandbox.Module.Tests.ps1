<#
    Minimal Pester sketch for the module.
#>

Describe 'Eigenverft.Manifested.Sandbox module' {
    BeforeAll {
        $moduleManifestPath = $null
        $testProjectRoot = $null
        $script:previousLocalRoot = [System.Environment]::GetEnvironmentVariable('EIGENVERFT_MANIFESTED_LOCALROOT', 'Process')
        $script:testLocalRoot = Join-Path $TestDrive 'manifested-localroot'
        [System.Environment]::SetEnvironmentVariable('EIGENVERFT_MANIFESTED_LOCALROOT', $script:testLocalRoot, 'Process')

        if ($PSCommandPath) {
            $testProjectRoot = Split-Path -Parent $PSCommandPath
        }
        elseif ($PSScriptRoot) {
            $testProjectRoot = $PSScriptRoot
        }

        if ($testProjectRoot) {
            $moduleManifestPath = Join-Path (Split-Path -Parent $testProjectRoot) 'Eigenverft.Manifested.Sandbox\Eigenverft.Manifested.Sandbox.psd1'
        }

        if (-not $moduleManifestPath -or -not (Test-Path -LiteralPath $moduleManifestPath)) {
            $moduleManifestPath = Join-Path (Get-Location) 'src\prj\Eigenverft.Manifested.Sandbox\Eigenverft.Manifested.Sandbox.psd1'
        }

        if (-not (Test-Path -LiteralPath $moduleManifestPath)) {
            throw "Could not find module manifest at '$moduleManifestPath'. Run the test from the repository root or update the test path."
        }

        Import-Module $moduleManifestPath -Force
    }

    AfterAll {
        Remove-Module Eigenverft.Manifested.Sandbox -Force -ErrorAction SilentlyContinue
        [System.Environment]::SetEnvironmentVariable('EIGENVERFT_MANIFESTED_LOCALROOT', $script:previousLocalRoot, 'Process')
    }

    It 'returns the loaded module version from Get-SandboxVersion' {
        $versionText = Get-SandboxVersion

        $versionText | Should -Match '^Eigenverft\.Manifested\.Sandbox \d+\.\d+\.\d+'
    }

    It 'returns live fact-based runtime state from packaged definitions without persisted state document fields' {
        $state = Get-SandboxState

        $state.PSObject.Properties.Name | Should -Contain 'DefinitionCount'
        $state.PSObject.Properties.Name | Should -Contain 'RuntimeCount'
        $state.PSObject.Properties.Name | Should -Contain 'Runtimes'
        $state.PSObject.Properties.Name | Should -Not -Contain 'StatePath'
        $state.PSObject.Properties.Name | Should -Not -Contain 'StateExists'
        $state.PSObject.Properties.Name | Should -Not -Contain 'Commands'
        $state.PSObject.Properties.Name | Should -Not -Contain 'Document'
        $state.DefinitionCount | Should -Be 3
        @($state.Runtimes).Count | Should -Be $state.RuntimeCount
    }

    It 'returns packaged block-driven command definitions without handler ids' {
        InModuleScope Eigenverft.Manifested.Sandbox {
            $definitions = Get-ManifestedCommandDefinitions

            @($definitions).Count | Should -Be 3
            @($definitions | ForEach-Object { $_.commandName }) | Should -Contain 'Initialize-NodeRuntime'
            @($definitions | ForEach-Object { $_.commandName }) | Should -Contain 'Initialize-GHCliRuntime'
            @($definitions | ForEach-Object { $_.commandName }) | Should -Contain 'Initialize-Ps7Runtime'

            foreach ($definition in @($definitions)) {
                $definition.PSObject.Properties.Name | Should -Contain 'facts'
                $definition.PSObject.Properties.Name | Should -Contain 'supply'
                $definition.PSObject.Properties.Name | Should -Contain 'artifact'
                $definition.PSObject.Properties.Name | Should -Contain 'install'
                $definition.PSObject.Properties.Name | Should -Contain 'environment'
                $definition.PSObject.Properties.Name | Should -Contain 'dependencies'
                $definition.PSObject.Properties.Name | Should -Contain 'policies'
                $definition.PSObject.Properties.Name | Should -Contain 'hooks'
                $definition.PSObject.Properties.Name | Should -Not -Contain 'handlerIds'

                @($definition.facts.PSObject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name).Count | Should -Be 1
                @($definition.supply.PSObject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name).Count | Should -Be 1
                $definition.environment.PSObject.Properties.Name | Should -Contain 'commandProjection'

                $context = Get-ManifestedRuntimeDescriptor -CommandName $definition.commandName
                $context.ExecutionModel | Should -Be 'DefinitionBlocks'
                $context.Definition.commandName | Should -Be $definition.commandName
            }

            $nodeDefinition = @($definitions | Where-Object { $_.commandName -eq 'Initialize-NodeRuntime' } | Select-Object -First 1)
            $nodeDefinition | Should -Not -BeNullOrEmpty
            $nodeDefinition.supply.PSObject.Properties.Name | Should -Contain 'nodeDist'
            $nodeDefinition.supply.PSObject.Properties.Name | Should -Not -Contain 'githubRelease'

            $ghcliDefinition = @($definitions | Where-Object { $_.commandName -eq 'Initialize-GHCliRuntime' } | Select-Object -First 1)
            $ghcliDefinition.supply.PSObject.Properties.Name | Should -Contain 'githubRelease'

            $ps7Definition = @($definitions | Where-Object { $_.commandName -eq 'Initialize-Ps7Runtime' } | Select-Object -First 1)
            $ps7Definition.supply.PSObject.Properties.Name | Should -Contain 'githubRelease'
        }
    }

    It 'keeps the migrated kernel free of handler catalog and projection indirection' {
        InModuleScope Eigenverft.Manifested.Sandbox {
            $moduleRoot = $ExecutionContext.SessionState.Module.ModuleBase
            $kernelPath = Join-Path $moduleRoot 'Private\Logic\Eigenverft.Manifested.Sandbox.Shared.RuntimeKernel.ps1'
            $commandEnvironmentPath = Join-Path $moduleRoot 'Private\Logic\Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment.ps1'

            $kernelSource = Get-Content -LiteralPath $kernelPath -Raw
            $commandEnvironmentSource = Get-Content -LiteralPath $commandEnvironmentPath -Raw

            $kernelSource | Should -Not -Match 'Get-ManifestedRuntimeHandlerCatalog'
            $kernelSource | Should -Not -Match 'Get-ManifestedRuntimeHandler'
            $kernelSource | Should -Not -Match 'Get-ManifestedDefinitionHandlerIdMap'
            $kernelSource | Should -Not -Match 'Resolve-ManifestedRuntimeDescriptorFromDefinition'
            $commandEnvironmentSource | Should -Not -Match 'CommandProjectionFunction'
            $kernelSource | Should -Match 'Get-ManifestedPortableRuntimePlanFromFacts'
            $kernelSource | Should -Match 'Get-ManifestedDependencyPlanFromDefinition'
            $kernelSource | Should -Match 'Get-ManifestedSuppliedArtifactFromDefinition'
            $kernelSource | Should -Match 'Test-ManifestedArtifactTrustFromDefinition'
            $kernelSource | Should -Match 'Invoke-ManifestedPortableZipInstallFromDefinition'
            $commandEnvironmentSource | Should -Match 'Get-ManifestedCommandProjectionFromDefinition'
        }
    }

    It 'returns the shared result contract for the generic command planning entrypoint' {
        $result = Initialize-SandboxCommand -Name 'Initialize-NodeRuntime' -WhatIf

        $result.PSObject.Properties.Name | Should -Contain 'CommandName'
        $result.PSObject.Properties.Name | Should -Contain 'RuntimeName'
        $result.PSObject.Properties.Name | Should -Contain 'FactsBefore'
        $result.PSObject.Properties.Name | Should -Contain 'Dependencies'
        $result.PSObject.Properties.Name | Should -Contain 'Plan'
        $result.PSObject.Properties.Name | Should -Contain 'ExecutedSteps'
        $result.PSObject.Properties.Name | Should -Contain 'FactsAfter'
        $result.PSObject.Properties.Name | Should -Contain 'EnvironmentResult'
        $result.PSObject.Properties.Name | Should -Contain 'RestartRequired'
        $result.PSObject.Properties.Name | Should -Contain 'Warnings'
        $result.PSObject.Properties.Name | Should -Contain 'Errors'
        $result.PSObject.Properties.Name | Should -Not -Contain 'InitialState'
        $result.PSObject.Properties.Name | Should -Not -Contain 'FinalState'
        $result.PSObject.Properties.Name | Should -Not -Contain 'ActionTaken'
        $result.PSObject.Properties.Name | Should -Not -Contain 'PlannedActions'
        $result.PSObject.Properties.Name | Should -Not -Contain 'PersistedStatePath'
        $result.CommandName | Should -Be 'Initialize-NodeRuntime'
        $result.RuntimeName | Should -Be 'NodeRuntime'
        @($result.ExecutedSteps).Count | Should -Be 0
    }

    It 'returns the shared result contract for Node runtime planning' {
        $result = Initialize-NodeRuntime -WhatIf

        $result.CommandName | Should -Be 'Initialize-NodeRuntime'
        $result.RuntimeName | Should -Be 'NodeRuntime'
        @($result.ExecutedSteps).Count | Should -Be 0
    }

    It 'returns the shared result contract for GitHub CLI runtime planning' {
        $result = Initialize-GHCliRuntime -WhatIf

        $result.CommandName | Should -Be 'Initialize-GHCliRuntime'
        $result.RuntimeName | Should -Be 'GHCliRuntime'
        @($result.ExecutedSteps).Count | Should -Be 0
        $result.PSObject.Properties.Name | Should -Not -Contain 'PersistedStatePath'
    }

    It 'returns the shared result contract for PowerShell runtime planning' {
        $result = Initialize-Ps7Runtime -WhatIf

        $result.CommandName | Should -Be 'Initialize-Ps7Runtime'
        $result.RuntimeName | Should -Be 'Ps7Runtime'
        @($result.ExecutedSteps).Count | Should -Be 0
        $result.PSObject.Properties.Name | Should -Not -Contain 'PersistedStatePath'
    }

    It 'stores command reports separately from planning state and exposes them only as observation' {
        InModuleScope Eigenverft.Manifested.Sandbox {
            $localRoot = [System.Environment]::GetEnvironmentVariable('EIGENVERFT_MANIFESTED_LOCALROOT', 'Process')
            $reportPath = Save-ManifestedCommandReport -CommandName 'Initialize-NodeRuntime' -RuntimeName 'NodeRuntime' -Result ([pscustomobject]@{
                    CommandName       = 'Initialize-NodeRuntime'
                    RuntimeName       = 'NodeRuntime'
                    FactsBefore       = [pscustomobject]@{ HasUsableRuntime = $false }
                    Dependencies      = @()
                    Plan              = @([pscustomobject]@{ Name = 'PlanOnly' })
                    ExecutedSteps     = @()
                    FactsAfter        = [pscustomobject]@{ HasUsableRuntime = $true }
                    EnvironmentResult = [pscustomobject]@{ Applicable = $true }
                    RestartRequired   = $false
                    Warnings          = @()
                    Errors            = @()
                }) -InvocationInput @{ RefreshRequested = $false } -LocalRoot $localRoot

            Test-Path -LiteralPath $reportPath | Should -BeTrue
            (Get-ManifestedCommandState -CommandName 'Initialize-NodeRuntime' -LocalRoot $localRoot) | Should -BeNullOrEmpty

            $summary = Get-ManifestedCommandReportSummary -CommandName 'Initialize-NodeRuntime' -LocalRoot $localRoot
            $summary.CommandName | Should -Be 'Initialize-NodeRuntime'
            $summary.RuntimeName | Should -Be 'NodeRuntime'
        }

        $state = Get-SandboxState -IncludeLastReportSummary -Raw
        $nodeState = @($state.Runtimes | Where-Object { $_.CommandName -eq 'Initialize-NodeRuntime' } | Select-Object -First 1)

        $nodeState | Should -Not -BeNullOrEmpty
        $nodeState.LastReportSummary | Should -Not -BeNullOrEmpty
        $nodeState.LastReportSummary.CommandName | Should -Be 'Initialize-NodeRuntime'
    }
}
