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
    return ([System.IO.Path]::GetFullPath((Join-Path $packageModelRoot 'External\npm\npmrc')))
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

function Resolve-PackageModelNpmInstallerCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $install = $PackageModelResult.Package.install
    if (-not $install.PSObject.Properties['installerCommand'] -or [string]::IsNullOrWhiteSpace([string]$install.installerCommand)) {
        throw "PackageModel npm global package install for '$($PackageModelResult.PackageId)' requires install.installerCommand."
    }

    $installerCommand = [string]$install.installerCommand
    $dependencyInfo = Resolve-PackageModelDependencyCommandPath -PackageModelResult $PackageModelResult -CommandName $installerCommand
    Write-PackageModelExecutionMessage -Message ("[STATE] Installer command ready: definition='{0}', command='{1}', path='{2}'." -f $dependencyInfo.DefinitionId, $dependencyInfo.Command, $dependencyInfo.CommandPath)

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
        throw "PackageModel npm global package install for '$($PackageModelResult.PackageId)' requires install.packageSpec."
    }

    $packageSpec = Resolve-PackageModelTemplateText -Text ([string]$install.packageSpec) -PackageModelConfig $PackageModelResult.PackageModelConfig -Package $PackageModelResult.Package
    $installerCommandInfo = Resolve-PackageModelNpmInstallerCommand -PackageModelResult $PackageModelResult
    $cacheDirectory = New-PackageModelNpmCacheDirectory -PackageModelResult $PackageModelResult
    $globalConfigPath = Initialize-PackageModelNpmGlobalConfig -GlobalConfigPath (Get-PackageModelNpmGlobalConfigPath -PackageModelResult $PackageModelResult)
    $stagePath = New-TemporaryStageDirectory -Prefix ('npm-' + ([string]$PackageModelResult.DefinitionId).ToLowerInvariant())
    $stagePromoted = $false

    $commandArguments = @('install', '-g', '--prefix', $stagePath, '--cache', $cacheDirectory)
    $commandArguments += @(Get-NpmGlobalConfigArguments -GlobalConfigPath $globalConfigPath)
    $commandArguments += $packageSpec

    Write-PackageModelExecutionMessage -Message ("[STATE] npm global package install:")
    Write-PackageModelExecutionMessage -Message ("[PATH] npm command: {0}" -f $installerCommandInfo.CommandPath)
    Write-PackageModelExecutionMessage -Message ("[PATH] npm stage: {0}" -f $stagePath)
    Write-PackageModelExecutionMessage -Message ("[PATH] npm cache: {0}" -f $cacheDirectory)
    Write-PackageModelExecutionMessage -Message ("[PATH] npm global config: {0}" -f $globalConfigPath)
    Write-PackageModelExecutionMessage -Message ("[STATE] npm package spec: {0}" -f $packageSpec)

    try {
        Push-Location $stagePath
        try {
            & $installerCommandInfo.CommandPath @commandArguments
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) {
                $exitCode = 0
            }
        }
        finally {
            Pop-Location
        }

        if ($exitCode -ne 0) {
            throw "PackageModel npm global package install for '$($PackageModelResult.PackageId)' failed with exit code $exitCode."
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
        InstallKind      = 'npmGlobalPackage'
        InstallDirectory = $PackageModelResult.InstallDirectory
        ReusedExisting   = $false
        InstallerCommand = $installerCommandInfo.Command
        InstallerCommandPath = $installerCommandInfo.CommandPath
        PackageSpec      = $packageSpec
        CommandArguments = @($commandArguments)
        CacheDirectory   = $cacheDirectory
        GlobalConfigPath = $globalConfigPath
        StagePath        = $stagePath
        ExitCode         = $exitCode
    }
}

