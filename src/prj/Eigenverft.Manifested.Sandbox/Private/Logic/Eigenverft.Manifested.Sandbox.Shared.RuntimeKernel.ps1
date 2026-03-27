<#
    Eigenverft.Manifested.Sandbox.Shared.RuntimeKernel
#>

if (-not $script:ManifestedLegacyRuntimeDescriptors) {
    $script:ManifestedLegacyRuntimeDescriptors = @{}
}

if (-not $script:ManifestedCommandDefinitions) {
    $script:ManifestedCommandDefinitions = @()
}

if (-not $script:ManifestedCommandDefinitionsByCommandName) {
    $script:ManifestedCommandDefinitionsByCommandName = @{}
}

if (-not $script:ManifestedCommandDefinitionsByRuntimeName) {
    $script:ManifestedCommandDefinitionsByRuntimeName = @{}
}

. "$PSScriptRoot\RuntimeKernel\Definitions\Manifested.CommandDefinitions.ps1"
. "$PSScriptRoot\RuntimeKernel\Facts\Manifested.RuntimeFacts.Model.ps1"
. "$PSScriptRoot\RuntimeKernel\Plan\Manifested.PlanModel.ps1"
. "$PSScriptRoot\RuntimeKernel\Definitions\Manifested.Versioning.ps1"
. "$PSScriptRoot\RuntimeKernel\Compat\Manifested.DescriptorFacade.ps1"
. "$PSScriptRoot\RuntimeKernel\Supply\Manifested.PythonSupply.ps1"
. "$PSScriptRoot\RuntimeKernel\Supply\Manifested.ArtifactSupply.ps1"
. "$PSScriptRoot\RuntimeKernel\Facts\Manifested.RuntimeFacts.Collectors.ps1"
. "$PSScriptRoot\RuntimeKernel\Facts\Manifested.RuntimeFacts.Portable.ps1"
. "$PSScriptRoot\RuntimeKernel\Facts\Manifested.RuntimeFacts.Python.ps1"
. "$PSScriptRoot\RuntimeKernel\Facts\Manifested.RuntimeFacts.Dispatch.ps1"
. "$PSScriptRoot\RuntimeKernel\Execute\Manifested.RepairAndArtifact.ps1"
. "$PSScriptRoot\RuntimeKernel\Execute\Manifested.InstallsAndHooks.ps1"
. "$PSScriptRoot\RuntimeKernel\Execute\Manifested.Repair.Runtime.ps1"
. "$PSScriptRoot\RuntimeKernel\Execute\Manifested.PythonRuntime.ps1"
. "$PSScriptRoot\RuntimeKernel\Execute\Manifested.Install.Shared.ps1"
. "$PSScriptRoot\RuntimeKernel\Execute\Manifested.PostInstall.Steps.ps1"
. "$PSScriptRoot\RuntimeKernel\Plan\Manifested.DependencyPlanning.ps1"
. "$PSScriptRoot\RuntimeKernel\Execute\Manifested.RuntimeExecution.ps1"

