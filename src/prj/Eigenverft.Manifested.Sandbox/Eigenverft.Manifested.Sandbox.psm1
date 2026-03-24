<#
    Eigenverft.Manifested.Sandbox root module
#>

# Public entrypoints
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.ps1"

# Private infrastructure
. "$PSScriptRoot\Private\Infra\Eigenverft.Manifested.Sandbox.Base.Invoke-WebRequestEx.ps1"
. "$PSScriptRoot\Private\Infra\Eigenverft.Manifested.Sandbox.Shared.Elevation.ps1"
. "$PSScriptRoot\Private\Infra\Eigenverft.Manifested.Sandbox.Shared.GitHubReleases.ps1"

# Private common helpers
. "$PSScriptRoot\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Paths.ps1"
. "$PSScriptRoot\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Cache.ps1"
. "$PSScriptRoot\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Extraction.ps1"
. "$PSScriptRoot\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Npm.ps1"

# Private logic
. "$PSScriptRoot\Private\Logic\Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment.ps1"

# Public state surface
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Shared.State.ps1"

# Public runtime commands
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache.ps1"
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache.ps1"
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache.ps1"
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache.ps1"
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache.ps1"
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache.ps1"
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntimeAndCache.ps1"
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache.ps1"
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.VsCodeRuntimeAndCache.ps1"
. "$PSScriptRoot\Public\Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache.ps1"

