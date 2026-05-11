<#
    Eigenverft.Manifested.Sandbox.Package - repository inventory management helpers.
#>

function Assert-PackageRepositoryId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryId
    )

    if ([string]::IsNullOrWhiteSpace($RepositoryId)) {
        throw 'RepositoryId must not be empty.'
    }
    if ($RepositoryId -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
        throw "RepositoryId '$RepositoryId' is invalid. Use letters, numbers, '-' or '_' and start with a letter."
    }
}

function Assert-PackageRepositorySource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryId,

        [Parameter(Mandatory = $true)]
        [psobject]$SourceValue,

        [Parameter(Mandatory = $true)]
        [string]$DocumentPath
    )

    foreach ($requiredProperty in @('kind', 'enabled', 'searchOrder', 'trusted', 'trustMode')) {
        if (-not $SourceValue.PSObject.Properties[$requiredProperty]) {
            throw "Package repository source '$RepositoryId' in '$DocumentPath' is missing '$requiredProperty'."
        }
    }
    if ($SourceValue.PSObject.Properties['priority']) {
        throw "Package repository source '$RepositoryId' in '$DocumentPath' still uses retired property 'priority'. Use 'searchOrder'."
    }

    $kind = [string]$SourceValue.kind
    $trustMode = [string]$SourceValue.trustMode
    if ($kind -notin @('moduleLocal', 'filesystem', 'httpsCatalog')) {
        throw "Package repository source '$RepositoryId' in '$DocumentPath' has unsupported kind '$kind'."
    }
    if ($trustMode -notin @('moduleShipped', 'unsigned', 'unsignedExplicit', 'signedCatalog')) {
        throw "Package repository source '$RepositoryId' in '$DocumentPath' has unsupported trustMode '$trustMode'."
    }

    if ([string]::Equals($kind, 'moduleLocal', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not $SourceValue.PSObject.Properties['definitionRoot'] -or [string]::IsNullOrWhiteSpace([string]$SourceValue.definitionRoot)) {
            throw "Package repository source '$RepositoryId' in '$DocumentPath' is missing definitionRoot."
        }
        if (-not [bool]$SourceValue.trusted -or -not [string]::Equals($trustMode, 'moduleShipped', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package repository source '$RepositoryId' in '$DocumentPath' kind moduleLocal must use trusted=true and trustMode='moduleShipped'."
        }
    }
    elseif ([string]::Equals($kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not $SourceValue.PSObject.Properties['basePath'] -or [string]::IsNullOrWhiteSpace([string]$SourceValue.basePath)) {
            throw "Package repository source '$RepositoryId' in '$DocumentPath' is missing basePath."
        }
        if ([bool]$SourceValue.trusted -and -not [string]::Equals($trustMode, 'unsignedExplicit', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package repository source '$RepositoryId' in '$DocumentPath' kind filesystem must use trustMode='unsignedExplicit' when trusted=true."
        }
        if ([string]::Equals($trustMode, 'unsignedExplicit', [System.StringComparison]::OrdinalIgnoreCase) -and -not [bool]$SourceValue.trusted) {
            throw "Package repository source '$RepositoryId' in '$DocumentPath' uses trustMode='unsignedExplicit' but trusted is false."
        }
    }
    elseif ([string]::Equals($kind, 'httpsCatalog', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($requiredHttpsProperty in @('baseUri', 'catalogPath')) {
            if (-not $SourceValue.PSObject.Properties[$requiredHttpsProperty] -or [string]::IsNullOrWhiteSpace([string]$SourceValue.$requiredHttpsProperty)) {
                throw "Package repository source '$RepositoryId' in '$DocumentPath' kind httpsCatalog is missing $requiredHttpsProperty."
            }
        }
    }
}

function Assert-PackageRepositoryInventorySchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RepositoryInventoryDocumentInfo
    )

    $document = $RepositoryInventoryDocumentInfo.Document
    if (-not $document.PSObject.Properties['inventoryVersion']) {
        throw "Package repository inventory '$($RepositoryInventoryDocumentInfo.Path)' is missing inventoryVersion."
    }
    if (-not $document.PSObject.Properties['repositorySources'] -or $null -eq $document.repositorySources) {
        throw "Package repository inventory '$($RepositoryInventoryDocumentInfo.Path)' is missing repositorySources."
    }

    foreach ($sourceProperty in @($document.repositorySources.PSObject.Properties)) {
        Assert-PackageRepositorySource -RepositoryId $sourceProperty.Name -SourceValue $sourceProperty.Value -DocumentPath $RepositoryInventoryDocumentInfo.Path
    }
}

function Get-PackageRepositoryInventoryInfo {
    [CmdletBinding()]
    param()

    $inventoryPath = Get-PackageRepositoryInventoryPath
    $documentInfo = Read-PackageJsonDocument -Path $inventoryPath
    Assert-PackageRepositoryInventorySchema -RepositoryInventoryDocumentInfo $documentInfo
    $documentInfo | Add-Member -MemberType NoteProperty -Name Exists -Value $true -Force
    return $documentInfo
}

function Get-PackageRepositoryInventoryEditInfo {
    [CmdletBinding()]
    param()

    $documentInfo = Get-PackageRepositoryInventoryInfo
    if (-not $documentInfo.Document.PSObject.Properties['repositorySources'] -or $null -eq $documentInfo.Document.repositorySources) {
        $documentInfo.Document | Add-Member -MemberType NoteProperty -Name 'repositorySources' -Value ([pscustomobject]@{}) -Force
    }
    return $documentInfo
}

function Save-PackageRepositoryInventoryDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$DocumentInfo
    )

    Assert-PackageRepositoryInventorySchema -RepositoryInventoryDocumentInfo $DocumentInfo

    $directory = Split-Path -Parent $DocumentInfo.Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    $temporaryPath = '{0}.{1}.tmp' -f $DocumentInfo.Path, ([guid]::NewGuid().ToString('N'))
    try {
        $DocumentInfo.Document | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        Move-Item -LiteralPath $temporaryPath -Destination $DocumentInfo.Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-PackageRepositorySourceProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Document,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryId
    )

    if (-not $Document.PSObject.Properties['repositorySources'] -or $null -eq $Document.repositorySources) {
        return $null
    }

    return $Document.repositorySources.PSObject.Properties[$RepositoryId]
}

function Get-PackageNextRepositorySearchOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Document
    )

    $maxSearchOrder = 0
    foreach ($sourceProperty in @($Document.repositorySources.PSObject.Properties)) {
        if ($sourceProperty.Value -and $sourceProperty.Value.PSObject.Properties['searchOrder']) {
            $current = [int]$sourceProperty.Value.searchOrder
            if ($current -gt $maxSearchOrder) {
                $maxSearchOrder = $current
            }
        }
    }

    return ([int]([Math]::Ceiling(($maxSearchOrder + 1) / 100.0) * 100))
}

function Get-PackageRepositorySearchOrderAfter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Document,

        [Parameter(Mandatory = $true)]
        [string]$AfterRepositoryId
    )

    $afterProperty = Get-PackageRepositorySourceProperty -Document $Document -RepositoryId $AfterRepositoryId
    if (-not $afterProperty) {
        throw "Package repository '$AfterRepositoryId' was not found, so no searchOrder can be placed after it."
    }
    if (-not $afterProperty.Value.PSObject.Properties['searchOrder']) {
        throw "Package repository '$AfterRepositoryId' has no searchOrder."
    }

    $afterOrder = [int]$afterProperty.Value.searchOrder
    $nextHigherOrder = $null
    foreach ($sourceProperty in @($Document.repositorySources.PSObject.Properties)) {
        if (-not $sourceProperty.Value -or -not $sourceProperty.Value.PSObject.Properties['searchOrder']) {
            continue
        }

        $currentOrder = [int]$sourceProperty.Value.searchOrder
        if ($currentOrder -gt $afterOrder -and ($null -eq $nextHigherOrder -or $currentOrder -lt $nextHigherOrder)) {
            $nextHigherOrder = $currentOrder
        }
    }

    if ($null -eq $nextHigherOrder) {
        return ($afterOrder + 100)
    }

    $candidate = [int][Math]::Floor(($afterOrder + $nextHigherOrder) / 2)
    if ($candidate -le $afterOrder -or $candidate -ge $nextHigherOrder) {
        throw "No integer searchOrder slot is available between '$AfterRepositoryId' ($afterOrder) and the next repository ($nextHigherOrder). Use -SearchOrder explicitly."
    }

    return $candidate
}

function New-PackageFilesystemRepositorySource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [int]$SearchOrder,

        [bool]$Enabled = $true,

        [bool]$Trusted = $false,

        [AllowNull()]
        [string]$TrustReason = $null
    )

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        throw 'BasePath must not be empty.'
    }

    $source = [ordered]@{
        kind        = 'filesystem'
        enabled     = $Enabled
        searchOrder = $SearchOrder
        basePath    = $BasePath
        trusted     = $Trusted
        trustMode   = if ($Trusted) { 'unsignedExplicit' } else { 'unsigned' }
    }

    if ($Trusted) {
        $source['trustedAtUtc'] = [DateTime]::UtcNow.ToString('o')
        if (-not [string]::IsNullOrWhiteSpace($TrustReason)) {
            $source['trustReason'] = $TrustReason
        }
    }

    return [pscustomobject]$source
}

function Resolve-PackageRepositoryRootForDisplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Source,

        [AllowNull()]
        [string]$ApplicationRootDirectory = $null
    )

    $kind = [string]$Source.kind
    try {
        if ([string]::Equals($kind, 'moduleLocal', [System.StringComparison]::OrdinalIgnoreCase)) {
            return Resolve-ConfiguredPath -PathValue ([string]$Source.definitionRoot) -BaseDirectory (Split-Path -Parent (Get-PackageConfigurationRoot)) -Tokens @{}
        }
        if ([string]::Equals($kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not [string]::IsNullOrWhiteSpace($ApplicationRootDirectory)) {
                return Resolve-PackageConfiguredPath -PathValue ([string]$Source.basePath) -ApplicationRootDirectory $ApplicationRootDirectory
            }
            return Resolve-PackagePathValue -PathValue ([string]$Source.basePath)
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-PackageFileSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Select-PackageRepositorySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryId,

        [Parameter(Mandatory = $true)]
        [psobject]$Source,

        [Parameter(Mandatory = $true)]
        [string]$InventoryPath,

        [AllowNull()]
        [string]$ApplicationRootDirectory = $null
    )

    $enabled = if ($Source.PSObject.Properties['enabled']) { [bool]$Source.enabled } else { $true }
    $trusted = if ($Source.PSObject.Properties['trusted']) { [bool]$Source.trusted } else { $false }
    $kind = if ($Source.PSObject.Properties['kind']) { [string]$Source.kind } else { $null }
    $trustMode = if ($Source.PSObject.Properties['trustMode']) { [string]$Source.trustMode } else { $null }

    $notes = New-Object System.Collections.Generic.List[string]
    if (-not $enabled) {
        $notes.Add('Disabled; package commands will not use this repository.') | Out-Null
    }
    if (-not $trusted) {
        $notes.Add('Untrusted; definitions cannot be executed until the repository is trusted.') | Out-Null
    }
    if ($kind -eq 'httpsCatalog') {
        $notes.Add('HTTPS catalog repositories are reserved for future support and are not executable in v1.') | Out-Null
    }
    if ($trusted -and [string]::Equals($trustMode, 'unsignedExplicit', [System.StringComparison]::OrdinalIgnoreCase)) {
        $notes.Add('Unsigned definitions are trusted by explicit local configuration.') | Out-Null
    }

    return [pscustomobject]@{
        RepositoryId     = $RepositoryId
        Kind             = $kind
        Enabled          = $enabled
        Trusted          = $trusted
        TrustMode        = $trustMode
        Effective        = ($enabled -and $trusted -and $kind -in @('moduleLocal', 'filesystem'))
        SearchOrder      = if ($Source.PSObject.Properties['searchOrder']) { [int]$Source.searchOrder } else { $null }
        DefinitionRoot   = if ($Source.PSObject.Properties['definitionRoot']) { [string]$Source.definitionRoot } else { $null }
        BasePath         = if ($Source.PSObject.Properties['basePath']) { [string]$Source.basePath } else { $null }
        ResolvedRootPath = Resolve-PackageRepositoryRootForDisplay -Source $Source -ApplicationRootDirectory $ApplicationRootDirectory
        InventoryPath    = $InventoryPath
        TrustedAtUtc     = if ($Source.PSObject.Properties['trustedAtUtc']) { [string]$Source.trustedAtUtc } else { $null }
        TrustReason      = if ($Source.PSObject.Properties['trustReason']) { [string]$Source.trustReason } else { $null }
        Notes            = @($notes.ToArray())
    }
}

function Get-PackageRepositorySummaries {
    [CmdletBinding()]
    param()

    $documentInfo = Get-PackageRepositoryInventoryEditInfo
    $applicationRootDirectory = $null
    try {
        $globalDocumentInfo = Read-PackageJsonDocument -Path (Get-PackageGlobalConfigPath)
        Assert-PackageGlobalConfigSchema -GlobalDocumentInfo $globalDocumentInfo
        $applicationRootDirectory = Resolve-PackageApplicationRootDirectory -GlobalConfiguration $globalDocumentInfo.Document.package
    }
    catch {
        Write-Warning "Repository summaries could not resolve application root. Showing raw repository inventory only. $($_.Exception.Message)"
    }

    foreach ($sourceProperty in @($documentInfo.Document.repositorySources.PSObject.Properties)) {
        Select-PackageRepositorySummary -RepositoryId $sourceProperty.Name -Source $sourceProperty.Value -InventoryPath $documentInfo.Path -ApplicationRootDirectory $applicationRootDirectory
    }
}

function New-PackageRepositoryCommandResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryId,

        [Parameter(Mandatory = $true)]
        [string]$InventoryPath,

        [AllowNull()]
        [psobject]$Before,

        [AllowNull()]
        [psobject]$After,

        [string]$Status = 'Updated',

        [string[]]$Notes = @()
    )

    foreach ($note in @($Notes)) {
        if (-not [string]::IsNullOrWhiteSpace($note)) {
            Write-Warning $note
        }
    }

    return [pscustomobject]@{
        Action        = $Action
        RepositoryId  = $RepositoryId
        InventoryPath = $InventoryPath
        Status        = $Status
        Before        = $Before
        After         = $After
        Notes         = @($Notes)
    }
}

function Resolve-PackageRepositoryRootPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryId,

        [Parameter(Mandatory = $true)]
        [psobject]$Source,

        [AllowNull()]
        [string]$ApplicationRootDirectory = $null
    )

    $kind = [string]$Source.kind
    if (-not [bool]$Source.enabled) {
        throw "Package repository '$RepositoryId' is disabled in RepositoryInventory.json."
    }
    if (-not [bool]$Source.trusted) {
        throw "Package repository '$RepositoryId' is not trusted. Use Trust-PackageRepository for trusted filesystem repositories."
    }

    if ([string]::Equals($kind, 'moduleLocal', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ([string]::Equals($RepositoryId, (Get-PackageDefaultRepositoryId), [System.StringComparison]::OrdinalIgnoreCase)) {
            return [System.IO.Path]::GetFullPath((Join-Path (Get-PackageRepositoriesRoot) $RepositoryId))
        }
        return Resolve-ConfiguredPath -PathValue ([string]$Source.definitionRoot) -BaseDirectory (Split-Path -Parent (Get-PackageConfigurationRoot)) -Tokens @{}
    }

    if ([string]::Equals($kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not [string]::Equals([string]$Source.trustMode, 'unsignedExplicit', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package repository '$RepositoryId' is filesystem but does not use trustMode='unsignedExplicit'. Use Trust-PackageRepository -AllowUnsignedDefinitions."
        }
        if (-not [string]::IsNullOrWhiteSpace($ApplicationRootDirectory)) {
            return Resolve-PackageConfiguredPath -PathValue ([string]$Source.basePath) -ApplicationRootDirectory $ApplicationRootDirectory
        }
        return Resolve-PackagePathValue -PathValue ([string]$Source.basePath)
    }

    if ([string]::Equals($kind, 'httpsCatalog', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package repository '$RepositoryId' uses kind 'httpsCatalog', which is reserved for future support and is not implemented yet."
    }

    throw "Package repository '$RepositoryId' uses unsupported kind '$kind'."
}

function Resolve-PackageDefinitionSnapshotReference {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RepositoryId = (Get-PackageDefaultRepositoryId),

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [string]$PackageInventoryFilePath,

        [AllowNull()]
        [string]$LiveResolutionError = $null
    )

    $resolvedRepositoryId = if ([string]::IsNullOrWhiteSpace($RepositoryId)) { Get-PackageDefaultRepositoryId } else { [string]$RepositoryId }
    if (-not (Test-Path -LiteralPath $PackageInventoryFilePath -PathType Leaf)) {
        throw "Package repository '$resolvedRepositoryId' definition '$DefinitionId' could not be resolved from the live repository source, and no package inventory exists for snapshot fallback. Live error: $LiveResolutionError"
    }

    $inventoryInfo = Read-PackageJsonDocument -Path $PackageInventoryFilePath
    $records = @(
        foreach ($record in @($inventoryInfo.Document.records)) {
            if ([string]::Equals([string]$record.definitionRepositoryId, $resolvedRepositoryId, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$record.definitionId, $DefinitionId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $snapshotPath = if ($record.PSObject.Properties['definitionSnapshotPath']) { [string]$record.definitionSnapshotPath } elseif ($record.PSObject.Properties['definitionLocalPath']) { [string]$record.definitionLocalPath } else { $null }
                if (-not [string]::IsNullOrWhiteSpace($snapshotPath) -and (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
                    $record
                }
            }
        }
    )

    if ($records.Count -eq 0) {
        throw "Package repository '$resolvedRepositoryId' definition '$DefinitionId' could not be resolved from the live repository source, and no usable definition snapshot was found in '$PackageInventoryFilePath'. Live error: $LiveResolutionError"
    }

    $selectedRecord = @($records | Sort-Object -Property updatedAtUtc -Descending | Select-Object -First 1)[0]
    $selectedSnapshotPath = if ($selectedRecord.PSObject.Properties['definitionSnapshotPath']) { [string]$selectedRecord.definitionSnapshotPath } else { [string]$selectedRecord.definitionLocalPath }

    return [pscustomobject]@{
        RepositoryId       = $resolvedRepositoryId
        DefinitionId       = [string]$DefinitionId
        DefinitionPath     = [System.IO.Path]::GetFullPath($selectedSnapshotPath)
        SourceKind         = 'snapshot'
        SourcePath         = if ($selectedRecord.PSObject.Properties['definitionSourcePath']) { [string]$selectedRecord.definitionSourcePath } else { $null }
        SourceHash         = if ($selectedRecord.PSObject.Properties['definitionSourceHash']) { [string]$selectedRecord.definitionSourceHash } else { $null }
        SnapshotPath       = [System.IO.Path]::GetFullPath($selectedSnapshotPath)
        SnapshotHash       = Get-PackageFileSha256 -Path $selectedSnapshotPath
        ResolvedAtUtc      = [DateTime]::UtcNow.ToString('o')
        SnapshotFallback   = $true
        FallbackReason     = $LiveResolutionError
        InventoryRecord    = $selectedRecord
    }
}
