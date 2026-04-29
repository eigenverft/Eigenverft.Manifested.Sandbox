<#
    Eigenverft.Manifested.Sandbox root module
#>

# Root entrypoints
. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.ps1"

# Generic ExecutionEngine support
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.StandardMessage.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.Archive.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.CommandResolution.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.FileSystem.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.PathTemplate.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.Registry.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.SystemResources.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.Elevation.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.PathRegistration.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.Npm.ps1"
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.InitializeProxyAccessProfile.ps1"

# Package support
. "$PSScriptRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.InvokeWebRequestEx.ps1"
. "$PSScriptRoot\Support\Upstream\Eigenverft.Manifested.Sandbox.Upstream.GitHubRelease.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.ExecutionMessage.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Bootstrap.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Config.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Selection.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Dependencies.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Source.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Ownership.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.State.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Validation.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Npm.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Install.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.EntryPoints.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.PathRegistration.ps1"
. "$PSScriptRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.CommandFlow.ps1"

# Package definitions
# Package definitions are JSON-only.

# Package commands
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.Qwen35_2B_Q8_0_Model.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.Qwen35_9B_Q6_K_Model.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.LlamaCppRuntime.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.VisualCppRedistributable.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.PowerShell7.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.PythonRuntime.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.NodeRuntime.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.CodexCli.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.GeminiCli.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.OpenCodeCli.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.QwenCli.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.GitHubCli.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.GitRuntime.ps1"
. "$PSScriptRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.VSCodeRuntime.ps1"
