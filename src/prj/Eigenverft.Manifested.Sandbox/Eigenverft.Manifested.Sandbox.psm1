<#
    Eigenverft.Manifested.Sandbox root module
#>

# Root entrypoints
. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.ps1"

# Generic ExecutionEngine support
. "$PSScriptRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.StandardMessage.ps1"
. "$PSScriptRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.Archive.ps1"
. "$PSScriptRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.CommandResolution.ps1"
. "$PSScriptRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.FileSystem.ps1"
. "$PSScriptRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.Registry.ps1"
. "$PSScriptRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.SystemResources.ps1"
. "$PSScriptRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.Elevation.ps1"
. "$PSScriptRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.PathRegistration.ps1"

# StateModel support
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Base.Invoke-WebRequestEx.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Elevation.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.GitHubReleases.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Paths.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Cache.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Extraction.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Npm.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment.ps1"

# StateModel definitions
. "$PSScriptRoot\StateModel\Definitions\Eigenverft.Manifested.Sandbox.Shared.State.ps1"

# StateModel commands
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache.ps1"

# PackageModel support
. "$PSScriptRoot\PackageModel\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.InvokeWebRequestEx.ps1"
. "$PSScriptRoot\PackageModel\Support\Upstream\Eigenverft.Manifested.Sandbox.PackageModel.Upstream.GitHubRelease.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.ExecutionMessage.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Bootstrap.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Config.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Selection.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Source.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Ownership.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Validation.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.Install.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.EntryPoints.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.PathRegistration.ps1"
. "$PSScriptRoot\PackageModel\Support\Package\Eigenverft.Manifested.Sandbox.PackageModel.CommandFlow.ps1"

# PackageModel definitions
# PackageModel definitions are JSON-only in this package-definition pass.

# PackageModel commands
. "$PSScriptRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.Qwen35_2B_Q6K.ps1"
. "$PSScriptRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.LlamaCppRuntime.ps1"
. "$PSScriptRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.VCRuntime.ps1"
. "$PSScriptRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.Ps7Runtime.ps1"
. "$PSScriptRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.PythonRuntime.ps1"
. "$PSScriptRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.NodeRuntime.ps1"
. "$PSScriptRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.GHCliRuntime.ps1"
. "$PSScriptRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.GitRuntime.ps1"
. "$PSScriptRoot\PackageModel\Commands\Eigenverft.Manifested.Sandbox.PackageModel.Cmd.VSCodeRuntime.ps1"
