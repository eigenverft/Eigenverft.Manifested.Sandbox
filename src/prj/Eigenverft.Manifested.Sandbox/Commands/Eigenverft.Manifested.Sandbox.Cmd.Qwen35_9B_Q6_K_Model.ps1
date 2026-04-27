<#
    Eigenverft.Manifested.Sandbox.Cmd.Qwen35_9B_Q6_K_Model
#>

function Invoke-Qwen35-9B-Q6-K-Model {
<#
.SYNOPSIS
Ensures the configured Qwen 3.5 9B Q6_K GGUF model is available through Package.

.DESCRIPTION
Loads the shipped Package JSON documents through the neutral Package
config loader, resolves the effective Qwen model resource release for the
current runtime context, evaluates existing-install ownership and policy,
saves the package file when needed, installs or reuses the package, validates
the installed resource, updates the ownership index, and returns the resolved
result object.

.EXAMPLE
Invoke-Qwen35-9B-Q6-K-Model
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -DefinitionId 'Qwen35_9B_Q6_K_Model' -CommandName 'Invoke-Qwen35-9B-Q6-K-Model')
}

