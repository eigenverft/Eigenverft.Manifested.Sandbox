<#
    Eigenverft.Manifested.Sandbox.Package.Npm
#>

function Get-PackageModelNpmGlobalConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $packageModelRoot = Split-Path -Parent ([string]$PackageModelResult.PackageModelConfig.PackageStateIndexFilePath)
    return ([System.IO.Path]::GetFullPath((Join-Path $packageModelRoot 'npm\npmrc')))
}

function New-PackageModelNpmCacheDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $segments = @(
        'npm-cache'
        [string]$PackageModelResult.DefinitionId
        [string]$PackageModelResult.Package.releaseTrack
        [string]$PackageModelResult.Package.version
        [string]$PackageModelResult.Package.flavor
    ) | ForEach-Object {
        ([string]$_).Trim() -replace '[\\/:\*\?"<>\|]', '-'
    }

    $cacheDirectory = [System.IO.Path]::GetFullPath((Join-Path $PackageModelResult.PackageModelConfig.InstallWorkspaceRootDirectory ($segments -join '\')))
    $null = New-Item -ItemType Directory -Path $cacheDirectory -Force
    return $cacheDirectory
}

function Initialize-PackageModelNpmGlobalConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GlobalConfigPath
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($GlobalConfigPath)
    $directoryPath = Split-Path -Parent $resolvedPath
    if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
        $null = New-Item -ItemType Directory -Path $directoryPath -Force
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        Set-Content -LiteralPath $resolvedPath -Value '' -Encoding UTF8
    }

    return $resolvedPath
}

function Resolve-PackageModelPackageManagerDependencyCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $install = $PackageModelResult.Package.install
    if (-not $install.PSObject.Properties['managerDependency'] -or $null -eq $install.managerDependency) {
        throw "PackageModel npm install for '$($PackageModelResult.PackageId)' requires install.managerDependency."
    }

    $dependency = $install.managerDependency
    $definitionId = if ($dependency.PSObject.Properties['definitionId']) { [string]$dependency.definitionId } else { $null }
    $commandName = if ($dependency.PSObject.Properties['command']) { [string]$dependency.command } else { $null }
    if ([string]::IsNullOrWhiteSpace($definitionId) -or [string]::IsNullOrWhiteSpace($commandName)) {
        throw "PackageModel npm install for '$($PackageModelResult.PackageId)' requires install.managerDependency.definitionId and install.managerDependency.command."
    }
    if ([string]::Equals($definitionId, [string]$PackageModelResult.DefinitionId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "PackageModel npm install for '$($PackageModelResult.PackageId)' cannot depend on its own definition '$definitionId'."
    }

    Write-PackageModelExecutionMessage -Message ("[STEP] Ensuring package-manager dependency '{0}' for command '{1}'." -f $definitionId, $commandName)
    $dependencyResult = Invoke-PackageModelDefinitionCommand -DefinitionId $definitionId -CommandName ("Invoke-{0}" -f $definitionId)
    if (-not $dependencyResult -or -not [string]::Equals([string]$dependencyResult.Status, 'Ready', [System.StringComparison]::OrdinalIgnoreCase)) {
        $dependencyStatus = if ($dependencyResult) { [string]$dependencyResult.Status } else { '<none>' }
        throw "PackageModel npm install dependency '$definitionId' did not become ready. Status='$dependencyStatus'."
    }

    $entryPoint = @(
        $dependencyResult.EntryPoints.Commands |
            Where-Object { [string]::Equals([string]$_.Name, $commandName, [System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
    )
    $commandPath = if ($entryPoint) { [string]$entryPoint[0].Path } else { $null }
    if ([string]::IsNullOrWhiteSpace($commandPath) -or -not (Test-Path -LiteralPath $commandPath -PathType Leaf)) {
        throw "PackageModel npm install dependency '$definitionId' did not expose command '$commandName'."
    }

    $dependencyInfo = [pscustomobject]@{
        DefinitionId = $definitionId
        Command      = $commandName
        Status       = [string]$dependencyResult.Status
        CommandPath  = [System.IO.Path]::GetFullPath($commandPath)
    }
    if ($PackageModelResult.PSObject.Properties['PackageManagerDependency']) {
        $PackageModelResult.PackageManagerDependency = $dependencyInfo
    }
    else {
        $PackageModelResult | Add-Member -MemberType NoteProperty -Name PackageManagerDependency -Value $dependencyInfo
    }
    Write-PackageModelExecutionMessage -Message ("[STATE] Package-manager dependency ready: definition='{0}', command='{1}', path='{2}'." -f $definitionId, $commandName, $dependencyInfo.CommandPath)

    return $dependencyInfo
}

function Install-PackageModelNpmPackage {
<#
.SYNOPSIS
Installs an exact npm package spec into a staged PackageModel-owned prefix.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $install = $PackageModelResult.Package.install
    if (-not $install.PSObject.Properties['packageSpec'] -or [string]::IsNullOrWhiteSpace([string]$install.packageSpec)) {
        throw "PackageModel npm install for '$($PackageModelResult.PackageId)' requires install.packageSpec."
    }

    $packageSpec = Resolve-PackageModelTemplateText -Text ([string]$install.packageSpec) -PackageModelConfig $PackageModelResult.PackageModelConfig -Package $PackageModelResult.Package
    $dependencyInfo = Resolve-PackageModelPackageManagerDependencyCommand -PackageModelResult $PackageModelResult
    $cacheDirectory = New-PackageModelNpmCacheDirectory -PackageModelResult $PackageModelResult
    $globalConfigPath = Initialize-PackageModelNpmGlobalConfig -GlobalConfigPath (Get-PackageModelNpmGlobalConfigPath -PackageModelResult $PackageModelResult)
    $stagePath = New-TemporaryStageDirectory -Prefix ('npm-' + ([string]$PackageModelResult.DefinitionId).ToLowerInvariant())
    $stagePromoted = $false

    $commandArguments = @('install', '-g', '--prefix', $stagePath, '--cache', $cacheDirectory)
    $commandArguments += @(Get-NpmGlobalConfigArguments -GlobalConfigPath $globalConfigPath)
    $commandArguments += $packageSpec

    Write-PackageModelExecutionMessage -Message ("[STATE] npm package-manager install:")
    Write-PackageModelExecutionMessage -Message ("[PATH] npm command: {0}" -f $dependencyInfo.CommandPath)
    Write-PackageModelExecutionMessage -Message ("[PATH] npm stage: {0}" -f $stagePath)
    Write-PackageModelExecutionMessage -Message ("[PATH] npm cache: {0}" -f $cacheDirectory)
    Write-PackageModelExecutionMessage -Message ("[PATH] npm global config: {0}" -f $globalConfigPath)
    Write-PackageModelExecutionMessage -Message ("[STATE] npm package spec: {0}" -f $packageSpec)

    try {
        Push-Location $stagePath
        try {
            & $dependencyInfo.CommandPath @commandArguments
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) {
                $exitCode = 0
            }
        }
        finally {
            Pop-Location
        }

        if ($exitCode -ne 0) {
            throw "PackageModel npm install for '$($PackageModelResult.PackageId)' failed with exit code $exitCode."
        }

        $installParent = Split-Path -Parent $PackageModelResult.InstallDirectory
        if (-not [string]::IsNullOrWhiteSpace($installParent)) {
            $null = New-Item -ItemType Directory -Path $installParent -Force
        }
        Remove-PathIfExists -Path $PackageModelResult.InstallDirectory | Out-Null
        Move-Item -LiteralPath $stagePath -Destination $PackageModelResult.InstallDirectory -Force
        $stagePromoted = $true
    }
    finally {
        if (-not $stagePromoted) {
            Remove-PathIfExists -Path $stagePath | Out-Null
        }
    }

    return [pscustomobject]@{
        Status           = Get-PackageModelOwnedInstallStatus -PackageModelResult $PackageModelResult
        InstallKind      = 'packageManagerInstall'
        ManagerKind      = 'npm'
        InstallDirectory = $PackageModelResult.InstallDirectory
        ReusedExisting   = $false
        PackageSpec      = $packageSpec
        Dependency       = $dependencyInfo
        CommandPath      = $dependencyInfo.CommandPath
        CommandArguments = @($commandArguments)
        CacheDirectory   = $cacheDirectory
        GlobalConfigPath = $globalConfigPath
        StagePath        = $stagePath
        ExitCode         = $exitCode
    }
}

