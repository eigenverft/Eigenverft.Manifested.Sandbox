<#
    Eigenverft.Manifested.Sandbox.Package.Validation
#>

function Get-PackageEntryPointDefinition {
<#
.SYNOPSIS
Returns an entry-point definition by name.

.DESCRIPTION
Searches the definition provided-tool collections and returns the first matching
command or app entry by name.

.PARAMETER Definition
The Package definition object.

.PARAMETER EntryPointName
The entry-point name to resolve.

.EXAMPLE
Get-PackageEntryPointDefinition -Definition $definition -EntryPointName code
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$EntryPointName
    )

    foreach ($entryPoint in @($Definition.providedTools.commands)) {
        if ([string]::Equals([string]$entryPoint.name, $EntryPointName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entryPoint
        }
    }
    foreach ($entryPoint in @($Definition.providedTools.apps)) {
        if ([string]::Equals([string]$entryPoint.name, $EntryPointName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entryPoint
        }
    }

    return $null
}

function Get-PackageCommandCheckPath {
<#
.SYNOPSIS
Resolves the command path used for a validation command check.

.DESCRIPTION
Uses an explicit relative path when provided, otherwise resolves the path from
the named Package entry point.

.PARAMETER PackageResult
The current Package result object.

.PARAMETER CommandCheck
The validation command-check definition.

.EXAMPLE
Get-PackageCommandCheckPath -PackageResult $result -CommandCheck $check
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [Parameter(Mandatory = $true)]
        [psobject]$CommandCheck
    )

    if ($CommandCheck.PSObject.Properties['relativePath'] -and -not [string]::IsNullOrWhiteSpace([string]$CommandCheck.relativePath)) {
        return (Join-Path $PackageResult.InstallDirectory (([string]$CommandCheck.relativePath) -replace '/', '\'))
    }

    if ($CommandCheck.PSObject.Properties['entryPoint'] -and -not [string]::IsNullOrWhiteSpace([string]$CommandCheck.entryPoint)) {
        $entryPoint = Get-PackageEntryPointDefinition -Definition $PackageResult.PackageConfig.Definition -EntryPointName ([string]$CommandCheck.entryPoint)
        if (-not $entryPoint -or -not $entryPoint.PSObject.Properties['relativePath']) {
            throw "Package validation entry point '$($CommandCheck.entryPoint)' was not found."
        }

        return (Join-Path $PackageResult.InstallDirectory (([string]$entryPoint.relativePath) -replace '/', '\'))
    }

    throw 'Package command checks require either relativePath or entryPoint.'
}

function Get-PackageJsonValue {
<#
.SYNOPSIS
Reads a dotted property path from an object.

.DESCRIPTION
Walks a dotted property path such as `version` or `metadata.name` and returns
the current value when every path segment exists.

.PARAMETER InputObject
The object to read from.

.PARAMETER PropertyPath
The dotted property path.

.EXAMPLE
Get-PackageJsonValue -InputObject $document -PropertyPath version
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyPath
    )

    $current = $InputObject
    foreach ($segment in @($PropertyPath -split '\.')) {
        if ($null -eq $current -or -not $current.PSObject.Properties[$segment]) {
            return $null
        }

        $current = $current.$segment
    }

    return $current
}

function Test-PackageValidationValueComparison {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object]$ActualValue,

        [AllowNull()]
        [object]$ExpectedValue,

        [string]$Operator = '=='
    )

    $actualText = [string]$ActualValue
    $expectedText = [string]$ExpectedValue
    $operatorText = if ([string]::IsNullOrWhiteSpace($Operator)) { '==' } else { $Operator }

    if ($operatorText -in @('=', '==')) {
        return [string]::Equals($actualText, $expectedText, [System.StringComparison]::OrdinalIgnoreCase)
    }
    if ($operatorText -eq '!=') {
        return (-not [string]::Equals($actualText, $expectedText, [System.StringComparison]::OrdinalIgnoreCase))
    }

    $actualVersion = ConvertTo-PackageVersion -VersionText $actualText
    $expectedVersion = ConvertTo-PackageVersion -VersionText $expectedText
    switch -Exact ($operatorText) {
        '>' { return $actualVersion -gt $expectedVersion }
        '>=' { return $actualVersion -ge $expectedVersion }
        '<' { return $actualVersion -lt $expectedVersion }
        '<=' { return $actualVersion -le $expectedVersion }
        default { throw "Unsupported Package validation comparison operator '$operatorText'." }
    }
}

function Test-PackageInstalledPackage {
<#
.SYNOPSIS
Validates an installed package against its Package rules.

.DESCRIPTION
Runs file, directory, command, metadata, signature, file-details, and registry
checks for the current install directory and attaches the validation result to
the Package result object.

.PARAMETER PackageResult
The Package result object to validate.

.EXAMPLE
Test-PackageInstalledPackage -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $package = $PackageResult.Package
    if (-not $package -or -not $package.PSObject.Properties['validation'] -or $null -eq $package.validation) {
        $PackageResult.Validation = [pscustomobject]@{
            Status       = 'Ready'
            Accepted     = $true
            InstallDirectory = $PackageResult.InstallDirectory
            Files        = @()
            Directories  = @()
            Commands     = @()
            MetadataFiles = @()
            Signatures   = @()
            FileDetails  = @()
            Registry     = @()
        }
        return $PackageResult
    }

    $installDirectory = $PackageResult.InstallDirectory
    $validation = $package.validation
    $requiresInstallDirectory = (@($validation.files).Count -gt 0) -or
        (@($validation.directories).Count -gt 0) -or
        (@($validation.commandChecks).Count -gt 0) -or
        (@($validation.metadataFiles).Count -gt 0) -or
        (@($validation.signatures).Count -gt 0) -or
        (@($validation.fileDetails).Count -gt 0)
    if ($requiresInstallDirectory -and ([string]::IsNullOrWhiteSpace($installDirectory) -or -not (Test-Path -LiteralPath $installDirectory))) {
        $PackageResult.Validation = [pscustomobject]@{
            Status           = 'Failed'
            Accepted         = $false
            FailureReason    = 'InstallDirectoryMissing'
            InstallDirectory = $installDirectory
            Files            = @()
            Directories      = @()
            Commands         = @()
            MetadataFiles    = @()
            Signatures       = @()
            FileDetails      = @()
            Registry         = @()
        }
        return $PackageResult
    }

    $fileResults = New-Object System.Collections.Generic.List[object]
    foreach ($relativePath in @($validation.files)) {
        if ($null -eq $relativePath) {
            continue
        }
        $path = Join-Path $installDirectory (([string]$relativePath) -replace '/', '\')
        $fileResults.Add([pscustomobject]@{
            RelativePath = $relativePath
            Path         = $path
            Exists       = (Test-Path -LiteralPath $path -PathType Leaf)
            Status       = if (Test-Path -LiteralPath $path -PathType Leaf) { 'Ready' } else { 'Missing' }
        }) | Out-Null
    }

    $directoryResults = New-Object System.Collections.Generic.List[object]
    foreach ($relativePath in @($validation.directories)) {
        if ($null -eq $relativePath) {
            continue
        }
        $path = Join-Path $installDirectory (([string]$relativePath) -replace '/', '\')
        $directoryResults.Add([pscustomobject]@{
            RelativePath = $relativePath
            Path         = $path
            Exists       = (Test-Path -LiteralPath $path -PathType Container)
            Status       = if (Test-Path -LiteralPath $path -PathType Container) { 'Ready' } else { 'Missing' }
        }) | Out-Null
    }

    $commandResults = New-Object System.Collections.Generic.List[object]
    foreach ($commandCheck in @($validation.commandChecks)) {
        if ($null -eq $commandCheck) {
            continue
        }
        $commandPath = Get-PackageCommandCheckPath -PackageResult $PackageResult -CommandCheck $commandCheck
        $arguments = @()
        foreach ($argument in @($commandCheck.arguments)) {
            $arguments += (Resolve-PackageTemplateText -Text ([string]$argument) -PackageConfig $PackageResult.PackageConfig -Package $package)
        }

        $outputLines = @()
        $exitCode = $null
        try {
            $outputLines = @(& $commandPath @arguments 2>&1)
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) {
                $exitCode = 0
            }
        }
        catch {
            $outputLines = @($_.Exception.Message)
            $exitCode = 1
        }

        $combinedOutput = (($outputLines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
        $pattern = if ($commandCheck.PSObject.Properties['outputPattern']) { [string]$commandCheck.outputPattern } else { '(?m)^(?<value>.+)$' }
        $match = [regex]::Match($combinedOutput, $pattern)
        $actualValue = if ($match.Success) {
            if ($match.Groups['value'] -and $match.Groups['value'].Success) {
                $match.Groups['value'].Value.Trim()
            }
            else {
                $match.Value.Trim()
            }
        }
        else {
            $null
        }

        $expectedValue = if ($commandCheck.PSObject.Properties['expectedValue'] -and -not [string]::IsNullOrWhiteSpace([string]$commandCheck.expectedValue)) {
            Resolve-PackageTemplateText -Text ([string]$commandCheck.expectedValue) -PackageConfig $PackageResult.PackageConfig -Package $package
        }
        else {
            $null
        }

        $isReady = ($exitCode -eq 0) -and ($null -ne $actualValue) -and (([string]::IsNullOrWhiteSpace($expectedValue)) -or ([string]::Equals([string]$actualValue, [string]$expectedValue, [System.StringComparison]::OrdinalIgnoreCase)))
        $commandResults.Add([pscustomobject]@{
            EntryPoint    = if ($commandCheck.PSObject.Properties['entryPoint']) { $commandCheck.entryPoint } else { $null }
            Path          = $commandPath
            ExitCode      = $exitCode
            ActualValue   = $actualValue
            ExpectedValue = $expectedValue
            Status        = if ($isReady) { 'Ready' } else { 'Failed' }
            Output        = $combinedOutput
        }) | Out-Null
    }

    $metadataResults = New-Object System.Collections.Generic.List[object]
    foreach ($metadataCheck in @($validation.metadataFiles)) {
        if ($null -eq $metadataCheck) {
            continue
        }
        $path = Join-Path $installDirectory (([string]$metadataCheck.relativePath) -replace '/', '\')
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $value = $null
        $status = 'Missing'

        if ($exists) {
            try {
                $document = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $value = Get-PackageJsonValue -InputObject $document -PropertyPath ([string]$metadataCheck.jsonPath)
                $expectedValue = Resolve-PackageTemplateText -Text ([string]$metadataCheck.expectedValue) -PackageConfig $PackageResult.PackageConfig -Package $package
                $status = if ([string]::Equals([string]$value, [string]$expectedValue, [System.StringComparison]::OrdinalIgnoreCase)) { 'Ready' } else { 'Failed' }
            }
            catch {
                $status = 'Failed'
            }
        }
        else {
            $expectedValue = Resolve-PackageTemplateText -Text ([string]$metadataCheck.expectedValue) -PackageConfig $PackageResult.PackageConfig -Package $package
        }

        $metadataResults.Add([pscustomobject]@{
            RelativePath = $metadataCheck.relativePath
            Path         = $path
            Exists       = $exists
            JsonPath     = $metadataCheck.jsonPath
            Value        = $value
            ExpectedValue = $expectedValue
            Status       = $status
        }) | Out-Null
    }

    $signatureResults = New-Object System.Collections.Generic.List[object]
    foreach ($signatureCheck in @($validation.signatures)) {
        if ($null -eq $signatureCheck) {
            continue
        }
        $path = Join-Path $installDirectory (([string]$signatureCheck.relativePath) -replace '/', '\')
        $status = 'Missing'
        $signatureStatus = $null
        $signerSubject = $null

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                $signature = Get-AuthenticodeSignature -FilePath $path
                $signatureStatus = $signature.Status.ToString()
                $signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
                $requiresValid = $true
                if ($signatureCheck.PSObject.Properties['requireValid']) {
                    $requiresValid = [bool]$signatureCheck.requireValid
                }
                $status = 'Ready'
                if ($requiresValid -and $signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
                    $status = 'Failed'
                }
                if ($status -eq 'Ready' -and $signatureCheck.PSObject.Properties['subjectContains'] -and
                    -not [string]::IsNullOrWhiteSpace([string]$signatureCheck.subjectContains) -and
                    ($null -eq $signerSubject -or $signerSubject -notmatch [regex]::Escape([string]$signatureCheck.subjectContains))) {
                    $status = 'Failed'
                }
            }
            catch {
                $status = 'Failed'
            }
        }

        $signatureResults.Add([pscustomobject]@{
            RelativePath     = $signatureCheck.relativePath
            Path             = $path
            SignatureStatus  = $signatureStatus
            SignerSubject    = $signerSubject
            Status           = $status
        }) | Out-Null
    }

    $fileDetailResults = New-Object System.Collections.Generic.List[object]
    foreach ($detailCheck in @($validation.fileDetails)) {
        if ($null -eq $detailCheck) {
            continue
        }
        $path = Join-Path $installDirectory (([string]$detailCheck.relativePath) -replace '/', '\')
        $productName = $null
        $fileDescription = $null
        $fileVersion = $null
        $productVersion = $null
        $status = 'Missing'

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                $item = Get-Item -LiteralPath $path -ErrorAction Stop
                $productName = if ($item.PSObject.Properties['VersionInfo'] -and $item.VersionInfo) { $item.VersionInfo.ProductName } else { $null }
                $fileDescription = if ($item.PSObject.Properties['VersionInfo'] -and $item.VersionInfo) { $item.VersionInfo.FileDescription } else { $null }
                $fileVersion = if ($item.PSObject.Properties['VersionInfo'] -and $item.VersionInfo) { $item.VersionInfo.FileVersion } else { $null }
                $productVersion = if ($item.PSObject.Properties['VersionInfo'] -and $item.VersionInfo) { $item.VersionInfo.ProductVersion } else { $null }
                $status = 'Ready'
                if ($detailCheck.PSObject.Properties['productName'] -and
                    -not [string]::IsNullOrWhiteSpace([string]$detailCheck.productName) -and
                    -not [string]::Equals([string]$productName, [string]$detailCheck.productName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $status = 'Failed'
                }
                if ($status -eq 'Ready' -and $detailCheck.PSObject.Properties['fileDescription'] -and
                    -not [string]::IsNullOrWhiteSpace([string]$detailCheck.fileDescription) -and
                    -not [string]::Equals([string]$fileDescription, [string]$detailCheck.fileDescription, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $status = 'Failed'
                }
                if ($status -eq 'Ready' -and $detailCheck.PSObject.Properties['fileVersion'] -and
                    -not [string]::IsNullOrWhiteSpace([string]$detailCheck.fileVersion) -and
                    -not [string]::Equals([string]$fileVersion, [string]$detailCheck.fileVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $status = 'Failed'
                }
                if ($status -eq 'Ready' -and $detailCheck.PSObject.Properties['productVersion'] -and
                    -not [string]::IsNullOrWhiteSpace([string]$detailCheck.productVersion) -and
                    -not [string]::Equals([string]$productVersion, [string]$detailCheck.productVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $status = 'Failed'
                }
            }
            catch {
                $status = 'Failed'
            }
        }

        $fileDetailResults.Add([pscustomobject]@{
            RelativePath    = $detailCheck.relativePath
            Path            = $path
            ProductName     = $productName
            FileDescription = $fileDescription
            FileVersion     = $fileVersion
            ProductVersion  = $productVersion
            Status          = $status
        }) | Out-Null
    }

    $registryResults = New-Object System.Collections.Generic.List[object]
    foreach ($registryCheck in @($validation.registryChecks)) {
        if ($null -eq $registryCheck) {
            continue
        }
        $registryPaths = if ($registryCheck.PSObject.Properties['paths'] -and @($registryCheck.paths).Count -gt 0) {
            @($registryCheck.paths | ForEach-Object { [string]$_ })
        }
        elseif ($registryCheck.PSObject.Properties['path'] -and -not [string]::IsNullOrWhiteSpace([string]$registryCheck.path)) {
            @([string]$registryCheck.path)
        }
        else {
            @()
        }
        $valueName = if ($registryCheck.PSObject.Properties['valueName'] -and -not [string]::IsNullOrWhiteSpace([string]$registryCheck.valueName)) {
            [string]$registryCheck.valueName
        }
        else {
            $null
        }
        $expectedValue = if ($registryCheck.PSObject.Properties['expectedValue']) {
            Resolve-PackageTemplateText -Text ([string]$registryCheck.expectedValue) -PackageConfig $PackageResult.PackageConfig -Package $package
        }
        else {
            $null
        }
        $operator = if ($registryCheck.PSObject.Properties['operator'] -and -not [string]::IsNullOrWhiteSpace([string]$registryCheck.operator)) {
            [string]$registryCheck.operator
        }
        else {
            '=='
        }
        $registryResolution = Resolve-RegistryValueFromPaths -Paths $registryPaths -ValueName $valueName
        $status = [string]$registryResolution.Status
        if ($status -eq 'Ready' -and $registryCheck.PSObject.Properties['expectedValue']) {
            $status = if (Test-PackageValidationValueComparison -ActualValue $registryResolution.ActualValue -ExpectedValue $expectedValue -Operator $operator) { 'Ready' } else { 'Failed' }
        }

        $registryResults.Add([pscustomobject]@{
            Path          = $registryResolution.Path
            Paths         = @($registryPaths)
            ValueName     = $valueName
            ActualValue   = $registryResolution.ActualValue
            ExpectedValue = $expectedValue
            Operator      = if ($registryCheck.PSObject.Properties['expectedValue']) { $operator } else { $null }
            Status        = $status
        }) | Out-Null
    }

    $allResults = @($fileResults.ToArray()) + @($directoryResults.ToArray()) + @($commandResults.ToArray()) + @($metadataResults.ToArray()) + @($signatureResults.ToArray()) + @($fileDetailResults.ToArray()) + @($registryResults.ToArray())
    $accepted = (@($allResults | Where-Object { $_.Status -ne 'Ready' }).Count -eq 0)

    $PackageResult.Validation = [pscustomobject]@{
        Status           = if ($accepted) { 'Ready' } else { 'Failed' }
        Accepted         = $accepted
        FailureReason    = if ($accepted) { $null } else { 'InstalledPackageValidationFailed' }
        InstallDirectory = $installDirectory
        Files            = @($fileResults.ToArray())
        Directories      = @($directoryResults.ToArray())
        Commands         = @($commandResults.ToArray())
        MetadataFiles    = @($metadataResults.ToArray())
        Signatures       = @($signatureResults.ToArray())
        FileDetails      = @($fileDetailResults.ToArray())
        Registry         = @($registryResults.ToArray())
    }

    $failedCount = @($allResults | Where-Object { $_.Status -ne 'Ready' }).Count
    Write-PackageExecutionMessage -Message ("[STATE] Validation completed for '{0}' with accepted='{1}', failedChecks={2}." -f $installDirectory, $accepted, $failedCount)

    return $PackageResult
}

