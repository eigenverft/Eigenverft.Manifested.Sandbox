<#
    Eigenverft.Manifested.Sandbox test import loader
#>

# Mirrors the module psm1 load order for repo-local testing.
$moduleProjectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Eigenverft.Manifested.Sandbox'

# Root entrypoints
. "$moduleProjectRoot\Eigenverft.Manifested.Sandbox.ps1"

# Generic ExecutionEngine support
. "$moduleProjectRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.StandardMessage.ps1"
. "$moduleProjectRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.Archive.ps1"
. "$moduleProjectRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.CommandResolution.ps1"
. "$moduleProjectRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.FileSystem.ps1"
. "$moduleProjectRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.SystemResources.ps1"
. "$moduleProjectRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.Elevation.ps1"
. "$moduleProjectRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.PathRegistration.ps1"

# StateModel support
. "$moduleProjectRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Base.Invoke-WebRequestEx.ps1"
. "$moduleProjectRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Elevation.ps1"
. "$moduleProjectRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.GitHubReleases.ps1"
. "$moduleProjectRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Paths.ps1"
. "$moduleProjectRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Cache.ps1"
. "$moduleProjectRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Extraction.ps1"
. "$moduleProjectRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Npm.ps1"
. "$moduleProjectRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Pip.ps1"
. "$moduleProjectRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment.ps1"

# StateModel definitions
. "$moduleProjectRoot\StateModel\Definitions\Eigenverft.Manifested.Sandbox.Shared.State.ps1"

# StateModel commands
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.PythonRuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache.ps1"

# PackageModel support
. "$moduleProjectRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.InvokeWebRequestEx.ps1"
. "$moduleProjectRoot\PackageModel\Support\Upstream\Eigenverft.Manifested.Sandbox.PackageModel.Upstream.GitHubRelease.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionMessage.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Bootstrap.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Config.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Selection.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Source.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Ownership.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Validation.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Install.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.EntryPoints.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.PathRegistration.ps1"
. "$moduleProjectRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.CommandFlow.ps1"

# PackageModel definitions
# PackageModel definitions are JSON-only in this package-definition pass.

# PackageModel commands
. "$moduleProjectRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.Qwen35_2B_Q6K.ps1"
. "$moduleProjectRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.LlamaCppRuntime.ps1"
. "$moduleProjectRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.VCRuntime.ps1"
. "$moduleProjectRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.Ps7Runtime.ps1"
. "$moduleProjectRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.GHCliRuntime.ps1"
. "$moduleProjectRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.GitRuntime.ps1"
. "$moduleProjectRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.VSCodeRuntime.ps1"
