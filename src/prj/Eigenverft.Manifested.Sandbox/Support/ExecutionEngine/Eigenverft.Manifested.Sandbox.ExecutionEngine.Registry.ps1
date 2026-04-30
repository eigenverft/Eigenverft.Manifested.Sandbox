<#
    Eigenverft.Manifested.Sandbox.ExecutionEngine.Registry
#>

function Test-RegistryPathExists {
<#
.SYNOPSIS
Returns whether a registry path exists.

.DESCRIPTION
Uses the PowerShell registry provider to test for the existence of a registry
path. Failures are treated as non-existent so callers can decide how to handle
missing or unreadable paths.

.EXAMPLE
Test-RegistryPathExists -Path 'HKLM:\SOFTWARE\Vendor\Product'
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        return (Test-Path -LiteralPath $Path)
    }
    catch {
        return $false
    }
}

function Get-RegistryValueData {
<#
.SYNOPSIS
Reads a value from a registry path.

.DESCRIPTION
Returns the read result in a normalized object so callers can distinguish
between missing paths, read failures, and successful value reads without
embedding registry-provider mechanics in higher-level workflows.

.EXAMPLE
Get-RegistryValueData -Path 'HKLM:\SOFTWARE\Vendor\Product' -ValueName 'Version'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [AllowNull()]
        [string]$ValueName
    )

    if (-not (Test-RegistryPathExists -Path $Path)) {
        return [pscustomobject]@{
            Path          = $Path
            ValueName     = $ValueName
            Value         = $null
            Exists        = $false
            ReadSucceeded = $false
            Status        = 'Missing'
        }
    }

    if ([string]::IsNullOrWhiteSpace($ValueName)) {
        return [pscustomobject]@{
            Path          = $Path
            ValueName     = $null
            Value         = $null
            Exists        = $true
            ReadSucceeded = $true
            Status        = 'Ready'
        }
    }

    try {
        $properties = Get-ItemProperty -LiteralPath $Path -Name $ValueName -ErrorAction Stop
        return [pscustomobject]@{
            Path          = $Path
            ValueName     = $ValueName
            Value         = $properties.$ValueName
            Exists        = $true
            ReadSucceeded = $true
            Status        = 'Ready'
        }
    }
    catch {
        return [pscustomobject]@{
            Path          = $Path
            ValueName     = $ValueName
            Value         = $null
            Exists        = $true
            ReadSucceeded = $false
            Status        = 'Failed'
        }
    }
}

function Resolve-RegistryValueFromPaths {
<#
.SYNOPSIS
Finds the first usable registry path from a candidate list.

.DESCRIPTION
Evaluates registry candidate paths in order and returns the first successful
match. If no candidate succeeds, the last failed candidate is preserved so
callers can surface a meaningful path in diagnostics.

.EXAMPLE
Resolve-RegistryValueFromPaths -Paths @('HKLM:\A', 'HKLM:\B') -ValueName 'Version'
#>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Paths,

        [AllowNull()]
        [string]$ValueName
    )

    $candidatePaths = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $result = [pscustomobject]@{
        Path         = if ($candidatePaths.Count -gt 0) { $candidatePaths[0] } else { $null }
        Paths        = @($candidatePaths)
        ValueName    = $ValueName
        ActualValue  = $null
        Status       = 'Missing'
    }

    foreach ($candidatePath in $candidatePaths) {
        $candidateResult = Get-RegistryValueData -Path $candidatePath -ValueName $ValueName
        if ($candidateResult.Status -eq 'Missing') {
            continue
        }

        $result.Path = $candidateResult.Path
        $result.ActualValue = $candidateResult.Value
        $result.Status = $candidateResult.Status

        if ($candidateResult.Status -eq 'Ready') {
            break
        }
    }

    return $result
}

function Get-WindowsUninstallRegistryEntry {
<#
.SYNOPSIS
Reads one Windows uninstall registry entry.

.DESCRIPTION
Returns a normalized uninstall-entry object from a concrete registry path. This
helper intentionally reads a direct key only; scanning uninstall roots belongs
in a separate helper when a package needs that behavior.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $result = [ordered]@{
        Path                 = $Path
        Exists               = $false
        ReadSucceeded        = $false
        Status               = 'Missing'
        DisplayName          = $null
        DisplayVersion       = $null
        Publisher            = $null
        InstallLocation      = $null
        DisplayIcon          = $null
        UninstallString      = $null
        QuietUninstallString = $null
    }

    if (-not (Test-RegistryPathExists -Path $Path)) {
        return [pscustomobject]$result
    }

    $result.Exists = $true

    try {
        $properties = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
        $result.ReadSucceeded = $true
        $result.Status = 'Ready'
        foreach ($propertyName in @('DisplayName', 'DisplayVersion', 'Publisher', 'InstallLocation', 'DisplayIcon', 'UninstallString', 'QuietUninstallString')) {
            if ($properties.PSObject.Properties[$propertyName]) {
                $result[$propertyName] = $properties.$propertyName
            }
        }
    }
    catch {
        $result.Status = 'Failed'
    }

    return [pscustomobject]$result
}

function Get-WindowsRegistryExecutablePathFromText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $candidateText = [Environment]::ExpandEnvironmentVariables(([string]$Text).Trim())
    if ($candidateText.StartsWith('"')) {
        $quotedMatch = [regex]::Match($candidateText, '^"([^"]+)"')
        if ($quotedMatch.Success) {
            return $quotedMatch.Groups[1].Value
        }
    }

    $extensionMatch = [regex]::Match($candidateText, '^(.*?\.(?:exe|msi|cmd|bat))(?=\s|,|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($extensionMatch.Success) {
        return ($extensionMatch.Groups[1].Value -replace ',\s*\d+$', '').Trim()
    }

    $firstToken = ($candidateText -split '\s+', 2)[0]
    return ($firstToken -replace ',\s*\d+$', '').Trim()
}

function Resolve-WindowsUninstallRegistryEntryPath {
<#
.SYNOPSIS
Resolves a filesystem path from a Windows uninstall registry entry.

.DESCRIPTION
Extracts common install-related paths from a normalized uninstall entry. The
helper accepts explicit source names so package logic can stay declarative and
future installer packages can add path-source strategies without changing
existing discovery flow.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Entry,

        [Parameter(Mandatory = $true)]
        [ValidateSet('installLocation', 'displayIcon', 'displayIconDirectory', 'uninstallString', 'uninstallStringDirectory')]
        [string]$Source
    )

    $rawPath = $null
    switch -Exact ($Source) {
        'installLocation' {
            $rawPath = if ($Entry.PSObject.Properties['InstallLocation']) { [string]$Entry.InstallLocation } else { $null }
        }
        'displayIcon' {
            $rawPath = Get-WindowsRegistryExecutablePathFromText -Text $(if ($Entry.PSObject.Properties['DisplayIcon']) { [string]$Entry.DisplayIcon } else { $null })
        }
        'displayIconDirectory' {
            $iconPath = Get-WindowsRegistryExecutablePathFromText -Text $(if ($Entry.PSObject.Properties['DisplayIcon']) { [string]$Entry.DisplayIcon } else { $null })
            $rawPath = if ([string]::IsNullOrWhiteSpace($iconPath)) { $null } else { Split-Path -Parent $iconPath }
        }
        'uninstallString' {
            $rawPath = Get-WindowsRegistryExecutablePathFromText -Text $(if ($Entry.PSObject.Properties['UninstallString']) { [string]$Entry.UninstallString } else { $null })
        }
        'uninstallStringDirectory' {
            $uninstallPath = Get-WindowsRegistryExecutablePathFromText -Text $(if ($Entry.PSObject.Properties['UninstallString']) { [string]$Entry.UninstallString } else { $null })
            $rawPath = if ([string]::IsNullOrWhiteSpace($uninstallPath)) { $null } else { Split-Path -Parent $uninstallPath }
        }
    }

    $result = [ordered]@{
        EntryPath    = if ($Entry.PSObject.Properties['Path']) { $Entry.Path } else { $null }
        Source       = $Source
        RawPath      = $rawPath
        ResolvedPath = $null
        Status       = 'Missing'
    }

    if ([string]::IsNullOrWhiteSpace($rawPath)) {
        return [pscustomobject]$result
    }

    try {
        $expandedPath = [Environment]::ExpandEnvironmentVariables([string]$rawPath)
        $result.ResolvedPath = [System.IO.Path]::GetFullPath($expandedPath)
        $result.Status = 'Ready'
    }
    catch {
        $result.ResolvedPath = $rawPath
        $result.Status = 'Failed'
    }

    return [pscustomobject]$result
}

