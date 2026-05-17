<#
    Eigenverft.Manifested.Sandbox.Package.PowerShellModule
#>

$script:PackagePowerShellModuleExecutionRoot = $PSScriptRoot

function Get-PackageWindowsPowerShellPath {
    [CmdletBinding()]
    param()

    $systemRoot = if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        [Environment]::GetFolderPath('Windows')
    }
    else {
        [string]$env:SystemRoot
    }
    $powerShellPath = [System.IO.Path]::GetFullPath((Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
        throw "Windows PowerShell 5.1 executable '$powerShellPath' was not found."
    }

    return $powerShellPath
}

function Get-PackagePowerShellModuleHelperScriptPath {
    [CmdletBinding()]
    param()

    $helperPath = [System.IO.Path]::GetFullPath((Join-Path $script:PackagePowerShellModuleExecutionRoot 'Invoke-PackagePowerShellModuleInstall.ps1'))
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
        throw "PowerShell module installer helper '$helperPath' was not found."
    }

    return $helperPath
}

function Get-PackagePowerShellModuleInstallOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $install = Get-PackageAssignedInstallOperation -Release $PackageResult.Package
    if (-not $install -or -not [string]::Equals([string]$install.kind, 'powershellModuleInstaller', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package '$($PackageResult.DefinitionId)' is not configured with packageOperations.assigned.install.kind powershellModuleInstaller."
    }
    foreach ($requiredProperty in @('moduleName', 'requiredVersion')) {
        if (-not $install.PSObject.Properties[$requiredProperty] -or [string]::IsNullOrWhiteSpace([string]$install.$requiredProperty)) {
            throw "Package '$($PackageResult.DefinitionId)' powershellModuleInstaller requires packageOperations.assigned.install.$requiredProperty."
        }
    }

    return $install
}

function New-PackagePowerShellModuleRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Check', 'Install')]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [Parameter(Mandatory = $true)]
        [psobject]$Install,

        [Parameter(Mandatory = $true)]
        [string]$StageDirectory,

        [Parameter(Mandatory = $true)]
        [string]$NugetDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ProviderDirectory
    )

    $scope = if ($Install.PSObject.Properties['scope'] -and -not [string]::IsNullOrWhiteSpace([string]$Install.scope)) {
        [string]$Install.scope
    }
    else {
        'CurrentUser'
    }
    $allowClobber = if ($Install.PSObject.Properties['allowClobber']) { [bool]$Install.allowClobber } else { $false }
    $skipPublisherCheck = if ($Install.PSObject.Properties['skipPublisherCheck']) { [bool]$Install.skipPublisherCheck } else { $false }
    $repositoryName = 'EVFLocal_{0}' -f ([Guid]::NewGuid().ToString('N').Substring(0, 12))

    return [pscustomobject]@{
        operation          = $Operation
        definitionId       = [string]$PackageResult.DefinitionId
        packageId          = [string]$PackageResult.PackageId
        moduleName         = [string]$Install.moduleName
        requiredVersion    = [string]$Install.requiredVersion
        scope              = $scope
        allowClobber       = $allowClobber
        skipPublisherCheck = $skipPublisherCheck
        requireNuGetProvider = if ($Install.PSObject.Properties['requireNuGetProvider']) { [bool]$Install.requireNuGetProvider } else { $false }
        repositoryName     = $repositoryName
        stageDirectory     = [System.IO.Path]::GetFullPath($StageDirectory)
        nugetDirectory     = [System.IO.Path]::GetFullPath($NugetDirectory)
        providerDirectory  = [System.IO.Path]::GetFullPath($ProviderDirectory)
    }
}

function Invoke-PackagePowerShellModuleHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [AllowNull()]
        [psobject]$Install,

        [ValidateSet('Check', 'Install')]
        [string]$Operation = 'Install'
    )

    if (-not $Install) {
        $Install = Get-PackagePowerShellModuleInstallOperation -PackageResult $PackageResult
    }
    foreach ($requiredProperty in @('moduleName', 'requiredVersion')) {
        if (-not $Install.PSObject.Properties[$requiredProperty] -or [string]::IsNullOrWhiteSpace([string]$Install.$requiredProperty)) {
            throw "Package '$($PackageResult.DefinitionId)' PowerShell module helper requires $requiredProperty."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$PackageResult.PackageInstallStageDirectory)) {
        throw "Package '$($PackageResult.DefinitionId)' powershellModuleInstaller requires a package install stage directory."
    }

    $stageDirectory = [System.IO.Path]::GetFullPath([string]$PackageResult.PackageInstallStageDirectory)
    if ($Operation -eq 'Install') {
        if ([string]::IsNullOrWhiteSpace([string]$PackageResult.PackageFilePath) -or -not (Test-Path -LiteralPath $PackageResult.PackageFilePath -PathType Leaf)) {
            throw "Package '$($PackageResult.DefinitionId)' powershellModuleInstaller requires a staged .nupkg package file."
        }
        Remove-PathIfExists -Path $stageDirectory | Out-Null
    }
    $null = New-Item -ItemType Directory -Path $stageDirectory -Force

    $nugetDirectory = [System.IO.Path]::GetFullPath((Join-Path $stageDirectory 'Nuget'))
    $providerDirectory = [System.IO.Path]::GetFullPath((Join-Path $stageDirectory 'Provider'))
    $null = New-Item -ItemType Directory -Path $nugetDirectory -Force
    $null = New-Item -ItemType Directory -Path $providerDirectory -Force

    if ($Operation -eq 'Install') {
        $targetPackageFile = [System.IO.Path]::GetFullPath((Join-Path $nugetDirectory (Split-Path -Leaf ([string]$PackageResult.PackageFilePath))))
        $null = Copy-FileToPath -SourcePath ([string]$PackageResult.PackageFilePath) -TargetPath $targetPackageFile -Overwrite
    }

    $requestPath = [System.IO.Path]::GetFullPath((Join-Path $stageDirectory 'powershell-module-install-request.json'))
    $resultPath = [System.IO.Path]::GetFullPath((Join-Path $stageDirectory 'powershell-module-install-result.json'))
    if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
        Remove-Item -LiteralPath $resultPath -Force
    }

    $request = New-PackagePowerShellModuleRequest -Operation $Operation -PackageResult $PackageResult -Install $Install -StageDirectory $stageDirectory -NugetDirectory $nugetDirectory -ProviderDirectory $providerDirectory
    $request | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding UTF8

    $timeoutSec = if ($Install.PSObject.Properties['timeoutSec'] -and [int]$Install.timeoutSec -gt 0) { [int]$Install.timeoutSec } else { 600 }
    $powerShellPath = Get-PackageWindowsPowerShellPath
    $helperScriptPath = Get-PackagePowerShellModuleHelperScriptPath
    $commandArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-NonInteractive'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $helperScriptPath
        '-RequestPath'
        $requestPath
        '-ResultPath'
        $resultPath
    )

    Write-PackageExecutionMessage -Message ("[STATE] PowerShell module helper operation='{0}', module='{1}', version='{2}'." -f $Operation, [string]$Install.moduleName, [string]$Install.requiredVersion)
    Write-PackageExecutionMessage -Message ("[PATH] PowerShell module helper: {0}" -f $helperScriptPath)
    Write-PackageExecutionMessage -Message ("[PATH] PowerShell module local repository: {0}" -f $nugetDirectory)

    $installerResult = Invoke-PackageInstallerCommand `
        -PackageResult $PackageResult `
        -CommandPath $powerShellPath `
        -CommandArguments @($commandArguments) `
        -WorkingDirectory $stageDirectory `
        -TimeoutSec $timeoutSec `
        -SuccessExitCodes @(0) `
        -RestartExitCodes @() `
        -TargetKind 'powershellModule' `
        -InstallerKind 'powershellModuleInstaller' `
        -UiMode 'silent' `
        -LogPath $null `
        -ElevationMode 'none'

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "PowerShell module helper did not write result JSON '$resultPath'."
    }

    $helperResult = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($helperResult.PSObject.Properties['success'] -and -not [bool]$helperResult.success) {
        $message = if ($helperResult.PSObject.Properties['errorMessage']) { [string]$helperResult.errorMessage } else { 'unknown helper failure' }
        throw "PowerShell module helper failed: $message"
    }

    return [pscustomobject]@{
        HelperResult = $helperResult
        Installer    = $installerResult
        RequestPath  = $requestPath
        ResultPath   = $resultPath
        NugetDirectory = $nugetDirectory
        ProviderDirectory = $providerDirectory
    }
}

function Test-PackagePowerShellModulePresence {
<#
.SYNOPSIS
Checks for an exact PowerShell module version through the same PS5.1 helper used by the installer.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$RequiredVersion,

        [string]$Scope = 'CurrentUser',

        [bool]$RequireNuGetProvider = $false
    )

    $install = [pscustomobject]@{
        kind                 = 'powershellModuleInstaller'
        moduleName           = $Name
        requiredVersion      = $RequiredVersion
        scope                = if ([string]::IsNullOrWhiteSpace($Scope)) { 'CurrentUser' } else { $Scope }
        allowClobber         = $false
        skipPublisherCheck   = $false
        timeoutSec           = 600
        requireNuGetProvider = $RequireNuGetProvider
    }

    $result = Invoke-PackagePowerShellModuleHelper -PackageResult $PackageResult -Install $install -Operation Check
    return $result.HelperResult
}

function Install-PackagePowerShellModule {
<#
.SYNOPSIS
Installs an exact PowerShell module version from the staged .nupkg through a local PSRepository.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $install = Get-PackagePowerShellModuleInstallOperation -PackageResult $PackageResult
    $result = Invoke-PackagePowerShellModuleHelper -PackageResult $PackageResult -Operation Install
    $helperResult = $result.HelperResult

    return [pscustomobject]@{
        Status           = 'Applied'
        InstallKind      = 'powershellModuleInstaller'
        TargetKind       = 'powershellModule'
        InstallDirectory = $null
        ReusedExisting   = $false
        ModuleName       = [string]$install.moduleName
        RequiredVersion  = [string]$install.requiredVersion
        InstalledVersion = if ($helperResult.PSObject.Properties['installedVersion']) { [string]$helperResult.installedVersion } else { $null }
        ModuleBase       = if ($helperResult.PSObject.Properties['moduleBase']) { [string]$helperResult.moduleBase } else { $null }
        Scope            = if ($helperResult.PSObject.Properties['scope']) { [string]$helperResult.scope } else { $null }
        PackageFilePath  = $PackageResult.PackageFilePath
        NugetDirectory   = $result.NugetDirectory
        ProviderDirectory = $result.ProviderDirectory
        RequestPath      = $result.RequestPath
        ResultPath       = $result.ResultPath
        Installer        = $result.Installer
    }
}
