function Add-ManifestedPostInstallStepResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[object]]$StepResults,

        [Parameter(Mandatory = $true)]
        [string]$Step,

        [Parameter(Mandatory = $true)]
        [string]$Action,

        $Result
    )

    $StepResults.Add([pscustomobject]@{
            Step   = $Step
            Action = $Action
            Result = $Result
        }) | Out-Null
}

function Test-ManifestedEnabledHookBlock {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [pscustomobject]$Hooks,

        [Parameter(Mandatory = $true)]
        [string]$HookName
    )

    if (-not $Hooks -or -not $Hooks.PSObject.Properties.Match($HookName).Count) {
        return $false
    }

    return ($null -ne $Hooks.$HookName)
}

function Invoke-ManifestedPostInstallSteps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $postInstall = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'hooks' -BlockName 'postInstall'
    if (-not $postInstall) {
        return [pscustomobject]@{
            Action      = 'Skipped'
            Steps       = @()
            StepResults = @()
        }
    }

    $stepResults = New-Object System.Collections.Generic.List[object]
    $declaredSteps = New-Object System.Collections.Generic.List[string]

    if (Test-ManifestedEnabledHookBlock -Hooks $postInstall -HookName 'enablePythonSiteImports') {
        $declaredSteps.Add('EnablePythonSiteImports') | Out-Null
        if ($Facts.RuntimeSource -eq 'Managed' -and -not [string]::IsNullOrWhiteSpace($Facts.RuntimeHome)) {
            $siteState = Enable-ManifestedPythonSiteImports -PythonHome $Facts.RuntimeHome
            Add-ManifestedPostInstallStepResult -StepResults $stepResults -Step 'EnablePythonSiteImports' -Action $(if ($siteState.IsReady) { 'Executed' } else { 'Failed' }) -Result $siteState
        }
        else {
            Add-ManifestedPostInstallStepResult -StepResults $stepResults -Step 'EnablePythonSiteImports' -Action 'Skipped' -Result $null
        }
    }

    if (Test-ManifestedEnabledHookBlock -Hooks $postInstall -HookName 'ensurePythonPip') {
        $declaredSteps.Add('EnsurePythonPip') | Out-Null
        if ($Facts.RuntimeSource -eq 'Managed' -and -not [string]::IsNullOrWhiteSpace($Facts.ExecutablePath) -and -not [string]::IsNullOrWhiteSpace($Facts.RuntimeHome)) {
            $pipResult = Ensure-ManifestedPythonPip -PythonExe $Facts.ExecutablePath -PythonHome $Facts.RuntimeHome -LocalRoot $LocalRoot
            Add-ManifestedPostInstallStepResult -StepResults $stepResults -Step 'EnsurePythonPip' -Action $(if ($pipResult.Action -eq 'Reused') { 'Reused' } else { 'Executed' }) -Result $pipResult
        }
        else {
            Add-ManifestedPostInstallStepResult -StepResults $stepResults -Step 'EnsurePythonPip' -Action 'Skipped' -Result $null
        }
    }

    if (Test-ManifestedEnabledHookBlock -Hooks $postInstall -HookName 'syncPythonPipProxy') {
        $declaredSteps.Add('SyncPythonPipProxy') | Out-Null
        if ($Facts.RuntimeSource -eq 'Managed' -and -not [string]::IsNullOrWhiteSpace($Facts.ExecutablePath)) {
            $proxyStatus = Get-ManifestedPipProxyConfigurationStatus -PythonExe $Facts.ExecutablePath -LocalRoot $LocalRoot
            $proxyResult = if ($proxyStatus.Action -eq 'NeedsManagedProxy') {
                Sync-ManifestedPipProxyConfiguration -PythonExe $Facts.ExecutablePath -Status $proxyStatus -LocalRoot $LocalRoot
            }
            else {
                $proxyStatus
            }

            Add-ManifestedPostInstallStepResult -StepResults $stepResults -Step 'SyncPythonPipProxy' -Action $(if ($proxyResult.Action -in @('Updated', 'Created')) { 'Executed' } else { 'Reused' }) -Result $proxyResult
        }
        else {
            Add-ManifestedPostInstallStepResult -StepResults $stepResults -Step 'SyncPythonPipProxy' -Action 'Skipped' -Result $null
        }
    }

    return [pscustomobject]@{
        Action      = if (@($stepResults | Where-Object { $_.Action -eq 'Executed' }).Count -gt 0) { 'Executed' } elseif (@($stepResults | Where-Object { $_.Action -eq 'Reused' }).Count -gt 0) { 'Reused' } else { 'Skipped' }
        Steps       = @($declaredSteps)
        StepResults = @($stepResults)
    }
}
