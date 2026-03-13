<#
Sandbox-focused PSGallery bootstrapper for installing and importing Eigenverft.Manifested.Sandbox.

Use via

iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/<branch>/iwr/bootstrapper.ps1 | iex

This is the published one-liner entrypoint.
It installs the current fixed defaults:

PowerShellGet
PackageManagement
Eigenverft.Manifested.Sandbox

Then it opens a new Windows PowerShell console for the follow-up commands:
Initialize-Ps7Runtime
Initialize-GitRuntime
Initialize-VSCodeRuntime
Initialize-NodeRuntime
Initialize-VCRuntime
Get-SandboxState

For the configurable variant, see iwr/bootstrapper.sandbox.generic.ps1.
#>

$i='PowerShellGet','PackageManagement','Eigenverft.Manifested.Sandbox';$s='CurrentUser';$g='PSGallery';$u='https://www.powershellgallery.com/api/v2';if($PSVersionTable.PSVersion.Major-ne5){return};try{Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted -Force}catch{};try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};[System.Net.WebRequest]::DefaultWebProxy=[System.Net.WebRequest]::GetSystemWebProxy();if([System.Net.WebRequest]::DefaultWebProxy){[System.Net.WebRequest]::DefaultWebProxy.Credentials=[System.Net.CredentialCache]::DefaultNetworkCredentials};$v=[version]'2.8.5.201';Install-PackageProvider NuGet -MinimumVersion $v -Scope $s -Force -ForceBootstrap|Out-Null;try{Set-PSRepository $g -InstallationPolicy Trusted -ea Stop}catch{Register-PSRepository $g -SourceLocation $u -ScriptSourceLocation $u -InstallationPolicy Trusted -ea Stop};Find-Module $i -Repository $g|select Name,Version|?{-not(Get-Module -ListAvailable $_.Name|sort Version -desc|select -f 1|? Version -eq $_.Version)}|%{Install-Module $_.Name -RequiredVersion $_.Version -Repository $g -Scope $s -Force -AllowClobber;try{Remove-Module $_.Name -ea 0}catch{};Import-Module $_.Name -MinimumVersion $_.Version -Force};Start-Process cmd '/c start "" powershell -NoExit -Command "Write-Host ''Initialized. Use this console.''"';exit
