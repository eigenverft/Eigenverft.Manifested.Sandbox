function ConvertTo-ManifestedFlexibleVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, '(\d+(?:\.\d+){1,3})')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-ManifestedMachineInstallerCachePathFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $cacheRoot = Get-ManifestedArtifactCacheRootFromDefinition -Definition $Definition -Layout $layout
    if ([string]::IsNullOrWhiteSpace($cacheRoot)) {
        return $null
    }

    $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'directDownload'
    if (-not $supplyBlock -or -not $supplyBlock.PSObject.Properties.Match('fileName').Count -or [string]::IsNullOrWhiteSpace($supplyBlock.fileName)) {
        return $null
    }

    return (Join-Path $cacheRoot ([string]$supplyBlock.fileName))
}

function Get-ManifestedMachineInstallerInfoFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [pscustomobject]$Artifact,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $factsBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'machinePrerequisite'
    $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'directDownload'
    $installerPath = if ($Artifact -and $Artifact.PSObject.Properties['Path'] -and -not [string]::IsNullOrWhiteSpace($Artifact.Path)) {
        [string]$Artifact.Path
    }
    else {
        Get-ManifestedMachineInstallerCachePathFromDefinition -Definition $Definition -LocalRoot $LocalRoot
    }

    $version = if ($Artifact -and $Artifact.PSObject.Properties['Version'] -and -not [string]::IsNullOrWhiteSpace($Artifact.Version)) { [string]$Artifact.Version } else { $null }
    $versionObject = if ($Artifact -and $Artifact.PSObject.Properties['VersionObject'] -and $Artifact.VersionObject) { $Artifact.VersionObject } else { $null }
    $signatureStatus = if ($Artifact -and $Artifact.PSObject.Properties['SignatureStatus'] -and -not [string]::IsNullOrWhiteSpace($Artifact.SignatureStatus)) { [string]$Artifact.SignatureStatus } else { $null }
    $signerSubject = if ($Artifact -and $Artifact.PSObject.Properties['SignerSubject'] -and -not [string]::IsNullOrWhiteSpace($Artifact.SignerSubject)) { [string]$Artifact.SignerSubject } else { $null }

    if (-not [string]::IsNullOrWhiteSpace($installerPath) -and (Test-Path -LiteralPath $installerPath)) {
        try {
            $item = Get-Item -LiteralPath $installerPath -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($version)) {
                $version = [string]$item.VersionInfo.FileVersion
            }
            if (-not $versionObject) {
                $versionObject = ConvertTo-ManifestedFlexibleVersionObject -VersionText $version
            }
        }
        catch {
        }

        if ([string]::IsNullOrWhiteSpace($signatureStatus) -or [string]::IsNullOrWhiteSpace($signerSubject)) {
            try {
                $signature = Get-AuthenticodeSignature -FilePath $installerPath
                $signatureStatus = $signature.Status.ToString()
                $signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
            }
            catch {
                $signatureStatus = $null
                $signerSubject = $null
            }
        }
    }

    return [pscustomobject]@{
        Architecture    = if ($factsBlock -and $factsBlock.PSObject.Properties.Match('architecture').Count -gt 0) { [string]$factsBlock.architecture } else { $null }
        FileName        = if ($Artifact -and $Artifact.PSObject.Properties['FileName'] -and -not [string]::IsNullOrWhiteSpace($Artifact.FileName)) { [string]$Artifact.FileName } elseif ($supplyBlock -and $supplyBlock.PSObject.Properties.Match('fileName').Count -gt 0) { [string]$supplyBlock.fileName } elseif (-not [string]::IsNullOrWhiteSpace($installerPath)) { Split-Path -Leaf $installerPath } else { $null }
        Path            = $installerPath
        Version         = $version
        VersionObject   = $versionObject
        Source          = if ($Artifact -and $Artifact.PSObject.Properties['Source'] -and -not [string]::IsNullOrWhiteSpace($Artifact.Source)) { [string]$Artifact.Source } elseif (-not [string]::IsNullOrWhiteSpace($installerPath) -and (Test-Path -LiteralPath $installerPath)) { 'cache' } else { $null }
        Action          = if ($Artifact -and $Artifact.PSObject.Properties['Action'] -and -not [string]::IsNullOrWhiteSpace($Artifact.Action)) { [string]$Artifact.Action } elseif (-not [string]::IsNullOrWhiteSpace($installerPath) -and (Test-Path -LiteralPath $installerPath)) { 'SelectedCache' } else { $null }
        DownloadUrl     = if ($Artifact -and $Artifact.PSObject.Properties['DownloadUrl'] -and -not [string]::IsNullOrWhiteSpace($Artifact.DownloadUrl)) { [string]$Artifact.DownloadUrl } elseif ($supplyBlock -and $supplyBlock.PSObject.Properties.Match('downloadUrl').Count -gt 0) { [string]$supplyBlock.downloadUrl } else { $null }
        SignatureStatus = $signatureStatus
        SignerSubject   = $signerSubject
    }
}

function Get-ManifestedInstalledMachinePrerequisiteRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    $factsBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'machinePrerequisite'
    $architecture = if ($factsBlock -and $factsBlock.PSObject.Properties.Match('architecture').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($factsBlock.architecture)) {
        ([string]$factsBlock.architecture).ToLowerInvariant()
    }
    else {
        'x64'
    }

    $subKeyPaths = @(
        ('SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\' + $architecture),
        ('SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\' + $architecture)
    )
    $views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32) | Select-Object -Unique

    foreach ($view in $views) {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        try {
            foreach ($subKeyPath in $subKeyPaths) {
                $subKey = $baseKey.OpenSubKey($subKeyPath)
                if (-not $subKey) {
                    continue
                }

                try {
                    $installed = [int]$subKey.GetValue('Installed', 0)
                    $versionText = [string]$subKey.GetValue('Version', '')
                    $versionObject = ConvertTo-ManifestedFlexibleVersionObject -VersionText $versionText

                    if (-not $versionObject) {
                        $major = $subKey.GetValue('Major', $null)
                        $minor = $subKey.GetValue('Minor', $null)
                        $build = $subKey.GetValue('Bld', $null)
                        $revision = $subKey.GetValue('Rbld', $null)

                        if ($null -ne $major -and $null -ne $minor -and $null -ne $build -and $null -ne $revision) {
                            $versionObject = [version]::new([int]$major, [int]$minor, [int]$build, [int]$revision)
                            $versionText = $versionObject.ToString()
                        }
                    }

                    if ($installed -eq 1) {
                        return [pscustomobject]@{
                            Installed     = $true
                            Architecture  = $architecture
                            Version       = $versionText
                            VersionObject = $versionObject
                            KeyPath       = $subKeyPath
                            RegistryView  = $view.ToString()
                        }
                    }
                }
                finally {
                    $subKey.Dispose()
                }
            }
        }
        finally {
            $baseKey.Dispose()
        }
    }

    return [pscustomobject]@{
        Installed     = $false
        Architecture  = $architecture
        Version       = $null
        VersionObject = $null
        KeyPath       = $null
        RegistryView  = $null
    }
}

function Get-ManifestedMachinePrerequisiteFactsFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return (New-ManifestedRuntimeFacts -RuntimeName $Definition.runtimeName -CommandName $Definition.commandName -RuntimeKind 'MachinePrerequisite' -LocalRoot $LocalRoot -Layout $null -PlatformSupported:$false -BlockedReason 'Only Windows hosts are supported by this VC runtime bootstrap.')
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $artifact = Get-ManifestedCachedInstallerArtifactFromDefinition -Definition $Definition -LocalRoot $layout.LocalRoot
    $installerInfo = Get-ManifestedMachineInstallerInfoFromDefinition -Definition $Definition -Artifact $artifact -LocalRoot $layout.LocalRoot
    $partialPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($installerInfo.Path)) {
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $installerInfo.Path
        if (Test-Path -LiteralPath $downloadPath) {
            $partialPaths += $downloadPath
        }
    }

    $installedRuntime = Get-ManifestedInstalledMachinePrerequisiteRuntime -Definition $Definition
    $runtimeValidation = [pscustomobject]@{
        Exists          = [bool]$installedRuntime.Installed
        IsInstalled     = [bool]$installedRuntime.Installed
        RestartRequired = $false
        FailureReason   = if ($installedRuntime.Installed) { $null } else { 'NotInstalled' }
        Architecture    = $installedRuntime.Architecture
        Version         = $installedRuntime.Version
        VersionObject   = $installedRuntime.VersionObject
        KeyPath         = $installedRuntime.KeyPath
        RegistryView    = $installedRuntime.RegistryView
    }
    $managedRuntime = if ($installedRuntime.Installed) {
        [pscustomobject]@{
            Version       = $installedRuntime.Version
            VersionObject = $installedRuntime.VersionObject
            Validation    = $runtimeValidation
        }
    }
    else {
        $null
    }
    $artifactForFacts = if (-not [string]::IsNullOrWhiteSpace($installerInfo.Path) -and (Test-Path -LiteralPath $installerInfo.Path)) {
        $installerInfo
    }
    else {
        $null
    }

    return (New-ManifestedRuntimeFacts -RuntimeName $Definition.runtimeName -CommandName $Definition.commandName -RuntimeKind 'MachinePrerequisite' -LocalRoot $layout.LocalRoot -Layout $layout -ManagedRuntime $managedRuntime -Artifact $artifactForFacts -PartialPaths $partialPaths -Version $(if ($installedRuntime.Version) { $installedRuntime.Version } elseif ($installerInfo.Version) { $installerInfo.Version } else { $null }) -RuntimeHome $null -RuntimeSource $(if ($installedRuntime.Installed) { 'Managed' } else { $null }) -ExecutablePath $null -RuntimeValidation $runtimeValidation -AdditionalProperties @{
            InstalledRuntime = $installedRuntime
            Runtime          = $runtimeValidation
            Installer        = $installerInfo
            InstallerPath    = $installerInfo.Path
        })
}

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
