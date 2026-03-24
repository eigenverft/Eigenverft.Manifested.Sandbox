<#
    Eigenverft.Manifested.Sandbox test import loader
#>

# Mirrors the module psm1 load order for repo-local testing.
$moduleProjectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Eigenverft.Manifested.Sandbox'

# Public entrypoints
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.ps1"

# Private infrastructure
. "$moduleProjectRoot\Private\Infra\Eigenverft.Manifested.Sandbox.Base.Invoke-WebRequestEx.ps1"
. "$moduleProjectRoot\Private\Infra\Eigenverft.Manifested.Sandbox.Shared.Elevation.ps1"
. "$moduleProjectRoot\Private\Infra\Eigenverft.Manifested.Sandbox.Shared.GitHubReleases.ps1"

# Private common helpers
. "$moduleProjectRoot\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Paths.ps1"
. "$moduleProjectRoot\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Cache.ps1"
. "$moduleProjectRoot\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Extraction.ps1"
. "$moduleProjectRoot\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Npm.ps1"

# Private logic
. "$moduleProjectRoot\Private\Logic\Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment.ps1"

# Public state surface
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Shared.State.ps1"

# Public runtime commands
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache.ps1"
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache.ps1"
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache.ps1"
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache.ps1"
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache.ps1"
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache.ps1"
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntimeAndCache.ps1"
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache.ps1"
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.VsCodeRuntimeAndCache.ps1"
. "$moduleProjectRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache.ps1"

