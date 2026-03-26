<#
    Eigenverft.Manifested.Sandbox.Runtime.Node.Package
#>

function Get-NodeRelease {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-NodeFlavor
    }

    $response = Invoke-WebRequestEx -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
    $items = $response.Content | ConvertFrom-Json

    $release = $items |
        Where-Object { $_.lts -and $_.lts -ne $false } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-NodeVersion -VersionText $_.version } } |
        Select-Object -First 1

    if (-not $release) {
        throw 'Unable to determine the latest Node.js LTS release.'
    }

    $fileName = 'node-{0}-{1}.zip' -f $release.version, $Flavor
    $baseUrl = 'https://nodejs.org/dist/{0}' -f $release.version

    [pscustomobject]@{
        Version     = $release.version
        Flavor      = $Flavor
        FileName    = $fileName
        Path        = $null
        Source      = 'online'
        Action      = 'SelectedOnline'
        NpmVersion  = $release.npm
        DownloadUrl = '{0}/{1}' -f $baseUrl, $fileName
        ShasumsUrl  = '{0}/SHASUMS256.txt' -f $baseUrl
    }
}

function Get-CachedNodeRuntimePackages {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-NodeFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $layout.NodeCacheRoot)) {
        return @()
    }

    $pattern = '^node-(v\d+\.\d+\.\d+)-' + [regex]::Escape($Flavor) + '\.zip$'

    $items = Get-ChildItem -LiteralPath $layout.NodeCacheRoot -File -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            [pscustomobject]@{
                Version     = $matches[1]
                Flavor      = $Flavor
                FileName    = $_.Name
                Path        = $_.FullName
                Source      = 'cache'
                Action      = 'SelectedCache'
                NpmVersion  = $null
                DownloadUrl = $null
                ShasumsUrl  = $null
            }
        } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-NodeVersion -VersionText $_.Version } }

    return @($items)
}

function Get-LatestCachedNodeRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-CachedNodeRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot | Select-Object -First 1)
}

function Save-NodeRuntimePackage {
    [CmdletBinding()]
    param(
        [switch]$RefreshNode,
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-NodeFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.NodeCacheRoot | Out-Null

    $release = $null
    try {
        $release = Get-NodeRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    if ($release) {
        $packagePath = Join-Path $layout.NodeCacheRoot $release.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($RefreshNode -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                Write-Host "Downloading Node.js $($release.Version) ($Flavor)..."
                Invoke-WebRequestEx -Uri $release.DownloadUrl -OutFile $downloadPath -UseBasicParsing
                Move-Item -LiteralPath $downloadPath -Destination $packagePath -Force
                $action = 'Downloaded'
            }
            catch {
                Remove-ManifestedPath -Path $downloadPath | Out-Null
                if (-not (Test-Path -LiteralPath $packagePath)) {
                    throw
                }

                Write-Warning ('Could not refresh the Node.js package. Using cached copy. ' + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        return [pscustomobject]@{
            Version     = $release.Version
            Flavor      = $Flavor
            FileName    = $release.FileName
            Path        = $packagePath
            Source      = if ($action -eq 'Downloaded') { 'online' } else { 'cache' }
            Action      = $action
            NpmVersion  = $release.NpmVersion
            DownloadUrl = $release.DownloadUrl
            ShasumsUrl  = $release.ShasumsUrl
        }
    }

    $cachedPackage = Get-LatestCachedNodeRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    if (-not $cachedPackage) {
        throw 'Could not reach nodejs.org and no cached Node.js ZIP was found.'
    }

    return [pscustomobject]@{
        Version     = $cachedPackage.Version
        Flavor      = $cachedPackage.Flavor
        FileName    = $cachedPackage.FileName
        Path        = $cachedPackage.Path
        Source      = 'cache'
        Action      = 'SelectedCache'
        NpmVersion  = $null
        DownloadUrl = $null
        ShasumsUrl  = $null
    }
}

