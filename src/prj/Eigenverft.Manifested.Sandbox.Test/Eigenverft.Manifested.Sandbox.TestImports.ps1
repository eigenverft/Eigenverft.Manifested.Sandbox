<#
    Eigenverft.Manifested.Sandbox test import loader
#>

# Mirrors the module psm1 load order for repo-local testing.
$moduleProjectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Eigenverft.Manifested.Sandbox'

# Root entrypoints
. "$moduleProjectRoot\Eigenverft.Manifested.Sandbox.ps1"

# Generic ExecutionEngine support
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.StandardMessage.ps1"
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.Archive.ps1"
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.CommandResolution.ps1"
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.FileSystem.ps1"
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.Registry.ps1"
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.SystemResources.ps1"
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.Elevation.ps1"
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.PathRegistration.ps1"
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.Npm.ps1"
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.InitializeProxyAccessProfile.ps1"

# Package support
. "$moduleProjectRoot\Support\ExecutionEngine\Eigenverft.Manifested.Sandbox.ExecutionEngine.InvokeWebRequestEx.ps1"
. "$moduleProjectRoot\Support\Upstream\Eigenverft.Manifested.Sandbox.Upstream.GitHubRelease.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.ExecutionMessage.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Bootstrap.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Config.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Selection.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Dependencies.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Source.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Ownership.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.State.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Validation.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Npm.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.Install.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.EntryPoints.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.PathRegistration.ps1"
. "$moduleProjectRoot\Support\Package\Eigenverft.Manifested.Sandbox.Package.CommandFlow.ps1"

# Package definitions
# Package definitions are JSON-only.

# Package commands
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.Qwen35_2B_Q8_0_Model.ps1"
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
. "$moduleProjectRoot\Commands\Eigenverft.Manifested.Sandbox.Cmd.VSCodeRuntime.ps1"

