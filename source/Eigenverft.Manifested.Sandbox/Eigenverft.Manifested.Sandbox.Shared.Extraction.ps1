<#
    Eigenverft.Manifested.Sandbox.Shared.Extraction
#>

function Get-ManifestedStageRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        throw 'A stage prefix is required.'
    }

    return (Join-Path (Get-ManifestedTemporaryRoot) $Prefix)
}

function Get-ManifestedLegacyStageDirectories {
    [CmdletBinding()]
    param(
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($RootPath) -or -not (Test-Path -LiteralPath $RootPath)) {
        return @()
    }

    $pattern = '_stage_{0}_*' -f $Prefix
    return @(Get-ChildItem -LiteralPath $RootPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern })
}

function New-ManifestedStageDirectory {
    [CmdletBinding()]
    param(
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [ValidateSet('LegacyLocal', 'TemporaryShort')]
        [string]$Mode = 'LegacyLocal'
    )

    switch ($Mode) {
        'LegacyLocal' {
            if ([string]::IsNullOrWhiteSpace($RootPath)) {
                throw 'A root path is required when using LegacyLocal stage mode.'
            }

            $stageRoot = New-ManifestedDirectory -Path $RootPath
            $stageName = '_stage_{0}_{1}' -f $Prefix, [Guid]::NewGuid().ToString('N')
        }

        'TemporaryShort' {
            $stageRoot = Get-ManifestedStageRoot -Prefix $Prefix
            New-ManifestedDirectory -Path $stageRoot | Out-Null
            $stageName = [Guid]::NewGuid().ToString('N').Substring(0, 12)
        }
    }

    $stagePath = Join-Path $stageRoot $stageName
    New-ManifestedDirectory -Path $stagePath | Out-Null

    return $stagePath
}

function Get-ManifestedStageDirectories {
    [CmdletBinding()]
    param(
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [ValidateSet('LegacyLocal', 'TemporaryShort')]
        [string]$Mode = 'LegacyLocal',

        [string[]]$LegacyRootPaths = @()
    )

    $stageDirectories = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]

    switch ($Mode) {
        'LegacyLocal' {
            foreach ($directory in @(Get-ManifestedLegacyStageDirectories -RootPath $RootPath -Prefix $Prefix)) {
                $stageDirectories.Add($directory) | Out-Null
            }
        }

        'TemporaryShort' {
            $stageRoot = Get-ManifestedStageRoot -Prefix $Prefix
            if (Test-Path -LiteralPath $stageRoot) {
                foreach ($directory in @(Get-ChildItem -LiteralPath $stageRoot -Directory -ErrorAction SilentlyContinue)) {
                    $stageDirectories.Add($directory) | Out-Null
                }
            }

            foreach ($legacyRootPath in @($LegacyRootPaths)) {
                foreach ($directory in @(Get-ManifestedLegacyStageDirectories -RootPath $legacyRootPath -Prefix $Prefix)) {
                    $stageDirectories.Add($directory) | Out-Null
                }
            }
        }
    }

    return @($stageDirectories | Sort-Object -Property FullName -Unique)
}

function Expand-ManifestedArchiveToStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $PackagePath)) {
        throw "Archive package '$PackagePath' was not found."
    }

    $stagePath = New-ManifestedStageDirectory -Prefix $Prefix -Mode TemporaryShort
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $stagePath -Force

    [pscustomobject]@{
        StagePath    = $stagePath
        ExpandedRoot = (Get-ManifestedExpandedArchiveRoot -StagePath $stagePath)
    }
}
