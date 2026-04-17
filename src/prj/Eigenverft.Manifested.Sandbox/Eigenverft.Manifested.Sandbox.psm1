<#
    Eigenverft.Manifested.Sandbox root module
#>

# Root entrypoints
. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.ps1"

# StateModel support
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Base.Invoke-WebRequestEx.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Elevation.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.GitHubReleases.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Paths.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Cache.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Extraction.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Npm.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.Pip.ps1"
. "$PSScriptRoot\StateModel\Support\Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment.ps1"

# StateModel definitions
. "$PSScriptRoot\StateModel\Definitions\Eigenverft.Manifested.Sandbox.Shared.State.ps1"

# StateModel commands
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.PythonRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.VsCodeRuntimeAndCache.ps1"
. "$PSScriptRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache.ps1"

# ConfigurationModel support
# ConfigurationModel is intentionally empty in this structure-only pass.

# ConfigurationModel definitions
# ConfigurationModel is intentionally empty in this structure-only pass.

# ConfigurationModel commands
# ConfigurationModel is intentionally empty in this structure-only pass.


