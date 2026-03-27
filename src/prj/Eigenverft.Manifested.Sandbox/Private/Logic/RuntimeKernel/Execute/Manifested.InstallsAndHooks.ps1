function Invoke-ManifestedNpmGlobalPackageInstallFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $installBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'npmGlobalPackage'
    $factsBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'facts' -BlockName 'npmCli'
    if (-not $installBlock -or -not $factsBlock) {
        throw "The npm CLI install blocks for '$($Definition.commandName)' were not available."
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $cacheRoot = $layout.($installBlock.cacheRootLayoutProperty)
    $toolsRoot = $layout.($installBlock.toolsRootLayoutProperty)
    New-ManifestedDirectory -Path $cacheRoot | Out-Null
    New-ManifestedDirectory -Path $toolsRoot | Out-Null

    $nodeFacts = Get-ManifestedRuntimeDependencyFacts -RuntimeName 'NodeRuntime' -LocalRoot $LocalRoot
    $npmCmd = $null
    if ($nodeFacts -and $nodeFacts.Runtime -and $nodeFacts.Runtime.PSObject.Properties['NpmCmd']) {
        $npmCmd = $nodeFacts.Runtime.NpmCmd
    }
    if ([string]::IsNullOrWhiteSpace($npmCmd) -and $nodeFacts -and -not [string]::IsNullOrWhiteSpace($nodeFacts.RuntimeHome)) {
        $candidateNpmCmd = Join-Path $nodeFacts.RuntimeHome 'npm.cmd'
        if (Test-Path -LiteralPath $candidateNpmCmd) {
            $npmCmd = $candidateNpmCmd
        }
    }
    if ([string]::IsNullOrWhiteSpace($npmCmd)) {
        throw "A usable npm command could not be resolved for '$($Definition.commandName)'."
    }

    $stagePrefix = if ($installBlock.PSObject.Properties.Match('stagePrefix').Count -gt 0) { $installBlock.stagePrefix } else { (($Definition.runtimeName -replace 'Runtime$', '')).ToLowerInvariant() }
    $stagePath = New-ManifestedStageDirectory -Prefix $stagePrefix -Mode TemporaryShort
    $npmConfiguration = Get-ManifestedManagedNpmCommandArguments -NpmCmd $npmCmd -LocalRoot $LocalRoot
    $npmArguments = @('install', '-g', '--prefix', $stagePath, '--cache', $cacheRoot)
    $npmArguments += @($npmConfiguration.CommandArguments)
    $npmArguments += $installBlock.packageSpec

    Write-Host ('Installing ' + $Definition.runtimeName + ' CLI into managed sandbox tools...')
    & $npmCmd @npmArguments
    if ($LASTEXITCODE -ne 0) {
        throw "npm install for $($Definition.runtimeName) exited with code $LASTEXITCODE."
    }

    $stageValidation = Test-ManifestedNpmCliRuntimeHome -Definition $Definition -RuntimeHome $stagePath
    if (-not $stageValidation.IsUsable) {
        throw "$($Definition.runtimeName) validation failed after staged install at $stagePath."
    }

    $version = if ($stageValidation.PackageVersion) { $stageValidation.PackageVersion } else { $stageValidation.ReportedVersion }
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Could not determine the installed version for '$($Definition.runtimeName)'."
    }

    $runtimeHome = Join-Path $toolsRoot $version
    if (Test-Path -LiteralPath $runtimeHome) {
        Remove-ManifestedPath -Path $runtimeHome | Out-Null
    }

    Move-Item -LiteralPath $stagePath -Destination $runtimeHome -Force

    $validation = Test-ManifestedNpmCliRuntimeHome -Definition $Definition -RuntimeHome $runtimeHome
    if (-not $validation.IsUsable) {
        throw "$($Definition.runtimeName) validation failed after install at $runtimeHome."
    }

    return [pscustomobject]@{
        Action          = 'Installed'
        Version         = $validation.PackageVersion
        RuntimeHome     = $runtimeHome
        ExecutablePath  = $validation.CommandPath
        PackageJsonPath = $validation.PackageJsonPath
        Source          = 'Managed'
        CacheRoot       = $cacheRoot
        NpmCmd          = $npmCmd
    }
}
