<#
    Eigenverft.Manifested.Sandbox test import loader
#>

# Mirrors the module psm1 load order for repo-local testing.
$moduleProjectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Eigenverft.Manifested.Sandbox'

# Root entrypoints
. "$moduleProjectRoot\Eigenverft.Manifested.Sandbox.ps1"

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
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.VsCodeRuntimeAndCache.ps1"
. "$moduleProjectRoot\StateModel\Commands\Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache.ps1"

# ConfigurationModel support, definitions, and commands are intentionally empty in this structure-only pass.

