<#
    Public package definition endpoint (scan root) management surface.

    Parameters named EndpointName identify a row by endpointName in PackageEndpointInventory.json.
    Invoke-Package -PublisherId is unrelated: it filters package definitions by trusted publisher identity.
#>

function Get-PackageEndpoint {
    [CmdletBinding()]
    param(
        [string]$EndpointName
    )

    $endpoints = @(Get-PackageEndpointSummaries)
    if ([string]::IsNullOrWhiteSpace($EndpointName)) {
        return $endpoints
    }

    $match = @($endpoints | Where-Object { [string]::Equals([string]$_.EndpointName, $EndpointName, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($match.Count -eq 0) {
        throw "Package endpoint '$EndpointName' was not found in '$((Get-PackageEndpointInventoryPath))'."
    }

    return $match
}

function Add-PackageEndpoint {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath,

        [int]$SearchOrder = -1,

        [string]$After,

        [switch]$Disabled,

        [switch]$TrustUnsigned,

        [AllowNull()]
        [string]$TrustReason = $null
    )

    Assert-PackageEndpointName -EndpointName $EndpointName

    $documentInfo = Get-PackageEndpointInventoryEditInfo
    if (Get-PackageEndpointSourceProperty -Document $documentInfo.Document -EndpointName $EndpointName) {
        throw "Package endpoint '$EndpointName' already exists in '$($documentInfo.Path)'. Use Set-PackageEndpoint to modify it."
    }

    $resolvedSearchOrder = if ($SearchOrder -ge 0) {
        $SearchOrder
    }
    elseif (-not [string]::IsNullOrWhiteSpace($After)) {
        Get-PackageEndpointSearchOrderAfter -Document $documentInfo.Document -AfterEndpointName $After
    }
    else {
        Get-PackageNextEndpointSearchOrder -Document $documentInfo.Document
    }
    $resolvedTrustReason = if ($TrustUnsigned.IsPresent) {
        if (-not [string]::IsNullOrWhiteSpace($TrustReason)) {
            [string]$TrustReason
        }
        else {
            'Trusted by Add-PackageEndpoint -TrustUnsigned.'
        }
    }
    else {
        $null
    }
    $source = New-PackageFilesystemRepositorySource -EndpointName $EndpointName -BasePath $BasePath -SearchOrder $resolvedSearchOrder -Enabled (-not $Disabled.IsPresent) -Trusted $TrustUnsigned.IsPresent -TrustReason $resolvedTrustReason

    if ($PSCmdlet.ShouldProcess($documentInfo.Path, "Add package endpoint '$EndpointName'")) {
        $documentInfo.Document.endpoints = @($documentInfo.Document.endpoints) + $source
        Save-PackageEndpointInventoryDocument -DocumentInfo $documentInfo
    }

    $afterSummary = Get-PackageEndpoint -EndpointName $EndpointName
    $notes = New-Object System.Collections.Generic.List[string]
    if ($Disabled.IsPresent) {
        $notes.Add("Endpoint '$EndpointName' was added disabled; package commands will not use it until enabled.") | Out-Null
    }
    if ($TrustUnsigned.IsPresent) {
        $notes.Add("Endpoint '$EndpointName' trusts unsigned filesystem definitions by explicit local configuration.") | Out-Null
    }
    else {
        $notes.Add("Endpoint '$EndpointName' was added untrusted; run Trust-PackageEndpoint -EndpointName '$EndpointName' -AllowUnsignedDefinitions before executing definitions from it.") | Out-Null
    }

    return New-PackageEndpointCommandResult -Action 'Add' -EndpointName $EndpointName -InventoryPath $documentInfo.Path -Before $null -After $afterSummary -Status 'Added' -Notes @($notes.ToArray())
}

function Add-TeamPackageEndpoint {
    <#
    .NOTES
    By default the team endpoint is added trusted for unsigned filesystem definitions so offline
    team shares work without a separate Trust-PackageEndpoint step. Use -Untrusted to require an
    explicit Trust-PackageEndpoint -AllowUnsignedDefinitions later (stricter workflow).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath,

        [ValidateNotNullOrEmpty()]
        [string]$EndpointName = 'teamPackageRepository',

        [int]$SearchOrder = -1,

        [string]$After,

        [switch]$Disabled,

        [switch]$Untrusted
    )

    $parameters = @{
        EndpointName = $EndpointName
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
    if (-not $Untrusted.IsPresent) {
        $parameters.TrustUnsigned = $true
        $parameters.TrustReason = 'Trusted by Add-TeamPackageEndpoint (team share default).'
    }
    if ($PSBoundParameters.ContainsKey('WhatIf')) {
        $parameters.WhatIf = [bool]$PSBoundParameters.WhatIf
    }
    if ($PSBoundParameters.ContainsKey('Confirm')) {
        $parameters.Confirm = [bool]$PSBoundParameters.Confirm
    }

    return Add-PackageEndpoint @parameters
}

function Set-PackageEndpoint {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointName,

        [string]$BasePath,

        [Nullable[int]]$SearchOrder,

        [switch]$Enable,

        [switch]$Disable,

        [switch]$Untrust
    )

    Assert-PackageEndpointName -EndpointName $EndpointName
    if ($Enable.IsPresent -and $Disable.IsPresent) { throw 'Use either -Enable or -Disable, not both.' }

    $before = Get-PackageEndpoint -EndpointName $EndpointName
    $documentInfo = Get-PackageEndpointInventoryEditInfo
    $sourceProperty = Get-PackageEndpointSourceProperty -Document $documentInfo.Document -EndpointName $EndpointName
    if (-not $sourceProperty) {
        throw "Package endpoint '$EndpointName' was not found in '$($documentInfo.Path)'. Use Add-PackageEndpoint to create it."
    }

    $source = $sourceProperty.Value
    if ($PSBoundParameters.ContainsKey('BasePath')) {
        if (-not [string]::Equals([string]$source.kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package endpoint '$EndpointName' is kind '$($source.kind)'. Only filesystem endpoints support -BasePath."
        }
        $source | Add-Member -MemberType NoteProperty -Name 'basePath' -Value $BasePath -Force
    }
    if ($PSBoundParameters.ContainsKey('SearchOrder')) { $source | Add-Member -MemberType NoteProperty -Name 'searchOrder' -Value ([int]$SearchOrder.Value) -Force }
    if ($Enable.IsPresent) { $source | Add-Member -MemberType NoteProperty -Name 'enabled' -Value $true -Force }
    if ($Disable.IsPresent) { $source | Add-Member -MemberType NoteProperty -Name 'enabled' -Value $false -Force }
    if ($Untrust.IsPresent) {
        if ([string]::Equals([string]$source.kind, 'moduleLocal', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package endpoint '$EndpointName' is moduleLocal and cannot be untrusted."
        }
        $source | Add-Member -MemberType NoteProperty -Name 'trusted' -Value $false -Force
        $source | Add-Member -MemberType NoteProperty -Name 'trustMode' -Value 'unsigned' -Force
        if ($source.PSObject.Properties['trustedAtUtc']) { $source.PSObject.Properties.Remove('trustedAtUtc') }
        if ($source.PSObject.Properties['trustReason']) { $source.PSObject.Properties.Remove('trustReason') }
    }

    if ($PSCmdlet.ShouldProcess($documentInfo.Path, "Set package endpoint '$EndpointName'")) {
        Save-PackageEndpointInventoryDocument -DocumentInfo $documentInfo
    }

    $after = Get-PackageEndpoint -EndpointName $EndpointName
    $notes = New-Object System.Collections.Generic.List[string]
    if (-not [bool]$after.Enabled) {
        $notes.Add("Endpoint '$EndpointName' was updated but remains disabled; package commands will not use it until enabled.") | Out-Null
    }
    if (-not [bool]$after.Trusted) {
        $notes.Add("Endpoint '$EndpointName' is untrusted; package commands will not execute definitions from it.") | Out-Null
    }
    if ($PSBoundParameters.ContainsKey('BasePath')) {
        $notes.Add("Endpoint '$EndpointName' base path is now '$($after.BasePath)' and resolves to '$($after.ResolvedRootPath)'.") | Out-Null
    }

    return New-PackageEndpointCommandResult -Action 'Set' -EndpointName $EndpointName -InventoryPath $documentInfo.Path -Before $before -After $after -Status 'Updated' -Notes @($notes.ToArray())
}

function Trust-PackageEndpoint {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointName,

        [switch]$AllowUnsignedDefinitions
    )

    Assert-PackageEndpointName -EndpointName $EndpointName
    if (-not $AllowUnsignedDefinitions.IsPresent) {
        throw "Trust-PackageEndpoint v1 supports only explicit unsigned filesystem trust. Re-run with -AllowUnsignedDefinitions if this is intentional."
    }

    $before = Get-PackageEndpoint -EndpointName $EndpointName
    $documentInfo = Get-PackageEndpointInventoryEditInfo
    $sourceProperty = Get-PackageEndpointSourceProperty -Document $documentInfo.Document -EndpointName $EndpointName
    if (-not $sourceProperty) {
        throw "Package endpoint '$EndpointName' was not found in '$($documentInfo.Path)'."
    }

    $source = $sourceProperty.Value
    if (-not [string]::Equals([string]$source.kind, 'filesystem', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package endpoint '$EndpointName' is kind '$($source.kind)'. Trust-PackageEndpoint v1 only supports filesystem endpoints."
    }

    $source | Add-Member -MemberType NoteProperty -Name 'trusted' -Value $true -Force
    $source | Add-Member -MemberType NoteProperty -Name 'trustMode' -Value 'unsignedExplicit' -Force
    $source | Add-Member -MemberType NoteProperty -Name 'trustedAtUtc' -Value ([DateTime]::UtcNow.ToString('o')) -Force
    $source | Add-Member -MemberType NoteProperty -Name 'trustReason' -Value 'Trusted by Trust-PackageEndpoint -AllowUnsignedDefinitions.' -Force

    if ($PSCmdlet.ShouldProcess($documentInfo.Path, "Trust package endpoint '$EndpointName'")) {
        Save-PackageEndpointInventoryDocument -DocumentInfo $documentInfo
    }

    $after = Get-PackageEndpoint -EndpointName $EndpointName
    return New-PackageEndpointCommandResult -Action 'Trust' -EndpointName $EndpointName -InventoryPath $documentInfo.Path -Before $before -After $after -Status 'Trusted' -Notes @(
        "Endpoint '$EndpointName' now trusts unsigned filesystem definitions by explicit local configuration."
    )
}

function Remove-PackageEndpoint {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointName,

        [switch]$Force
    )

    Assert-PackageEndpointName -EndpointName $EndpointName
    if ([string]::Equals($EndpointName, (Get-PackageDefaultEndpointName), [System.StringComparison]::OrdinalIgnoreCase) -and -not $Force.IsPresent) {
        throw "Removing '$EndpointName' can leave Package without its shipped definition scan endpoint. Re-run with -Force if this is intentional."
    }

    $before = Get-PackageEndpoint -EndpointName $EndpointName
    $documentInfo = Get-PackageEndpointInventoryEditInfo
    $sourceProperty = Get-PackageEndpointSourceProperty -Document $documentInfo.Document -EndpointName $EndpointName
    if (-not $sourceProperty) {
        throw "Package endpoint '$EndpointName' was not found in '$($documentInfo.Path)'."
    }

    if ($PSCmdlet.ShouldProcess($documentInfo.Path, "Remove package endpoint '$EndpointName'")) {
        $documentInfo.Document.endpoints = @($documentInfo.Document.endpoints | Where-Object {
                -not ([string]::Equals([string]$_.endpointName, $EndpointName, [System.StringComparison]::OrdinalIgnoreCase))
            })
        Save-PackageEndpointInventoryDocument -DocumentInfo $documentInfo
    }

    return New-PackageEndpointCommandResult -Action 'Remove' -EndpointName $EndpointName -InventoryPath $documentInfo.Path -Before $before -After $null -Status 'Removed' -Notes @(
        "Endpoint '$EndpointName' was removed from configuration only. Repository files, installed packages, and local definition snapshots were not deleted."
    )
}
