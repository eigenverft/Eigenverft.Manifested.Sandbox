<#
    Eigenverft.Manifested.Sandbox.Runtime.Python.Pip
#>

function Save-PythonGetPipScript {
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

    [pscustomobject]@{
        Path   = $scriptPath
        Action = $action
        Uri    = 'https://bootstrap.pypa.io/get-pip.py'
    }
}

function Ensure-PythonPip {
    [Diagnostics.CodeAnalysis.SuppressMessage('PSUseApprovedVerbs', '', Justification = 'Retains the established helper name used by runtime descriptors and orchestration code.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $pipProxyConfiguration = Get-ManifestedPipProxyConfigurationStatus -PythonExe $PythonExe -LocalRoot $LocalRoot
    if ($pipProxyConfiguration.Action -eq 'NeedsManagedProxy') {
        $pipProxyConfiguration = Sync-ManifestedPipProxyConfiguration -PythonExe $PythonExe -Status $pipProxyConfiguration -LocalRoot $LocalRoot
    }

    $existingPipProbe = Get-PythonPipVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
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
        }
    }

    $bootstrap = 'EnsurePip'
    $ensurePipResult = Invoke-ManifestedPipAwarePythonCommand -PythonExe $PythonExe -Arguments @('-m', 'ensurepip', '--default-pip') -LocalRoot $LocalRoot
    $pipVersion = Get-PythonPipVersion -PythonExe $PythonExe -LocalRoot $LocalRoot
    $getPipScript = $null

    if ($ensurePipResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($pipVersion)) {
        $bootstrap = 'GetPip'
        $getPipScript = Save-PythonGetPipScript -LocalRoot $LocalRoot
        $getPipResult = Invoke-ManifestedPipAwarePythonCommand -PythonExe $PythonExe -Arguments @($getPipScript.Path) -LocalRoot $LocalRoot
        if ($getPipResult.ExitCode -ne 0) {
            throw (New-PythonRuntimeValidationFailureMessage -Operation 'get-pip bootstrap' -PythonHome $PythonHome -CommandResult $getPipResult -LocalRoot $LocalRoot)
        }

        $pipVersion = Get-PythonPipVersion -PythonExe $PythonExe -LocalRoot $LocalRoot
    }

    if ([string]::IsNullOrWhiteSpace($pipVersion)) {
        $bootstrapCommandResult = if ($bootstrap -eq 'EnsurePip') { $ensurePipResult } else { $getPipResult }
        throw (New-PythonRuntimeValidationFailureMessage -Operation 'pip bootstrap' -PythonHome $PythonHome -CommandResult $bootstrapCommandResult -LocalRoot $LocalRoot)
    }

    $wrapperInfo = Set-ManifestedManagedPipWrappers -PythonHome $PythonHome -LocalRoot $LocalRoot

    [pscustomobject]@{
        Action                = if ($bootstrap -eq 'EnsurePip') { 'InstalledEnsurePip' } else { 'InstalledGetPip' }
        Bootstrap             = $bootstrap
        PipVersion            = $pipVersion
        GetPipScript          = $getPipScript
        WrapperInfo           = $wrapperInfo
        PipProxyConfiguration = $pipProxyConfiguration
    }
}

