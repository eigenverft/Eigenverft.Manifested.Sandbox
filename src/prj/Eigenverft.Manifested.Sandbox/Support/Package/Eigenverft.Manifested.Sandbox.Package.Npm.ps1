<#
    Eigenverft.Manifested.Sandbox.Package.Npm
#>

function Get-PackageNpmGlobalConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $packageRoot = Get-PackageRootFromStateIndexPath -PackageStateIndexFilePath ([string]$PackageResult.PackageConfig.PackageStateIndexFilePath)
    return ([System.IO.Path]::GetFullPath((Join-Path $packageRoot 'Configuration\External\npm\npmrc')))
}

function New-PackageNpmCacheDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $packageRoot = Get-PackageRootFromStateIndexPath -PackageStateIndexFilePath ([string]$PackageResult.PackageConfig.PackageStateIndexFilePath)
    $segments = @(
        'Caches'
        'npm'
        [string]$PackageResult.DefinitionId
        [string]$PackageResult.Package.releaseTrack
        [string]$PackageResult.Package.version
        [string]$PackageResult.Package.flavor
    ) | ForEach-Object {
        ([string]$_).Trim() -replace '[\\/:\*\?"<>\|]', '-'
    }

    $cacheDirectory = [System.IO.Path]::GetFullPath((Join-Path $packageRoot ($segments -join '\')))
    $null = New-Item -ItemType Directory -Path $cacheDirectory -Force
    return $cacheDirectory
}

function Initialize-PackageNpmGlobalConfig {
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

function Resolve-PackageNpmInstallerCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $install = $PackageResult.Package.install
    if (-not $install.PSObject.Properties['installerCommand'] -or [string]::IsNullOrWhiteSpace([string]$install.installerCommand)) {
        throw "Package npm global package install for '$($PackageResult.PackageId)' requires install.installerCommand."
    }

    $installerCommand = [string]$install.installerCommand
    $dependencyInfo = Resolve-PackageDependencyCommandPath -PackageResult $PackageResult -CommandName $installerCommand
    Write-PackageExecutionMessage -Message ("[STATE] Installer command ready: definition='{0}', command='{1}', path='{2}'." -f $dependencyInfo.DefinitionId, $dependencyInfo.Command, $dependencyInfo.CommandPath)

    return $dependencyInfo
}

function Install-PackageNpmPackage {
<#
.SYNOPSIS
Installs an exact npm package spec into a staged Package-owned prefix.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $install = $PackageResult.Package.install
    if (-not $install.PSObject.Properties['packageSpec'] -or [string]::IsNullOrWhiteSpace([string]$install.packageSpec)) {
        throw "Package npm global package install for '$($PackageResult.PackageId)' requires install.packageSpec."
    }

    $packageSpec = Resolve-PackageTemplateText -Text ([string]$install.packageSpec) -PackageConfig $PackageResult.PackageConfig -Package $PackageResult.Package
    $installerCommandInfo = Resolve-PackageNpmInstallerCommand -PackageResult $PackageResult
    $cacheDirectory = New-PackageNpmCacheDirectory -PackageResult $PackageResult
    $globalConfigPath = Initialize-PackageNpmGlobalConfig -GlobalConfigPath (Get-PackageNpmGlobalConfigPath -PackageResult $PackageResult)
    if ([string]::IsNullOrWhiteSpace([string]$PackageResult.PackageInstallStageDirectory)) {
        throw "Package npm global package install for '$($PackageResult.PackageId)' requires a package install stage directory."
    }
    $stagePath = [System.IO.Path]::GetFullPath([string]$PackageResult.PackageInstallStageDirectory)
    Remove-PathIfExists -Path $stagePath | Out-Null
    $null = New-Item -ItemType Directory -Path $stagePath -Force
    $stagePromoted = $false

    $commandArguments = @('install', '-g', '--prefix', $stagePath, '--cache', $cacheDirectory)
    $commandArguments += @(Get-NpmGlobalConfigArguments -GlobalConfigPath $globalConfigPath)
    $commandArguments += $packageSpec

    Write-PackageExecutionMessage -Message ("[STATE] npm global package install:")
    Write-PackageExecutionMessage -Message ("[PATH] npm command: {0}" -f $installerCommandInfo.CommandPath)
    Write-PackageExecutionMessage -Message ("[PATH] npm stage: {0}" -f $stagePath)
    Write-PackageExecutionMessage -Message ("[PATH] npm cache: {0}" -f $cacheDirectory)
    Write-PackageExecutionMessage -Message ("[PATH] npm global config: {0}" -f $globalConfigPath)
    Write-PackageExecutionMessage -Message ("[STATE] npm package spec: {0}" -f $packageSpec)

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
            throw "Package npm global package install for '$($PackageResult.PackageId)' failed with exit code $exitCode."
        }

        $installParent = Split-Path -Parent $PackageResult.InstallDirectory
        if (-not [string]::IsNullOrWhiteSpace($installParent)) {
            $null = New-Item -ItemType Directory -Path $installParent -Force
        }
        Remove-PathIfExists -Path $PackageResult.InstallDirectory | Out-Null
        Move-Item -LiteralPath $stagePath -Destination $PackageResult.InstallDirectory -Force
        $stagePromoted = $true
    }
    finally {
        if (-not $stagePromoted) {
            Write-PackageExecutionMessage -Level 'WRN' -Message ("[WARN] Preserving failed npm package install stage '{0}' for inspection." -f $stagePath)
        }
    }

    return [pscustomobject]@{
        Status           = Get-PackageOwnedInstallStatus -PackageResult $PackageResult
        InstallKind      = 'npmGlobalPackage'
        InstallDirectory = $PackageResult.InstallDirectory
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


