<#
    Eigenverft.Manifested.Sandbox test import loader
#>

# Mirrors the module psm1 load order for repo-local testing.
$moduleProjectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Eigenverft.Manifested.Sandbox'

# Root entrypoints
. "$moduleProjectRoot\Eigenverft.Manifested.Sandbox.ps1"

# Generic ExecutionCore support
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.StandardMessage.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.Archive.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.CommandResolution.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.FileSystem.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.PathTemplate.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.Registry.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.SystemResources.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.Elevation.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.PathRegistration.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.Npm.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.InitializeProxyAccessProfile.ps1"

# Package support
. "$moduleProjectRoot\Support\ExecutionCore\Eigenverft.Manifested.Sandbox.ExecutionCore.InvokeWebRequestEx.ps1"
. "$moduleProjectRoot\Support\ExecutionCore\Upstream\Eigenverft.Manifested.Sandbox.ExecutionCore.Upstream.GitHubRelease.ps1"
. "$moduleProjectRoot\Support\Package\Execution\Eigenverft.Manifested.Sandbox.Package.ExecutionMessage.ps1"
. "$moduleProjectRoot\Support\Package\Execution\Eigenverft.Manifested.Sandbox.Package.Bootstrap.ps1"
. "$moduleProjectRoot\Support\Package\Schema\Eigenverft.Manifested.Sandbox.Package.DefinitionReference.ps1"
. "$moduleProjectRoot\Support\Package\Schema\Eigenverft.Manifested.Sandbox.Package.Config.ps1"
. "$moduleProjectRoot\Support\Package\Schema\Eigenverft.Manifested.Sandbox.Package.DefinitionSchema.ReleaseMerge.ps1"
. "$moduleProjectRoot\Support\Package\Schema\Eigenverft.Manifested.Sandbox.Package.DefinitionSchema.Wire1_1.ps1"
. "$moduleProjectRoot\Support\Package\Schema\Eigenverft.Manifested.Sandbox.Package.DefinitionSchema.ps1"
. "$moduleProjectRoot\Support\Package\Execution\Eigenverft.Manifested.Sandbox.Package.LocalEnvironment.ps1"
. "$moduleProjectRoot\Support\Package\Schema\Eigenverft.Manifested.Sandbox.Package.Selection.ps1"
. "$moduleProjectRoot\Support\Package\Lifecycle\Eigenverft.Manifested.Sandbox.Package.Dependencies.ps1"
. "$moduleProjectRoot\Support\Package\Schema\Eigenverft.Manifested.Sandbox.Package.Source.ps1"
. "$moduleProjectRoot\Support\Package\State\Eigenverft.Manifested.Sandbox.Package.Ownership.ps1"
. "$moduleProjectRoot\Support\Package\State\Eigenverft.Manifested.Sandbox.Package.OperationHistory.ps1"
. "$moduleProjectRoot\Support\Package\State\Eigenverft.Manifested.Sandbox.Package.State.ps1"
. "$moduleProjectRoot\Support\Package\Lifecycle\Eigenverft.Manifested.Sandbox.Package.Validation.ps1"
. "$moduleProjectRoot\Support\Package\Execution\Eigenverft.Manifested.Sandbox.Package.Npm.ps1"
# Package install fragments (order-sensitive); orchestrator last — keep in sync with psm1
. "$moduleProjectRoot\Support\Package\Lifecycle\Eigenverft.Manifested.Sandbox.Package.Install.Existing.ps1"
. "$moduleProjectRoot\Support\Package\Lifecycle\Eigenverft.Manifested.Sandbox.Package.Install.Preparation.ps1"
. "$moduleProjectRoot\Support\Package\Lifecycle\Eigenverft.Manifested.Sandbox.Package.Install.Artifact.ps1"
. "$moduleProjectRoot\Support\Package\Lifecycle\Eigenverft.Manifested.Sandbox.Package.Install.InstallerEngine.ps1"
. "$moduleProjectRoot\Support\Package\Lifecycle\Eigenverft.Manifested.Sandbox.Package.Install.ps1"
. "$moduleProjectRoot\Support\Package\Lifecycle\Eigenverft.Manifested.Sandbox.Package.EntryPoints.ps1"
. "$moduleProjectRoot\Support\Package\Execution\Eigenverft.Manifested.Sandbox.Package.Shims.ps1"
. "$moduleProjectRoot\Support\Package\Execution\Eigenverft.Manifested.Sandbox.Package.PathRegistration.ps1"
. "$moduleProjectRoot\Support\Package\Lifecycle\Eigenverft.Manifested.Sandbox.Package.CommandFlow.ps1"

# Package definitions
# Package definitions are JSON-only.

# Package commands
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.Qwen35_2B_Q8_0_Model.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.Qwen35_9B_Q6_K_Model.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.LlamaCppRuntime.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.VisualCppRedistributable.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.PowerShell7.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.PythonRuntime.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.NodeRuntime.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.CodexCli.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.GeminiCli.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.OpenCodeCli.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.QwenCli.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.GitHubCli.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.GitRuntime.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.NotepadPlusPlus.ps1"
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.VSCodeRuntime.ps1"

