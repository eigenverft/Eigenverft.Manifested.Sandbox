function Get-ManifestedManagedPythonRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Join-Path $layout.PythonToolsRoot ($Version + '\' + $Flavor))
}

function Get-ManifestedPythonReportedVersionProbe {
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

function Get-ManifestedPythonReportedVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-ManifestedPythonReportedVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot).ReportedVersion
}

function Get-ManifestedPythonPipVersionProbe {
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

function Get-ManifestedPythonPipVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-ManifestedPythonPipVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot).PipVersion
}

function Get-ManifestedPythonCommandFailureHint {
    [CmdletBinding()]
    param(
        [pscustomobject]$CommandResult
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

function New-ManifestedPythonRuntimeValidationFailureMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [string]$ExpectedVersion,

        [string]$ReportedVersion,

        [pscustomobject]$CommandResult,

        [pscustomobject]$SiteImportsState
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

    $hint = Get-ManifestedPythonCommandFailureHint -CommandResult $CommandResult
    if (-not [string]::IsNullOrWhiteSpace($hint)) {
        $lines.Add($hint) | Out-Null
    }

    return (@($lines) -join [Environment]::NewLine)
}

function Test-ManifestedPythonRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$VersionSpec,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $pythonExe = Join-Path $PythonHome 'python.exe'
    $pipCmd = Join-Path $PythonHome 'pip.cmd'
    $pip3Cmd = Join-Path $PythonHome 'pip3.cmd'
    $siteState = Test-ManifestedPythonSiteImports -PythonHome $PythonHome
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
    }
    else {
        $versionProbe = Get-ManifestedPythonReportedVersionProbe -PythonExe $pythonExe -LocalRoot $LocalRoot
        $reportedVersion = $versionProbe.ReportedVersion
        $versionCommandResult = $versionProbe.CommandResult
        $versionObject = ConvertTo-ManifestedVersionObjectFromRule -VersionText $reportedVersion -Rule $VersionSpec.RuntimeVersionRule
        $pipProbe = if ($siteState.ImportSiteEnabled) { Get-ManifestedPythonPipVersionProbe -PythonExe $pythonExe -LocalRoot $LocalRoot } else { $null }
        $pipVersion = if ($pipProbe) { $pipProbe.PipVersion } else { $null }
        $pipCommandResult = if ($pipProbe) { $pipProbe.CommandResult } else { $null }
        $hasWrappers = (Test-Path -LiteralPath $pipCmd) -and (Test-Path -LiteralPath $pip3Cmd)
        $status = if ($versionObject -and $siteState.IsReady -and $hasWrappers -and -not [string]::IsNullOrWhiteSpace($pipVersion)) { 'Ready' } else { 'NeedsRepair' }
    }

    return [pscustomobject]@{
        Status               = $status
        IsReady              = ($status -eq 'Ready')
        PythonHome           = $PythonHome
        PythonExe            = $pythonExe
        PipCmd               = $pipCmd
        Pip3Cmd              = $pip3Cmd
        ReportedVersion      = $reportedVersion
        PipVersion           = $pipVersion
        PthPath              = $siteState.PthPath
        SiteImports          = $siteState
        VersionCommandResult = $versionCommandResult
        PipCommandResult     = $pipCommandResult
        ValidationHint       = if (-not [string]::IsNullOrWhiteSpace($reportedVersion) -and -not [string]::IsNullOrWhiteSpace($pipVersion)) {
            $null
        }
        elseif ($versionCommandResult -and [string]::IsNullOrWhiteSpace($reportedVersion)) {
            Get-ManifestedPythonCommandFailureHint -CommandResult $versionCommandResult
        }
        elseif ($pipCommandResult -and [string]::IsNullOrWhiteSpace($pipVersion)) {
            Get-ManifestedPythonCommandFailureHint -CommandResult $pipCommandResult
        }
        else {
            $null
        }
    }
}

function Get-ManifestedInstalledPythonRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$Flavor = (Get-ManifestedDefinitionFlavor -Definition $Definition),

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $versionSpec = Get-ManifestedVersionSpec -Definition $Definition
    $entries = @()

    if (Test-Path -LiteralPath $layout.PythonToolsRoot) {
        $versionRoots = Get-ChildItem -LiteralPath $layout.PythonToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedVersionObjectFromRule -VersionText $_.Name -Rule $versionSpec.RuntimeVersionRule } }

        foreach ($versionRoot in $versionRoots) {
            $pythonHome = Join-Path $versionRoot.FullName $Flavor
            if (-not (Test-Path -LiteralPath $pythonHome)) {
                continue
            }

            $validation = Test-ManifestedPythonRuntimeHome -PythonHome $pythonHome -VersionSpec $versionSpec -LocalRoot $layout.LocalRoot
            $expectedVersion = ConvertTo-ManifestedVersionObjectFromRule -VersionText $versionRoot.Name -Rule $versionSpec.RuntimeVersionRule
            $reportedVersion = ConvertTo-ManifestedVersionObjectFromRule -VersionText $validation.ReportedVersion -Rule $versionSpec.RuntimeVersionRule
            $versionMatches = (-not $reportedVersion) -or (-not $expectedVersion) -or ($reportedVersion -eq $expectedVersion)

            $entries += [pscustomobject]@{
                Version        = $versionRoot.Name
                Flavor         = $Flavor
                PythonHome     = $pythonHome
                PythonExe      = $validation.PythonExe
                Validation     = $validation
                VersionMatches = $versionMatches
                PipVersion     = $validation.PipVersion
                IsReady        = ($validation.IsReady -and $versionMatches)
            }
        }
    }

    return [pscustomobject]@{
        Current = ($entries | Where-Object { $_.IsReady } | Select-Object -First 1)
        Valid   = @($entries | Where-Object { $_.IsReady })
        Invalid = @($entries | Where-Object { -not $_.IsReady })
    }
}

function Get-ManifestedPythonExternalPaths {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    foreach ($commandName in @('python.exe', 'python')) {
        foreach ($command in @(Get-Command -Name $commandName -CommandType Application -All -ErrorAction SilentlyContinue)) {
            $commandPath = $null
            if ($command.PSObject.Properties['Path'] -and $command.Path) {
                $commandPath = $command.Path
            }
            elseif ($command.PSObject.Properties['Source'] -and $command.Source) {
                $commandPath = $command.Source
            }

            if (-not [string]::IsNullOrWhiteSpace($commandPath) -and $commandPath -like '*.exe') {
                $candidatePaths.Add($commandPath) | Out-Null
            }
        }
    }

    $additionalPatterns = @()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $additionalPatterns += (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\python.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $additionalPatterns += (Join-Path $env:ProgramFiles 'Python*\python.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $additionalPatterns += (Join-Path $env:USERPROFILE '.pyenv\pyenv-win\versions\*\python.exe')
    }

    foreach ($pattern in $additionalPatterns) {
        foreach ($candidate in @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)) {
            $candidatePaths.Add($candidate.FullName) | Out-Null
        }
    }

    $resolvedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $fullCandidatePath = Get-ManifestedFullPath -Path $candidatePath
        if ([string]::IsNullOrWhiteSpace($fullCandidatePath) -or -not (Test-Path -LiteralPath $fullCandidatePath)) {
            continue
        }
        if (Test-ManifestedPathIsUnderRoot -Path $fullCandidatePath -RootPath $layout.PythonToolsRoot) {
            continue
        }
        if ($fullCandidatePath -like '*\WindowsApps\python.exe') {
            continue
        }

        $resolvedPaths.Add($fullCandidatePath) | Out-Null
    }

    return @($resolvedPaths | Select-Object -Unique)
}

function Test-ManifestedExternalPythonRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$VersionSpec,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $versionProbe = Get-ManifestedPythonReportedVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    $reportedVersion = $versionProbe.ReportedVersion
    $versionObject = ConvertTo-ManifestedVersionObjectFromRule -VersionText $reportedVersion -Rule $VersionSpec.RuntimeVersionRule
    $pipProbe = if ($versionObject -and (Test-ManifestedExternalVersion -Version $versionObject -VersionPolicy $VersionSpec.VersionPolicy -Rule $VersionSpec.RuntimeVersionRule)) {
        Get-ManifestedPythonPipVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    }
    else {
        $null
    }
    $pipVersion = if ($pipProbe) { $pipProbe.PipVersion } else { $null }
    $isReady = ($versionObject -and (Test-ManifestedExternalVersion -Version $versionObject -VersionPolicy $VersionSpec.VersionPolicy -Rule $VersionSpec.RuntimeVersionRule) -and -not [string]::IsNullOrWhiteSpace($pipVersion))

    return [pscustomobject]@{
        Status               = if ($isReady) { 'Ready' } else { 'Invalid' }
        IsReady              = $isReady
        PythonHome           = if (Test-Path -LiteralPath $PythonExe) { Split-Path -Parent $PythonExe } else { $null }
        PythonExe            = $PythonExe
        ReportedVersion      = if ($versionObject) { $versionObject.ToString() } else { $reportedVersion }
        PipVersion           = $pipVersion
        VersionCommandResult = $versionProbe.CommandResult
        PipCommandResult     = if ($pipProbe) { $pipProbe.CommandResult } else { $null }
    }
}

function Get-ManifestedPythonRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CandidatePath,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$VersionSpec,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $validation = Test-ManifestedExternalPythonRuntime -PythonExe $CandidatePath -VersionSpec $VersionSpec -LocalRoot $LocalRoot
    if (-not $validation.IsReady) {
        return $null
    }

    return [pscustomobject]@{
        Version     = $validation.ReportedVersion
        Flavor      = $null
        PythonHome  = $validation.PythonHome
        PythonExe   = $validation.PythonExe
        Validation  = $validation
        PipVersion  = $validation.PipVersion
        IsReady     = $true
        Source      = 'External'
        Discovery   = 'Path'
    }
}

function Get-ManifestedSystemPythonRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $versionSpec = Get-ManifestedVersionSpec -Definition $Definition
    foreach ($candidatePath in @(Get-ManifestedPythonExternalPaths -LocalRoot $LocalRoot)) {
        $runtime = Get-ManifestedPythonRuntimeFromCandidatePath -CandidatePath $candidatePath -VersionSpec $versionSpec -LocalRoot $LocalRoot
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Get-ManifestedPythonEmbeddableRuntimeFactsFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $flavor = Get-ManifestedDefinitionFlavor -Definition $Definition
    $layout = $null
    try {
        $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    }
    catch {
        return (New-ManifestedRuntimeFacts -RuntimeName $Definition.runtimeName -CommandName $Definition.commandName -RuntimeKind 'PortablePackage' -LocalRoot $LocalRoot -Layout $layout -PlatformSupported:$false -BlockedReason $_.Exception.Message -AdditionalProperties @{
                Flavor              = $flavor
                Package             = $null
                PackagePath         = $null
                PipVersion          = $null
                PipCmd              = $null
                Pip3Cmd             = $null
                InvalidRuntimeHomes = @()
            })
    }

    $partialPaths = @()
    if (Test-Path -LiteralPath $layout.PythonCacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.PythonCacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'python' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-ManifestedInstalledPythonRuntime -Definition $Definition -Flavor $flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-ManifestedSystemPythonRuntime -Definition $Definition -LocalRoot $layout.LocalRoot
    }

    $package = Get-LatestCachedZipArtifactFromDefinition -Definition $Definition -Flavor $flavor -LocalRoot $layout.LocalRoot
    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty PythonHome)
    $executablePath = if ($currentRuntime) { $currentRuntime.PythonExe } else { $null }

    return (New-ManifestedRuntimeFacts -RuntimeName $Definition.runtimeName -CommandName $Definition.commandName -RuntimeKind 'PortablePackage' -LocalRoot $layout.LocalRoot -Layout $layout -ManagedRuntime $managedRuntime -ExternalRuntime $externalRuntime -Artifact $package -PartialPaths $partialPaths -InvalidPaths $invalidRuntimeHomes -Version $(if ($currentRuntime) { $currentRuntime.Version } elseif ($package) { $package.Version } else { $null }) -RuntimeHome $(if ($currentRuntime) { $currentRuntime.PythonHome } else { $null }) -RuntimeSource $(if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }) -ExecutablePath $executablePath -RuntimeValidation $(if ($currentRuntime) { $currentRuntime.Validation } else { $null }) -AdditionalProperties @{
            Flavor              = $flavor
            Package             = $package
            PackagePath         = if ($package) { $package.Path } else { $null }
            PipVersion          = if ($currentRuntime -and $currentRuntime.PSObject.Properties['PipVersion']) { $currentRuntime.PipVersion } else { $null }
            PipCmd              = if ($currentRuntime -and $currentRuntime.PSObject.Properties['PipCmd']) { $currentRuntime.PipCmd } else { $null }
            Pip3Cmd             = if ($currentRuntime -and $currentRuntime.PSObject.Properties['Pip3Cmd']) { $currentRuntime.Pip3Cmd } else { $null }
            InvalidRuntimeHomes = $invalidRuntimeHomes
        })
}
