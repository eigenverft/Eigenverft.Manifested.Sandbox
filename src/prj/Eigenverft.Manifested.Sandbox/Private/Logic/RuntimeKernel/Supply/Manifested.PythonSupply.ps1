function Get-ManifestedPythonReleaseCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$VersionSpec
    )

    $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'pythonEmbed'
    if (-not $supplyBlock) {
        return @()
    }

    $releaseCandidatesPattern = if ($supplyBlock.PSObject.Properties.Match('releaseCandidatesPattern').Count -gt 0 -and $supplyBlock.releaseCandidatesPattern) {
        [string]$supplyBlock.releaseCandidatesPattern
    }
    else {
        '(?is)<a href="/downloads/release/python-(?<slug>\d+)/">Python (?<version>\d+\.\d+\.\d+) - (?<releaseDate>[^<]+)</a>'
    }

    $response = Invoke-WebRequestEx -Uri 'https://www.python.org/downloads/windows/' -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -UseBasicParsing
    $matches = [regex]::Matches($response.Content, $releaseCandidatesPattern)
    $items = New-Object System.Collections.Generic.List[object]
    $seenVersions = @{}

    foreach ($match in $matches) {
        $versionText = $match.Groups['version'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($versionText) -or $seenVersions.ContainsKey($versionText)) {
            continue
        }

        $versionObject = ConvertTo-ManifestedVersionObjectFromRule -VersionText $versionText -Rule $VersionSpec.RuntimeVersionRule
        if (-not $versionObject -or -not (Test-ManifestedManagedVersion -Version $versionObject -VersionPolicy $VersionSpec.VersionPolicy -Rule $VersionSpec.RuntimeVersionRule)) {
            continue
        }

        $seenVersions[$versionText] = $true
        $items.Add([pscustomobject]@{
                ReleaseId   = $match.Groups['slug'].Value.Trim()
                Version     = $versionText
                ReleaseDate = $match.Groups['releaseDate'].Value.Trim()
                ReleaseUrl  = ('https://www.python.org/downloads/release/python-{0}/' -f $match.Groups['slug'].Value.Trim())
            }) | Out-Null
    }

    return @(
        $items |
            Sort-Object -Descending -Property @{
                Expression = { ConvertTo-ManifestedVersionObjectFromRule -VersionText $_.Version -Rule $VersionSpec.RuntimeVersionRule }
            }
    )
}

function Get-ManifestedPythonReleaseAssetDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReleaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'pythonEmbed'
    if (-not $supplyBlock) {
        throw "The pythonEmbed supply block for '$($Definition.commandName)' was not available."
    }

    $descriptionPattern = Get-ManifestedFlavorMappedValue -Map $supplyBlock.descriptionPatternByFlavor -Flavor $Flavor
    if ([string]::IsNullOrWhiteSpace($descriptionPattern)) {
        throw "Unsupported Python flavor '$Flavor'."
    }

    $response = Invoke-WebRequestEx -Uri $ReleaseUrl -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -UseBasicParsing
    $pattern = '(?is)<tr>\s*<td><a href="(?<url>[^"]+)">' + $descriptionPattern + '</a>.*?<td><code class="checksum">(?<checksumHtml>.*?)</code></td>\s*</tr>'
    $match = [regex]::Match($response.Content, $pattern)
    if (-not $match.Success) {
        throw "Could not find the Python embeddable package row for flavor '$Flavor' in $ReleaseUrl."
    }

    $downloadUrl = $match.Groups['url'].Value.Trim()
    $checksumText = ($match.Groups['checksumHtml'].Value -replace '<[^>]+>', '')
    $checksum = ($checksumText -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
    if ($checksum.Length -ne 64) {
        throw "Could not resolve a trusted SHA256 checksum for '$downloadUrl'."
    }

    return [pscustomobject]@{
        DownloadUrl = $downloadUrl
        FileName    = [System.IO.Path]::GetFileName(([uri]$downloadUrl).AbsolutePath)
        Sha256      = $checksum
        ShaSource   = 'ReleaseHtml'
    }
}
