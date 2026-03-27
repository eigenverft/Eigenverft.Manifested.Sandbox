function Get-ManifestedRuntimeDependencyFacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeName,

        [string]$LocalRoot = (Get-ManifestedLocalRoot),

        [hashtable]$FactsCache = @{}
    )

    $dependencyContext = Get-ManifestedRuntimeContext -RuntimeName $RuntimeName
    if (-not $dependencyContext) {
        return $null
    }

    return (Get-ManifestedRuntimeFactsFromContext -Context $dependencyContext -LocalRoot $LocalRoot -FactsCache $FactsCache)
}

function Invoke-ManifestedPortableArchiveInstallFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $packageInfo = if ($Facts.PSObject.Properties['Package']) { $Facts.Package } else { $null }
    if (-not $packageInfo) {
        throw "The package for '$($Definition.commandName)' was not available for install."
    }

    $factsBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'portableRuntime'
    $installBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'portableArchive'
    if (-not $factsBlock -or -not $installBlock) {
        throw "The portable archive install blocks for '$($Definition.commandName)' were not available."
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $toolsRoot = $layout.($installBlock.toolsRootLayoutProperty)
    $versionFolderName = Expand-ManifestedDefinitionTemplate -Template $(if ($installBlock.PSObject.Properties.Match('versionFolderTemplate').Count -gt 0) { $installBlock.versionFolderTemplate } else { '{version}' }) -Version $packageInfo.Version -TagName $packageInfo.Version -Flavor $null
    $versionFolderName = $versionFolderName.Replace('{versionNoPrefixV}', $packageInfo.Version.TrimStart('v', 'V'))
    $runtimeHome = Join-Path (Join-Path $toolsRoot $versionFolderName) $Facts.Flavor
    $currentValidation = Test-ManifestedPortableRuntimeHome -Definition $Definition -RuntimeHome $runtimeHome

    if (-not $currentValidation.IsUsable) {
        New-ManifestedDirectory -Path (Split-Path -Parent $runtimeHome) | Out-Null

        $stagePrefix = if ($installBlock.PSObject.Properties.Match('stagePrefix').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($installBlock.stagePrefix)) { [string]$installBlock.stagePrefix } else { [string]$factsBlock.stagePrefix }
        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $packageInfo.Path -Prefix $stagePrefix
            if (-not (Test-Path -LiteralPath $stageInfo.ExpandedRoot)) {
                throw "The archive for '$($Definition.commandName)' did not extract as expected."
            }

            if (Test-Path -LiteralPath $runtimeHome) {
                Remove-ManifestedPath -Path $runtimeHome | Out-Null
            }

            New-ManifestedDirectory -Path $runtimeHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $runtimeHome -Force
            }

            foreach ($relativeDirectory in @($installBlock.createDirectories)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$relativeDirectory)) {
                    New-ManifestedDirectory -Path (Join-Path $runtimeHome ([string]$relativeDirectory)) | Out-Null
                }
            }
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $validation = Test-ManifestedPortableRuntimeHome -Definition $Definition -RuntimeHome $runtimeHome
    if (-not $validation.IsUsable) {
        throw "$($Definition.runtimeName) validation failed after install at $runtimeHome."
    }

    $result = [ordered]@{
        Action         = if ($currentValidation.IsUsable) { 'Skipped' } else { 'Installed' }
        Version        = $packageInfo.Version
        Flavor         = $Facts.Flavor
        RuntimeHome    = $runtimeHome
        ExecutablePath = $validation.ExecutablePath
        Source         = $packageInfo.Source
        DownloadUrl    = if ($packageInfo.PSObject.Properties['DownloadUrl']) { $packageInfo.DownloadUrl } else { $null }
        Sha256         = if ($packageInfo.PSObject.Properties['Sha256']) { $packageInfo.Sha256 } else { $null }
    }
    foreach ($property in @($validation.PSObject.Properties)) {
        if ($result.Contains($property.Name)) {
            continue
        }
        $result[$property.Name] = $property.Value
    }

    return [pscustomobject]$result
}

function Invoke-ManifestedPythonEmbeddableInstallFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [bool]$RefreshRequested = $false,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $packageInfo = if ($Facts.PSObject.Properties['Package']) { $Facts.Package } else { $null }
    if (-not $packageInfo) {
        throw "The package for '$($Definition.commandName)' was not available for install."
    }

    return (Install-PythonRuntime -PackageInfo $packageInfo -Flavor $Facts.Flavor -LocalRoot $LocalRoot -ForceInstall:$RefreshRequested)
}

function Invoke-ManifestedMachineInstallerFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [hashtable]$CommandOptions = @{},

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $installerInfo = if ($Facts.PSObject.Properties['Artifact'] -and $Facts.Artifact) { $Facts.Artifact } elseif ($Facts.PSObject.Properties['Installer'] -and $Facts.Installer) { $Facts.Installer } else { $null }
    if (-not $installerInfo) {
        throw "The installer for '$($Definition.commandName)' was not available."
    }

    $timeoutSec = 300
    if ($CommandOptions.ContainsKey('InstallTimeoutSec') -and $CommandOptions['InstallTimeoutSec']) {
        $timeoutSec = [int]$CommandOptions['InstallTimeoutSec']
    }

    return (Install-VCRuntime -InstallerInfo $installerInfo -InstallTimeoutSec $timeoutSec -LocalRoot $LocalRoot)
}

function Install-ManifestedRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [bool]$RefreshRequested = $false,

        [hashtable]$CommandOptions = @{},

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'portableArchive') {
        return (Invoke-ManifestedPortableArchiveInstallFromDefinition -Definition $Definition -Facts $Facts -LocalRoot $LocalRoot)
    }
    if (Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'pythonEmbeddableZip') {
        return (Invoke-ManifestedPythonEmbeddableInstallFromDefinition -Definition $Definition -Facts $Facts -RefreshRequested:$RefreshRequested -LocalRoot $LocalRoot)
    }
    if (Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'machineInstaller') {
        return (Invoke-ManifestedMachineInstallerFromDefinition -Definition $Definition -Facts $Facts -CommandOptions $CommandOptions -LocalRoot $LocalRoot)
    }
    if (Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'npmGlobalPackage') {
        return (Invoke-ManifestedNpmGlobalPackageInstallFromDefinition -Definition $Definition -Facts $Facts -LocalRoot $LocalRoot)
    }

    throw "No install function is defined for '$($Definition.commandName)'."
}
