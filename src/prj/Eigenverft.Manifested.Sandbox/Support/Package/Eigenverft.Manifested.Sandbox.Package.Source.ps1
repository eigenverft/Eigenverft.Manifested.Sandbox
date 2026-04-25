<#
    Eigenverft.Manifested.Sandbox.Package.Source
#>

function Get-PackageModelPackageFileIndex {
<#
.SYNOPSIS
Loads the PackageModel package-file index.

.DESCRIPTION
Returns the configured package-file index document, or an empty record set when
the index file does not exist yet.

.PARAMETER PackageModelConfig
The resolved PackageModel config object.

.EXAMPLE
Get-PackageModelPackageFileIndex -PackageModelConfig $config
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelConfig
    )

    $indexPath = $PackageModelConfig.PackageFileIndexFilePath
    if ([string]::IsNullOrWhiteSpace($indexPath)) {
        throw 'PackageModel package-file index path is not configured.'
    }

    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        return [pscustomobject]@{
            Path    = $indexPath
            Records = @()
        }
    }

    $documentInfo = Read-PackageModelJsonDocument -Path $indexPath
    $records = if ($documentInfo.Document.PSObject.Properties['records']) { @($documentInfo.Document.records) } else { @() }
    return [pscustomobject]@{
        Path    = $documentInfo.Path
        Records = $records
    }
}

function Save-PackageModelPackageFileIndex {
<#
.SYNOPSIS
Writes the PackageModel package-file index to disk.

.DESCRIPTION
Persists the normalized package-file index document to the configured index path.

.PARAMETER IndexPath
The target index file path.

.PARAMETER Records
The package-file records to persist.

.EXAMPLE
Save-PackageModelPackageFileIndex -IndexPath $path -Records $records
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IndexPath,

        [Parameter(Mandatory = $true)]
        [object[]]$Records
    )

    $directoryPath = Split-Path -Parent $IndexPath
    if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
        $null = New-Item -ItemType Directory -Path $directoryPath -Force
    }

    [ordered]@{
        schemaVersion = 1
        records = @($Records)
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $IndexPath -Encoding UTF8
}

function Update-PackageModelPackageFileIndexRecord {
<#
.SYNOPSIS
Updates the PackageModel package-file index for one resolved package file path.

.DESCRIPTION
Refreshes the tracked source and package metadata for a package-file path in
the package-file index.

.PARAMETER PackageModelResult
The current PackageModel result object.

.PARAMETER PackageFilePath
The package-file path to write into the index.

.PARAMETER SourceScope
The source scope that produced the artifact.

.PARAMETER SourceId
The source id that produced the artifact.

.EXAMPLE
Update-PackageModelPackageFileIndexRecord -PackageModelResult $result -PackageFilePath $path -SourceScope environment -SourceId defaultPackageDepot
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult,

        [Parameter(Mandatory = $true)]
        [string]$PackageFilePath,

        [AllowNull()]
        [string]$SourceScope,

        [AllowNull()]
        [string]$SourceId
    )

    if ([string]::IsNullOrWhiteSpace($PackageFilePath)) {
        return
    }

    $normalizedPackageFilePath = [System.IO.Path]::GetFullPath($PackageFilePath)
    $index = Get-PackageModelPackageFileIndex -PackageModelConfig $PackageModelResult.PackageModelConfig
    $records = @(
        foreach ($record in @($index.Records)) {
            if (-not [string]::Equals([string]$record.path, $normalizedPackageFilePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $record
            }
        }
    )

    $records += [pscustomobject]@{
        path         = $normalizedPackageFilePath
        definitionId = $PackageModelResult.DefinitionId
        releaseId    = $PackageModelResult.PackageId
        releaseTrack = $PackageModelResult.ReleaseTrack
        flavor       = if ($PackageModelResult.Package -and $PackageModelResult.Package.PSObject.Properties['flavor']) { [string]$PackageModelResult.Package.flavor } else { $null }
        version      = $PackageModelResult.PackageVersion
        sourceScope  = $SourceScope
        sourceId     = $SourceId
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    Save-PackageModelPackageFileIndex -IndexPath $index.Path -Records $records
}

function Get-PackageModelSourceDefinition {
<#
.SYNOPSIS
Returns a resolved PackageModel source definition by sourceRef.

.DESCRIPTION
Looks up an acquisition source from the effective acquisition environment or
from definition-local upstream sources and returns the normalized source
definition with scope and id metadata.

.PARAMETER PackageModelConfig
The resolved PackageModel config object.

.PARAMETER SourceRef
The acquisition-candidate sourceRef object.

.EXAMPLE
Get-PackageModelSourceDefinition -PackageModelConfig $config -SourceRef $candidate.sourceRef
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelConfig,

        [Parameter(Mandatory = $true)]
        [psobject]$SourceRef
    )

    $scope = [string]$SourceRef.scope
    $id = [string]$SourceRef.id
    $sourceObject = $null

    switch -Exact ($scope) {
        'environment' {
            foreach ($property in @($PackageModelConfig.EnvironmentSources.PSObject.Properties)) {
                if ([string]::Equals([string]$property.Name, $id, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $sourceObject = $property.Value
                    $id = $property.Name
                    break
                }
            }
            if (-not $sourceObject) {
                throw "PackageModel environment source '$($SourceRef.id)' was not found in the effective acquisition environment."
            }
        }
        'definition' {
            foreach ($property in @($PackageModelConfig.DefinitionUpstreamSources.PSObject.Properties)) {
                if ([string]::Equals([string]$property.Name, $id, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $sourceObject = $property.Value
                    $id = $property.Name
                    break
                }
            }
            if (-not $sourceObject) {
                throw "PackageModel definition source '$($SourceRef.id)' was not found in definition '$($PackageModelConfig.DefinitionId)'."
            }
        }
        default {
            throw "Unsupported PackageModel sourceRef.scope '$scope'."
        }
    }

    return [pscustomobject]@{
        Scope           = $scope
        Id              = $id
        Kind            = if ($sourceObject.PSObject.Properties['kind']) { [string]$sourceObject.kind } else { $null }
        BaseUri         = if ($sourceObject.PSObject.Properties['baseUri']) { [string]$sourceObject.baseUri } else { $null }
        BasePath        = if ($sourceObject.PSObject.Properties['basePath']) { [string]$sourceObject.basePath } else { $null }
        RepositoryOwner = if ($sourceObject.PSObject.Properties['repositoryOwner']) { [string]$sourceObject.repositoryOwner } else { $null }
        RepositoryName  = if ($sourceObject.PSObject.Properties['repositoryName']) { [string]$sourceObject.repositoryName } else { $null }
    }
}

function Resolve-PackageModelSource {
<#
.SYNOPSIS
Resolves a concrete source location from a source definition and acquisition candidate.

.DESCRIPTION
Combines a resolved source definition with one release acquisition candidate
and returns the concrete URI or filesystem path that should be used for the
package-file save.

.PARAMETER SourceDefinition
The resolved source definition for the acquisition candidate.

.PARAMETER AcquisitionCandidate
The release acquisition candidate.

.PARAMETER Package
The selected effective release object. Required for source kinds that resolve
through release metadata, such as GitHub release lookup by tag.

.EXAMPLE
Resolve-PackageModelSource -SourceDefinition $source -AcquisitionCandidate $candidate
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SourceDefinition,

        [Parameter(Mandatory = $true)]
        [psobject]$AcquisitionCandidate,

        [AllowNull()]
        [psobject]$Package
    )

    switch -Exact ([string]$SourceDefinition.Kind) {
        'download' {
            if ([string]::IsNullOrWhiteSpace([string]$SourceDefinition.BaseUri)) {
                throw "PackageModel download source '$($SourceDefinition.Id)' does not define baseUri."
            }
            if (-not $AcquisitionCandidate.PSObject.Properties['sourcePath'] -or [string]::IsNullOrWhiteSpace([string]$AcquisitionCandidate.sourcePath)) {
                throw "PackageModel acquisition candidate for '$($SourceDefinition.Id)' does not define sourcePath."
            }

            $baseUriText = ([string]$SourceDefinition.BaseUri).TrimEnd('/') + '/'
            $resolvedUri = [System.Uri]::new([System.Uri]$baseUriText, [string]$AcquisitionCandidate.sourcePath)
            return [pscustomobject]@{
                Kind           = 'download'
                ResolvedSource = $resolvedUri.AbsoluteUri
            }
        }
        'githubRelease' {
            if (-not $Package) {
                throw "PackageModel GitHub release source '$($SourceDefinition.Id)' requires the selected package release context."
            }
            if ([string]::IsNullOrWhiteSpace([string]$SourceDefinition.RepositoryOwner)) {
                throw "PackageModel GitHub release source '$($SourceDefinition.Id)' does not define repositoryOwner."
            }
            if ([string]::IsNullOrWhiteSpace([string]$SourceDefinition.RepositoryName)) {
                throw "PackageModel GitHub release source '$($SourceDefinition.Id)' does not define repositoryName."
            }
            if (-not $Package.PSObject.Properties['releaseTag'] -or [string]::IsNullOrWhiteSpace([string]$Package.releaseTag)) {
                throw "PackageModel release '$($Package.id)' requires releaseTag when acquisition uses GitHub release source '$($SourceDefinition.Id)'."
            }
            if (-not $Package.PSObject.Properties['packageFile'] -or
                $null -eq $Package.packageFile -or
                -not $Package.packageFile.PSObject.Properties['fileName'] -or
                [string]::IsNullOrWhiteSpace([string]$Package.packageFile.fileName)) {
                throw "PackageModel release '$($Package.id)' requires packageFile.fileName when acquisition uses GitHub release source '$($SourceDefinition.Id)'."
            }

            $release = Get-GitHubRelease -RepositoryOwner $SourceDefinition.RepositoryOwner -RepositoryName $SourceDefinition.RepositoryName -ReleaseTag ([string]$Package.releaseTag)
            $assetName = [string]$Package.packageFile.fileName
            $matchedAsset = @(
                $release.Assets | Where-Object {
                    [string]::Equals([string]$_.Name, $assetName, [System.StringComparison]::OrdinalIgnoreCase)
                }
            ) | Select-Object -First 1

            if (-not $matchedAsset) {
                throw "GitHub release '$($Package.releaseTag)' for '$($SourceDefinition.RepositoryOwner)/$($SourceDefinition.RepositoryName)' does not contain asset '$assetName'."
            }
            if ([string]::IsNullOrWhiteSpace([string]$matchedAsset.DownloadUrl)) {
                throw "GitHub release '$($Package.releaseTag)' asset '$assetName' for '$($SourceDefinition.RepositoryOwner)/$($SourceDefinition.RepositoryName)' does not expose a download URL."
            }

            return [pscustomobject]@{
                Kind           = 'download'
                ResolvedSource = [string]$matchedAsset.DownloadUrl
            }
        }
        'filesystem' {
            if (-not $AcquisitionCandidate.PSObject.Properties['sourcePath'] -or [string]::IsNullOrWhiteSpace([string]$AcquisitionCandidate.sourcePath)) {
                throw "PackageModel acquisition candidate for '$($SourceDefinition.Id)' does not define sourcePath."
            }

            $sourcePath = ([string]$AcquisitionCandidate.sourcePath).Trim() -replace '/', '\'
            if ([System.IO.Path]::IsPathRooted($sourcePath)) {
                $resolvedPath = Resolve-PackageModelPathValue -PathValue $sourcePath
            }
            else {
                if ([string]::IsNullOrWhiteSpace([string]$SourceDefinition.BasePath)) {
                    throw "PackageModel filesystem source '$($SourceDefinition.Id)' does not define basePath."
                }

                $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $SourceDefinition.BasePath $sourcePath))
            }

            return [pscustomobject]@{
                Kind           = 'filesystem'
                ResolvedSource = $resolvedPath
            }
        }
        default {
            throw "Unsupported PackageModel source kind '$($SourceDefinition.Kind)'."
        }
    }
}

function Test-PackageModelSavedFile {
<#
.SYNOPSIS
Evaluates a package file against a save-time verification policy.

.DESCRIPTION
Applies the acquisition candidate verification policy to a local file and
returns the verification status, whether the file is accepted, and the expected
and actual SHA256 values when hashing is performed.

.PARAMETER Path
The local file path to verify.

.PARAMETER Verification
The verification policy object from the acquisition candidate.

.EXAMPLE
Test-PackageModelSavedFile -Path .\package.zip -Verification $verification
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [AllowNull()]
        [psobject]$Verification
    )

    if ($Verification -is [System.Collections.IDictionary]) {
        $Verification = [pscustomobject]$Verification
    }

    $authenticode = if ($Verification -and $Verification.PSObject.Properties['authenticode'] -and $null -ne $Verification.authenticode) {
        if ($Verification.authenticode -is [System.Collections.IDictionary]) {
            [pscustomobject]$Verification.authenticode
        }
        else {
            $Verification.authenticode
        }
    }
    else {
        $null
    }

    $mode = if ($Verification -and $Verification.PSObject.Properties['mode'] -and -not [string]::IsNullOrWhiteSpace([string]$Verification.mode)) {
        ([string]$Verification.mode).ToLowerInvariant()
    }
    else {
        'none'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Status       = 'FileMissing'
            Accepted     = $false
            Verified     = $false
            Mode         = $mode
            Algorithm    = $null
            ExpectedHash = $null
            ActualHash   = $null
        }
    }

    if ($mode -eq 'none' -and -not $authenticode) {
        return [pscustomobject]@{
            Status       = 'VerificationSkipped'
            Accepted     = $true
            Verified     = $false
            Mode         = $mode
            Algorithm    = $null
            ExpectedHash = $null
            ActualHash   = $null
            SignatureStatus = $null
            SignerSubject = $null
        }
    }

    $algorithm = if ($Verification -and $Verification.PSObject.Properties['algorithm'] -and -not [string]::IsNullOrWhiteSpace([string]$Verification.algorithm)) {
        ([string]$Verification.algorithm).ToLowerInvariant()
    }
    else {
        'sha256'
    }
    if ($algorithm -ne 'sha256') {
        return [pscustomobject]@{
            Status       = 'VerificationAlgorithmUnsupported'
            Accepted     = $false
            Verified     = $false
            Mode         = $mode
            Algorithm    = $algorithm
            ExpectedHash = $null
            ActualHash   = $null
            SignatureStatus = $null
            SignerSubject = $null
        }
    }

    $expectedHash = if ($Verification -and $Verification.PSObject.Properties['sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Verification.sha256)) {
        ([string]$Verification.sha256).Trim().ToLowerInvariant()
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($expectedHash) -and -not $authenticode) {
        return [pscustomobject]@{
            Status       = if ($mode -eq 'required') { 'VerificationHashMissing' } else { 'VerificationHashMissingOptional' }
            Accepted     = ($mode -ne 'required')
            Verified     = $false
            Mode         = $mode
            Algorithm    = $algorithm
            ExpectedHash = $null
            ActualHash   = $null
            SignatureStatus = $null
            SignerSubject = $null
        }
    }

    $actualHash = $null
    $hashAccepted = $true
    if (-not [string]::IsNullOrWhiteSpace($expectedHash)) {
        $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        $hashAccepted = ($actualHash -eq $expectedHash)
    }

    $signatureStatus = $null
    $signerSubject = $null
    $authenticodeAccepted = $true
    if ($authenticode) {
        $authenticodeAccepted = $false
        try {
            $signature = Get-AuthenticodeSignature -FilePath $Path
            $signatureStatus = $signature.Status.ToString()
            $signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
            $requiresValid = $true
            if ($authenticode.PSObject.Properties['requireValid']) {
                $requiresValid = [bool]$authenticode.requireValid
            }

            $authenticodeAccepted = (-not $requiresValid) -or ($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid)
            if ($authenticodeAccepted -and $authenticode.PSObject.Properties['subjectContains'] -and
                -not [string]::IsNullOrWhiteSpace([string]$authenticode.subjectContains)) {
                $authenticodeAccepted = ($null -ne $signerSubject -and $signerSubject -match [regex]::Escape([string]$authenticode.subjectContains))
            }
        }
        catch {
            $signatureStatus = 'Failed'
            $authenticodeAccepted = $false
        }
    }

    $accepted = $hashAccepted -and $authenticodeAccepted
    $status = if (-not $hashAccepted) {
        'VerificationFailed'
    }
    elseif ($authenticode -and -not $authenticodeAccepted) {
        'AuthenticodeFailed'
    }
    elseif ($authenticode -and [string]::IsNullOrWhiteSpace($expectedHash)) {
        'AuthenticodePassed'
    }
    else {
        'VerificationPassed'
    }

    return [pscustomobject]@{
        Status       = $status
        Accepted     = $accepted
        Verified     = $true
        Mode         = $mode
        Algorithm    = $algorithm
        ExpectedHash = $expectedHash
        ActualHash   = $actualHash
        SignatureStatus = $signatureStatus
        SignerSubject = $signerSubject
    }
}

function Save-PackageModelDownloadFile {
<#
.SYNOPSIS
Downloads a package file to a local path.

.DESCRIPTION
Uses the module's download helper to fetch a package file from an HTTP or HTTPS
source into a staging path for later verification and promotion.

.PARAMETER Uri
The package download URI.

.PARAMETER TargetPath
The local staging path that should receive the file.

.EXAMPLE
Save-PackageModelDownloadFile -Uri https://example.org/package.zip -TargetPath C:\Temp\package.zip
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    Invoke-WebRequestEx -Uri $Uri -OutFile $TargetPath -UseBasicParsing
    return (Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop).Path
}

function Save-PackageModelFilesystemFile {
<#
.SYNOPSIS
Copies a package file from a filesystem source.

.DESCRIPTION
Copies a package file from a local or network filesystem path into a staging
path for later verification and promotion.

.PARAMETER SourcePath
The local or network path that contains the package file.

.PARAMETER TargetPath
The local staging path that should receive the copy.

.EXAMPLE
Save-PackageModelFilesystemFile -SourcePath \\server\share\package.zip -TargetPath C:\Temp\package.zip
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "PackageModel filesystem source '$SourcePath' does not exist."
    }

    return (Copy-FileToPath -SourcePath $SourcePath -TargetPath $TargetPath -Overwrite)
}

function Test-PackageModelPackageFileAcquisitionRequired {
<#
.SYNOPSIS
Determines whether the selected release needs an acquired package file.

.DESCRIPTION
Interprets the current install kind so acquisition is skipped for install flows
that do not consume a saved package file.

.PARAMETER Package
The selected release object.

.EXAMPLE
Test-PackageModelPackageFileAcquisitionRequired -Package $package
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Package
    )

    $installKind = if ($Package.install -and $Package.install.PSObject.Properties['kind']) {
        [string]$Package.install.kind
    }
    else {
        $null
    }

    switch -Exact ($installKind) {
        'expandArchive' { return $true }
        'placePackageFile' { return $true }
        'runInstaller' {
            return (-not $Package.install.PSObject.Properties['commandPath'] -or [string]::IsNullOrWhiteSpace([string]$Package.install.commandPath))
        }
        default { return $false }
    }
}

function Get-PackageModelPreferredVerification {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$AcquisitionCandidates
    )

    foreach ($candidate in @($AcquisitionCandidates)) {
        if ($candidate.PSObject.Properties['verification'] -and $null -ne $candidate.verification) {
            return $candidate.verification
        }
    }

    return [pscustomobject]@{ mode = 'none' }
}

function Resolve-PackageModelAcquisitionCandidateVerification {
<#
.SYNOPSIS
Builds the effective verification policy for one acquisition candidate.

.DESCRIPTION
Combines acquisition-candidate verification mode with canonical package-file
integrity metadata when present, while remaining compatible with older
candidate-local hash definitions.

.PARAMETER Package
The selected effective release.

.PARAMETER AcquisitionCandidate
The raw acquisition candidate.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Package,

        [AllowNull()]
        [psobject]$AcquisitionCandidate
    )

    $candidateVerification = if ($AcquisitionCandidate -and $AcquisitionCandidate.PSObject.Properties['verification']) {
        $AcquisitionCandidate.verification
    }
    else {
        $null
    }
    if ($candidateVerification -is [System.Collections.IDictionary]) {
        $candidateVerification = [pscustomobject]$candidateVerification
    }

    $packageIntegrity = if ($Package -and
        $Package.PSObject.Properties['packageFile'] -and
        $Package.packageFile -and
        $Package.packageFile.PSObject.Properties['integrity']) {
        $Package.packageFile.integrity
    }
    else {
        $null
    }
    if ($packageIntegrity -is [System.Collections.IDictionary]) {
        $packageIntegrity = [pscustomobject]$packageIntegrity
    }

    $packageAuthenticode = if ($Package -and
        $Package.PSObject.Properties['packageFile'] -and
        $Package.packageFile -and
        $Package.packageFile.PSObject.Properties['authenticode']) {
        $Package.packageFile.authenticode
    }
    else {
        $null
    }
    if ($packageAuthenticode -is [System.Collections.IDictionary]) {
        $packageAuthenticode = [pscustomobject]$packageAuthenticode
    }

    $mode = if ($candidateVerification -and $candidateVerification.PSObject.Properties['mode'] -and -not [string]::IsNullOrWhiteSpace([string]$candidateVerification.mode)) {
        [string]$candidateVerification.mode
    }
    else {
        'none'
    }

    $algorithm = if ($packageIntegrity -and $packageIntegrity.PSObject.Properties['algorithm'] -and -not [string]::IsNullOrWhiteSpace([string]$packageIntegrity.algorithm)) {
        [string]$packageIntegrity.algorithm
    }
    elseif ($candidateVerification -and $candidateVerification.PSObject.Properties['algorithm'] -and -not [string]::IsNullOrWhiteSpace([string]$candidateVerification.algorithm)) {
        [string]$candidateVerification.algorithm
    }
    else {
        'sha256'
    }

    $sha256 = if ($packageIntegrity -and $packageIntegrity.PSObject.Properties['sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$packageIntegrity.sha256)) {
        [string]$packageIntegrity.sha256
    }
    elseif ($candidateVerification -and $candidateVerification.PSObject.Properties['sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$candidateVerification.sha256)) {
        [string]$candidateVerification.sha256
    }
    else {
        $null
    }

    $verification = [ordered]@{
        mode = $mode
    }
    if (-not [string]::IsNullOrWhiteSpace($algorithm)) {
        $verification.algorithm = $algorithm
    }
    if (-not [string]::IsNullOrWhiteSpace($sha256)) {
        $verification.sha256 = $sha256
    }
    if ($packageAuthenticode) {
        $verification.authenticode = $packageAuthenticode
    }

    return [pscustomobject]$verification
}

function Get-PackageModelPackageDepotSources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelConfig
    )

    $orderedSources = New-Object System.Collections.Generic.List[object]

    foreach ($property in @($PackageModelConfig.EnvironmentSources.PSObject.Properties)) {
        $source = $property.Value
        if (-not [string]::Equals([string]$source.kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ([string]::Equals([string]$property.Name, 'defaultPackageDepot', [System.StringComparison]::OrdinalIgnoreCase)) {
            $orderedSources.Add([pscustomobject]@{
                id       = $property.Name
                priority = 0
            }) | Out-Null
        }
        else {
            $orderedSources.Add([pscustomobject]@{
                id       = $property.Name
                priority = 1000
            }) | Out-Null
        }
    }

    return @(
        $orderedSources.ToArray() |
            Sort-Object -Property priority, id
    )
}

function Build-PackageModelAcquisitionPlan {
<#
.SYNOPSIS
Builds the internal PackageModel acquisition plan for the selected release.

.DESCRIPTION
Normalizes the ordered acquisition candidates and captures the install-workspace
and default-depot targets so later package-file save steps can execute linearly.

.PARAMETER PackageModelResult
The PackageModel result object to enrich.

.EXAMPLE
Build-PackageModelAcquisitionPlan -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $package = $PackageModelResult.Package
    if (-not $package) {
        throw 'Build-PackageModelAcquisitionPlan requires a selected release.'
    }

    if ([string]::Equals([string]$PackageModelResult.InstallOrigin, 'AlreadySatisfied', [System.StringComparison]::OrdinalIgnoreCase)) {
        $PackageModelResult.AcquisitionPlan = [pscustomobject]@{
            PackageFileRequired      = $false
            InstallWorkspaceFilePath = $PackageModelResult.PackageFilePath
            Candidates               = @()
        }
        Write-PackageModelExecutionMessage -Message '[STATE] Acquisition skipped because package target is already satisfied.'
        return $PackageModelResult
    }

    $requiresPackageFile = Test-PackageModelPackageFileAcquisitionRequired -Package $package
    $orderedCandidates = New-Object System.Collections.Generic.List[object]
    if ($requiresPackageFile -and $package.PSObject.Properties['acquisitionCandidates']) {
        foreach ($candidate in @($package.acquisitionCandidates | Sort-Object -Property @{
                    Expression = { if ($_.PSObject.Properties['priority']) { [int]$_.priority } else { [int]::MaxValue } }
                })) {
            $resolvedVerification = Resolve-PackageModelAcquisitionCandidateVerification -Package $package -AcquisitionCandidate $candidate
            switch -Exact ([string]$candidate.kind) {
                'packageDepot' {
                    $resolvedDepotSourcePath = Join-Path $PackageModelResult.PackageFileRelativeDirectory ([string]$package.packageFile.fileName)
                    foreach ($depotSource in @(Get-PackageModelPackageDepotSources -PackageModelConfig $PackageModelResult.PackageModelConfig)) {
                        $orderedCandidates.Add([pscustomobject]@{
                            kind         = 'packageDepot'
                            priority     = if ($candidate.PSObject.Properties['priority']) { [int]$candidate.priority } else { [int]::MaxValue }
                            sourceRef    = [pscustomobject]@{
                                scope = 'environment'
                                id    = $depotSource.id
                            }
                            sourcePath   = $resolvedDepotSourcePath
                            verification = $resolvedVerification
                        }) | Out-Null
                    }
                }
                'download' {
                    $orderedCandidates.Add([pscustomobject]@{
                        kind         = 'download'
                        priority     = if ($candidate.PSObject.Properties['priority']) { [int]$candidate.priority } else { [int]::MaxValue }
                        sourceRef    = [pscustomobject]@{
                            scope = 'definition'
                            id    = [string]$candidate.sourceId
                        }
                        sourcePath   = [string]$candidate.sourcePath
                        verification = $resolvedVerification
                    }) | Out-Null
                }
                'filesystem' {
                    $orderedCandidates.Add([pscustomobject]@{
                        kind         = 'filesystem'
                        priority     = if ($candidate.PSObject.Properties['priority']) { [int]$candidate.priority } else { [int]::MaxValue }
                        sourceRef    = if ($candidate.PSObject.Properties['sourceId'] -and -not [string]::IsNullOrWhiteSpace([string]$candidate.sourceId)) {
                            [pscustomobject]@{
                                scope = 'environment'
                                id    = [string]$candidate.sourceId
                            }
                        }
                        else {
                            $null
                        }
                        sourcePath   = [string]$candidate.sourcePath
                        verification = $resolvedVerification
                    }) | Out-Null
                }
            }
        }
    }

    $PackageModelResult.AcquisitionPlan = [pscustomobject]@{
        PackageFileRequired    = $requiresPackageFile
        InstallWorkspaceFilePath = $PackageModelResult.PackageFilePath
        DefaultPackageDepotFilePath = $PackageModelResult.DefaultPackageDepotFilePath
        Candidates             = @(
            $orderedCandidates.ToArray() |
                Sort-Object -Property priority, @{
                    Expression = {
                        if ($_.sourceRef) { [string]$_.sourceRef.id } else { [string]::Empty }
                    }
                }
        )
    }

    $candidateSummary = @(
        foreach ($candidate in @($PackageModelResult.AcquisitionPlan.Candidates)) {
            $sourceSummary = if ($candidate.sourceRef) {
                '{0}:{1}' -f [string]$candidate.sourceRef.scope, [string]$candidate.sourceRef.id
            }
            else {
                'direct'
            }
            '{0}@{1}->{2}' -f [string]$candidate.kind, [string]$candidate.priority, $sourceSummary
        }
    ) -join ', '
    if ([string]::IsNullOrWhiteSpace($candidateSummary)) {
        $candidateSummary = '<none>'
    }
    Write-PackageModelExecutionMessage -Message ("[STATE] Acquisition plan packageFileRequired='{0}' with {1} candidate(s): {2}." -f $requiresPackageFile, @($PackageModelResult.AcquisitionPlan.Candidates).Count, $candidateSummary)

    return $PackageModelResult
}

function Save-PackageModelPackageFile {
<#
.SYNOPSIS
Ensures the selected package file is present in the install workspace.

.DESCRIPTION
Reuses an already-present verified package file when possible, then checks the
default package depot, and otherwise attempts each configured acquisition
candidate in priority order until one succeeds or all candidates fail.

.PARAMETER PackageModelResult
The PackageModel result object to enrich.

.EXAMPLE
Save-PackageModelPackageFile -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $package = $PackageModelResult.Package
    $packageModelConfig = $PackageModelResult.PackageModelConfig

    if (-not $package -or -not $package.PSObject.Properties['install'] -or -not $package.install) {
        throw 'Save-PackageModelPackageFile requires a selected release with install settings.'
    }

    if ($PackageModelResult.ExistingPackage -and
        $PackageModelResult.ExistingPackage.PSObject.Properties['Decision'] -and
        $PackageModelResult.ExistingPackage.Decision -in @('ReusePackageModelOwned', 'AdoptExternal')) {
        $PackageModelResult.PackageFileSave = [pscustomobject]@{
            Success         = $true
            Status          = 'Skipped'
            PackageFilePath = $PackageModelResult.PackageFilePath
            SelectedSource  = $null
            Verification    = $null
            Attempts        = @()
            FailureReason   = $null
            ErrorMessage    = $null
        }
        Write-PackageModelExecutionMessage -Message ("[STATE] Package file step skipped because existing install decision is '{0}'." -f [string]$PackageModelResult.ExistingPackage.Decision)
        return $PackageModelResult
    }

    if (-not $PackageModelResult.AcquisitionPlan) {
        $PackageModelResult = Build-PackageModelAcquisitionPlan -PackageModelResult $PackageModelResult
    }

    if (-not $PackageModelResult.AcquisitionPlan.PackageFileRequired) {
        $PackageModelResult.PackageFileSave = [pscustomobject]@{
            Success         = $true
            Status          = 'Skipped'
            PackageFilePath = $PackageModelResult.PackageFilePath
            SelectedSource  = $null
            Verification    = $null
            Attempts        = @()
            FailureReason   = $null
            ErrorMessage    = $null
        }
        Write-PackageModelExecutionMessage -Message "[STATE] Package file step skipped because the selected install kind does not require a saved package file."
        return $PackageModelResult
    }

    if ([string]::IsNullOrWhiteSpace($PackageModelResult.PackageFilePath)) {
        throw "PackageModel release '$($package.id)' does not define packageFile.fileName."
    }

    $orderedCandidates = @($PackageModelResult.AcquisitionPlan.Candidates)
    if (-not $orderedCandidates) {
        throw "PackageModel release '$($package.id)' does not define any acquisition candidates."
    }

    $attempts = New-Object System.Collections.Generic.List[object]
    $preferredVerification = Get-PackageModelPreferredVerification -AcquisitionCandidates $orderedCandidates

    if (Test-Path -LiteralPath $PackageModelResult.PackageFilePath) {
        $verification = Test-PackageModelSavedFile -Path $PackageModelResult.PackageFilePath -Verification $preferredVerification
        $attempts.Add([pscustomobject]@{
            AttemptType        = 'ReuseCheck'
            Status             = if ($verification.Accepted) { 'ReusedPackageFile' } else { 'ReuseRejected' }
            SourceScope        = 'installWorkspace'
            SourceId           = 'installWorkspace'
            SourceKind         = 'filesystem'
            ResolvedSource     = $PackageModelResult.PackageFilePath
            VerificationStatus = $verification.Status
            ErrorMessage       = if ($verification.Accepted) { $null } else { 'Existing install-workspace file did not satisfy verification.' }
        }) | Out-Null

        if ($verification.Accepted) {
            Update-PackageModelPackageFileIndexRecord -PackageModelResult $PackageModelResult -PackageFilePath $PackageModelResult.PackageFilePath -SourceScope 'installWorkspace' -SourceId 'installWorkspace'
            $PackageModelResult.PackageFileSave = [pscustomobject]@{
                Success         = $true
                Status          = 'ReusedPackageFile'
                PackageFilePath = $PackageModelResult.PackageFilePath
                SelectedSource  = [pscustomobject]@{
                    SourceScope = 'installWorkspace'
                    SourceId    = 'installWorkspace'
                    SourceKind  = 'filesystem'
                    ResolvedSource = $PackageModelResult.PackageFilePath
                }
                Verification    = $verification
                Attempts        = @($attempts.ToArray())
                FailureReason   = $null
                ErrorMessage    = $null
            }
            Write-PackageModelExecutionMessage -Message ("[ACTION] Reused install workspace package file '{0}'." -f $PackageModelResult.PackageFilePath)
            return $PackageModelResult
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($PackageModelResult.DefaultPackageDepotFilePath) -and
        (Test-Path -LiteralPath $PackageModelResult.DefaultPackageDepotFilePath)) {
        $verification = Test-PackageModelSavedFile -Path $PackageModelResult.DefaultPackageDepotFilePath -Verification $preferredVerification
        $attempts.Add([pscustomobject]@{
            AttemptType        = 'DepotReuseCheck'
            Status             = if ($verification.Accepted) { 'HydratedFromDefaultPackageDepot' } else { 'DefaultPackageDepotRejected' }
            SourceScope        = 'environment'
            SourceId           = 'defaultPackageDepot'
            SourceKind         = 'filesystem'
            ResolvedSource     = $PackageModelResult.DefaultPackageDepotFilePath
            VerificationStatus = $verification.Status
            ErrorMessage       = if ($verification.Accepted) { $null } else { 'Default package-depot artifact did not satisfy verification.' }
        }) | Out-Null

        if ($verification.Accepted) {
            $null = New-Item -ItemType Directory -Path $PackageModelResult.InstallWorkspaceDirectory -Force
            $null = Copy-FileToPath -SourcePath $PackageModelResult.DefaultPackageDepotFilePath -TargetPath $PackageModelResult.PackageFilePath -Overwrite
            Update-PackageModelPackageFileIndexRecord -PackageModelResult $PackageModelResult -PackageFilePath $PackageModelResult.DefaultPackageDepotFilePath -SourceScope 'environment' -SourceId 'defaultPackageDepot'
            Update-PackageModelPackageFileIndexRecord -PackageModelResult $PackageModelResult -PackageFilePath $PackageModelResult.PackageFilePath -SourceScope 'environment' -SourceId 'defaultPackageDepot'
            $PackageModelResult.PackageFileSave = [pscustomobject]@{
                Success         = $true
                Status          = 'HydratedFromDefaultPackageDepot'
                PackageFilePath = $PackageModelResult.PackageFilePath
                SelectedSource  = [pscustomobject]@{
                    SourceScope    = 'environment'
                    SourceId       = 'defaultPackageDepot'
                    SourceKind     = 'filesystem'
                    ResolvedSource = $PackageModelResult.DefaultPackageDepotFilePath
                }
                Verification    = $verification
                Attempts        = @($attempts.ToArray())
                FailureReason   = $null
                ErrorMessage    = $null
            }
            Write-PackageModelExecutionMessage -Message ("[ACTION] Hydrated install workspace package file from default package depot '{0}'." -f $PackageModelResult.DefaultPackageDepotFilePath)
            return $PackageModelResult
        }
    }

    $null = New-Item -ItemType Directory -Path $PackageModelResult.InstallWorkspaceDirectory -Force

    foreach ($candidate in $orderedCandidates) {
        $sourceDefinition = $null
        $resolvedSource = $null
        $verification = $null
        $stagingPath = '{0}.{1}.partial' -f $PackageModelResult.PackageFilePath, ([guid]::NewGuid().ToString('N'))

        try {
            if ($candidate.sourceRef) {
                $sourceDefinition = Get-PackageModelSourceDefinition -PackageModelConfig $packageModelConfig -SourceRef $candidate.sourceRef
            }
            elseif ([string]::Equals([string]$candidate.kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
                $sourceDefinition = [pscustomobject]@{
                    Scope   = 'direct'
                    Id      = 'directFilesystem'
                    Kind    = 'filesystem'
                    BaseUri = $null
                    BasePath = $null
                }
            }
            else {
                throw "PackageModel acquisition candidate kind '$($candidate.kind)' could not be resolved to a source definition."
            }
            $resolvedSource = Resolve-PackageModelSource -SourceDefinition $sourceDefinition -AcquisitionCandidate $candidate -Package $package

            switch -Exact ([string]$resolvedSource.Kind) {
                'download' {
                    $null = Save-PackageModelDownloadFile -Uri $resolvedSource.ResolvedSource -TargetPath $stagingPath
                }
                'filesystem' {
                    $null = Save-PackageModelFilesystemFile -SourcePath $resolvedSource.ResolvedSource -TargetPath $stagingPath
                }
                default {
                    throw "Unsupported package-file source kind '$($resolvedSource.Kind)'."
                }
            }

            $verification = Test-PackageModelSavedFile -Path $stagingPath -Verification $candidate.verification
            if (-not $verification.Accepted) {
                if (Test-Path -LiteralPath $stagingPath) {
                    Remove-Item -LiteralPath $stagingPath -Force -ErrorAction SilentlyContinue
                }

                $attempts.Add([pscustomobject]@{
                    AttemptType        = 'Save'
                    Status             = 'Failed'
                    SourceScope        = $sourceDefinition.Scope
                    SourceId           = $sourceDefinition.Id
                    SourceKind         = $resolvedSource.Kind
                    ResolvedSource     = $resolvedSource.ResolvedSource
                    VerificationStatus = $verification.Status
                    ErrorMessage       = 'Saved package file did not satisfy verification.'
                }) | Out-Null

                if (-not $packageModelConfig.AllowAcquisitionFallback) {
                    break
                }

                continue
            }

            if (Test-Path -LiteralPath $PackageModelResult.PackageFilePath) {
                Remove-Item -LiteralPath $PackageModelResult.PackageFilePath -Force
            }
            Move-Item -LiteralPath $stagingPath -Destination $PackageModelResult.PackageFilePath -Force
            Update-PackageModelPackageFileIndexRecord -PackageModelResult $PackageModelResult -PackageFilePath $PackageModelResult.PackageFilePath -SourceScope $sourceDefinition.Scope -SourceId $sourceDefinition.Id

            if ([string]::Equals([string]$resolvedSource.Kind, 'download', [System.StringComparison]::OrdinalIgnoreCase) -and
                $packageModelConfig.MirrorDownloadedArtifactsToDefaultPackageDepot -and
                -not [string]::IsNullOrWhiteSpace($PackageModelResult.DefaultPackageDepotFilePath)) {
                $null = New-Item -ItemType Directory -Path (Split-Path -Parent $PackageModelResult.DefaultPackageDepotFilePath) -Force
                $null = Copy-FileToPath -SourcePath $PackageModelResult.PackageFilePath -TargetPath $PackageModelResult.DefaultPackageDepotFilePath -Overwrite
                Update-PackageModelPackageFileIndexRecord -PackageModelResult $PackageModelResult -PackageFilePath $PackageModelResult.DefaultPackageDepotFilePath -SourceScope $sourceDefinition.Scope -SourceId $sourceDefinition.Id
            }
            elseif ([string]::Equals([string]$sourceDefinition.Scope, 'environment', [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$sourceDefinition.Id, 'defaultPackageDepot', [System.StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::IsNullOrWhiteSpace($PackageModelResult.DefaultPackageDepotFilePath)) {
                Update-PackageModelPackageFileIndexRecord -PackageModelResult $PackageModelResult -PackageFilePath $PackageModelResult.DefaultPackageDepotFilePath -SourceScope 'environment' -SourceId 'defaultPackageDepot'
            }

            $attempts.Add([pscustomobject]@{
                AttemptType        = 'Save'
                Status             = 'SavedPackageFile'
                SourceScope        = $sourceDefinition.Scope
                SourceId           = $sourceDefinition.Id
                SourceKind         = $resolvedSource.Kind
                ResolvedSource     = $resolvedSource.ResolvedSource
                VerificationStatus = $verification.Status
                ErrorMessage       = $null
            }) | Out-Null

            $PackageModelResult.PackageFileSave = [pscustomobject]@{
                Success         = $true
                Status          = 'SavedPackageFile'
                PackageFilePath = $PackageModelResult.PackageFilePath
                SelectedSource  = [pscustomobject]@{
                    SourceScope    = $sourceDefinition.Scope
                    SourceId       = $sourceDefinition.Id
                    SourceKind     = $resolvedSource.Kind
                    ResolvedSource = $resolvedSource.ResolvedSource
                }
                Verification    = $verification
                Attempts        = @($attempts.ToArray())
                FailureReason   = $null
                ErrorMessage    = $null
            }
            Write-PackageModelExecutionMessage -Message ("[ACTION] Saved package file from '{0}:{1}'." -f $sourceDefinition.Scope, $sourceDefinition.Id)
            return $PackageModelResult
        }
        catch {
            if (Test-Path -LiteralPath $stagingPath) {
                Remove-Item -LiteralPath $stagingPath -Force -ErrorAction SilentlyContinue
            }

            $attempts.Add([pscustomobject]@{
                AttemptType        = 'Save'
                Status             = 'Failed'
                SourceScope        = if ($sourceDefinition) { $sourceDefinition.Scope } elseif ($candidate.sourceRef) { [string]$candidate.sourceRef.scope } else { $null }
                SourceId           = if ($sourceDefinition) { $sourceDefinition.Id } elseif ($candidate.sourceRef) { [string]$candidate.sourceRef.id } else { $null }
                SourceKind         = if ($resolvedSource) { $resolvedSource.Kind } else { $null }
                ResolvedSource     = if ($resolvedSource) { $resolvedSource.ResolvedSource } else { $null }
                VerificationStatus = if ($verification) { $verification.Status } else { $null }
                ErrorMessage       = $_.Exception.Message
            }) | Out-Null

            if (-not $packageModelConfig.AllowAcquisitionFallback) {
                break
            }
        }
    }

    $PackageModelResult.PackageFileSave = [pscustomobject]@{
        Success         = $false
        Status          = 'Failed'
        PackageFilePath = $PackageModelResult.PackageFilePath
        SelectedSource  = $null
        Verification    = $null
        Attempts        = @($attempts.ToArray())
        FailureReason   = 'AllSourcesFailed'
        ErrorMessage    = "All acquisition candidates failed for PackageModel release '$($package.id)'."
    }

    Write-PackageModelExecutionMessage -Level 'ERR' -Message ("[ACTION] All acquisition candidates failed for release '{0}'." -f $package.id)

    return $PackageModelResult
}

