<#
    Eigenverft.Manifested.Sandbox root module
#>

# Shared platform surface
. "$PSScriptRoot\Core\Eigenverft.Manifested.Sandbox.Core.ps1"

# Runtime packs
. "$PSScriptRoot\RuntimePacks\Node\Eigenverft.Manifested.Sandbox.RuntimePack.Node.ps1"
. "$PSScriptRoot\RuntimePacks\Python\Eigenverft.Manifested.Sandbox.RuntimePack.Python.ps1"
. "$PSScriptRoot\RuntimePacks\VCRuntime\Eigenverft.Manifested.Sandbox.RuntimePack.VCRuntime.ps1"
. "$PSScriptRoot\RuntimePacks\NpmCli\Eigenverft.Manifested.Sandbox.RuntimePack.NpmCli.ps1"
. "$PSScriptRoot\RuntimePacks\GitHubPortable\Eigenverft.Manifested.Sandbox.RuntimePack.GitHubPortable.ps1"

