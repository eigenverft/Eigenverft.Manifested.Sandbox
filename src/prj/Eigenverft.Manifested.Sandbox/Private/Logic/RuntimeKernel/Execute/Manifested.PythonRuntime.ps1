function Get-ManifestedPythonRuntimePthPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    if (-not (Test-Path -LiteralPath $PythonHome)) {
        return $null
    }

    $pthFile = @(Get-ChildItem -LiteralPath $PythonHome -File -Filter 'python*._pth' -ErrorAction SilentlyContinue | Sort-Object -Property Name | Select-Object -First 1)
    if (-not $pthFile) {
        return $null
    }

    return $pthFile[0].FullName
}

function Test-ManifestedPythonSiteImports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    $pthPath = Get-ManifestedPythonRuntimePthPath -PythonHome $PythonHome
    if ([string]::IsNullOrWhiteSpace($pthPath) -or -not (Test-Path -LiteralPath $pthPath)) {
        return [pscustomobject]@{
            Exists                 = $false
            PthPath                = $pthPath
            ImportSiteEnabled      = $false
            SitePackagesPathListed = $false
            IsReady                = $false
        }
    }

    $lines = @(Get-Content -LiteralPath $pthPath -ErrorAction SilentlyContinue)
    $importSiteEnabled = $false
    $sitePackagesPathListed = $false

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq 'import site') {
            $importSiteEnabled = $true
        }
        elseif ($trimmedLine -ieq 'Lib\site-packages') {
            $sitePackagesPathListed = $true
        }
    }

    return [pscustomobject]@{
        Exists                 = $true
        PthPath                = $pthPath
        ImportSiteEnabled      = $importSiteEnabled
        SitePackagesPathListed = $sitePackagesPathListed
        IsReady                = ($importSiteEnabled -and $sitePackagesPathListed)
    }
}

function Enable-ManifestedPythonSiteImports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    $pthState = Test-ManifestedPythonSiteImports -PythonHome $PythonHome
    if (-not $pthState.Exists) {
        throw "Could not find the Python runtime ._pth file under $PythonHome."
    }

    $sitePackagesRoot = Join-Path $PythonHome 'Lib\site-packages'
    New-ManifestedDirectory -Path $sitePackagesRoot | Out-Null

    $lines = @(Get-Content -LiteralPath $pthState.PthPath -ErrorAction Stop)
    $updatedLines = New-Object System.Collections.Generic.List[string]
    $hasImportSite = $false
    $hasSitePackages = $false

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()

        if ($trimmedLine -match '^(#\s*)?import\s+site$') {
            if (-not $hasImportSite) {
                $updatedLines.Add('import site') | Out-Null
                $hasImportSite = $true
            }

            continue
        }

        if ($trimmedLine -ieq 'Lib\site-packages') {
            if (-not $hasSitePackages) {
                $updatedLines.Add('Lib\site-packages') | Out-Null
                $hasSitePackages = $true
            }

            continue
        }

        $updatedLines.Add($line) | Out-Null
    }

    if (-not $hasSitePackages) {
        $updatedLines.Add('Lib\site-packages') | Out-Null
    }
    if (-not $hasImportSite) {
        $updatedLines.Add('import site') | Out-Null
    }

    Set-Content -LiteralPath $pthState.PthPath -Value @($updatedLines) -Encoding ASCII
    return (Test-ManifestedPythonSiteImports -PythonHome $PythonHome)
}

function Save-ManifestedPythonGetPipScript {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $scriptPath = Join-Path $layout.PythonCacheRoot 'get-pip.py'
    $downloadPath = Get-ManifestedDownloadPath -TargetPath $scriptPath
    New-ManifestedDirectory -Path $layout.PythonCacheRoot | Out-Null

    $action = 'ReusedCache'
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Remove-ManifestedPath -Path $downloadPath | Out-Null

        try {
            Write-Host 'Downloading get-pip.py bootstrap script...'
            Enable-ManifestedTls12Support
            Invoke-WebRequestEx -Uri 'https://bootstrap.pypa.io/get-pip.py' -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -OutFile $downloadPath -UseBasicParsing
            Move-Item -LiteralPath $downloadPath -Destination $scriptPath -Force
            $action = 'Downloaded'
        }
        catch {
            Remove-ManifestedPath -Path $downloadPath | Out-Null
            if (-not (Test-Path -LiteralPath $scriptPath)) {
                throw
            }

            Write-Warning ('Could not refresh get-pip.py. Using cached copy. ' + $_.Exception.Message)
            $action = 'ReusedCache'
        }
    }

    return [pscustomobject]@{
        Path   = $scriptPath
        Action = $action
        Uri    = 'https://bootstrap.pypa.io/get-pip.py'
    }
}

function Ensure-ManifestedPythonPip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $siteState = Enable-ManifestedPythonSiteImports -PythonHome $PythonHome
    if (-not $siteState.IsReady) {
        throw "Python site import enablement failed for $PythonHome."
    }

    $pipProxyConfiguration = Get-ManifestedPipProxyConfigurationStatus -PythonExe $PythonExe -LocalRoot $LocalRoot
    if ($pipProxyConfiguration.Action -eq 'NeedsManagedProxy') {
        $pipProxyConfiguration = Sync-ManifestedPipProxyConfiguration -PythonExe $PythonExe -Status $pipProxyConfiguration -LocalRoot $LocalRoot
    }

    $existingPipProbe = Get-ManifestedPythonPipVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    $existingPipVersion = $existingPipProbe.PipVersion
    if (-not [string]::IsNullOrWhiteSpace($existingPipVersion)) {
        $wrapperInfo = Set-ManifestedManagedPipWrappers -PythonHome $PythonHome -LocalRoot $LocalRoot
        return [pscustomobject]@{
            Action                = 'Reused'
            Bootstrap             = 'Existing'
            PipVersion            = $existingPipVersion
            GetPipScript          = $null
            WrapperInfo           = $wrapperInfo
            PipProxyConfiguration = $pipProxyConfiguration
            ExistingPipProbe      = $existingPipProbe
            SiteImports           = $siteState
        }
    }

    $bootstrap = 'EnsurePip'
    $ensurePipResult = Invoke-ManifestedPipAwarePythonCommand -PythonExe $PythonExe -Arguments @('-m', 'ensurepip', '--default-pip') -LocalRoot $LocalRoot
    $pipVersion = Get-ManifestedPythonPipVersion -PythonExe $PythonExe -LocalRoot $LocalRoot
    $getPipScript = $null
    $getPipResult = $null

    if ($ensurePipResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($pipVersion)) {
        $bootstrap = 'GetPip'
        $getPipScript = Save-ManifestedPythonGetPipScript -LocalRoot $LocalRoot
        $getPipResult = Invoke-ManifestedPipAwarePythonCommand -PythonExe $PythonExe -Arguments @($getPipScript.Path) -LocalRoot $LocalRoot
        if ($getPipResult.ExitCode -ne 0) {
            throw (New-ManifestedPythonRuntimeValidationFailureMessage -Operation 'get-pip bootstrap' -PythonHome $PythonHome -CommandResult $getPipResult -SiteImportsState $siteState)
        }

        $pipVersion = Get-ManifestedPythonPipVersion -PythonExe $PythonExe -LocalRoot $LocalRoot
    }

    if ([string]::IsNullOrWhiteSpace($pipVersion)) {
        $bootstrapCommandResult = if ($bootstrap -eq 'EnsurePip') { $ensurePipResult } else { $getPipResult }
        throw (New-ManifestedPythonRuntimeValidationFailureMessage -Operation 'pip bootstrap' -PythonHome $PythonHome -CommandResult $bootstrapCommandResult -SiteImportsState $siteState)
    }

    $wrapperInfo = Set-ManifestedManagedPipWrappers -PythonHome $PythonHome -LocalRoot $LocalRoot

    return [pscustomobject]@{
        Action                = if ($bootstrap -eq 'EnsurePip') { 'InstalledEnsurePip' } else { 'InstalledGetPip' }
        Bootstrap             = $bootstrap
        PipVersion            = $pipVersion
        GetPipScript          = $getPipScript
        WrapperInfo           = $wrapperInfo
        PipProxyConfiguration = $pipProxyConfiguration
        SiteImports           = $siteState
    }
}

function Install-ManifestedPythonEmbeddableRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor = (Get-ManifestedDefinitionFlavor -Definition $Definition),

        [string]$LocalRoot = (Get-ManifestedLocalRoot),

        [switch]$ForceInstall
    )

    if ($PackageInfo.PSObject.Properties['Flavor'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Flavor)) {
        $Flavor = $PackageInfo.Flavor
    }

    $versionSpec = Get-ManifestedVersionSpec -Definition $Definition
    $pythonHome = Get-ManifestedManagedPythonRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $currentValidation = Test-ManifestedPythonRuntimeHome -PythonHome $pythonHome -VersionSpec $versionSpec -LocalRoot $LocalRoot
    $siteState = $null

    if ($ForceInstall -or $currentValidation.Status -ne 'Ready') {
        New-ManifestedDirectory -Path (Split-Path -Parent $pythonHome) | Out-Null

        $stagePrefix = 'python'
        $installBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'pythonEmbeddableZip'
        if ($installBlock -and $installBlock.PSObject.Properties.Match('stagePrefix').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($installBlock.stagePrefix)) {
            $stagePrefix = [string]$installBlock.stagePrefix
        }

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix $stagePrefix
            if (-not (Test-Path -LiteralPath $stageInfo.ExpandedRoot)) {
                throw 'The Python embeddable ZIP did not extract as expected.'
            }

            if (Test-Path -LiteralPath $pythonHome) {
                Remove-ManifestedPath -Path $pythonHome | Out-Null
            }

            New-ManifestedDirectory -Path $pythonHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $pythonHome -Force
            }

            $siteState = Enable-ManifestedPythonSiteImports -PythonHome $pythonHome
            if (-not $siteState.IsReady) {
                throw "Python site import enablement failed for $pythonHome."
            }
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $pythonExe = Join-Path $pythonHome 'python.exe'
    $versionProbe = Get-ManifestedPythonReportedVersionProbe -PythonExe $pythonExe -LocalRoot $LocalRoot
    $reportedVersion = $versionProbe.ReportedVersion
    $reportedVersionObject = ConvertTo-ManifestedVersionObjectFromRule -VersionText $reportedVersion -Rule $versionSpec.RuntimeVersionRule
    $expectedVersionObject = ConvertTo-ManifestedVersionObjectFromRule -VersionText $PackageInfo.Version -Rule $versionSpec.RuntimeVersionRule
    if (-not $reportedVersionObject -or -not $expectedVersionObject -or $reportedVersionObject -ne $expectedVersionObject) {
        throw (New-ManifestedPythonRuntimeValidationFailureMessage -Operation 'post-install version check' -PythonHome $pythonHome -ExpectedVersion $PackageInfo.Version -ReportedVersion $reportedVersion -CommandResult $versionProbe.CommandResult -SiteImportsState $siteState)
    }

    $pipResult = Ensure-ManifestedPythonPip -PythonExe $pythonExe -PythonHome $pythonHome -LocalRoot $LocalRoot
    $validation = Test-ManifestedPythonRuntimeHome -PythonHome $pythonHome -VersionSpec $versionSpec -LocalRoot $LocalRoot
    if ($validation.Status -ne 'Ready') {
        $validationCommandResult = if ([string]::IsNullOrWhiteSpace($validation.ReportedVersion)) {
            $validation.VersionCommandResult
        }
        elseif ([string]::IsNullOrWhiteSpace($validation.PipVersion)) {
            $validation.PipCommandResult
        }
        else {
            $validation.VersionCommandResult
        }

        throw (New-ManifestedPythonRuntimeValidationFailureMessage -Operation 'post-pip validation' -PythonHome $pythonHome -ExpectedVersion $PackageInfo.Version -ReportedVersion $validation.ReportedVersion -CommandResult $validationCommandResult -SiteImportsState $validation.SiteImports)
    }

    return [pscustomobject]@{
        Action       = if ($ForceInstall -or $currentValidation.Status -ne 'Ready') { 'Installed' } else { 'Skipped' }
        Version      = $PackageInfo.Version
        Flavor       = $Flavor
        RuntimeHome  = $pythonHome
        ExecutablePath = $validation.PythonExe
        PythonHome   = $pythonHome
        PythonExe    = $validation.PythonExe
        PipCmd       = $validation.PipCmd
        Pip3Cmd      = $validation.Pip3Cmd
        PthPath      = $validation.PthPath
        PipVersion   = $validation.PipVersion
        PipResult    = $pipResult
        Source       = $PackageInfo.Source
    }
}
