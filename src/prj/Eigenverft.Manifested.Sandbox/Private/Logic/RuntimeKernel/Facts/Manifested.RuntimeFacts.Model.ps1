function New-ManifestedRuntimeFacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeName,

        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeKind,

        [Parameter(Mandatory = $true)]
        [string]$LocalRoot,

        [pscustomobject]$Layout,

        [bool]$PlatformSupported = $true,

        [string]$BlockedReason,

        [pscustomobject]$ManagedRuntime,

        [pscustomobject]$ExternalRuntime,

        [pscustomobject]$Artifact,

        [string[]]$PartialPaths = @(),

        [string[]]$InvalidPaths = @(),

        [string]$Version,

        [string]$RuntimeHome,

        [string]$RuntimeSource,

        [string]$ExecutablePath,

        [pscustomobject]$RuntimeValidation,

        [hashtable]$AdditionalProperties = @{}
    )

    $activeRuntime = if ($ManagedRuntime) { $ManagedRuntime } else { $ExternalRuntime }
    $resolvedRuntimeSource = if (-not [string]::IsNullOrWhiteSpace($RuntimeSource)) {
        $RuntimeSource
    }
    elseif ($ManagedRuntime) {
        'Managed'
    }
    elseif ($ExternalRuntime) {
        'External'
    }
    else {
        $null
    }

    $facts = [ordered]@{
        RuntimeName           = $RuntimeName
        CommandName           = $CommandName
        RuntimeKind           = $RuntimeKind
        LocalRoot             = $LocalRoot
        Layout                = $Layout
        PlatformSupported     = [bool]$PlatformSupported
        BlockedReason         = $BlockedReason
        ManagedRuntime        = $ManagedRuntime
        ExternalRuntime       = $ExternalRuntime
        ActiveRuntime         = $activeRuntime
        CurrentVersion        = if (-not [string]::IsNullOrWhiteSpace($Version)) { $Version } elseif ($activeRuntime -and $activeRuntime.PSObject.Properties['Version']) { $activeRuntime.Version } else { $null }
        RuntimeHome           = if (-not [string]::IsNullOrWhiteSpace($RuntimeHome)) { $RuntimeHome } elseif ($activeRuntime -and $activeRuntime.PSObject.Properties['RuntimeHome']) { $activeRuntime.RuntimeHome } else { $null }
        RuntimeSource         = $resolvedRuntimeSource
        ExecutablePath        = if (-not [string]::IsNullOrWhiteSpace($ExecutablePath)) { $ExecutablePath } elseif ($activeRuntime -and $activeRuntime.PSObject.Properties['ExecutablePath']) { $activeRuntime.ExecutablePath } else { $null }
        Runtime               = if ($RuntimeValidation) { $RuntimeValidation } elseif ($activeRuntime -and $activeRuntime.PSObject.Properties['Validation']) { $activeRuntime.Validation } else { $null }
        Artifact              = $Artifact
        ArtifactPath          = if ($Artifact -and $Artifact.PSObject.Properties['Path']) { $Artifact.Path } else { $null }
        PartialPaths          = [string[]]@($PartialPaths)
        InvalidPaths          = [string[]]@($InvalidPaths)
        HasRepairableResidue  = (@($PartialPaths).Count -gt 0) -or (@($InvalidPaths).Count -gt 0)
        HasManagedRuntime     = ($null -ne $ManagedRuntime)
        HasExternalRuntime    = ($null -ne $ExternalRuntime)
        HasUsableRuntime      = ($null -ne $activeRuntime)
        HasArtifact           = ($null -ne $Artifact)
        ArtifactIsTrusted     = if ($Artifact -and $Artifact.PSObject.Properties['Sha256']) { -not [string]::IsNullOrWhiteSpace($Artifact.Sha256) } else { $false }
        Diagnostics           = @()
    }

    foreach ($entry in $AdditionalProperties.GetEnumerator()) {
        $facts[$entry.Key] = $entry.Value
    }

    return [pscustomobject]$facts
}


