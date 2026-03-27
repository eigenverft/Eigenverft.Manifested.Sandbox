function Invoke-ManifestedRuntimeRepairFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [string[]]$CorruptArtifactPaths = @(),

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Repair-ManifestedRuntime -Facts $Facts -CorruptArtifactPaths $CorruptArtifactPaths -LocalRoot $LocalRoot)
}

function Get-ManifestedSuppliedArtifactFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [bool]$RefreshRequested = $false,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $flavor = Get-ManifestedDefinitionFlavor -Definition $Definition
    $cacheRoot = Get-ManifestedArtifactCacheRootFromDefinition -Definition $Definition -Layout $layout
    if (-not [string]::IsNullOrWhiteSpace($cacheRoot)) {
        New-ManifestedDirectory -Path $cacheRoot | Out-Null
    }

    $supplyGitHubRelease = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'githubRelease'
    $supplyNodeDist = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'nodeDist'
    $supplyDirectDownload = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'directDownload'
    $supplyPythonEmbed = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'pythonEmbed'
    $supplyVSCodeUpdate = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'vsCodeUpdate'

    $onlineArtifact = $null
    try {
        if ($supplyGitHubRelease) {
            $onlineArtifact = Get-ManifestedOnlineGitHubReleaseArtifactFromDefinition -Definition $Definition -Flavor $flavor
        }
        elseif ($supplyNodeDist) {
            $onlineArtifact = Get-ManifestedOnlineNodeDistArtifactFromDefinition -Definition $Definition -Flavor $flavor
        }
        elseif ($supplyDirectDownload) {
            $onlineArtifact = Get-ManifestedDirectDownloadArtifactFromDefinition -Definition $Definition
        }
        elseif ($supplyPythonEmbed) {
            $onlineArtifact = Get-ManifestedOnlinePythonEmbedArtifactFromDefinition -Definition $Definition -Flavor $flavor
        }
        elseif ($supplyVSCodeUpdate) {
            $onlineArtifact = Get-ManifestedOnlineVSCodeArtifactFromDefinition -Definition $Definition -Flavor $flavor
        }
    }
    catch {
        $onlineArtifact = $null
    }

    if ($onlineArtifact) {
        $packagePath = Join-Path $cacheRoot $onlineArtifact.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($RefreshRequested -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                $downloadMessage = $null
                if ($supplyGitHubRelease -and $supplyGitHubRelease.PSObject.Properties.Match('downloadMessage').Count -gt 0) {
                    $downloadMessage = Expand-ManifestedDefinitionTemplate -Template $Definition.supply.githubRelease.downloadMessage -Version $onlineArtifact.Version -TagName $onlineArtifact.TagName -Flavor $flavor
                }
                elseif ($supplyNodeDist -and $supplyNodeDist.PSObject.Properties.Match('downloadMessage').Count -gt 0) {
                    $downloadMessage = Expand-ManifestedDefinitionTemplate -Template $Definition.supply.nodeDist.downloadMessage -Version $onlineArtifact.Version -TagName $onlineArtifact.TagName -Flavor $flavor
                }
                elseif ($supplyPythonEmbed -and $supplyPythonEmbed.PSObject.Properties.Match('downloadMessage').Count -gt 0) {
                    $downloadMessage = Expand-ManifestedDefinitionTemplate -Template $Definition.supply.pythonEmbed.downloadMessage -Version $onlineArtifact.Version -TagName $onlineArtifact.TagName -Flavor $flavor
                }
                elseif ($supplyVSCodeUpdate -and $supplyVSCodeUpdate.PSObject.Properties.Match('downloadMessage').Count -gt 0) {
                    $downloadMessage = Expand-ManifestedDefinitionTemplate -Template $Definition.supply.vsCodeUpdate.downloadMessage -Version $onlineArtifact.Version -TagName $onlineArtifact.TagName -Flavor $flavor
                }
                elseif ($supplyDirectDownload -and $supplyDirectDownload.PSObject.Properties.Match('downloadMessage').Count -gt 0) {
                    $downloadMessage = $Definition.supply.directDownload.downloadMessage
                }
                if (-not [string]::IsNullOrWhiteSpace($downloadMessage)) {
                    Write-Host $downloadMessage
                }

                $downloadParameters = @{
                    Uri            = $onlineArtifact.DownloadUrl
                    OutFile        = $downloadPath
                    UseBasicParsing = $true
                }
                if ($supplyGitHubRelease -or $supplyVSCodeUpdate) {
                    Enable-ManifestedTls12Support
                    $downloadParameters['Headers'] = @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' }
                }

                Invoke-WebRequestEx @downloadParameters
                Move-Item -LiteralPath $downloadPath -Destination $packagePath -Force
                $action = 'Downloaded'
            }
            catch {
                Remove-ManifestedPath -Path $downloadPath | Out-Null
                if (-not (Test-Path -LiteralPath $packagePath)) {
                    throw
                }

                Write-Warning ('Could not refresh the packaged artifact for ' + $Definition.commandName + '. Using cached copy. ' + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        $packageInfo = [pscustomobject]@{
            TagName     = if ($onlineArtifact.PSObject.Properties['TagName']) { $onlineArtifact.TagName } else { $null }
            Version     = $onlineArtifact.Version
            Flavor      = $flavor
            FileName    = $onlineArtifact.FileName
            Path        = $packagePath
            Source      = if ($action -eq 'Downloaded') { 'online' } else { 'cache' }
            Action      = $action
            DownloadUrl = if ($onlineArtifact.PSObject.Properties['DownloadUrl']) { $onlineArtifact.DownloadUrl } else { $null }
            Sha256      = if ($onlineArtifact.PSObject.Properties['Sha256']) { $onlineArtifact.Sha256 } else { $null }
            ShaSource   = if ($onlineArtifact.PSObject.Properties['ShaSource']) { $onlineArtifact.ShaSource } else { $null }
            ReleaseUrl  = if ($onlineArtifact.PSObject.Properties['ReleaseUrl']) { $onlineArtifact.ReleaseUrl } else { $null }
            ShasumsUrl  = if ($onlineArtifact.PSObject.Properties['ShasumsUrl']) { $onlineArtifact.ShasumsUrl } else { $null }
            NpmVersion  = if ($onlineArtifact.PSObject.Properties['NpmVersion']) { $onlineArtifact.NpmVersion } else { $null }
            ReleaseId   = if ($onlineArtifact.PSObject.Properties['ReleaseId']) { $onlineArtifact.ReleaseId } else { $null }
            Channel     = if ($onlineArtifact.PSObject.Properties['Channel']) { $onlineArtifact.Channel } else { $null }
        }

        Save-ManifestedArtifactMetadataFromPackage -PackageInfo $packageInfo
        return $packageInfo
    }

    $cachedArtifact = if (Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'executableInstaller') {
        Get-ManifestedCachedInstallerArtifactFromDefinition -Definition $Definition -Flavor $flavor -LocalRoot $LocalRoot
    }
    else {
        Get-LatestCachedZipArtifactFromDefinition -Definition $Definition -Flavor $flavor -LocalRoot $LocalRoot
    }
    if (-not $cachedArtifact) {
        $offlineError = $null
        foreach ($supplyName in @('githubRelease', 'nodeDist', 'directDownload', 'pythonEmbed', 'vsCodeUpdate')) {
            $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName $supplyName
            if ($supplyBlock -and $supplyBlock.PSObject.Properties.Match('offlineError').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($supplyBlock.offlineError)) {
                $offlineError = $supplyBlock.offlineError
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($offlineError)) {
            $offlineError = "Could not resolve an online artifact or cached installer/package for '$($Definition.commandName)'."
        }

        throw $offlineError
    }

    Save-ManifestedArtifactMetadataFromPackage -PackageInfo $cachedArtifact
    return $cachedArtifact
}

function Test-ManifestedArtifactTrustFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Artifact
    )

    if (-not (Test-Path -LiteralPath $Artifact.Path)) {
        return [pscustomobject]@{
            Exists           = $false
            IsTrusted        = $false
            CanRepair        = $false
            FailureReason    = 'ArtifactMissing'
            Version          = if ($Artifact.PSObject.Properties['Version']) { $Artifact.Version } else { $null }
            Flavor           = if ($Artifact.PSObject.Properties['Flavor']) { $Artifact.Flavor } else { $null }
            FileName         = if ($Artifact.PSObject.Properties['FileName']) { $Artifact.FileName } else { $null }
            Path             = $Artifact.Path
            Source           = if ($Artifact.PSObject.Properties['Source']) { $Artifact.Source } else { $null }
            Verified         = $false
            Verification     = 'Missing'
            VerificationMode = 'Missing'
            ExpectedHash     = $null
            ActualHash       = $null
        }
    }

    $installerArtifact = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'executableInstaller'
    if ($installerArtifact) {
        $signature = Get-AuthenticodeSignature -FilePath $Artifact.Path
        $signatureStatus = $signature.Status.ToString()
        $signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
        $expectedSignerPattern = if ($installerArtifact.PSObject.Properties.Match('expectedSignerSubjectMatch').Count -gt 0) { $installerArtifact.expectedSignerSubjectMatch } else { 'Microsoft Corporation' }
        $isTrusted = (($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid) -and ($signerSubject -match $expectedSignerPattern))

        return [pscustomobject]@{
            Exists           = $true
            IsTrusted        = $isTrusted
            CanRepair        = (-not $isTrusted)
            FailureReason    = if ($isTrusted) { $null } else { 'SignatureValidationFailed' }
            Version          = if ($Artifact.PSObject.Properties['Version']) { $Artifact.Version } else { $null }
            FileName         = if ($Artifact.PSObject.Properties['FileName']) { $Artifact.FileName } else { $null }
            Path             = $Artifact.Path
            Source           = if ($Artifact.PSObject.Properties['Source']) { $Artifact.Source } else { $null }
            Verified         = $isTrusted
            Verification     = 'Authenticode'
            VerificationMode = 'Authenticode'
            ExpectedHash     = $null
            ActualHash       = $null
            SignatureStatus  = $signatureStatus
            SignerSubject    = $signerSubject
        }
    }

    $nodeDistSupply = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'nodeDist'
    if ($nodeDistSupply) {
        $verified = $false
        $verification = 'OfflineCache'
        $expectedHash = $null
        $actualHash = $null
        $isTrusted = $false
        $canRepair = $false
        $failureReason = $null

        if ($Artifact.PSObject.Properties['ShasumsUrl'] -and -not [string]::IsNullOrWhiteSpace($Artifact.ShasumsUrl)) {
            $expectedHash = Get-NodePackageExpectedSha256 -ShasumsUrl $Artifact.ShasumsUrl -FileName $Artifact.FileName
            $actualHash = (Get-FileHash -LiteralPath $Artifact.Path -Algorithm SHA256).Hash.ToLowerInvariant()
            $verified = $true
            $verification = 'SHA256'
            $isTrusted = ($actualHash -eq $expectedHash)
            $canRepair = (-not $isTrusted)
            $failureReason = if ($isTrusted) { $null } else { 'HashMismatch' }
        }

        return [pscustomobject]@{
            Exists           = $true
            IsTrusted        = $isTrusted
            CanRepair        = $canRepair
            FailureReason    = $failureReason
            Version          = if ($Artifact.PSObject.Properties['Version']) { $Artifact.Version } else { $null }
            Flavor           = if ($Artifact.PSObject.Properties['Flavor']) { $Artifact.Flavor } else { $null }
            FileName         = if ($Artifact.PSObject.Properties['FileName']) { $Artifact.FileName } else { $null }
            Path             = $Artifact.Path
            Source           = if ($Artifact.PSObject.Properties['Source']) { $Artifact.Source } else { $null }
            Verified         = $verified
            Verification     = $verification
            VerificationMode = $verification
            ExpectedHash     = $expectedHash
            ActualHash       = $actualHash
        }
    }

    if (-not $Artifact.PSObject.Properties['Sha256'] -or [string]::IsNullOrWhiteSpace($Artifact.Sha256)) {
        return [pscustomobject]@{
            Exists           = $true
            IsTrusted        = $false
            CanRepair        = $false
            FailureReason    = 'TrustedHashUnavailable'
            TagName          = if ($Artifact.PSObject.Properties['TagName']) { $Artifact.TagName } else { $null }
            Version          = if ($Artifact.PSObject.Properties['Version']) { $Artifact.Version } else { $null }
            Flavor           = if ($Artifact.PSObject.Properties['Flavor']) { $Artifact.Flavor } else { $null }
            FileName         = if ($Artifact.PSObject.Properties['FileName']) { $Artifact.FileName } else { $null }
            Path             = $Artifact.Path
            Source           = if ($Artifact.PSObject.Properties['Source']) { $Artifact.Source } else { $null }
            Verified         = $false
            Verification     = 'MissingTrustedHash'
            VerificationMode = 'MissingTrustedHash'
            ExpectedHash     = $null
            ActualHash       = $null
        }
    }

    $actualHash = (Get-FileHash -LiteralPath $Artifact.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = $Artifact.Sha256.ToLowerInvariant()
    $isTrusted = ($actualHash -eq $expectedHash)

    return [pscustomobject]@{
        Exists           = $true
        IsTrusted        = $isTrusted
        CanRepair        = (-not $isTrusted)
        FailureReason    = if ($isTrusted) { $null } else { 'HashMismatch' }
        TagName          = if ($Artifact.PSObject.Properties['TagName']) { $Artifact.TagName } else { $null }
        Version          = if ($Artifact.PSObject.Properties['Version']) { $Artifact.Version } else { $null }
        Flavor           = if ($Artifact.PSObject.Properties['Flavor']) { $Artifact.Flavor } else { $null }
        FileName         = if ($Artifact.PSObject.Properties['FileName']) { $Artifact.FileName } else { $null }
        Path             = $Artifact.Path
        Source           = if ($Artifact.PSObject.Properties['Source']) { $Artifact.Source } else { $null }
        Verified         = $true
        Verification     = if ($Artifact.PSObject.Properties['ShaSource'] -and -not [string]::IsNullOrWhiteSpace($Artifact.ShaSource)) { $Artifact.ShaSource } else { 'SHA256' }
        VerificationMode = if ($Artifact.PSObject.Properties['ShaSource'] -and -not [string]::IsNullOrWhiteSpace($Artifact.ShaSource)) { $Artifact.ShaSource } else { 'SHA256' }
        ExpectedHash     = $expectedHash
        ActualHash       = $actualHash
    }
}


