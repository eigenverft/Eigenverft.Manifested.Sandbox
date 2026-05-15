<#
    Eigenverft.Manifested.Sandbox.Package - PackagePublisherInventory.json management helpers.
#>

function Get-PackagePublisherEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Document
    )

    if (-not $Document.PSObject.Properties['publishers'] -or $null -eq $Document.publishers) {
        return @()
    }
    if ($Document.publishers -isnot [System.Array]) {
        throw "Package publisher inventory must define publishers as an array of objects with publisherId."
    }

    return @($Document.publishers)
}

function Assert-PackagePublisherInventorySchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PublisherInventoryDocumentInfo
    )

    $document = $PublisherInventoryDocumentInfo.Document
    if (-not $document.PSObject.Properties['inventoryVersion']) {
        throw "Package publisher inventory '$($PublisherInventoryDocumentInfo.Path)' is missing inventoryVersion."
    }
    if (-not $document.PSObject.Properties['publishers'] -or $null -eq $document.publishers) {
        throw "Package publisher inventory '$($PublisherInventoryDocumentInfo.Path)' is missing publishers."
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($publisher in @(Get-PackagePublisherEntries -Document $document)) {
        foreach ($requiredProperty in @('publisherId', 'enabled', 'trusted', 'searchOrder', 'trustMode')) {
            if (-not $publisher.PSObject.Properties[$requiredProperty] -or
                ($requiredProperty -in @('publisherId', 'trustMode') -and [string]::IsNullOrWhiteSpace([string]$publisher.$requiredProperty))) {
                throw "Package publisher inventory '$($PublisherInventoryDocumentInfo.Path)' has a publisher missing '$requiredProperty'."
            }
        }

        $publisherId = [string]$publisher.publisherId
        if (-not $seen.Add($publisherId)) {
            throw "Package publisher inventory '$($PublisherInventoryDocumentInfo.Path)' defines duplicate publisherId '$publisherId'."
        }
        if ($publisherId -notmatch '^[A-Za-z][A-Za-z0-9_.-]*$') {
            throw "Package publisher '$publisherId' in '$($PublisherInventoryDocumentInfo.Path)' is invalid. Use letters, numbers, '.', '-' or '_' and start with a letter."
        }

        $trustMode = [string]$publisher.trustMode
        if ($trustMode -notin @('moduleShipped', 'unsignedExplicit')) {
            throw "Package publisher '$publisherId' in '$($PublisherInventoryDocumentInfo.Path)' has unsupported trustMode '$trustMode'."
        }
        if ([string]::Equals($trustMode, 'moduleShipped', [System.StringComparison]::OrdinalIgnoreCase) -and -not [bool]$publisher.trusted) {
            throw "Package publisher '$publisherId' uses trustMode='moduleShipped' but trusted is false."
        }
        if ([string]::Equals($trustMode, 'unsignedExplicit', [System.StringComparison]::OrdinalIgnoreCase) -and -not [bool]$publisher.trusted) {
            throw "Package publisher '$publisherId' uses trustMode='unsignedExplicit' but trusted is false."
        }
    }
}

function Get-PackagePublisherInventoryInfo {
    [CmdletBinding()]
    param()

    $inventoryPath = Get-PackagePublisherInventoryPath
    $documentInfo = Read-PackageJsonDocument -Path $inventoryPath
    Assert-PackagePublisherInventorySchema -PublisherInventoryDocumentInfo $documentInfo
    $documentInfo | Add-Member -MemberType NoteProperty -Name Exists -Value $true -Force
    return $documentInfo
}

function Get-PackageEnabledTrustedPublisherRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PublisherInventoryDocument
    )

    $rows = @(
        foreach ($publisher in @(Get-PackagePublisherEntries -Document $PublisherInventoryDocument)) {
            if (-not [bool]$publisher.enabled) {
                continue
            }
            if (-not [bool]$publisher.trusted) {
                continue
            }

            [pscustomobject]@{
                PublisherId   = [string]$publisher.publisherId
                PublisherName = if ($publisher.PSObject.Properties['publisherName']) { [string]$publisher.publisherName } else { $null }
                SearchOrder   = if ($publisher.PSObject.Properties['searchOrder']) { [int]$publisher.searchOrder } else { 1000 }
                TrustMode     = [string]$publisher.trustMode
                Source        = $publisher
            }
        }
    )

    return @($rows | Sort-Object -Property SearchOrder, PublisherId)
}
