<#
    Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment
#>

function Get-ManifestedPathEntryKey {
<#
.SYNOPSIS
Normalizes a PATH entry into a stable comparison key.

.DESCRIPTION
Trims surrounding whitespace and quotes, resolves the entry to a full path when
possible, removes a trailing backslash for non-root paths, and lowercases the
result so PATH comparisons stay case-insensitive on Windows.

.PARAMETER Path
The PATH entry to normalize.

.EXAMPLE
Get-ManifestedPathEntryKey -Path ' "C:\Tools\Node\" '

.EXAMPLE
Get-ManifestedPathEntryKey -Path $env:ProgramFiles

.NOTES
Returns $null when the input is empty or only whitespace.
#>
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $trimmedPath = $Path.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($trimmedPath)) {
        return $null
    }

    $normalizedPath = $trimmedPath
    try {
        $normalizedPath = [System.IO.Path]::GetFullPath($trimmedPath)
    }
    catch {
        $normalizedPath = $trimmedPath
    }

    if ($normalizedPath.Length -gt 3) {
        $normalizedPath = $normalizedPath.TrimEnd('\')
    }

    return $normalizedPath.ToLowerInvariant()
}

function Test-ManifestedPathEntryMatch {
    [CmdletBinding()]
    param(
        [string]$LeftPath,

        [string]$RightPath
    )

    $leftKey = Get-ManifestedPathEntryKey -Path $LeftPath
    $rightKey = Get-ManifestedPathEntryKey -Path $RightPath
    if ([string]::IsNullOrWhiteSpace($leftKey) -or [string]::IsNullOrWhiteSpace($rightKey)) {
        return $false
    }

    return $leftKey -eq $rightKey
}

function Get-ManifestedPathEntries {
    [CmdletBinding()]
    param(
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return @()
    }

    return @(
        $PathValue -split ';' |
            ForEach-Object { $_.Trim().Trim('"') } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-ManifestedResolvedApplicationPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $command = @(Get-Command -Name $CommandName -CommandType Application -All -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $command) {
        return $null
    }

    $commandPath = $null
    if ($command[0].PSObject.Properties['Path'] -and $command[0].Path) {
        $commandPath = $command[0].Path
    }
    elseif ($command[0].PSObject.Properties['Source'] -and $command[0].Source) {
        $commandPath = $command[0].Source
    }

    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return $null
    }

    return (Get-ManifestedFullPath -Path $commandPath)
}

function Set-ManifestedPathEntries {
    [CmdletBinding()]
    param(
        [string]$CurrentPath,

        [string[]]$DesiredLeadingEntries = @()
    )

    $entries = New-Object System.Collections.Generic.List[string]
    $seenEntries = @{}

    foreach ($entry in @($DesiredLeadingEntries)) {
        $key = Get-ManifestedPathEntryKey -Path $entry
        if ([string]::IsNullOrWhiteSpace($key) -or $seenEntries.ContainsKey($key)) {
            continue
        }

        $entries.Add((Get-ManifestedFullPath -Path $entry)) | Out-Null
        $seenEntries[$key] = $true
    }

    foreach ($entry in @(Get-ManifestedPathEntries -PathValue $CurrentPath)) {
        $key = Get-ManifestedPathEntryKey -Path $entry
        if ([string]::IsNullOrWhiteSpace($key) -or $seenEntries.ContainsKey($key)) {
            continue
        }

        $entries.Add($entry) | Out-Null
        $seenEntries[$key] = $true
    }

    [pscustomobject]@{
        Value   = ($entries -join ';')
        Entries = @($entries)
    }
}

function Publish-ManifestedEnvironmentChange {
    [CmdletBinding()]
    param()

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return
    }

    if (-not ('EigenverftManifestedNativeMethods' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class EigenverftManifestedNativeMethods
{
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        string lParam,
        uint fuFlags,
        uint uTimeout,
        out UIntPtr lpdwResult);
}
"@ -ErrorAction SilentlyContinue | Out-Null
    }

    $broadcastHandle = [IntPtr]0xffff
    $messageId = 0x001A
    $abortIfHung = 0x0002
    $sendResult = [UIntPtr]::Zero

    try {
        [void][EigenverftManifestedNativeMethods]::SendMessageTimeout(
            $broadcastHandle,
            $messageId,
            [UIntPtr]::Zero,
            'Environment',
            $abortIfHung,
            5000,
            [ref]$sendResult
        )
    }
    catch {
        Write-Verbose ('Could not broadcast environment change notification. ' + $_.Exception.Message)
    }
}

function Get-ManifestedCommandEnvironmentSpec {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'DescriptorFacts', Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(ParameterSetName = 'DescriptorFacts', Mandatory = $true)]
        [pscustomobject]$Facts,

        [Parameter(ParameterSetName = 'LegacyCommand', Mandatory = $true)]
        [string]$CommandName,

        [Parameter(ParameterSetName = 'LegacyCommand')]
        [pscustomobject]$RuntimeState
    )

    if ($PSCmdlet.ParameterSetName -eq 'LegacyCommand') {
        $Descriptor = Get-ManifestedCommandContext -CommandName $CommandName
        if (-not $Descriptor) {
            return [pscustomobject]@{
                Applicable                 = $false
                CommandName                = $CommandName
                CommandNames               = @()
                DesiredExecutablePath      = $null
                DesiredCommandDirectory    = $null
                ExpectedCommandPaths       = [ordered]@{}
            }
        }

        $Facts = $RuntimeState
    }

    $definitionProjection = $null
    if ($Descriptor.PSObject.Properties['Definition'] -and $Descriptor.Definition) {
        $definitionProjection = Get-ManifestedDefinitionBlock -Definition $Descriptor.Definition -SectionName 'environment' -BlockName 'commandProjection'
    }

    if (-not $definitionProjection) {
        return [pscustomobject]@{
            Applicable                 = $false
            CommandName                = $Descriptor.CommandName
            RuntimeName                = $Descriptor.RuntimeName
            CommandNames               = @()
            DesiredExecutablePath      = $null
            DesiredCommandDirectory    = $null
            ExpectedCommandPaths       = [ordered]@{}
        }
    }

    $projection = Get-ManifestedCommandProjectionFromDefinition -Definition $Descriptor.Definition -Facts $Facts
    if (-not $projection) {
        return [pscustomobject]@{
            Applicable                 = $false
            CommandName                = $Descriptor.CommandName
            RuntimeName                = $Descriptor.RuntimeName
            CommandNames               = @()
            DesiredExecutablePath      = $null
            DesiredCommandDirectory    = $null
            ExpectedCommandPaths       = [ordered]@{}
        }
    }

    $expectedCommandPaths = if ($projection.PSObject.Properties['ExpectedCommandPaths'] -and $projection.ExpectedCommandPaths) { $projection.ExpectedCommandPaths } else { [ordered]@{} }
    $desiredDirectory = if ($projection.PSObject.Properties['DesiredCommandDirectory']) { $projection.DesiredCommandDirectory } else { $null }
    $desiredExecutablePath = if ($projection.PSObject.Properties['DesiredExecutablePath']) { $projection.DesiredExecutablePath } else { $null }

    return [pscustomobject]@{
        Applicable                 = [bool](($projection.PSObject.Properties['Applicable'] -and $projection.Applicable) -and -not [string]::IsNullOrWhiteSpace($desiredDirectory) -and ($expectedCommandPaths.Count -gt 0))
        CommandName                = $Descriptor.CommandName
        RuntimeName                = $Descriptor.RuntimeName
        CommandNames               = @($expectedCommandPaths.Keys)
        DesiredExecutablePath      = if (-not [string]::IsNullOrWhiteSpace($desiredExecutablePath)) { Get-ManifestedFullPath -Path $desiredExecutablePath } else { $null }
        DesiredCommandDirectory    = if (-not [string]::IsNullOrWhiteSpace($desiredDirectory)) { Get-ManifestedFullPath -Path $desiredDirectory } else { $null }
        ExpectedCommandPaths       = $expectedCommandPaths
    }
}

function Get-ManifestedCommandLineEnvironmentState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Specification
    )

    if (-not $Specification.Applicable) {
        return [pscustomobject]@{
            Applicable                 = $false
            IsAligned                  = $false
            NeedsSync                  = $false
            ScopeApplied               = @()
            CommandNames               = if ($Specification.PSObject.Properties['CommandNames']) { @($Specification.CommandNames) } else { @() }
            DesiredExecutablePath      = if ($Specification.PSObject.Properties['DesiredExecutablePath']) { $Specification.DesiredExecutablePath } else { $null }
            DesiredCommandDirectory    = if ($Specification.PSObject.Properties['DesiredCommandDirectory']) { $Specification.DesiredCommandDirectory } else { $null }
            ResolvedCommandPaths       = [ordered]@{}
            ProcessPathUpdated         = $false
            UserPathUpdated            = $false
            ProcessPathContainsDesired = $false
            UserPathContainsDesired    = $false
            ProcessPathPrefersDesired  = $false
            UserPathPrefersDesired     = $false
            ValidationSucceeded        = $true
        }
    }

    $processPath = [System.Environment]::GetEnvironmentVariable('Path', 'Process')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $desiredDirectory = $Specification.DesiredCommandDirectory
    $processEntries = @(Get-ManifestedPathEntries -PathValue $processPath)
    $userEntries = @(Get-ManifestedPathEntries -PathValue $userPath)

    $processContainsDesired = $false
    foreach ($entry in $processEntries) {
        if (Test-ManifestedPathEntryMatch -LeftPath $entry -RightPath $desiredDirectory) {
            $processContainsDesired = $true
            break
        }
    }
    $processPrefersDesired = ($processEntries.Count -gt 0) -and (Test-ManifestedPathEntryMatch -LeftPath $processEntries[0] -RightPath $desiredDirectory)

    $userContainsDesired = $false
    foreach ($entry in $userEntries) {
        if (Test-ManifestedPathEntryMatch -LeftPath $entry -RightPath $desiredDirectory) {
            $userContainsDesired = $true
            break
        }
    }
    $userPrefersDesired = ($userEntries.Count -gt 0) -and (Test-ManifestedPathEntryMatch -LeftPath $userEntries[0] -RightPath $desiredDirectory)

    $resolvedCommandPaths = [ordered]@{}
    $allCommandsResolvedAsExpected = $true
    foreach ($commandName in @($Specification.CommandNames)) {
        $expectedPath = $Specification.ExpectedCommandPaths[$commandName]
        $resolvedPath = Get-ManifestedResolvedApplicationPath -CommandName $commandName
        $resolvedCommandPaths[$commandName] = $resolvedPath

        if (-not (Test-ManifestedPathEntryMatch -LeftPath $resolvedPath -RightPath $expectedPath)) {
            $allCommandsResolvedAsExpected = $false
        }
    }

    $isAligned = ($allCommandsResolvedAsExpected -and $processPrefersDesired -and $userPrefersDesired)

    return [pscustomobject]@{
        Applicable                 = $true
        IsAligned                  = $isAligned
        NeedsSync                  = (-not $isAligned)
        ScopeApplied               = @()
        CommandNames               = @($Specification.CommandNames)
        DesiredExecutablePath      = $Specification.DesiredExecutablePath
        DesiredCommandDirectory    = $desiredDirectory
        ResolvedCommandPaths       = $resolvedCommandPaths
        ProcessPathUpdated         = $false
        UserPathUpdated            = $false
        ProcessPathContainsDesired = $processContainsDesired
        UserPathContainsDesired    = $userContainsDesired
        ProcessPathPrefersDesired  = $processPrefersDesired
        UserPathPrefersDesired     = $userPrefersDesired
        ValidationSucceeded        = $true
    }
}

function Get-ManifestedCommandEnvironmentResult {
    [CmdletBinding(DefaultParameterSetName = 'DescriptorFacts')]
    param(
        [Parameter(ParameterSetName = 'DescriptorFacts', Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(ParameterSetName = 'DescriptorFacts', Mandatory = $true)]
        [pscustomobject]$Facts,

        [Parameter(ParameterSetName = 'LegacyCommand', Mandatory = $true)]
        [string]$CommandName,

        [Parameter(ParameterSetName = 'LegacyCommand')]
        [pscustomobject]$RuntimeState
    )

    $specification = if ($PSCmdlet.ParameterSetName -eq 'LegacyCommand') {
        Get-ManifestedCommandEnvironmentSpec -CommandName $CommandName -RuntimeState $RuntimeState
    }
    else {
        Get-ManifestedCommandEnvironmentSpec -Descriptor $Descriptor -Facts $Facts
    }

    return (Get-ManifestedCommandLineEnvironmentState -Specification $specification)
}

function Sync-ManifestedCommandLineEnvironment {
    [CmdletBinding(DefaultParameterSetName = 'DescriptorFacts')]
    param(
        [Parameter(ParameterSetName = 'DescriptorFacts', Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(ParameterSetName = 'DescriptorFacts', Mandatory = $true)]
        [pscustomobject]$Facts,

        [Parameter(ParameterSetName = 'Specification', Mandatory = $true)]
        [pscustomobject]$Specification
    )

    if ($PSCmdlet.ParameterSetName -eq 'DescriptorFacts') {
        $Specification = Get-ManifestedCommandEnvironmentSpec -Descriptor $Descriptor -Facts $Facts
    }

    $initialState = Get-ManifestedCommandLineEnvironmentState -Specification $Specification
    if (-not $initialState.Applicable) {
        return $initialState
    }

    $processPath = [System.Environment]::GetEnvironmentVariable('Path', 'Process')
    $processUpdate = Set-ManifestedPathEntries -CurrentPath $processPath -DesiredLeadingEntries @($Specification.DesiredCommandDirectory)
    $processPathUpdated = ($processUpdate.Value -ne $processPath)
    if ($processPathUpdated) {
        [System.Environment]::SetEnvironmentVariable('Path', $processUpdate.Value, 'Process')
        $env:PATH = $processUpdate.Value
    }

    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $safeUserPath = if ($null -eq $userPath) { '' } else { $userPath }
    $userUpdate = Set-ManifestedPathEntries -CurrentPath $safeUserPath -DesiredLeadingEntries @($Specification.DesiredCommandDirectory)
    $userPathUpdated = ($userUpdate.Value -ne $safeUserPath)
    if ($userPathUpdated) {
        [System.Environment]::SetEnvironmentVariable('Path', $userUpdate.Value, 'User')
        Publish-ManifestedEnvironmentChange
    }

    $finalState = Get-ManifestedCommandLineEnvironmentState -Specification $Specification
    $scopeApplied = New-Object System.Collections.Generic.List[string]
    if ($processPathUpdated) {
        $scopeApplied.Add('Process') | Out-Null
    }
    if ($userPathUpdated) {
        $scopeApplied.Add('User') | Out-Null
    }

    $result = [pscustomobject]@{
        Applicable                 = $true
        IsAligned                  = [bool]$finalState.IsAligned
        NeedsSync                  = [bool]$finalState.NeedsSync
        ScopeApplied               = @($scopeApplied)
        CommandNames               = @($finalState.CommandNames)
        DesiredExecutablePath      = $finalState.DesiredExecutablePath
        DesiredCommandDirectory    = $finalState.DesiredCommandDirectory
        ResolvedCommandPaths       = $finalState.ResolvedCommandPaths
        ProcessPathUpdated         = $processPathUpdated
        UserPathUpdated            = $userPathUpdated
        ProcessPathContainsDesired = $finalState.ProcessPathContainsDesired
        UserPathContainsDesired    = $finalState.UserPathContainsDesired
        ProcessPathPrefersDesired  = $finalState.ProcessPathPrefersDesired
        UserPathPrefersDesired     = $finalState.UserPathPrefersDesired
        ValidationSucceeded        = [bool]$finalState.IsAligned
    }

    if (-not $result.ValidationSucceeded) {
        $resolvedPaths = @()
        foreach ($commandName in @($result.CommandNames)) {
            $resolvedPaths += ('{0}={1}' -f $commandName, $result.ResolvedCommandPaths[$commandName])
        }

        throw ('Command-line environment synchronization failed for {0}. Expected directory {1}. Resolved commands: {2}' -f $Specification.CommandName, $result.DesiredCommandDirectory, ($resolvedPaths -join ', '))
    }

    return $result
}
