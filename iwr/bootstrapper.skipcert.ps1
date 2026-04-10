<#
Default PSGallery bootstrapper variant for installing/importing Eigenverft.Manifested.Sandbox,
then opening a new Windows PowerShell console and invoking the default follow-up command.

Current defaults:

$i='PowerShellGet','PackageManagement','Eigenverft.Manifested.Sandbox'
$c='Get-SandboxVersion'

Use via (Proxy-aware for corporate environments, skips TLS certificate validation):

$u='https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/<branch>/iwr/bootstrapper.skipcert.ps1';try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};try{[System.Net.ServicePointManager]::ServerCertificateValidationCallback={$true}}catch{};$p=[System.Net.WebRequest]::GetSystemWebProxy();if(-not $p.IsBypassed($u)){iwr $u -Proxy ($p.GetProxy($u).AbsoluteUri) -ProxyUseDefaultCredentials -UseBasicParsing|iex}else{iwr $u -UseBasicParsing|iex}

Use this variant only in Windows PowerShell 5.1 environments where TLS interception or
broken enterprise trust chains require bypassing certificate validation for the bootstrap
download and PSGallery install path. This is intentionally insecure.

This is the published bootstrapper entrypoint that skips TLS certificate validation.
For the standard bootstrapper, see iwr/bootstrapper.ps1.
For the configurable variant, see iwr/bootstrapper.sandbox.generic.ps1.

#>

$c = 'Get-SandboxVersion'
$i = 'PackageManagement','PowerShellGet','Eigenverft.Manifested.Sandbox'
$s = 'CurrentUser'
$g = 'PSGallery'
$u = 'https://www.powershellgallery.com/api/v2'

if ($PSVersionTable.PSVersion.Major -ne 5) { return }

try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted -Force } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

[System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
if ([System.Net.WebRequest]::DefaultWebProxy) {
    [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
}

if (-not ('BootstrapperCertificateValidationHelper' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class BootstrapperCertificateValidationHelper
{
    public static bool AcceptAll(
        object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors)
    {
        return true;
    }
}
'@
}

$bindingFlags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static
$acceptAllMethod = [BootstrapperCertificateValidationHelper].GetMethod('AcceptAll', $bindingFlags)

if ($null -eq $acceptAllMethod) {
    throw 'Failed to resolve BootstrapperCertificateValidationHelper.AcceptAll.'
}

$acceptAllCallback = [System.Net.Security.RemoteCertificateValidationCallback](
    [System.Delegate]::CreateDelegate(
        [System.Net.Security.RemoteCertificateValidationCallback],
        $acceptAllMethod
    )
)

$previousCertificateValidationCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback

try {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $acceptAllCallback

    $v = [version]'2.8.5.201'
    Install-PackageProvider NuGet -MinimumVersion $v -Scope $s -Force -ForceBootstrap | Out-Null

    try {
        Set-PSRepository $g -InstallationPolicy Trusted -ErrorAction Stop
    }
    catch {
        Register-PSRepository $g -SourceLocation $u -ScriptSourceLocation $u -InstallationPolicy Trusted -ErrorAction Stop
    }

    Find-Module $i -Repository $g |
        Select-Object Name, Version |
        Where-Object {
            -not (
                Get-Module -ListAvailable $_.Name |
                    Sort-Object Version -Descending |
                    Select-Object -First 1 |
                    Where-Object Version -eq $_.Version
            )
        } |
        ForEach-Object {
            $installModuleParameters = @{
                RequiredVersion = $_.Version
                Repository = $g
                Scope = $s
                Force = $true
                AllowClobber = $true
            }

            if ((Get-Command Install-Module).Parameters.ContainsKey('SkipPublisherCheck')) {
                $installModuleParameters['SkipPublisherCheck'] = $true
            }

            Install-Module $_.Name @installModuleParameters
            try { Remove-Module $_.Name -ErrorAction SilentlyContinue } catch {}
            Import-Module $_.Name -MinimumVersion $_.Version -Force
        }
}
finally {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $previousCertificateValidationCallback
}

Start-Process cmd "/c start `"`" powershell -NoExit -Command `"$c;`""
exit
