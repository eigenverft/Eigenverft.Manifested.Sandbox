<#
    Eigenverft.Manifested.Sandbox.Cmd.Qwen35_2B_Q6K
#>

function Invoke-Qwen35-2B-Q6K {
<#
.SYNOPSIS
Ensures the configured Qwen 3.5 2B Q6_K GGUF model is available through PackageModel.

.DESCRIPTION
Loads the shipped PackageModel JSON documents through the neutral PackageModel
config loader, resolves the effective Qwen model resource release for the
current runtime context, evaluates existing-install ownership and policy,
saves the package file when needed, installs or reuses the package, validates
the installed resource, updates the ownership index, and returns the resolved
result object.

.EXAMPLE
Invoke-Qwen35-2B-Q6K
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'Qwen35_2B_Q6K' -CommandName 'Invoke-Qwen35-2B-Q6K')
}

