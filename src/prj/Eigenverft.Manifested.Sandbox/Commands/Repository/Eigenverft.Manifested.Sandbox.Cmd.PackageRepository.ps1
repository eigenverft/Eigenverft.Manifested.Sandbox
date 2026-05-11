<#
    Public repository-management command surface.
#>

function Get-PackageRepository {
    [CmdletBinding()]
    param(
        [string]$RepositoryId
    )

    $repositories = @(Get-PackageRepositorySummaries)
    if ([string]::IsNullOrWhiteSpace($RepositoryId)) {
        return $repositories
    }

    $match = @($repositories | Where-Object { [string]::Equals([string]$_.RepositoryId, $RepositoryId, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($match.Count -eq 0) {
        throw "Package repository '$RepositoryId' was not found in '$((Get-PackageRepositoryInventoryPath))'."
    }

    return $match
}

function Add-PackageRepository {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath,

        [int]$SearchOrder = -1,

        [string]$After,

        [switch]$Disabled,

        [switch]$TrustUnsigned
    )

    Assert-PackageRepositoryId -RepositoryId $RepositoryId

    $documentInfo = Get-PackageRepositoryInventoryEditInfo
    if (Get-PackageRepositorySourceProperty -Document $documentInfo.Document -RepositoryId $RepositoryId) {
        throw "Package repository '$RepositoryId' already exists in '$($documentInfo.Path)'. Use Set-PackageRepository to modify it."
    }

    $resolvedSearchOrder = if ($SearchOrder -ge 0) {
        $SearchOrder
    }
    elseif (-not [string]::IsNullOrWhiteSpace($After)) {
        Get-PackageRepositorySearchOrderAfter -Document $documentInfo.Document -AfterRepositoryId $After
    }
    else {
        Get-PackageNextRepositorySearchOrder -Document $documentInfo.Document
    }
    $source = New-PackageFilesystemRepositorySource -BasePath $BasePath -SearchOrder $resolvedSearchOrder -Enabled (-not $Disabled.IsPresent) -Trusted $TrustUnsigned.IsPresent -TrustReason 'Trusted by Add-PackageRepository -TrustUnsigned.'

    if ($PSCmdlet.ShouldProcess($documentInfo.Path, "Add package repository '$RepositoryId'")) {
        $documentInfo.Document.repositorySources | Add-Member -MemberType NoteProperty -Name $RepositoryId -Value $source -Force
        Save-PackageRepositoryInventoryDocument -DocumentInfo $documentInfo
    }

    $afterSummary = Get-PackageRepository -RepositoryId $RepositoryId
    $notes = New-Object System.Collections.Generic.List[string]
    if ($Disabled.IsPresent) {
        $notes.Add("Repository '$RepositoryId' was added disabled; package commands will not use it until enabled.") | Out-Null
    }
    if ($TrustUnsigned.IsPresent) {
        $notes.Add("Repository '$RepositoryId' trusts unsigned filesystem definitions by explicit local configuration.") | Out-Null
    }
    else {
        $notes.Add("Repository '$RepositoryId' was added untrusted; run Trust-PackageRepository -RepositoryId '$RepositoryId' -AllowUnsignedDefinitions before executing definitions from it.") | Out-Null
    }

    return New-PackageRepositoryCommandResult -Action 'Add' -RepositoryId $RepositoryId -InventoryPath $documentInfo.Path -Before $null -After $afterSummary -Status 'Added' -Notes @($notes.ToArray())
}

function Add-TeamPackageRepository {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath,

        [ValidateNotNullOrEmpty()]
        [string]$RepositoryId = 'teamPackageRepository',

        [int]$SearchOrder = -1,

        [string]$After,

        [switch]$Disabled,

        [switch]$TrustUnsigned
    )

    $parameters = @{
        RepositoryId = $RepositoryId
        BasePath     = $BasePath
    }
    if ($SearchOrder -ge 0) {
        $parameters.SearchOrder = $SearchOrder
    }
    elseif (-not [string]::IsNullOrWhiteSpace($After)) {
        $parameters.After = $After
    }
    else {
        $parameters.SearchOrder = 150
    }
    if ($Disabled.IsPresent) {
        $parameters.Disabled = $true
    }
    if ($TrustUnsigned.IsPresent) {
        $parameters.TrustUnsigned = $true
    }
    if ($PSBoundParameters.ContainsKey('WhatIf')) {
        $parameters.WhatIf = [bool]$PSBoundParameters.WhatIf
    }
    if ($PSBoundParameters.ContainsKey('Confirm')) {
        $parameters.Confirm = [bool]$PSBoundParameters.Confirm
    }

    return Add-PackageRepository @parameters
}

function Set-PackageRepository {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryId,

        [string]$BasePath,

        [Nullable[int]]$SearchOrder,

        [switch]$Enable,

        [switch]$Disable,

        [switch]$Untrust
    )

    Assert-PackageRepositoryId -RepositoryId $RepositoryId
    if ($Enable.IsPresent -and $Disable.IsPresent) { throw 'Use either -Enable or -Disable, not both.' }

    $before = Get-PackageRepository -RepositoryId $RepositoryId
    $documentInfo = Get-PackageRepositoryInventoryEditInfo
    $sourceProperty = Get-PackageRepositorySourceProperty -Document $documentInfo.Document -RepositoryId $RepositoryId
    if (-not $sourceProperty) {
        throw "Package repository '$RepositoryId' was not found in '$($documentInfo.Path)'. Use Add-PackageRepository to create it."
    }

    $source = $sourceProperty.Value
    if ($PSBoundParameters.ContainsKey('BasePath')) {
        if (-not [string]::Equals([string]$source.kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package repository '$RepositoryId' is kind '$($source.kind)'. Only filesystem repositories support -BasePath."
        }
        $source | Add-Member -MemberType NoteProperty -Name 'basePath' -Value $BasePath -Force
    }
    if ($PSBoundParameters.ContainsKey('SearchOrder')) { $source | Add-Member -MemberType NoteProperty -Name 'searchOrder' -Value ([int]$SearchOrder.Value) -Force }
    if ($Enable.IsPresent) { $source | Add-Member -MemberType NoteProperty -Name 'enabled' -Value $true -Force }
    if ($Disable.IsPresent) { $source | Add-Member -MemberType NoteProperty -Name 'enabled' -Value $false -Force }
    if ($Untrust.IsPresent) {
        if ([string]::Equals([string]$source.kind, 'moduleLocal', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package repository '$RepositoryId' is moduleLocal and cannot be untrusted."
        }
        $source | Add-Member -MemberType NoteProperty -Name 'trusted' -Value $false -Force
        $source | Add-Member -MemberType NoteProperty -Name 'trustMode' -Value 'unsigned' -Force
        if ($source.PSObject.Properties['trustedAtUtc']) { $source.PSObject.Properties.Remove('trustedAtUtc') }
        if ($source.PSObject.Properties['trustReason']) { $source.PSObject.Properties.Remove('trustReason') }
    }

    if ($PSCmdlet.ShouldProcess($documentInfo.Path, "Set package repository '$RepositoryId'")) {
        Save-PackageRepositoryInventoryDocument -DocumentInfo $documentInfo
    }

    $after = Get-PackageRepository -RepositoryId $RepositoryId
    $notes = New-Object System.Collections.Generic.List[string]
    if (-not [bool]$after.Enabled) {
        $notes.Add("Repository '$RepositoryId' was updated but remains disabled; package commands will not use it until enabled.") | Out-Null
    }
    if (-not [bool]$after.Trusted) {
        $notes.Add("Repository '$RepositoryId' is untrusted; package commands will not execute definitions from it.") | Out-Null
    }
    if ($PSBoundParameters.ContainsKey('BasePath')) {
        $notes.Add("Repository '$RepositoryId' base path is now '$($after.BasePath)' and resolves to '$($after.ResolvedRootPath)'.") | Out-Null
    }

    return New-PackageRepositoryCommandResult -Action 'Set' -RepositoryId $RepositoryId -InventoryPath $documentInfo.Path -Before $before -After $after -Status 'Updated' -Notes @($notes.ToArray())
}

function Trust-PackageRepository {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryId,

        [switch]$AllowUnsignedDefinitions
    )

    Assert-PackageRepositoryId -RepositoryId $RepositoryId
    if (-not $AllowUnsignedDefinitions.IsPresent) {
        throw "Trust-PackageRepository v1 supports only explicit unsigned filesystem trust. Re-run with -AllowUnsignedDefinitions if this is intentional."
    }

    $before = Get-PackageRepository -RepositoryId $RepositoryId
    $documentInfo = Get-PackageRepositoryInventoryEditInfo
    $sourceProperty = Get-PackageRepositorySourceProperty -Document $documentInfo.Document -RepositoryId $RepositoryId
    if (-not $sourceProperty) {
        throw "Package repository '$RepositoryId' was not found in '$($documentInfo.Path)'."
    }

    $source = $sourceProperty.Value
    if (-not [string]::Equals([string]$source.kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package repository '$RepositoryId' is kind '$($source.kind)'. Trust-PackageRepository v1 only supports filesystem repositories."
    }

    $source | Add-Member -MemberType NoteProperty -Name 'trusted' -Value $true -Force
    $source | Add-Member -MemberType NoteProperty -Name 'trustMode' -Value 'unsignedExplicit' -Force
    $source | Add-Member -MemberType NoteProperty -Name 'trustedAtUtc' -Value ([DateTime]::UtcNow.ToString('o')) -Force
    $source | Add-Member -MemberType NoteProperty -Name 'trustReason' -Value 'Trusted by Trust-PackageRepository -AllowUnsignedDefinitions.' -Force

    if ($PSCmdlet.ShouldProcess($documentInfo.Path, "Trust package repository '$RepositoryId'")) {
        Save-PackageRepositoryInventoryDocument -DocumentInfo $documentInfo
    }

    $after = Get-PackageRepository -RepositoryId $RepositoryId
    return New-PackageRepositoryCommandResult -Action 'Trust' -RepositoryId $RepositoryId -InventoryPath $documentInfo.Path -Before $before -After $after -Status 'Trusted' -Notes @(
        "Repository '$RepositoryId' now trusts unsigned filesystem definitions by explicit local configuration."
    )
}

function Remove-PackageRepository {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryId,

        [switch]$Force
    )

    Assert-PackageRepositoryId -RepositoryId $RepositoryId
    if ([string]::Equals($RepositoryId, (Get-PackageDefaultRepositoryId), [System.StringComparison]::OrdinalIgnoreCase) -and -not $Force.IsPresent) {
        throw "Removing '$RepositoryId' can leave Package without its shipped definition repository. Re-run with -Force if this is intentional."
    }

    $before = Get-PackageRepository -RepositoryId $RepositoryId
    $documentInfo = Get-PackageRepositoryInventoryEditInfo
    $sourceProperty = Get-PackageRepositorySourceProperty -Document $documentInfo.Document -RepositoryId $RepositoryId
    if (-not $sourceProperty) {
        throw "Package repository '$RepositoryId' was not found in '$($documentInfo.Path)'."
    }

    if ($PSCmdlet.ShouldProcess($documentInfo.Path, "Remove package repository '$RepositoryId'")) {
        $documentInfo.Document.repositorySources.PSObject.Properties.Remove($RepositoryId)
        Save-PackageRepositoryInventoryDocument -DocumentInfo $documentInfo
    }

    return New-PackageRepositoryCommandResult -Action 'Remove' -RepositoryId $RepositoryId -InventoryPath $documentInfo.Path -Before $before -After $null -Status 'Removed' -Notes @(
        "Repository '$RepositoryId' was removed from configuration only. Repository files, installed packages, and local definition snapshots were not deleted."
    )
}
