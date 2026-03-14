<#
    Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment
#>

function Get-ManifestedPathEntryKey {
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
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [pscustomobject]$RuntimeState
    )

    $runtimeHome = if ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeHome']) { $RuntimeState.RuntimeHome } else { $null }
    $executablePath = if ($RuntimeState -and $RuntimeState.PSObject.Properties['ExecutablePath']) { $RuntimeState.ExecutablePath } else { $null }
    $cliCommandPath = if ($RuntimeState -and $RuntimeState.PSObject.Properties['CliCommandPath']) { $RuntimeState.CliCommandPath } else { $null }
    $runtimeSource = if ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeSource']) { $RuntimeState.RuntimeSource } else { $null }

    $desiredCommandDirectory = $null
    $expectedCommandPaths = [ordered]@{}

    switch ($CommandName) {
        'Initialize-NodeRuntime' {
            if (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $desiredCommandDirectory = $runtimeHome
            }
            elseif (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $desiredCommandDirectory = Split-Path -Parent $executablePath
            }

            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $expectedCommandPaths['node.exe'] = (Get-ManifestedFullPath -Path $executablePath)
            }
            if (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $expectedCommandPaths['npm.cmd'] = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'npm.cmd'))
            }
        }
        'Initialize-CodexRuntime' {
            if (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $desiredCommandDirectory = $runtimeHome
            }
            elseif (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $desiredCommandDirectory = Split-Path -Parent $executablePath
            }

            $codexCommandPath = $null
            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $codexCommandPath = (Get-ManifestedFullPath -Path $executablePath)
            }
            elseif (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $codexCommandPath = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome 'codex.cmd'))
            }

            if (-not [string]::IsNullOrWhiteSpace($codexCommandPath)) {
                $expectedCommandPaths['codex'] = $codexCommandPath
                $expectedCommandPaths['codex.cmd'] = $codexCommandPath
            }
        }
        'Initialize-Ps7Runtime' {
            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $desiredCommandDirectory = Split-Path -Parent $executablePath
                $expectedCommandPaths['pwsh.exe'] = (Get-ManifestedFullPath -Path $executablePath)
            }
        }
        'Initialize-GitRuntime' {
            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                $desiredCommandDirectory = Split-Path -Parent $executablePath
                $expectedCommandPaths['git.exe'] = (Get-ManifestedFullPath -Path $executablePath)
            }
        }
        'Initialize-VSCodeRuntime' {
            if (-not [string]::IsNullOrWhiteSpace($cliCommandPath)) {
                $desiredCommandDirectory = Split-Path -Parent $cliCommandPath
                $expectedCommandPaths['code'] = (Get-ManifestedFullPath -Path $cliCommandPath)
                $expectedCommandPaths['code.cmd'] = (Get-ManifestedFullPath -Path $cliCommandPath)
            }
            elseif (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
                $desiredCommandDirectory = Join-Path $runtimeHome 'bin'
                $expectedCommandPaths['code'] = (Get-ManifestedFullPath -Path (Join-Path $desiredCommandDirectory 'code.cmd'))
                $expectedCommandPaths['code.cmd'] = (Get-ManifestedFullPath -Path (Join-Path $desiredCommandDirectory 'code.cmd'))
            }
        }
    }

    $applicable = (-not [string]::IsNullOrWhiteSpace($desiredCommandDirectory)) -and ($expectedCommandPaths.Count -gt 0)

    [pscustomobject]@{
        Applicable              = $applicable
        CommandName             = $CommandName
        CommandNames            = @($expectedCommandPaths.Keys)
        DesiredExecutablePath   = if (-not [string]::IsNullOrWhiteSpace($executablePath)) { Get-ManifestedFullPath -Path $executablePath } else { $null }
        DesiredCommandDirectory = if (-not [string]::IsNullOrWhiteSpace($desiredCommandDirectory)) { Get-ManifestedFullPath -Path $desiredCommandDirectory } else { $null }
        ExpectedCommandPaths    = $expectedCommandPaths
        RuntimeSource           = $runtimeSource
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
            Applicable              = $false
            Status                  = 'NotApplicable'
            ScopeApplied            = @()
            CommandNames            = if ($Specification.PSObject.Properties['CommandNames']) { @($Specification.CommandNames) } else { @() }
            DesiredExecutablePath   = if ($Specification.PSObject.Properties['DesiredExecutablePath']) { $Specification.DesiredExecutablePath } else { $null }
            DesiredCommandDirectory = if ($Specification.PSObject.Properties['DesiredCommandDirectory']) { $Specification.DesiredCommandDirectory } else { $null }
            ResolvedCommandPaths    = [ordered]@{}
            ProcessPathUpdated      = $false
            UserPathUpdated         = $false
            ProcessPathContainsDesired = $false
            UserPathContainsDesired = $false
            ProcessPathPrefersDesired = $false
            UserPathPrefersDesired  = $false
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

    $status = if ($allCommandsResolvedAsExpected -and $processPrefersDesired -and $userPrefersDesired) {
        'Aligned'
    }
    else {
        'NeedsSync'
    }

    [pscustomobject]@{
        Applicable                 = $true
        Status                     = $status
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
    }
}

function Get-ManifestedCommandEnvironmentResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [pscustomobject]$RuntimeState
    )

    $specification = Get-ManifestedCommandEnvironmentSpec -CommandName $CommandName -RuntimeState $RuntimeState
    return (Get-ManifestedCommandLineEnvironmentState -Specification $specification)
}

function Sync-ManifestedCommandLineEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Specification
    )

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

    $status = if ($finalState.Status -eq 'Aligned') {
        if ($scopeApplied.Count -gt 0) { 'Updated' } else { 'Aligned' }
    }
    else {
        'ValidationFailed'
    }

    $result = [pscustomobject]@{
        Applicable                 = $true
        Status                     = $status
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
    }

    if ($status -eq 'ValidationFailed') {
        $resolvedPaths = @()
        foreach ($commandName in @($result.CommandNames)) {
            $resolvedPaths += ('{0}={1}' -f $commandName, $result.ResolvedCommandPaths[$commandName])
        }

        throw ('Command-line environment synchronization failed for {0}. Expected directory {1}. Resolved commands: {2}' -f $Specification.CommandName, $result.DesiredCommandDirectory, ($resolvedPaths -join ', '))
    }

    return $result
}
