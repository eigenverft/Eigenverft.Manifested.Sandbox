function Test-ManifestedNpmCliRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $factsBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'npmCli'
    $commandFileName = if ($factsBlock.PSObject.Properties.Match('commandFileName').Count -gt 0) { $factsBlock.commandFileName } else { $null }
    $packageJsonRelativePath = if ($factsBlock.PSObject.Properties.Match('packageJsonRelativePath').Count -gt 0) { $factsBlock.packageJsonRelativePath } else { $null }

    $commandPath = if (-not [string]::IsNullOrWhiteSpace($commandFileName)) { Join-Path $RuntimeHome $commandFileName } else { $null }
    $packageJsonPath = if (-not [string]::IsNullOrWhiteSpace($packageJsonRelativePath)) { Join-Path $RuntimeHome $packageJsonRelativePath } else { $null }
    $packageVersion = $null
    $reportedVersion = $null
    $exists = (Test-Path -LiteralPath $RuntimeHome)
    $hasRequiredFiles = $false
    $versionsAligned = $false
    $failureReason = $null

    if (-not $exists) {
        $failureReason = 'RuntimeHomeMissing'
    }
    elseif ([string]::IsNullOrWhiteSpace($commandPath) -or [string]::IsNullOrWhiteSpace($packageJsonPath) -or -not (Test-Path -LiteralPath $commandPath) -or -not (Test-Path -LiteralPath $packageJsonPath)) {
        $failureReason = 'RequiredFilesMissing'
    }
    else {
        $hasRequiredFiles = $true

        try {
            $packageDocument = Get-Content -LiteralPath $packageJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
            $packageVersion = ConvertTo-ManifestedSemanticVersionText -VersionText ([string]$packageDocument.version)
        }
        catch {
            $packageVersion = $null
        }

        try {
            $reportedVersion = (& $commandPath --version 2>$null | Select-Object -First 1)
            if ($reportedVersion) {
                $reportedVersion = ConvertTo-ManifestedSemanticVersionText -VersionText $reportedVersion.ToString().Trim()
            }
        }
        catch {
            $reportedVersion = $null
        }

        if (-not [string]::IsNullOrWhiteSpace($packageVersion) -and -not [string]::IsNullOrWhiteSpace($reportedVersion) -and $packageVersion -eq $reportedVersion) {
            $versionsAligned = $true
        }
        else {
            $failureReason = 'VersionMismatch'
        }
    }

    return [pscustomobject]@{
        Exists           = $exists
        HasRequiredFiles = $hasRequiredFiles
        VersionsAligned  = $versionsAligned
        IsUsable         = ($exists -and $hasRequiredFiles -and $versionsAligned)
        FailureReason    = $failureReason
        RuntimeHome      = $RuntimeHome
        CommandPath      = $commandPath
        PackageJsonPath  = $packageJsonPath
        PackageVersion   = $packageVersion
        ReportedVersion  = $reportedVersion
    }
}

function Get-ManifestedNpmCliFactsFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return (New-ManifestedRuntimeFacts -RuntimeName $Definition.runtimeName -CommandName $Definition.commandName -RuntimeKind 'NpmCli' -LocalRoot $LocalRoot -Layout $null -PlatformSupported:$false -BlockedReason ('Only Windows hosts are supported by this ' + $Definition.runtimeName + ' bootstrap.'))
    }

    $factsBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'npmCli'
    $installBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'npmGlobalPackage'
    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $toolsRoot = $layout.($installBlock.toolsRootLayoutProperty)
    $stagePrefix = if ($installBlock.PSObject.Properties.Match('stagePrefix').Count -gt 0) { $installBlock.stagePrefix } else { (($Definition.runtimeName -replace 'Runtime$', '')).ToLowerInvariant() }

    $partialPaths = @()
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix $stagePrefix -Mode TemporaryShort -LegacyRootPaths @($toolsRoot) | Select-Object -ExpandProperty FullName)

    $entries = @()
    if (Test-Path -LiteralPath $toolsRoot) {
        $runtimeRoots = Get-ChildItem -LiteralPath $toolsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike ('_stage_' + $stagePrefix + '_*') } |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedSemanticVersionObject -VersionText $_.Name } }, Name

        foreach ($runtimeRoot in $runtimeRoots) {
            $validation = Test-ManifestedNpmCliRuntimeHome -Definition $Definition -RuntimeHome $runtimeRoot.FullName
            $expectedVersion = ConvertTo-ManifestedSemanticVersionText -VersionText $runtimeRoot.Name
            $runtimeVersion = if ($validation.PackageVersion) { $validation.PackageVersion } else { $expectedVersion }
            $versionMatches = (-not $expectedVersion) -or (-not $validation.PackageVersion) -or ($expectedVersion -eq $validation.PackageVersion)
            $isUsable = ($validation.IsUsable -and $versionMatches)

            $entries += [pscustomobject]@{
                Version         = $runtimeVersion
                RuntimeHome     = $runtimeRoot.FullName
                ExecutablePath  = $validation.CommandPath
                PackageJsonPath = $validation.PackageJsonPath
                Validation      = $validation
                VersionMatches  = $versionMatches
                IsUsable        = $isUsable
                Source          = 'Managed'
            }
        }
    }

    $managedRuntime = $entries | Where-Object { $_.IsUsable } | Select-Object -First 1
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $candidatePaths = New-Object System.Collections.Generic.List[string]
        foreach ($commandName in @($Definition.environment.commandProjection.expectedCommands)) {
            $candidatePath = Get-ManifestedApplicationPath -CommandName $commandName -ExcludedRoots @($toolsRoot)
            if (-not [string]::IsNullOrWhiteSpace($candidatePath)) {
                $candidatePaths.Add($candidatePath) | Out-Null
            }

            if ($commandName -match '\.cmd$') {
                $alternateCommandName = [System.IO.Path]::GetFileNameWithoutExtension($commandName)
                if (-not [string]::IsNullOrWhiteSpace($alternateCommandName)) {
                    $alternateCandidatePath = Get-ManifestedApplicationPath -CommandName $alternateCommandName -ExcludedRoots @($toolsRoot)
                    if (-not [string]::IsNullOrWhiteSpace($alternateCandidatePath)) {
                        $candidatePaths.Add($alternateCandidatePath) | Out-Null
                    }
                }
            }
        }

        foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
            $resolvedCandidatePath = Get-ManifestedFullPath -Path $candidatePath
            if ([string]::IsNullOrWhiteSpace($resolvedCandidatePath) -or -not (Test-Path -LiteralPath $resolvedCandidatePath)) {
                continue
            }

            $runtimeHome = Split-Path -Parent $resolvedCandidatePath
            $validation = Test-ManifestedNpmCliRuntimeHome -Definition $Definition -RuntimeHome $runtimeHome
            if (-not $validation.IsUsable) {
                continue
            }

            $externalRuntime = [pscustomobject]@{
                Version         = $validation.PackageVersion
                RuntimeHome     = $runtimeHome
                ExecutablePath  = $validation.CommandPath
                PackageJsonPath = $validation.PackageJsonPath
                Validation      = $validation
                IsUsable        = $true
                Source          = 'External'
                Discovery       = 'Path'
            }
            break
        }
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $invalidRuntimeHomes = @($entries | Where-Object { -not $_.IsUsable } | Select-Object -ExpandProperty RuntimeHome)

    return (New-ManifestedRuntimeFacts -RuntimeName $Definition.runtimeName -CommandName $Definition.commandName -RuntimeKind 'NpmCli' -LocalRoot $layout.LocalRoot -Layout $layout -ManagedRuntime $managedRuntime -ExternalRuntime $externalRuntime -PartialPaths $partialPaths -InvalidPaths $invalidRuntimeHomes -Version $(if ($currentRuntime) { $currentRuntime.Version } else { $null }) -RuntimeHome $(if ($currentRuntime) { $currentRuntime.RuntimeHome } else { $null }) -RuntimeSource $(if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }) -ExecutablePath $(if ($currentRuntime) { $currentRuntime.ExecutablePath } else { $null }) -RuntimeValidation $(if ($currentRuntime) { $currentRuntime.Validation } else { $null }) -AdditionalProperties @{
            PackageJsonPath     = if ($currentRuntime) { $currentRuntime.PackageJsonPath } else { $null }
            InvalidRuntimeHomes = $invalidRuntimeHomes
        })
}
