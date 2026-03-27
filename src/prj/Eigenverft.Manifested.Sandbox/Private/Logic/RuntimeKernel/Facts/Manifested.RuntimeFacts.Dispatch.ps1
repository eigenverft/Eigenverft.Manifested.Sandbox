function Get-ManifestedRuntimeFactsFromContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [string]$LocalRoot = (Get-ManifestedLocalRoot),

        [hashtable]$FactsCache = @{}
    )

    $cacheKey = if ($Context.PSObject.Properties['RuntimeName']) { [string]$Context.RuntimeName } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($cacheKey) -and $FactsCache.ContainsKey($cacheKey)) {
        return $FactsCache[$cacheKey]
    }

    if ($Context.PSObject.Properties['ExecutionModel'] -and $Context.ExecutionModel -eq 'DefinitionBlocks' -and $Context.PSObject.Properties['Definition'] -and $Context.Definition) {
        $facts = $null
        if (Get-ManifestedDefinitionBlock -Definition $Context.Definition -SectionName 'facts' -BlockName 'portableRuntime') {
            $facts = Get-ManifestedPortableRuntimeFactsFromDefinition -Definition $Context.Definition -LocalRoot $LocalRoot
        }
        elseif (Get-ManifestedDefinitionBlock -Definition $Context.Definition -SectionName 'facts' -BlockName 'pythonEmbeddableRuntime') {
            $facts = Get-ManifestedPythonEmbeddableRuntimeFactsFromDefinition -Definition $Context.Definition -LocalRoot $LocalRoot
        }
        elseif (Get-ManifestedDefinitionBlock -Definition $Context.Definition -SectionName 'facts' -BlockName 'machinePrerequisite') {
            $facts = Get-ManifestedMachinePrerequisiteFactsFromDefinition -Definition $Context.Definition -LocalRoot $LocalRoot
        }
        elseif (Get-ManifestedDefinitionBlock -Definition $Context.Definition -SectionName 'facts' -BlockName 'npmCli') {
            $facts = Get-ManifestedNpmCliFactsFromDefinition -Definition $Context.Definition -LocalRoot $LocalRoot
        }
        else {
            throw "No fact collector is defined for '$($Context.CommandName)'."
        }

        if (-not [string]::IsNullOrWhiteSpace($cacheKey)) {
            $FactsCache[$cacheKey] = $facts
        }

        return $facts
    }

    $facts = (& $Context.FactsFunction -LocalRoot $LocalRoot)
    if (-not [string]::IsNullOrWhiteSpace($cacheKey)) {
        $FactsCache[$cacheKey] = $facts
    }

    return $facts
}
