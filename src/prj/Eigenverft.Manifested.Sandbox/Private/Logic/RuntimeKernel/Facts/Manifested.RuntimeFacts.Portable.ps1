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

function Expand-ManifestedHostPathPattern {
    [CmdletBinding()]
    param(
        [string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        return $null
    }

    return ($Pattern.
        Replace('{ProgramFiles}', $(if ($env:ProgramFiles) { $env:ProgramFiles } else { '' })).
        Replace('{LocalAppData}', $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { '' })).
        Replace('{UserProfile}', $(if ($env:USERPROFILE) { $env:USERPROFILE } else { '' })))
}

function Get-ManifestedManagedVersionFolderName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Block,

        [string]$Version
    )

    $template = if ($Block.PSObject.Properties.Match('versionFolderTemplate').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Block.versionFolderTemplate)) {
        $Block.versionFolderTemplate
    }
    else {
        '{version}'
    }

    $versionNoPrefixV = if ([string]::IsNullOrWhiteSpace($Version)) { $null } else { $Version.TrimStart('v', 'V') }
    return (($template -replace '\{versionNoPrefixV\}', [regex]::Escape($(if ($null -ne $versionNoPrefixV) { $versionNoPrefixV } else { '' }))) -replace '\{version\}', [regex]::Escape($(if ($null -ne $Version) { $Version } else { '' })))
}

function Get-ManifestedManagedVersionFolderPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Block,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Layout,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $toolsRootLayoutProperty = $Block.toolsRootLayoutProperty
    if (-not $Layout.PSObject.Properties.Match($toolsRootLayoutProperty).Count) {
        throw "Definition references unknown layout property '$toolsRootLayoutProperty'."
    }

    $toolsRoot = $Layout.$toolsRootLayoutProperty
    $versionFolderName = Expand-ManifestedDefinitionTemplate -Template $(if ($Block.PSObject.Properties.Match('versionFolderTemplate').Count -gt 0) { $Block.versionFolderTemplate } else { '{version}' }) -Version $Version -TagName $Version -Flavor $null
    $versionFolderName = $versionFolderName.Replace('{versionNoPrefixV}', $Version.TrimStart('v', 'V'))
    return (Join-Path $toolsRoot $versionFolderName)
}

function Get-ManifestedPortableResolvedNamedPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RuntimeBlock,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $namedPaths = [ordered]@{}

    if ($RuntimeBlock.PSObject.Properties.Match('namedFilePaths').Count -gt 0 -and $RuntimeBlock.namedFilePaths) {
        foreach ($property in @($RuntimeBlock.namedFilePaths.PSObject.Properties)) {
            $namedPaths[$property.Name] = (Get-ManifestedFullPath -Path (Join-Path $RuntimeHome ([string]$property.Value)))
        }
    }

    if ($RuntimeBlock.PSObject.Properties.Match('namedDirectoryPaths').Count -gt 0 -and $RuntimeBlock.namedDirectoryPaths) {
        foreach ($property in @($RuntimeBlock.namedDirectoryPaths.PSObject.Properties)) {
            $namedPaths[$property.Name] = (Get-ManifestedFullPath -Path (Join-Path $RuntimeHome ([string]$property.Value)))
        }
    }

    return $namedPaths
}

function Get-ManifestedPortableResolvedPathFromCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome,

        [string[]]$Candidates = @()
    )

    foreach ($candidate in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $candidatePath = Join-Path $RuntimeHome $candidate
        if (Test-Path -LiteralPath $candidatePath) {
            return (Get-ManifestedFullPath -Path $candidatePath)
        }
    }

    if (@($Candidates).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Candidates[0])) {
        return (Get-ManifestedFullPath -Path (Join-Path $RuntimeHome $Candidates[0]))
    }

    return $null
}

function Get-ManifestedPortableReportedVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$VersionProbe,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $executablePath = Get-ManifestedPortableResolvedPathFromCandidates -RuntimeHome $RuntimeHome -Candidates @($VersionProbe.executableCandidates)
    if ([string]::IsNullOrWhiteSpace($executablePath) -or -not (Test-Path -LiteralPath $executablePath)) {
        return [pscustomobject]@{
            ExecutablePath = $executablePath
            RawOutput      = $null
            Version        = $null
        }
    }

    $rawOutput = $null
    try {
        $rawOutput = (& $executablePath @($VersionProbe.arguments) 2>$null | Select-Object -First 1)
        if ($rawOutput) {
            $rawOutput = $rawOutput.ToString().Trim()
        }
    }
    catch {
        $rawOutput = $null
    }

    $version = $null
    if (-not [string]::IsNullOrWhiteSpace($rawOutput)) {
        $pattern = if ($VersionProbe.PSObject.Properties.Match('regex').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($VersionProbe.regex)) { $VersionProbe.regex } else { '(\d+(?:\.\d+){1,3})' }
        $match = [regex]::Match($rawOutput, $pattern)
        if ($match.Success) {
            $version = if ($match.Groups.Count -gt 1) { $match.Groups[1].Value } else { $match.Value }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($version) -and $VersionProbe.PSObject.Properties.Match('normalizeRegex').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($VersionProbe.normalizeRegex)) {
        $replacement = if ($VersionProbe.PSObject.Properties.Match('normalizeReplacement').Count -gt 0) { $VersionProbe.normalizeReplacement } else { '$1' }
        $version = ($version -replace $VersionProbe.normalizeRegex, $replacement)
    }

    if (-not [string]::IsNullOrWhiteSpace($version) -and $VersionProbe.PSObject.Properties.Match('prefix').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($VersionProbe.prefix) -and -not $version.StartsWith($VersionProbe.prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $version = ($VersionProbe.prefix + $version)
    }

    return [pscustomobject]@{
        ExecutablePath = $executablePath
        RawOutput      = $rawOutput
        Version        = $version
    }
}

function Test-ManifestedPortableRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $runtimeBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'portableRuntime'
    if (-not $runtimeBlock) {
        throw "Portable runtime facts are not defined for '$($Definition.commandName)'."
    }

    $exists = (Test-Path -LiteralPath $RuntimeHome)
    $requiredGroups = if ($runtimeBlock.PSObject.Properties.Match('requiredPathGroups').Count -gt 0) { @($runtimeBlock.requiredPathGroups) } else { @() }
    $resolvedGroups = New-Object System.Collections.Generic.List[object]
    $hasRequiredFiles = $exists
    $failureReason = $null

    if (-not $exists) {
        $hasRequiredFiles = $false
        $failureReason = 'RuntimeHomeMissing'
    }
    else {
        foreach ($group in @($requiredGroups)) {
            $candidateGroup = @()
            foreach ($candidate in @($group)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
                    $candidateGroup += [string]$candidate
                }
            }

            $resolvedPath = Get-ManifestedPortableResolvedPathFromCandidates -RuntimeHome $RuntimeHome -Candidates $candidateGroup
            $groupResolved = (-not [string]::IsNullOrWhiteSpace($resolvedPath)) -and (Test-Path -LiteralPath $resolvedPath)
            if (-not $groupResolved) {
                $hasRequiredFiles = $false
                $failureReason = 'RequiredFilesMissing'
            }

            $resolvedGroups.Add([pscustomobject]@{
                    Candidates = @($candidateGroup)
                    Path       = $resolvedPath
                    Exists     = $groupResolved
                }) | Out-Null
        }
    }

    $namedPaths = Get-ManifestedPortableResolvedNamedPaths -RuntimeBlock $runtimeBlock -RuntimeHome $RuntimeHome
    $versionProbe = if ($runtimeBlock.PSObject.Properties.Match('versionProbe').Count -gt 0) { $runtimeBlock.versionProbe } else { $null }
    $versionResult = $null
    $reportedVersion = $null
    if ($exists -and $hasRequiredFiles -and $versionProbe) {
        $versionResult = Get-ManifestedPortableReportedVersion -VersionProbe $versionProbe -RuntimeHome $RuntimeHome
        $reportedVersion = $versionResult.Version
        if ([string]::IsNullOrWhiteSpace($reportedVersion)) {
            $failureReason = 'VersionProbeFailed'
        }
    }

    $hasRequiredDirectories = $true
    if ($exists -and $runtimeBlock.PSObject.Properties.Match('requiredDirectories').Count -gt 0) {
        foreach ($relativeDirectory in @($runtimeBlock.requiredDirectories)) {
            if ([string]::IsNullOrWhiteSpace([string]$relativeDirectory)) {
                continue
            }

            if (-not (Test-Path -LiteralPath (Join-Path $RuntimeHome ([string]$relativeDirectory)))) {
                $hasRequiredDirectories = $false
                if ([string]::IsNullOrWhiteSpace($failureReason)) {
                    $failureReason = 'RequiredDirectoriesMissing'
                }
                break
            }
        }
    }

    $signatureStatus = $null
    $signerSubject = $null
    $signatureValid = $true
    if ($exists -and $hasRequiredFiles -and $runtimeBlock.PSObject.Properties.Match('signerSubjectMatch').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($runtimeBlock.signerSubjectMatch)) {
        $signatureValid = $false
        $signatureTarget = if ($versionResult -and -not [string]::IsNullOrWhiteSpace($versionResult.ExecutablePath)) { $versionResult.ExecutablePath } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($signatureTarget) -and (Test-Path -LiteralPath $signatureTarget)) {
            try {
                $signature = Get-AuthenticodeSignature -FilePath $signatureTarget
                $signatureStatus = $signature.Status.ToString()
                $signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
                $signatureValid = ($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid) -and ($signerSubject -match [string]$runtimeBlock.signerSubjectMatch)
            }
            catch {
                $signatureValid = $false
            }
        }

        if (-not $signatureValid -and [string]::IsNullOrWhiteSpace($failureReason)) {
            $failureReason = 'SignatureValidationFailed'
        }
    }

    $fileInfoValid = $true
    $fileInfoSnapshot = [ordered]@{}
    if ($exists -and $hasRequiredFiles -and $runtimeBlock.PSObject.Properties.Match('fileInfoAnyOf').Count -gt 0 -and $runtimeBlock.fileInfoAnyOf) {
        $fileInfoValid = $false
        $fileInfoTarget = if ($versionResult -and -not [string]::IsNullOrWhiteSpace($versionResult.ExecutablePath)) { $versionResult.ExecutablePath } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($fileInfoTarget) -and (Test-Path -LiteralPath $fileInfoTarget)) {
            try {
                $item = Get-Item -LiteralPath $fileInfoTarget -ErrorAction Stop
                foreach ($property in @($runtimeBlock.fileInfoAnyOf.PSObject.Properties)) {
                    $actualValue = if ($item.VersionInfo.PSObject.Properties.Match($property.Name).Count -gt 0) { [string]$item.VersionInfo.($property.Name) } else { $null }
                    $fileInfoSnapshot[$property.Name] = $actualValue

                    foreach ($allowedValue in @($property.Value)) {
                        if ($actualValue -eq [string]$allowedValue) {
                            $fileInfoValid = $true
                            break
                        }
                    }

                    if ($fileInfoValid) {
                        break
                    }
                }
            }
            catch {
                $fileInfoValid = $false
            }
        }

        if (-not $fileInfoValid -and [string]::IsNullOrWhiteSpace($failureReason)) {
            $failureReason = 'FileInfoValidationFailed'
        }
    }

    $isUsable = ($exists -and $hasRequiredFiles -and $hasRequiredDirectories -and $signatureValid -and $fileInfoValid -and ($null -eq $versionProbe -or -not [string]::IsNullOrWhiteSpace($reportedVersion)))

    $portableFailureReason = if ($isUsable) { $null } else { $failureReason }
    $portableExecutablePath = if ($versionResult) { $versionResult.ExecutablePath } else { $null }
    $portableRawVersionOutput = if ($versionResult) { $versionResult.RawOutput } else { $null }
    $resolvedPathGroups = @($resolvedGroups | ForEach-Object { $_ })

    $result = New-Object System.Collections.Specialized.OrderedDictionary
    $result['Exists'] = $exists
    $result['HasRequiredFiles'] = $hasRequiredFiles
    $result['HasRequiredDirectories'] = $hasRequiredDirectories
    $result['SignatureValid'] = $signatureValid
    $result['FileInfoValid'] = $fileInfoValid
    $result['IsUsable'] = $isUsable
    $result['FailureReason'] = $portableFailureReason
    $result['RuntimeHome'] = $RuntimeHome
    $result['ResolvedPathGroups'] = $resolvedPathGroups
    $result['ExecutablePath'] = $portableExecutablePath
    $result['ReportedVersion'] = $reportedVersion
    $result['RawVersionOutput'] = $portableRawVersionOutput
    $result['SignatureStatus'] = $signatureStatus
    $result['SignerSubject'] = $signerSubject
    $result['FileInfo'] = [pscustomobject]$fileInfoSnapshot

    foreach ($entry in $namedPaths.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Key)) {
            continue
        }

        $result[[string]$entry.Key] = $entry.Value
    }

    return [pscustomobject]$result
}

function Get-ManifestedPortableExternalRuntimeFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Layout
    )

    $runtimeBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'portableRuntime'
    $externalDiscovery = if ($runtimeBlock -and $runtimeBlock.PSObject.Properties.Match('externalDiscovery').Count -gt 0) { $runtimeBlock.externalDiscovery } else { $null }
    if (-not $externalDiscovery) {
        return $null
    }

    $excludedRoots = @()
    if ($runtimeBlock.PSObject.Properties.Match('toolsRootLayoutProperty').Count -gt 0 -and $Layout.PSObject.Properties.Match($runtimeBlock.toolsRootLayoutProperty).Count -gt 0) {
        $excludedRoots += $Layout.($runtimeBlock.toolsRootLayoutProperty)
    }

    $additionalPaths = New-Object System.Collections.Generic.List[string]
    foreach ($pathPattern in @($externalDiscovery.additionalPathPatterns)) {
        $expandedPath = Expand-ManifestedHostPathPattern -Pattern ([string]$pathPattern)
        if ([string]::IsNullOrWhiteSpace($expandedPath)) {
            continue
        }

        if ($expandedPath.IndexOfAny([char[]]@('*', '?')) -ge 0) {
            foreach ($matchedPath in @(Get-ChildItem -Path $expandedPath -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)) {
                if (-not [string]::IsNullOrWhiteSpace($matchedPath)) {
                    $additionalPaths.Add($matchedPath) | Out-Null
                }
            }
        }
        else {
            $additionalPaths.Add($expandedPath) | Out-Null
        }
    }

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    foreach ($commandName in @($externalDiscovery.commandNames)) {
        if ([string]::IsNullOrWhiteSpace([string]$commandName)) {
            continue
        }

        $candidatePath = Get-ManifestedApplicationPath -CommandName ([string]$commandName) -ExcludedRoots $excludedRoots -AdditionalPaths @($additionalPaths)
        if (-not [string]::IsNullOrWhiteSpace($candidatePath)) {
            $candidatePaths.Add($candidatePath) | Out-Null
        }
    }

    foreach ($candidatePath in @($additionalPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path -LiteralPath $candidatePath)) {
            $candidatePaths.Add($candidatePath) | Out-Null
        }
    }

    $trimLeafNames = @()
    foreach ($trimLeafName in @($externalDiscovery.runtimeHomeTrimLeafNames)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$trimLeafName)) {
            $trimLeafNames += ([string]$trimLeafName)
        }
    }

    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $resolvedCandidatePath = Get-ManifestedFullPath -Path $candidatePath
        if ([string]::IsNullOrWhiteSpace($resolvedCandidatePath) -or -not (Test-Path -LiteralPath $resolvedCandidatePath)) {
            continue
        }

        $runtimeHome = Split-Path -Parent $resolvedCandidatePath
        while (-not [string]::IsNullOrWhiteSpace($runtimeHome) -and ($trimLeafNames -contains (Split-Path -Leaf $runtimeHome))) {
            $runtimeHome = Split-Path -Parent $runtimeHome
        }

        $validation = Test-ManifestedPortableRuntimeHome -Definition $Definition -RuntimeHome $runtimeHome
        if (-not $validation.IsUsable) {
            continue
        }

        $runtime = [ordered]@{
            Version       = $validation.ReportedVersion
            Flavor        = $null
            RuntimeHome   = $runtimeHome
            ExecutablePath = $validation.ExecutablePath
            Validation    = $validation
            IsUsable      = $true
            Source        = 'External'
            Discovery     = 'Path'
        }
        foreach ($property in @($validation.PSObject.Properties)) {
            if ($runtime.Contains($property.Name)) {
                continue
            }
            $runtime[$property.Name] = $property.Value
        }

        return [pscustomobject]$runtime
    }

    return $null
}

function Get-ManifestedPortableRuntimeFactsFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = $null
    $runtimeBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'portableRuntime'
    try {
        $flavor = Get-ManifestedDefinitionFlavor -Definition $Definition
        if ([string]::IsNullOrWhiteSpace($flavor)) {
            $blockedReason = if ($runtimeBlock -and $runtimeBlock.PSObject.Properties.Match('unsupportedHostMessage').Count -gt 0) { [string]$runtimeBlock.unsupportedHostMessage } else { 'The current host is not supported for this portable runtime.' }
            return (New-ManifestedRuntimeFacts -RuntimeName $Definition.runtimeName -CommandName $Definition.commandName -RuntimeKind 'PortablePackage' -LocalRoot $LocalRoot -Layout $layout -PlatformSupported:$false -BlockedReason $blockedReason -AdditionalProperties @{
                    Flavor              = $null
                    Package             = $null
                    PackagePath         = $null
                    InvalidRuntimeHomes = @()
                })
        }

        $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    }
    catch {
        return (New-ManifestedRuntimeFacts -RuntimeName $Definition.runtimeName -CommandName $Definition.commandName -RuntimeKind 'PortablePackage' -LocalRoot $LocalRoot -Layout $layout -PlatformSupported:$false -BlockedReason $_.Exception.Message -AdditionalProperties @{
                Flavor              = $(if ($flavor) { $flavor } else { $null })
                Package             = $null
                PackagePath         = $null
                InvalidRuntimeHomes = @()
            })
    }

    $partialPaths = @()
    $cacheRoot = Get-ManifestedArtifactCacheRootFromDefinition -Definition $Definition -Layout $layout
    if (-not [string]::IsNullOrWhiteSpace($cacheRoot) -and (Test-Path -LiteralPath $cacheRoot)) {
        $partialPaths += @(Get-ChildItem -LiteralPath $cacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }

    $stagePrefix = if ($runtimeBlock.PSObject.Properties.Match('stagePrefix').Count -gt 0) { [string]$runtimeBlock.stagePrefix } else { ($Definition.runtimeName -replace 'Runtime$', '').ToLowerInvariant() }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix $stagePrefix -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $toolsRoot = $layout.($runtimeBlock.toolsRootLayoutProperty)
    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace($toolsRoot) -and (Test-Path -LiteralPath $toolsRoot)) {
        $versionRoots = Get-ChildItem -LiteralPath $toolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedFlexibleVersionObject -VersionText $_.Name } }, Name

        foreach ($versionRoot in $versionRoots) {
            $runtimeHome = Join-Path $versionRoot.FullName $flavor
            if (-not (Test-Path -LiteralPath $runtimeHome)) {
                continue
            }

            $validation = Test-ManifestedPortableRuntimeHome -Definition $Definition -RuntimeHome $runtimeHome
            $expectedVersionTemplate = if ($runtimeBlock.PSObject.Properties.Match('expectedVersionTemplate').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($runtimeBlock.expectedVersionTemplate)) {
                $runtimeBlock.expectedVersionTemplate
            }
            else {
                if ($runtimeBlock.PSObject.Properties.Match('versionFolderTemplate').Count -gt 0) { $runtimeBlock.versionFolderTemplate } else { '{version}' }
            }
            $expectedVersion = Expand-ManifestedDefinitionTemplate -Template $expectedVersionTemplate -Version $versionRoot.Name -TagName $versionRoot.Name -Flavor $null
            $expectedVersion = $expectedVersion.Replace('{versionNoPrefixV}', $versionRoot.Name.TrimStart('v', 'V'))
            $versionMatches = [string]::IsNullOrWhiteSpace($validation.ReportedVersion) -or [string]::IsNullOrWhiteSpace($expectedVersion) -or ($validation.ReportedVersion -eq $expectedVersion)
            $resolvedVersion = if (-not [string]::IsNullOrWhiteSpace($validation.ReportedVersion)) { $validation.ReportedVersion } else { $expectedVersion }
            $entry = [ordered]@{
                Version        = $resolvedVersion
                Flavor         = $flavor
                RuntimeHome    = $runtimeHome
                ExecutablePath = $validation.ExecutablePath
                Validation     = $validation
                VersionMatches = $versionMatches
                IsUsable       = ($validation.IsUsable -and $versionMatches)
            }
            foreach ($property in @($validation.PSObject.Properties)) {
                if ([string]::IsNullOrWhiteSpace([string]$property.Name)) {
                    continue
                }

                if ($entry.Contains([string]$property.Name)) {
                    continue
                }
                $entry[[string]$property.Name] = $property.Value
            }
            $entries += [pscustomobject]$entry
        }
    }

    $managedRuntime = @($entries | Where-Object { $_.IsUsable } | Select-Object -First 1)
    $managedRuntime = if ($managedRuntime) { $managedRuntime[0] } else { $null }
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-ManifestedPortableExternalRuntimeFromDefinition -Definition $Definition -Layout $layout
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $package = Get-LatestCachedZipArtifactFromDefinition -Definition $Definition -Flavor $flavor -LocalRoot $layout.LocalRoot
    $invalidRuntimeHomes = @($entries | Where-Object { -not $_.IsUsable } | Select-Object -ExpandProperty RuntimeHome)

    $additionalProperties = [ordered]@{
        Flavor              = $flavor
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
    }
    if ($currentRuntime) {
        foreach ($property in @($currentRuntime.PSObject.Properties)) {
            if ($property.Name -in @('Version', 'Flavor', 'RuntimeHome', 'ExecutablePath', 'Validation', 'VersionMatches', 'IsUsable', 'Source', 'Discovery')) {
                continue
            }
            $additionalProperties[$property.Name] = $property.Value
        }
    }

    return (New-ManifestedRuntimeFacts -RuntimeName $Definition.runtimeName -CommandName $Definition.commandName -RuntimeKind 'PortablePackage' -LocalRoot $layout.LocalRoot -Layout $layout -ManagedRuntime $managedRuntime -ExternalRuntime $externalRuntime -Artifact $package -PartialPaths $partialPaths -InvalidPaths $invalidRuntimeHomes -Version $(if ($currentRuntime) { $currentRuntime.Version } elseif ($package) { $package.Version } else { $null }) -RuntimeHome $(if ($currentRuntime) { $currentRuntime.RuntimeHome } else { $null }) -RuntimeSource $(if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }) -ExecutablePath $(if ($currentRuntime) { $currentRuntime.ExecutablePath } else { $null }) -RuntimeValidation $(if ($currentRuntime) { $currentRuntime.Validation } else { $null }) -AdditionalProperties $additionalProperties)
}
