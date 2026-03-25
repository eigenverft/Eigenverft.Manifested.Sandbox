<#
    Eigenverft.Manifested.Sandbox.Core
#>

# Public entrypoints
. "$PSScriptRoot\..\Eigenverft.Manifested.Sandbox.ps1"

# Private infrastructure
. "$PSScriptRoot\..\Private\Infra\Eigenverft.Manifested.Sandbox.Base.Invoke-WebRequestEx.ps1"
. "$PSScriptRoot\..\Private\Infra\Eigenverft.Manifested.Sandbox.Shared.Elevation.ps1"
. "$PSScriptRoot\..\Private\Infra\Eigenverft.Manifested.Sandbox.Shared.GitHubReleases.ps1"

# Private common helpers
. "$PSScriptRoot\..\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Paths.ps1"
. "$PSScriptRoot\..\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Cache.ps1"
. "$PSScriptRoot\..\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Extraction.ps1"
. "$PSScriptRoot\..\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Npm.ps1"
. "$PSScriptRoot\..\Private\Common\Eigenverft.Manifested.Sandbox.Shared.Pip.ps1"

# Private logic
. "$PSScriptRoot\..\Private\Logic\Eigenverft.Manifested.Sandbox.RuntimeRegistry.ps1"
. "$PSScriptRoot\..\Private\Logic\Eigenverft.Manifested.Sandbox.RuntimePack.Node.ps1"
. "$PSScriptRoot\..\Private\Logic\Eigenverft.Manifested.Sandbox.RuntimePack.Python.ps1"
. "$PSScriptRoot\..\Private\Logic\Eigenverft.Manifested.Sandbox.RuntimePack.MachinePrerequisite.ps1"
. "$PSScriptRoot\..\Private\Logic\Eigenverft.Manifested.Sandbox.RuntimePack.NpmCli.ps1"
. "$PSScriptRoot\..\Private\Logic\Eigenverft.Manifested.Sandbox.RuntimePack.GitHubPortable.ps1"
. "$PSScriptRoot\..\Private\Logic\Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment.ps1"

# Public state surface
. "$PSScriptRoot\..\Public\Eigenverft.Manifested.Sandbox.Shared.State.ps1"
