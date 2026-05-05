<#
    Eigenverft.Manifested.Sandbox.Package.OperationHistory
#>

function Get-PackageOperationHistory {
<#
.SYNOPSIS
Loads the Package operation-history document.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageConfig
    )

    $historyPath = $PackageConfig.PackageOperationHistoryFilePath
    if ([string]::IsNullOrWhiteSpace($historyPath)) {
        throw 'Package operation-history path is not configured.'
    }

    if (-not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        return [pscustomobject]@{
            Path    = $historyPath
            Records = @()
        }
    }

    $documentInfo = Read-PackageJsonDocument -Path $historyPath
    $records = if ($documentInfo.Document.PSObject.Properties['records']) { @($documentInfo.Document.records) } else { @() }
    return [pscustomobject]@{
        Path    = $documentInfo.Path
        Records = $records
    }
}

function Save-PackageOperationHistory {
<#
.SYNOPSIS
Writes the Package operation-history document.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HistoryPath,

        [Parameter(Mandatory = $true)]
        [object[]]$Records
    )

    $directoryPath = Split-Path -Parent $HistoryPath
    if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
        $null = New-Item -ItemType Directory -Path $directoryPath -Force
    }

    [ordered]@{
        schemaVersion = 1
        records       = @($Records)
    } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $HistoryPath -Encoding UTF8
}

function Select-PackageOperationDependencySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Dependency
    )

    $dependencyResult = if ($Dependency.PSObject.Properties['Result']) { $Dependency.Result } else { $null }
    return [pscustomobject]@{
        repositoryId  = if ($Dependency.PSObject.Properties['RepositoryId']) { [string]$Dependency.RepositoryId } elseif ($dependencyResult -and $dependencyResult.PSObject.Properties['RepositoryId']) { [string]$dependencyResult.RepositoryId } else { $null }
        definitionId  = if ($Dependency.PSObject.Properties['DefinitionId']) { [string]$Dependency.DefinitionId } elseif ($dependencyResult -and $dependencyResult.PSObject.Properties['DefinitionId']) { [string]$dependencyResult.DefinitionId } else { $null }
        desiredState  = if ($dependencyResult -and $dependencyResult.PSObject.Properties['DesiredState']) { [string]$dependencyResult.DesiredState } else { 'Assigned' }
        status        = if ($Dependency.PSObject.Properties['Status']) { [string]$Dependency.Status } elseif ($dependencyResult -and $dependencyResult.PSObject.Properties['Status']) { [string]$dependencyResult.Status } else { $null }
        failureReason = if ($dependencyResult -and $dependencyResult.PSObject.Properties['FailureReason']) { [string]$dependencyResult.FailureReason } else { $null }
        installOrigin = if ($Dependency.PSObject.Properties['InstallOrigin']) { [string]$Dependency.InstallOrigin } elseif ($dependencyResult -and $dependencyResult.PSObject.Properties['InstallOrigin']) { [string]$dependencyResult.InstallOrigin } else { $null }
    }
}

function New-PackageOperationHistoryRecord {
<#
.SYNOPSIS
Creates one operation-history record from a finalized Package result.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [AllowNull()]
        [string]$FailedStep,

        [Parameter(Mandatory = $true)]
        [string]$CompletedAtUtc
    )

    $packageFilePreparation = $PackageResult.PackageFilePreparation
    $selectedSource = if ($packageFilePreparation -and $packageFilePreparation.PSObject.Properties['SelectedSource']) { $packageFilePreparation.SelectedSource } else { $null }
    $verification = if ($packageFilePreparation -and $packageFilePreparation.PSObject.Properties['Verification']) { $packageFilePreparation.Verification } else { $null }
    $installStatus = if ($PackageResult.Install -and $PackageResult.Install.PSObject.Properties['Status']) { [string]$PackageResult.Install.Status } else { $null }
    $operationId = if ($PackageResult.PSObject.Properties['OperationId'] -and -not [string]::IsNullOrWhiteSpace([string]$PackageResult.OperationId)) {
        [string]$PackageResult.OperationId
    }
    else {
        [guid]::NewGuid().ToString('n')
    }
    $startedAtUtc = if ($PackageResult.PSObject.Properties['OperationStartedAtUtc'] -and -not [string]::IsNullOrWhiteSpace([string]$PackageResult.OperationStartedAtUtc)) {
        [string]$PackageResult.OperationStartedAtUtc
    }
    else {
        $CompletedAtUtc
    }

    return [pscustomobject]@{
        operationId                   = $operationId
        startedAtUtc                  = $startedAtUtc
        completedAtUtc                = $CompletedAtUtc
        repositoryId                  = [string]$PackageResult.RepositoryId
        definitionId                  = [string]$PackageResult.DefinitionId
        desiredState                  = [string]$PackageResult.DesiredState
        status                        = [string]$PackageResult.Status
        failureReason                 = [string]$PackageResult.FailureReason
        errorMessage                  = [string]$PackageResult.ErrorMessage
        failedStep                    = $FailedStep
        packageId                     = [string]$PackageResult.PackageId
        packageVersion                = [string]$PackageResult.PackageVersion
        releaseTrack                  = [string]$PackageResult.ReleaseTrack
        flavor                        = if ($PackageResult.Package -and $PackageResult.Package.PSObject.Properties['flavor']) { [string]$PackageResult.Package.flavor } else { $null }
        installOrigin                 = [string]$PackageResult.InstallOrigin
        installStatus                 = $installStatus
        installDirectory              = [string]$PackageResult.InstallDirectory
        packageFilePreparation        = [pscustomobject]@{
            status                      = if ($packageFilePreparation -and $packageFilePreparation.PSObject.Properties['Status']) { [string]$packageFilePreparation.Status } else { $null }
            success                     = if ($packageFilePreparation -and $packageFilePreparation.PSObject.Properties['Success']) { [bool]$packageFilePreparation.Success } else { $null }
            packageFilePath             = [string]$PackageResult.PackageFilePath
            defaultPackageDepotFilePath = [string]$PackageResult.DefaultPackageDepotFilePath
            sourceScope                 = if ($selectedSource -and $selectedSource.PSObject.Properties['SourceScope']) { [string]$selectedSource.SourceScope } else { $null }
            sourceId                    = if ($selectedSource -and $selectedSource.PSObject.Properties['SourceId']) { [string]$selectedSource.SourceId } else { $null }
            verificationStatus          = if ($verification -and $verification.PSObject.Properties['Status']) { [string]$verification.Status } else { $null }
        }
        dependencies                  = @($PackageResult.Dependencies | ForEach-Object { Select-PackageOperationDependencySummary -Dependency $_ })
    }
}

function Add-PackageOperationHistoryRecord {
<#
.SYNOPSIS
Appends one Package operation-history record.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageConfig,

        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [AllowNull()]
        [string]$FailedStep
    )

    try {
        $completedAtUtc = [DateTime]::UtcNow.ToString('o')
        $history = Get-PackageOperationHistory -PackageConfig $PackageConfig
        $records = @($history.Records)
        $records += New-PackageOperationHistoryRecord -PackageResult $PackageResult -FailedStep $FailedStep -CompletedAtUtc $completedAtUtc
        Save-PackageOperationHistory -HistoryPath $history.Path -Records $records
        Write-PackageExecutionMessage -Message ("[STATE] Appended package operation-history record for definition '{0}' with status '{1}' at '{2}'." -f [string]$PackageResult.DefinitionId, [string]$PackageResult.Status, $history.Path)
    }
    catch {
        Write-PackageExecutionMessage -Level 'WRN' -Message ("[WARN] Failed to append package operation history for definition '{0}': {1}" -f [string]$PackageResult.DefinitionId, $_.Exception.Message)
    }
}
