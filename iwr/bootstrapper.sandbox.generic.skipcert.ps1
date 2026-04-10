<#
Generic sandbox PSGallery bootstrapper variant for installing/importing configurable modules,
then opening a new Windows PowerShell console and invoking a configurable command.

Configure:

$i = modules to install and import
$c = command to invoke in the new console after bootstrap

Current defaults:

$i='PowerShellGet','PackageManagement','Eigenverft.Manifested.Sandbox'
$c=''

If $i or $c are already set before invocation, this script keeps those values.

Use via (Proxy-aware for corporate environments, skips TLS certificate validation):

$u='https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/<branch>/iwr/bootstrapper.sandbox.generic.skipcert.ps1';try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};try{[System.Net.ServicePointManager]::ServerCertificateValidationCallback={$true}}catch{};$p=[System.Net.WebRequest]::GetSystemWebProxy();if(-not $p.IsBypassed($u)){iwr $u -Proxy ($p.GetProxy($u).AbsoluteUri) -ProxyUseDefaultCredentials -UseBasicParsing|iex}else{iwr $u -UseBasicParsing|iex}

Use this variant only in Windows PowerShell 5.1 environments where TLS interception or
broken enterprise trust chains require bypassing certificate validation for the bootstrap
download and PSGallery install path. This is intentionally insecure.

This is the configurable variant of iwr/bootstrapper.skipcert.ps1.
For the standard configurable variant, see iwr/bootstrapper.sandbox.generic.ps1.
The published default bootstrapper one-liner stays unchanged.

#>

if ($null -eq $c) { $c = '' }; if ($null -eq $i) { $i = 'PackageManagement','PowerShellGet','Eigenverft.Manifested.Sandbox' }; $s = 'CurrentUser'; $g = 'PSGallery'; $u = 'https://www.powershellgallery.com/api/v2'; if ($PSVersionTable.PSVersion.Major -ne 5) { return }; try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted -Force } catch {}; try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}; [System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy(); if ([System.Net.WebRequest]::DefaultWebProxy) { [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials }; if (-not ('BootstrapperCertificateValidationHelper' -as [type])) { Add-Type -TypeDefinition 'using System.Net.Security;using System.Security.Cryptography.X509Certificates;public static class BootstrapperCertificateValidationHelper{public static bool AcceptAll(object sender,X509Certificate certificate,X509Chain chain,SslPolicyErrors sslPolicyErrors){return true;}}' }; $m = [BootstrapperCertificateValidationHelper].GetMethod('AcceptAll', [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static); if ($null -eq $m) { throw 'Failed to resolve BootstrapperCertificateValidationHelper.AcceptAll.' }; $cb = [System.Net.Security.RemoteCertificateValidationCallback]([System.Delegate]::CreateDelegate([System.Net.Security.RemoteCertificateValidationCallback], $m)); $prev = [System.Net.ServicePointManager]::ServerCertificateValidationCallback; try { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $cb; $v = [version]'2.8.5.201'; Install-PackageProvider NuGet -MinimumVersion $v -Scope $s -Force -ForceBootstrap | Out-Null; try { Set-PSRepository $g -InstallationPolicy Trusted -ErrorAction Stop } catch { Register-PSRepository $g -SourceLocation $u -ScriptSourceLocation $u -InstallationPolicy Trusted -ErrorAction Stop }; Find-Module $i -Repository $g | Select-Object Name, Version | Where-Object { -not (Get-Module -ListAvailable $_.Name | Sort-Object Version -Descending | Select-Object -First 1 | Where-Object Version -eq $_.Version) } | ForEach-Object { $p = @{ RequiredVersion = $_.Version; Repository = $g; Scope = $s; Force = $true; AllowClobber = $true }; if ((Get-Command Install-Module).Parameters.ContainsKey('SkipPublisherCheck')) { $p['SkipPublisherCheck'] = $true }; Install-Module $_.Name @p; try { Remove-Module $_.Name -ErrorAction SilentlyContinue } catch {}; Import-Module $_.Name -MinimumVersion $_.Version -Force } } finally { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $prev }; Start-Process cmd "/c start `"`" powershell -NoExit -Command `"$c;`""; exit
