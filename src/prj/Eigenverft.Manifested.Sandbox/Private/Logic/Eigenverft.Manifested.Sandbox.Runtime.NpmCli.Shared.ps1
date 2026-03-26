<#
    Eigenverft.Manifested.Sandbox.Runtime.NpmCli.Shared
#>

function ConvertTo-ManifestedNpmCliVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, 'v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?)')
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value
}

function ConvertTo-ManifestedNpmCliVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    $normalizedVersion = ConvertTo-ManifestedNpmCliVersion -VersionText $VersionText
    if ([string]::IsNullOrWhiteSpace($normalizedVersion)) {
        return $null
    }

    $match = [regex]::Match($normalizedVersion, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-ManifestedNpmCliRuntimeDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Codex', 'OpenCode', 'Gemini', 'Qwen')]
        [string]$Name
    )

    switch ($Name) {
        'Codex' {
            return [pscustomobject]@{
                Name                    = 'CodexRuntime'
                RuntimeFamily           = 'NpmCli'
                RuntimePack             = 'NpmCli'
                SnapshotName            = 'CodexRuntime'
                SnapshotPathProperty    = 'RuntimeHome'
                StateFunctionName       = 'Get-CodexRuntimeState'
                InitializeCommandName   = 'Initialize-CodexRuntime'
                DisplayName             = 'Codex'
                DependencyCommandNames  = @('Initialize-VCRuntime', 'Initialize-NodeRuntime')
                DirectInstallDependencies = @(
                    [pscustomobject]@{
                        CommandName = 'Initialize-VCRuntime'
                    }
                )
                ToolsRootPropertyName   = 'CodexToolsRoot'
                CacheRootPropertyName   = 'CodexCacheRoot'
                InstallFunctionName     = 'Install-CodexRuntime'
                RepairFunctionName      = 'Repair-CodexRuntime'
                RuntimeTestFunctionName = 'Test-CodexRuntime'
                PackageJsonPropertyName = 'PackageJsonPath'
                ExecutablePropertyName  = 'CodexCmd'
                ExecutableFileName      = 'codex.cmd'
                CandidateLeafNames      = @('codex.cmd', 'codex')
                DiscoveryCommandNames   = @('codex.cmd', 'codex')
                CommandEnvironmentNames = @('codex', 'codex.cmd')
                PackageId               = '@openai/codex@latest'
                PackageJsonRelativePath = 'node_modules\@openai\codex\package.json'
                StagePrefix             = 'codex'
                NodeDependency          = [pscustomobject]@{
                    Required       = $true
                    MinimumVersion = $null
                }
                BlockedReason           = 'Only Windows hosts are supported by this Codex runtime bootstrap.'
            }
        }
        'OpenCode' {
            return [pscustomobject]@{
                Name                    = 'OpenCodeRuntime'
                RuntimeFamily           = 'NpmCli'
                RuntimePack             = 'NpmCli'
                SnapshotName            = 'OpenCodeRuntime'
                SnapshotPathProperty    = 'RuntimeHome'
                StateFunctionName       = 'Get-OpenCodeRuntimeState'
                InitializeCommandName   = 'Initialize-OpenCodeRuntime'
                DisplayName             = 'OpenCode'
                DependencyCommandNames  = @('Initialize-NodeRuntime')
                DirectInstallDependencies = @()
                ToolsRootPropertyName   = 'OpenCodeToolsRoot'
                CacheRootPropertyName   = 'OpenCodeCacheRoot'
                InstallFunctionName     = 'Install-OpenCodeRuntime'
                RepairFunctionName      = 'Repair-OpenCodeRuntime'
                RuntimeTestFunctionName = 'Test-OpenCodeRuntime'
                PackageJsonPropertyName = 'PackageJsonPath'
                ExecutablePropertyName  = 'OpenCodeCmd'
                ExecutableFileName      = 'opencode.cmd'
                CandidateLeafNames      = @('opencode.cmd', 'opencode')
                DiscoveryCommandNames   = @('opencode.cmd', 'opencode')
                CommandEnvironmentNames = @('opencode', 'opencode.cmd')
                PackageId               = 'opencode-ai@latest'
                PackageJsonRelativePath = 'node_modules\opencode-ai\package.json'
                StagePrefix             = 'opencode'
                NodeDependency          = [pscustomobject]@{
                    Required       = $true
                    MinimumVersion = $null
                }
                BlockedReason           = 'Only Windows hosts are supported by this OpenCode runtime bootstrap.'
            }
        }
        'Gemini' {
            return [pscustomobject]@{
                Name                    = 'GeminiRuntime'
                RuntimeFamily           = 'NpmCli'
                RuntimePack             = 'NpmCli'
                SnapshotName            = 'GeminiRuntime'
                SnapshotPathProperty    = 'RuntimeHome'
                StateFunctionName       = 'Get-GeminiRuntimeState'
                InitializeCommandName   = 'Initialize-GeminiRuntime'
                DisplayName             = 'Gemini'
                DependencyCommandNames  = @('Initialize-NodeRuntime')
                DirectInstallDependencies = @()
                ToolsRootPropertyName   = 'GeminiToolsRoot'
                CacheRootPropertyName   = 'GeminiCacheRoot'
                InstallFunctionName     = 'Install-GeminiRuntime'
                RepairFunctionName      = 'Repair-GeminiRuntime'
                RuntimeTestFunctionName = 'Test-GeminiRuntime'
                PackageJsonPropertyName = 'PackageJsonPath'
                ExecutablePropertyName  = 'GeminiCmd'
                ExecutableFileName      = 'gemini.cmd'
                CandidateLeafNames      = @('gemini.cmd', 'gemini')
                DiscoveryCommandNames   = @('gemini.cmd', 'gemini')
                CommandEnvironmentNames = @('gemini', 'gemini.cmd')
                PackageId               = '@google/gemini-cli@latest'
                PackageJsonRelativePath = 'node_modules\@google\gemini-cli\package.json'
                StagePrefix             = 'gemini'
                NodeDependency          = [pscustomobject]@{
                    Required       = $true
                    MinimumVersion = [version]'20.0.0'
                }
                BlockedReason           = 'Only Windows hosts are supported by this Gemini runtime bootstrap.'
            }
        }
        'Qwen' {
            return [pscustomobject]@{
                Name                    = 'QwenRuntime'
                RuntimeFamily           = 'NpmCli'
                RuntimePack             = 'NpmCli'
                SnapshotName            = 'QwenRuntime'
                SnapshotPathProperty    = 'RuntimeHome'
                StateFunctionName       = 'Get-QwenRuntimeState'
                InitializeCommandName   = 'Initialize-QwenRuntime'
                DisplayName             = 'Qwen'
                DependencyCommandNames  = @('Initialize-NodeRuntime')
                DirectInstallDependencies = @()
                ToolsRootPropertyName   = 'QwenToolsRoot'
                CacheRootPropertyName   = 'QwenCacheRoot'
                InstallFunctionName     = 'Install-QwenRuntime'
                RepairFunctionName      = 'Repair-QwenRuntime'
                RuntimeTestFunctionName = 'Test-QwenRuntime'
                PackageJsonPropertyName = 'PackageJsonPath'
                ExecutablePropertyName  = 'QwenCmd'
                ExecutableFileName      = 'qwen.cmd'
                CandidateLeafNames      = @('qwen.cmd', 'qwen')
                DiscoveryCommandNames   = @('qwen.cmd', 'qwen')
                CommandEnvironmentNames = @('qwen', 'qwen.cmd')
                PackageId               = '@qwen-code/qwen-code@latest'
                PackageJsonRelativePath = 'node_modules\@qwen-code\qwen-code\package.json'
                StagePrefix             = 'qwen'
                NodeDependency          = [pscustomobject]@{
                    Required       = $true
                    MinimumVersion = [version]'20.0.0'
                }
                BlockedReason           = 'Only Windows hosts are supported by this Qwen runtime bootstrap.'
            }
        }
    }
}

function Get-ManifestedCodexNpmCliRuntimeDefinition {
    [CmdletBinding()]
    param()

    return (Get-ManifestedNpmCliRuntimeDefinition -Name 'Codex')
}

function Get-ManifestedOpenCodeNpmCliRuntimeDefinition {
    [CmdletBinding()]
    param()

    return (Get-ManifestedNpmCliRuntimeDefinition -Name 'OpenCode')
}

function Get-ManifestedGeminiNpmCliRuntimeDefinition {
    [CmdletBinding()]
    param()

    return (Get-ManifestedNpmCliRuntimeDefinition -Name 'Gemini')
}

function Get-ManifestedQwenNpmCliRuntimeDefinition {
    [CmdletBinding()]
    param()

    return (Get-ManifestedNpmCliRuntimeDefinition -Name 'Qwen')
}

function New-ManifestedNpmCliCommandEnvironmentResolver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames,

        [Parameter(Mandatory = $true)]
        [string]$ExecutableFileName
    )

    $resolvedCommandNames = @($CommandNames)
    $resolvedExecutableFileName = $ExecutableFileName

    return {
        param([pscustomobject]$RuntimeState)

        $runtimeHome = if ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeHome']) { $RuntimeState.RuntimeHome } else { $null }
        $executablePath = if ($RuntimeState -and $RuntimeState.PSObject.Properties['ExecutablePath']) { $RuntimeState.ExecutablePath } else { $null }
        $desiredCommandDirectory = $null
        $expectedCommandPaths = [ordered]@{}

        if (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
            $desiredCommandDirectory = $runtimeHome
        }
        elseif (-not [string]::IsNullOrWhiteSpace($executablePath)) {
            $desiredCommandDirectory = Split-Path -Parent $executablePath
        }

        $commandPath = $null
        if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
            $commandPath = (Get-ManifestedFullPath -Path $executablePath)
        }
        elseif (-not [string]::IsNullOrWhiteSpace($runtimeHome)) {
            $commandPath = (Get-ManifestedFullPath -Path (Join-Path $runtimeHome $resolvedExecutableFileName))
        }

        if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
            foreach ($commandName in @($resolvedCommandNames)) {
                $expectedCommandPaths[$commandName] = $commandPath
            }
        }

        [pscustomobject]@{
            DesiredCommandDirectory = $desiredCommandDirectory
            ExpectedCommandPaths    = $expectedCommandPaths
        }
    }
}

function New-ManifestedNpmCliRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    return [pscustomobject]@{
        Name                    = $Definition.Name
        RuntimeFamily           = $Definition.RuntimeFamily
        RuntimePack             = $Definition.RuntimePack
        SnapshotName            = $Definition.SnapshotName
        SnapshotPathProperty    = $Definition.SnapshotPathProperty
        StateFunctionName       = $Definition.StateFunctionName
        InitializeCommandName   = $Definition.InitializeCommandName
        DisplayName             = $Definition.DisplayName
        DependencyCommandNames  = @($Definition.DependencyCommandNames)
        DirectInstallDependencies = @($Definition.DirectInstallDependencies)
        ToolsRootPropertyName   = $Definition.ToolsRootPropertyName
        InstallFunctionName     = $Definition.InstallFunctionName
        RepairFunctionName      = $Definition.RepairFunctionName
        RuntimeTestFunctionName = $Definition.RuntimeTestFunctionName
        PackageJsonPropertyName = $Definition.PackageJsonPropertyName
        NodeDependency          = $Definition.NodeDependency
        ResolveCommandEnvironment = (New-ManifestedNpmCliCommandEnvironmentResolver -CommandNames $Definition.CommandEnvironmentNames -ExecutableFileName $Definition.ExecutableFileName)
    }
}

function Get-ManifestedNpmCliRuntimePackageJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Join-Path $RuntimeHome $Definition.PackageJsonRelativePath)
}

function Get-ManifestedNpmCliRuntimePackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath
    )

    if (-not (Test-Path -LiteralPath $PackageJsonPath)) {
        return $null
    }

    try {
        $packageDocument = Get-Content -LiteralPath $PackageJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
        return (ConvertTo-ManifestedNpmCliVersion -VersionText ([string]$packageDocument.version))
    }
    catch {
        return $null
    }
}

function Test-ManifestedNpmCliRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $executablePath = Join-Path $RuntimeHome $Definition.ExecutableFileName
    $packageJsonPath = Get-ManifestedNpmCliRuntimePackageJsonPath -Definition $Definition -RuntimeHome $RuntimeHome
    $packageVersion = $null
    $reportedVersion = $null

    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        $status = 'Missing'
    }
    elseif (-not (Test-Path -LiteralPath $executablePath) -or -not (Test-Path -LiteralPath $packageJsonPath)) {
        $status = 'NeedsRepair'
    }
    else {
        $packageVersion = Get-ManifestedNpmCliRuntimePackageVersion -Definition $Definition -PackageJsonPath $packageJsonPath

        try {
            $reportedVersion = (& $executablePath --version 2>$null | Select-Object -First 1)
            if ($reportedVersion) {
                $reportedVersion = (ConvertTo-ManifestedNpmCliVersion -VersionText $reportedVersion.ToString().Trim())
            }
        }
        catch {
            $reportedVersion = $null
        }

        if ([string]::IsNullOrWhiteSpace($packageVersion) -or [string]::IsNullOrWhiteSpace($reportedVersion)) {
            $status = 'NeedsRepair'
        }
        elseif ($packageVersion -ne $reportedVersion) {
            $status = 'NeedsRepair'
        }
        else {
            $status = 'Ready'
        }
    }

    $result = [ordered]@{
        Status      = $status
        IsReady     = ($status -eq 'Ready')
        RuntimeHome = $RuntimeHome
    }
    $result[$Definition.ExecutablePropertyName] = $executablePath
    $result['PackageJsonPath'] = $packageJsonPath
    $result['PackageVersion'] = $packageVersion
    $result['ReportedVersion'] = $reportedVersion
    return [pscustomobject]$result
}

function Get-InstalledManifestedNpmCliRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $toolsRoot = $layout.($Definition.ToolsRootPropertyName)
    $entries = @()

    if (Test-Path -LiteralPath $toolsRoot) {
        $runtimeRoots = Get-ChildItem -LiteralPath $toolsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike ('_stage_{0}_*' -f $Definition.StagePrefix) } |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedNpmCliVersionObject -VersionText $_.Name } }, Name

        foreach ($runtimeRoot in $runtimeRoots) {
            $validation = Test-ManifestedNpmCliRuntime -Definition $Definition -RuntimeHome $runtimeRoot.FullName
            $expectedVersion = ConvertTo-ManifestedNpmCliVersion -VersionText $runtimeRoot.Name
            $runtimeVersion = if ($validation.PackageVersion) { $validation.PackageVersion } else { $expectedVersion }
            $versionMatches = (-not $expectedVersion) -or (-not $validation.PackageVersion) -or ($expectedVersion -eq $validation.PackageVersion)

            $entry = [ordered]@{
                Version        = $runtimeVersion
                RuntimeHome    = $runtimeRoot.FullName
            }
            $entry[$Definition.ExecutablePropertyName] = $validation.($Definition.ExecutablePropertyName)
            $entry['PackageJsonPath'] = $validation.PackageJsonPath
            $entry['Validation'] = $validation
            $entry['VersionMatches'] = $versionMatches
            $entry['IsReady'] = ($validation.IsReady -and $versionMatches)
            $entry['Source'] = 'Managed'
            $entries += [pscustomobject]$entry
        }
    }

    [pscustomobject]@{
        Current = ($entries | Where-Object { $_.IsReady } | Select-Object -First 1)
        Valid   = @($entries | Where-Object { $_.IsReady })
        Invalid = @($entries | Where-Object { -not $_.IsReady })
    }
}

function Get-ManifestedNpmCliRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$CandidatePath
    )

    $resolvedCandidatePath = Get-ManifestedFullPath -Path $CandidatePath
    if ([string]::IsNullOrWhiteSpace($resolvedCandidatePath) -or -not (Test-Path -LiteralPath $resolvedCandidatePath)) {
        return $null
    }

    $leafName = Split-Path -Leaf $resolvedCandidatePath
    $isSupportedLeaf = $false
    foreach ($candidateLeafName in @($Definition.CandidateLeafNames)) {
        if ($leafName -ieq $candidateLeafName) {
            $isSupportedLeaf = $true
            break
        }
    }
    if (-not $isSupportedLeaf) {
        return $null
    }

    $runtimeHome = Split-Path -Parent $resolvedCandidatePath
    $validation = Test-ManifestedNpmCliRuntime -Definition $Definition -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        return $null
    }

    $result = [ordered]@{
        Version        = $validation.PackageVersion
        RuntimeHome    = $runtimeHome
    }
    $result[$Definition.ExecutablePropertyName] = $validation.($Definition.ExecutablePropertyName)
    $result['PackageJsonPath'] = $validation.PackageJsonPath
    $result['Validation'] = $validation
    $result['IsReady'] = $true
    $result['Source'] = 'External'
    $result['Discovery'] = 'Path'
    return [pscustomobject]$result
}

function Get-SystemManifestedNpmCliRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $toolsRoot = $layout.($Definition.ToolsRootPropertyName)
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    foreach ($commandName in @($Definition.DiscoveryCommandNames)) {
        $candidatePath = Get-ManifestedApplicationPath -CommandName $commandName -ExcludedRoots @($toolsRoot)
        if (-not [string]::IsNullOrWhiteSpace($candidatePath)) {
            $candidatePaths.Add($candidatePath) | Out-Null
        }
    }

    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $runtime = Get-ManifestedNpmCliRuntimeFromCandidatePath -Definition $Definition -CandidatePath $candidatePath
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Get-ManifestedNpmCliRuntimeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return [pscustomobject]@{
            Status              = 'Blocked'
            LocalRoot           = $LocalRoot
            Layout              = $null
            CurrentVersion      = $null
            RuntimeHome         = $null
            RuntimeSource       = $null
            ExecutablePath      = $null
            Runtime             = $null
            InvalidRuntimeHomes = @()
            PartialPaths        = @()
            BlockedReason       = $Definition.BlockedReason
            PackageJsonPath     = $null
        }
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $toolsRoot = $layout.($Definition.ToolsRootPropertyName)
    $partialPaths = @(
        Get-ManifestedStageDirectories -Prefix $Definition.StagePrefix -Mode TemporaryShort -LegacyRootPaths @($toolsRoot) |
            Select-Object -ExpandProperty FullName
    )

    $installed = Get-InstalledManifestedNpmCliRuntime -Definition $Definition -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemManifestedNpmCliRuntime -Definition $Definition -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty RuntimeHome)

    if ($invalidRuntimeHomes.Count -gt 0) {
        $status = 'NeedsRepair'
    }
    elseif ($partialPaths.Count -gt 0) {
        $status = 'Partial'
    }
    elseif ($currentRuntime) {
        $status = 'Ready'
    }
    else {
        $status = 'Missing'
    }

    [pscustomobject]@{
        Status              = $status
        LocalRoot           = $layout.LocalRoot
        Layout              = $layout
        CurrentVersion      = if ($currentRuntime) { $currentRuntime.Version } else { $null }
        RuntimeHome         = if ($currentRuntime) { $currentRuntime.RuntimeHome } else { $null }
        RuntimeSource       = $runtimeSource
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.($Definition.ExecutablePropertyName) } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        PartialPaths        = $partialPaths
        BlockedReason       = $null
        PackageJsonPath     = if ($currentRuntime) { $currentRuntime.PackageJsonPath } else { $null }
    }
}

function Repair-ManifestedNpmCliRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [pscustomobject]$State,

        [string[]]$CorruptRuntimeHomes = @(),

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-ManifestedNpmCliRuntimeState -Definition $Definition -LocalRoot $LocalRoot
    }

    $pathsToRemove = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($State.PartialPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($State.InvalidRuntimeHomes)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($CorruptRuntimeHomes)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }

    $removedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($pathsToRemove | Select-Object -Unique)) {
        if (Remove-ManifestedPath -Path $path) {
            $removedPaths.Add($path) | Out-Null
        }
    }

    [pscustomobject]@{
        Action       = if ($removedPaths.Count -gt 0) { 'Repaired' } else { 'Skipped' }
        RemovedPaths = @($removedPaths)
        LocalRoot    = $State.LocalRoot
        Layout       = $State.Layout
    }
}

function Install-ManifestedNpmCliRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $cacheRoot = $layout.($Definition.CacheRootPropertyName)
    $toolsRoot = $layout.($Definition.ToolsRootPropertyName)
    New-ManifestedDirectory -Path $cacheRoot | Out-Null
    New-ManifestedDirectory -Path $toolsRoot | Out-Null

    $stagePath = New-ManifestedStageDirectory -Prefix $Definition.StagePrefix -Mode TemporaryShort
    $npmConfiguration = Get-ManifestedManagedNpmCommandArguments -NpmCmd $NpmCmd -LocalRoot $LocalRoot
    $npmArguments = @('install', '-g', '--prefix', $stagePath, '--cache', $cacheRoot)
    $npmArguments += @($npmConfiguration.CommandArguments)
    $npmArguments += $Definition.PackageId

    Write-Host ('Installing {0} CLI into managed sandbox tools...' -f $Definition.DisplayName)
    & $NpmCmd @npmArguments
    if ($LASTEXITCODE -ne 0) {
        throw ("npm install for {0} exited with code {1}." -f $Definition.DisplayName, $LASTEXITCODE)
    }

    $stageValidation = Test-ManifestedNpmCliRuntime -Definition $Definition -RuntimeHome $stagePath
    if (-not $stageValidation.IsReady) {
        throw ("{0} runtime validation failed after staged install at {1}." -f $Definition.DisplayName, $stagePath)
    }

    $version = if ($stageValidation.PackageVersion) { $stageValidation.PackageVersion } else { ConvertTo-ManifestedNpmCliVersion -VersionText $stageValidation.ReportedVersion }
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw ("Could not determine the installed {0} version from {1}." -f $Definition.DisplayName, $stageValidation.PackageJsonPath)
    }

    $runtimeHome = Join-Path $toolsRoot $version
    if (Test-Path -LiteralPath $runtimeHome) {
        Remove-ManifestedPath -Path $runtimeHome | Out-Null
    }

    Move-Item -LiteralPath $stagePath -Destination $runtimeHome -Force

    $validation = Test-ManifestedNpmCliRuntime -Definition $Definition -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        throw ("{0} runtime validation failed after install at {1}." -f $Definition.DisplayName, $runtimeHome)
    }

    $result = [ordered]@{
        Action      = 'Installed'
        Version     = $validation.PackageVersion
        RuntimeHome = $runtimeHome
    }
    $result[$Definition.ExecutablePropertyName] = $validation.($Definition.ExecutablePropertyName)
    $result['PackageJsonPath'] = $validation.PackageJsonPath
    $result['Source'] = 'Managed'
    $result['CacheRoot'] = $cacheRoot
    $result['NpmCmd'] = $NpmCmd
    return [pscustomobject]$result
}
