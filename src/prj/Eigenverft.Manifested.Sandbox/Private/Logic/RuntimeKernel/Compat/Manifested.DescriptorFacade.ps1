function Register-ManifestedRuntimeDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor
    )

    if (-not $Descriptor.PSObject.Properties['RuntimeName'] -or [string]::IsNullOrWhiteSpace($Descriptor.RuntimeName)) {
        throw 'Runtime descriptors must define RuntimeName.'
    }

    if (-not $Descriptor.PSObject.Properties['CommandName'] -or [string]::IsNullOrWhiteSpace($Descriptor.CommandName)) {
        throw "Runtime descriptor '$($Descriptor.RuntimeName)' must define CommandName."
    }

    $script:ManifestedLegacyRuntimeDescriptors[$Descriptor.RuntimeName] = $Descriptor
    return $Descriptor
}


function Get-ManifestedRuntimeDescriptors {
    [CmdletBinding()]
    param()

    $descriptors = New-Object System.Collections.Generic.List[object]
    foreach ($definition in @(Get-ManifestedCommandDefinitions)) {
        $descriptors.Add((New-ManifestedCommandExecutionContext -Definition $definition)) | Out-Null
    }

    foreach ($legacyDescriptor in @($script:ManifestedLegacyRuntimeDescriptors.Values)) {
        $descriptors.Add($legacyDescriptor) | Out-Null
    }

    return @($descriptors | Sort-Object RuntimeName)
}

function Get-ManifestedRuntimeDescriptor {
    [CmdletBinding(DefaultParameterSetName = 'ByRuntimeName')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByRuntimeName')]
        [string]$RuntimeName,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByCommandName')]
        [string]$CommandName
    )

    switch ($PSCmdlet.ParameterSetName) {
        'ByRuntimeName' {
            $definition = Get-ManifestedCommandDefinition -RuntimeName $RuntimeName
            if ($definition) {
                return (New-ManifestedCommandExecutionContext -Definition $definition)
            }

            if ($script:ManifestedLegacyRuntimeDescriptors.ContainsKey($RuntimeName)) {
                return $script:ManifestedLegacyRuntimeDescriptors[$RuntimeName]
            }
        }

        'ByCommandName' {
            $definition = Get-ManifestedCommandDefinition -CommandName $CommandName
            if ($definition) {
                return (New-ManifestedCommandExecutionContext -Definition $definition)
            }

            foreach ($descriptor in @($script:ManifestedLegacyRuntimeDescriptors.Values)) {
                if ($descriptor.CommandName -eq $CommandName) {
                    return $descriptor
                }
            }
        }
    }

    return $null
}


