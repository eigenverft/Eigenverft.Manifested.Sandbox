<#
    Eigenverft.Manifested.Sandbox.Runtime.Python.Validation
#>

function Test-PythonSiteImportsEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    $pthPath = Get-PythonRuntimePthPath -PythonHome $PythonHome
    if ([string]::IsNullOrWhiteSpace($pthPath) -or -not (Test-Path -LiteralPath $pthPath)) {
        return [pscustomobject]@{
            Exists                 = $false
            PthPath                = $pthPath
            ImportSiteEnabled      = $false
            SitePackagesPathListed = $false
            IsReady                = $false
        }
    }

    $lines = @(Get-Content -LiteralPath $pthPath -ErrorAction SilentlyContinue)
    $importSiteEnabled = $false
    $sitePackagesPathListed = $false

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq 'import site') {
            $importSiteEnabled = $true
        }
        elseif ($trimmedLine -ieq 'Lib\site-packages') {
            $sitePackagesPathListed = $true
        }
    }

    [pscustomobject]@{
        Exists                 = $true
        PthPath                = $pthPath
        ImportSiteEnabled      = $importSiteEnabled
        SitePackagesPathListed = $sitePackagesPathListed
        IsReady                = ($importSiteEnabled -and $sitePackagesPathListed)
    }
}

function Enable-PythonSiteImports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    $pthState = Test-PythonSiteImportsEnabled -PythonHome $PythonHome
    if (-not $pthState.Exists) {
        throw "Could not find the Python runtime ._pth file under $PythonHome."
    }

    $sitePackagesRoot = Join-Path $PythonHome 'Lib\site-packages'
    New-ManifestedDirectory -Path $sitePackagesRoot | Out-Null

    $lines = @(Get-Content -LiteralPath $pthState.PthPath -ErrorAction Stop)
    $updatedLines = New-Object System.Collections.Generic.List[string]
    $hasImportSite = $false
    $hasSitePackages = $false

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()

        if ($trimmedLine -match '^(#\s*)?import\s+site$') {
            if (-not $hasImportSite) {
                $updatedLines.Add('import site') | Out-Null
                $hasImportSite = $true
            }

            continue
        }

        if ($trimmedLine -ieq 'Lib\site-packages') {
            if (-not $hasSitePackages) {
                $updatedLines.Add('Lib\site-packages') | Out-Null
                $hasSitePackages = $true
            }

            continue
        }

        $updatedLines.Add($line) | Out-Null
    }

    if (-not $hasSitePackages) {
        $updatedLines.Add('Lib\site-packages') | Out-Null
    }
    if (-not $hasImportSite) {
        $updatedLines.Add('import site') | Out-Null
    }

    Set-Content -LiteralPath $pthState.PthPath -Value @($updatedLines) -Encoding ASCII
    return (Test-PythonSiteImportsEnabled -PythonHome $PythonHome)
}

function Get-PythonReportedVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $probe = Get-PythonReportedVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    return $probe.ReportedVersion
}

function Get-PythonReportedVersionProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not (Test-Path -LiteralPath $PythonExe)) {
        return [pscustomobject]@{
            ReportedVersion = $null
            CommandResult   = $null
        }
    }

    $commandResult = Invoke-ManifestedPythonCommand -PythonExe $PythonExe -Arguments @('-c', 'import sys; print(*sys.version_info[:3], sep=chr(46))') -LocalRoot $LocalRoot
    $reportedVersion = $null
    if ($commandResult.ExitCode -eq 0) {
        $versionLine = @($commandResult.OutputLines | Select-Object -First 1)
        if ($versionLine) {
            $reportedVersion = $versionLine[0].ToString().Trim()
        }
    }

    return [pscustomobject]@{
        ReportedVersion = $reportedVersion
        CommandResult   = $commandResult
    }
}

function Get-PythonPipVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $probe = Get-PythonPipVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    return $probe.PipVersion
}

function Get-PythonPipVersionProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not (Test-Path -LiteralPath $PythonExe)) {
        return [pscustomobject]@{
            PipVersion    = $null
            CommandResult = $null
        }
    }

    $commandResult = Invoke-ManifestedPipAwarePythonCommand -PythonExe $PythonExe -Arguments @('-m', 'pip', '--version') -LocalRoot $LocalRoot
    $pipVersion = $null
    if ($commandResult.ExitCode -eq 0) {
        $versionLine = @($commandResult.OutputLines | Select-Object -First 1)
        if ($versionLine) {
            $pipVersion = $versionLine[0].ToString().Trim()
        }
    }

    return [pscustomobject]@{
        PipVersion    = $pipVersion
        CommandResult = $commandResult
    }
}

function Get-PythonCommandFailureHint {
    [CmdletBinding()]
    param(
        [pscustomobject]$CommandResult,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $CommandResult) {
        return $null
    }

    $combinedText = @(
        $CommandResult.ExceptionMessage
        $CommandResult.OutputText
    ) -join [Environment]::NewLine

    if ($combinedText -match 'No module named encodings|init_fs_encoding') {
        return 'The Python process started with an invalid import-path configuration. The managed runtime now clears PYTHONHOME and PYTHONPATH automatically; if this persists, repair the managed runtime cache and retry.'
    }

    return $null
}

function New-PythonRuntimeValidationFailureMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [string]$ExpectedVersion,

        [string]$ReportedVersion,

        [pscustomobject]$CommandResult,

        [pscustomobject]$SiteImportsState,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("Python runtime validation failed during {0} at {1}." -f $Operation, $PythonHome)) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
        $lines.Add(("Expected version: {0}." -f $ExpectedVersion)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($ReportedVersion)) {
        $lines.Add(("Reported version: {0}." -f $ReportedVersion)) | Out-Null
    }
    if ($CommandResult -and $null -ne $CommandResult.ExitCode) {
        $lines.Add(("python.exe exit code: {0}." -f $CommandResult.ExitCode)) | Out-Null
    }
    if ($CommandResult -and -not [string]::IsNullOrWhiteSpace($CommandResult.ExceptionMessage)) {
        $lines.Add(("Startup error: {0}" -f $CommandResult.ExceptionMessage)) | Out-Null
    }
    if ($CommandResult -and -not [string]::IsNullOrWhiteSpace($CommandResult.OutputText)) {
        $lines.Add(("python.exe output:{0}{1}" -f [Environment]::NewLine, $CommandResult.OutputText)) | Out-Null
    }
    if ($SiteImportsState) {
        $lines.Add(("Site imports: import site={0}; Lib\\site-packages listed={1}; pth={2}." -f $SiteImportsState.ImportSiteEnabled, $SiteImportsState.SitePackagesPathListed, $SiteImportsState.PthPath)) | Out-Null
    }
    if ($CommandResult -and $CommandResult.IsManagedPython -and @($CommandResult.SanitizedVariables).Count -gt 0) {
        $lines.Add(("Managed runtime startup cleared: {0}." -f (@($CommandResult.SanitizedVariables) -join ', '))) | Out-Null
    }

    $hint = Get-PythonCommandFailureHint -CommandResult $CommandResult -LocalRoot $LocalRoot
    if (-not [string]::IsNullOrWhiteSpace($hint)) {
        $lines.Add($hint) | Out-Null
    }

    return (@($lines) -join [Environment]::NewLine)
}

function Test-PythonRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $pythonExe = Join-Path $PythonHome 'python.exe'
    $pipCmd = Join-Path $PythonHome 'pip.cmd'
    $pip3Cmd = Join-Path $PythonHome 'pip3.cmd'
    $siteState = Test-PythonSiteImportsEnabled -PythonHome $PythonHome
    $versionCommandResult = $null
    $pipCommandResult = $null

    if (-not (Test-Path -LiteralPath $PythonHome)) {
        $status = 'Missing'
        $reportedVersion = $null
        $pipVersion = $null
    }
    elseif (-not (Test-Path -LiteralPath $pythonExe)) {
        $status = 'NeedsRepair'
        $reportedVersion = $null
        $pipVersion = $null
        $versionCommandResult = $null
        $pipCommandResult = $null
    }
    else {
        $versionProbe = Get-PythonReportedVersionProbe -PythonExe $pythonExe -LocalRoot $LocalRoot
        $reportedVersion = $versionProbe.ReportedVersion
        $versionCommandResult = $versionProbe.CommandResult
        $versionObject = ConvertTo-PythonVersion -VersionText $reportedVersion
        $pipProbe = if ($siteState.ImportSiteEnabled) { Get-PythonPipVersionProbe -PythonExe $pythonExe -LocalRoot $LocalRoot } else { $null }
        $pipVersion = if ($pipProbe) { $pipProbe.PipVersion } else { $null }
        $pipCommandResult = if ($pipProbe) { $pipProbe.CommandResult } else { $null }
        $hasWrappers = (Test-Path -LiteralPath $pipCmd) -and (Test-Path -LiteralPath $pip3Cmd)
        $status = if ($versionObject -and $siteState.IsReady -and $hasWrappers -and -not [string]::IsNullOrWhiteSpace($pipVersion)) { 'Ready' } else { 'NeedsRepair' }
    }

    [pscustomobject]@{
        Status            = $status
        IsReady           = ($status -eq 'Ready')
        PythonHome        = $PythonHome
        PythonExe         = $pythonExe
        PipCmd            = $pipCmd
        Pip3Cmd           = $pip3Cmd
        ReportedVersion   = $reportedVersion
        PipVersion        = $pipVersion
        PthPath           = $siteState.PthPath
        SiteImports       = $siteState
        VersionCommandResult = $versionCommandResult
        PipCommandResult  = $pipCommandResult
        ValidationHint    = if (-not [string]::IsNullOrWhiteSpace($reportedVersion) -and -not [string]::IsNullOrWhiteSpace($pipVersion)) {
            $null
        }
        elseif ($versionCommandResult -and [string]::IsNullOrWhiteSpace($reportedVersion)) {
            Get-PythonCommandFailureHint -CommandResult $versionCommandResult -LocalRoot $LocalRoot
        }
        elseif ($pipCommandResult -and [string]::IsNullOrWhiteSpace($pipVersion)) {
            Get-PythonCommandFailureHint -CommandResult $pipCommandResult -LocalRoot $LocalRoot
        }
        else {
            $null
        }
    }
}

function Test-PythonRuntimeFromState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State.RuntimeHome -and -not $State.ExecutablePath) {
        return $null
    }

    if ($State.RuntimeSource -eq 'Managed' -and $State.RuntimeHome) {
        return (Test-PythonRuntime -PythonHome $State.RuntimeHome -LocalRoot $LocalRoot)
    }

    if ($State.RuntimeSource -eq 'External' -and $State.ExecutablePath) {
        return (Test-ExternalPythonRuntime -PythonExe $State.ExecutablePath -LocalRoot $LocalRoot)
    }

    return $null
}

