# Eigenverft.Manifested.Sandbox

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/Eigenverft.Manifested.Sandbox?label=PSGallery&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Sandbox) [![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/Eigenverft.Manifested.Sandbox?label=Downloads&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Sandbox) [![PowerShell Support](https://img.shields.io/badge/PowerShell-5.1%2B%20Desktop%2FCore-5391FE?logo=powershell&logoColor=white)](src/prj/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.psd1) [![Build Status](https://img.shields.io/github/actions/workflow/status/eigenverft/Eigenverft.Manifested.Sandbox/cicd.yml?branch=main&label=build)](https://github.com/eigenverft/Eigenverft.Manifested.Sandbox/actions/workflows/cicd.yml) [![License](https://img.shields.io/github/license/eigenverft/Eigenverft.Manifested.Sandbox?logo=mit)](LICENSE)

Windows-focused PowerShell module and bootstrap flow for quickly turning a fresh Windows Sandbox session into a usable development environment, especially from a `.wsb` startup entrypoint. It can provision managed Python, PowerShell 7, Node.js, OpenCode CLI, Gemini CLI, Qwen CLI, Codex CLI, GitHub CLI, MinGit, VS Code, and Microsoft Visual C++ runtime prerequisites when you want them.

The primary intent is fast, repeatable setup inside Windows Sandbox. The same bootstrap pattern can also run on a normal Windows machine, but that is a secondary use case rather than the main focus of this repo.

🚀 **Key Features:**
- Fast Windows Sandbox bring-up from a `.wsb` startup command or a manual shell
- Managed runtime provisioning for `python`, `pip`, `pwsh`, `git`, `gh`, `code`, `node`, `npm`, `opencode`, `gemini`, `qwen`, `codex`, and VC++ prerequisites
- Runtime discovery that can reuse compatible external installs or refresh to sandbox-owned managed copies
- Persisted command results plus live runtime snapshots through `Get-SandboxState`
- Managed npm ownership under the sandbox Node runtime, including proxy-aware npm configuration when Windows resolves the npm registry through a proxy
- Reusable `iwr | iex` bootstrap flow for repo-specific or generic PowerShell handoff scenarios
- PowerShell 5.1-first bootstrap path with normal Windows machine support as a secondary workflow

## 📌 Current State

The module currently exports these public commands:

- `Get-SandboxVersion`
- `Get-SandboxState`
- `Initialize-PythonRuntime`
- `Initialize-Ps7Runtime`
- `Initialize-GitRuntime`
- `Initialize-VSCodeRuntime`
- `Initialize-NodeRuntime`
- `Initialize-OpenCodeRuntime`
- `Initialize-GeminiRuntime`
- `Initialize-QwenRuntime`
- `Initialize-CodexRuntime`
- `Initialize-GHCliRuntime`
- `Initialize-VCRuntime`

There is not yet a single combined `Initialize-Sandbox` command. The current model is a set of small init commands that each read real state, plan from that state, perform bounded repair or install work, and persist the observed result.

---

## 🧭 Motivation

Windows Sandbox is ideal for disposable setup checks: bootstrap a repo, validate installer behavior, and test fresh-machine assumptions without touching your main workstation.

The problem is that a blank `.wsb` session still takes manual work to become useful. This project turns that repeated setup into a small versioned PowerShell entrypoint so the environment is quick to reuse instead of tedious to rebuild.

## 🖥️ Host Requirements

Windows Sandbox on the host requires Windows 10/11 `1903+`, Pro/Enterprise/Education/Pro Education/SE, virtualization enabled, 4 GB RAM, 1 GB free disk, 2 CPU cores, and the `Windows Sandbox` feature enabled.

## 🖼️ Preview

![Windows Sandbox preview showing the module version in PowerShell and a follow-up runtime command](resources/screenshots/windows-sandbox-bootstrap-preview.png)

Example Windows Sandbox session after the bootstrapper opens PowerShell and the follow-up runtime commands are available.

---

## 📥 Bootstrapper

The bootstrapper is optimized for getting a Windows Sandbox session ready quickly. It installs the required PowerShell package tooling plus `Eigenverft.Manifested.Sandbox` from the PowerShell Gallery, then opens a new Windows PowerShell console and runs the default follow-up command.

> 💡 Even if you do not end up using this module's managed runtime installers, the bootstrapper is still useful as a reusable startup pattern. It gives you a simple way to install a chosen set of PowerShell Gallery modules, open a fresh console, and immediately run a preset command chain.

PowerShell Gallery package: [Eigenverft.Manifested.Sandbox](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Sandbox)

### 🔐 Trust / Install Notes

The published bootstrap one-liner first downloads [`iwr/bootstrapper.ps1`](https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.ps1) from `raw.githubusercontent.com` and then, in Windows PowerShell 5.1:

- Enables TLS 1.2 if possible
- Tries to set the current user's execution policy to `Unrestricted`
- Bootstraps the `NuGet` package provider in `CurrentUser` scope
- Trusts or registers `PSGallery`
- Installs `PackageManagement`, `PowerShellGet`, and `Eigenverft.Manifested.Sandbox` in `CurrentUser` scope
- Opens a new Windows PowerShell session and runs `Get-SandboxVersion`

Admin rights are not required for the bootstrap or module install path. Later runtime actions can have different requirements; for example, `Initialize-VCRuntime` may still require elevation when the VC++ runtime needs to be installed or repaired.

### ▶️ Run It

> 💡 **Why is this command so long?** It includes a built-in proxy handshake. In heavily managed corporate environments, basic downloads often fail. This one-liner explicitly checks for and dynamically authenticates through your system's proxy with default network credentials before downloading the bootstrap script.

From Windows PowerShell 5.1:

```powershell
$u='https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.ps1';try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};$p=[System.Net.WebRequest]::GetSystemWebProxy();if(-not $p.IsBypassed($u)){iwr $u -Proxy ($p.GetProxy($u).AbsoluteUri) -ProxyUseDefaultCredentials -UseBasicParsing|iex}else{iwr $u -UseBasicParsing|iex}
```

From `cmd.exe`:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$u='https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.ps1';try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};$p=[System.Net.WebRequest]::GetSystemWebProxy();if(-not $p.IsBypassed($u)){iwr $u -Proxy ($p.GetProxy($u).AbsoluteUri) -ProxyUseDefaultCredentials -UseBasicParsing|iex}else{iwr $u -UseBasicParsing|iex}" && exit
```

### ⚠️ Skip Certificate Validation Variant

If your Windows PowerShell 5.1 environment is behind TLS interception or has an unusable enterprise trust chain, there is also an explicitly insecure bootstrapper variant that bypasses TLS certificate validation for both the initial download and the PSGallery bootstrap/install flow.

```powershell
$u='https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.skipcert.ps1';try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};try{[System.Net.ServicePointManager]::ServerCertificateValidationCallback={$true}}catch{};$p=[System.Net.WebRequest]::GetSystemWebProxy();if(-not $p.IsBypassed($u)){iwr $u -Proxy ($p.GetProxy($u).AbsoluteUri) -ProxyUseDefaultCredentials -UseBasicParsing|iex}else{iwr $u -UseBasicParsing|iex}
```

### 🧰 Generic Bootstrap Variant

A generic version of the bootstrapper lets you specify which PowerShell Gallery modules to install and which command to invoke automatically, so it can be reused for projects beyond `Eigenverft.Manifested.Sandbox` and for repo-specific bootstrap flows that just need a clean handoff into PowerShell.

```powershell
$c='Initialize-VCRuntime;Initialize-PythonRuntime;Initialize-Ps7Runtime;Initialize-GitRuntime;Initialize-GHCliRuntime;Initialize-VSCodeRuntime;Initialize-NodeRuntime;Initialize-OpenCodeRuntime;Initialize-CodexRuntime;Get-SandboxState';$i='PackageManagement','PowerShellGet','Eigenverft.Manifested.Sandbox';$u='https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.sandbox.generic.ps1';try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};$p=[System.Net.WebRequest]::GetSystemWebProxy();if(-not $p.IsBypassed($u)){iwr $u -Proxy ($p.GetProxy($u).AbsoluteUri) -ProxyUseDefaultCredentials -UseBasicParsing|iex}else{iwr $u -UseBasicParsing|iex}
```

If that same generic flow needs to run in a Windows PowerShell 5.1 environment with TLS interception or an unusable trust chain, swap the URL to the explicitly insecure generic skip-cert variant:

```powershell
$c='Initialize-VCRuntime;Initialize-PythonRuntime;Initialize-Ps7Runtime;Initialize-GitRuntime;Initialize-GHCliRuntime;Initialize-VSCodeRuntime;Initialize-NodeRuntime;Initialize-OpenCodeRuntime;Initialize-CodexRuntime;Get-SandboxState';$i='PackageManagement','PowerShellGet','Eigenverft.Manifested.Sandbox';$u='https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.sandbox.generic.skipcert.ps1';try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};try{[System.Net.ServicePointManager]::ServerCertificateValidationCallback={$true}}catch{};$p=[System.Net.WebRequest]::GetSystemWebProxy();if(-not $p.IsBypassed($u)){iwr $u -Proxy ($p.GetProxy($u).AbsoluteUri) -ProxyUseDefaultCredentials -UseBasicParsing|iex}else{iwr $u -UseBasicParsing|iex}
```

> 💡 To test another branch, replace `main` with the branch name in the URL.

The published default bootstrapper currently uses:

```powershell
$i='PackageManagement','PowerShellGet','Eigenverft.Manifested.Sandbox'
$c='Get-SandboxVersion'
```

The configurable variant keeps the same overall bootstrap pattern, but lets you preset `$i` and `$c` before invocation. That same pattern also maps well to Windows Sandbox `.wsb` startup definitions, where you often want the XML to stay small while the real startup behavior lives in versioned PowerShell.

---

## 💻 Windows Sandbox `.wsb` Example

If you want a ready-to-use Windows Sandbox entry file, save something like this as `sandbox.wsb` and launch it:

```xml
<Configuration>

  <!-- Hardware / integration toggles -->
  <VGpu>Enable</VGpu>
  <Networking>Enable</Networking>

  <AudioInput>Enable</AudioInput>
  <VideoInput>Enable</VideoInput>

  <PrinterRedirection>Enable</PrinterRedirection>
  <ClipboardRedirection>Enable</ClipboardRedirection>

  <MemoryInMB>4096</MemoryInMB>

  <!-- Map host folder into the sandbox -->
  <MappedFolders>
    <MappedFolder>
      <HostFolder>C:\temp</HostFolder>
      <SandboxFolder>C:\temp</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>

  <!-- Auto-start: PowerShell startup -->
  <LogonCommand>
    <Command>cmd /c start "" powershell.exe -NoExit -Command "function Import-B64Def{[CmdletBinding()]param([Parameter(Mandatory=$true,Position=0)][string]$Text);Add-Type -AssemblyName System.IO.Compression;$z=[Convert]::FromBase64String($Text);$i=New-Object IO.MemoryStream(,$z);$o=New-Object IO.MemoryStream;try{$d=New-Object IO.Compression.DeflateStream($i,[IO.Compression.CompressionMode]::Decompress);try{$b=New-Object byte[] 4096;do{$n=$d.Read($b,0,$b.Length);if($n -gt 0){$o.Write($b,0,$n)}}while($n -gt 0)}finally{$d.Dispose()};[scriptblock]::Create([Text.Encoding]::UTF8.GetString($o.ToArray()))}finally{$o.Dispose();$i.Dispose()}};$s='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';. (Import-B64Def $s);Initialize-ProxyAccessProfile4;if($null -eq $c){$c=''};if($null -eq $i){$i='PackageManagement','PowerShellGet','Eigenverft.Manifested.Sandbox'};$s='CurrentUser';$g='PSGallery';$u='https://www.powershellgallery.com/api/v2';$pp=@{};$pm=@{};$pr=$null;try{$pp=$Global:ProxyParamsInstallPackageProvider;$pm=$Global:ProxyParamsInstallModule;$pr=$Global:ProxyParamsPrepareSession}catch{};if($PSVersionTable.PSVersion.Major -ne 5){return};try{Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted -Force}catch{};try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};if($pr){$null=$pr.Invoke()}else{[Net.WebRequest]::DefaultWebProxy=[Net.WebRequest]::GetSystemWebProxy();if([Net.WebRequest]::DefaultWebProxy){[Net.WebRequest]::DefaultWebProxy.Credentials=[Net.CredentialCache]::DefaultNetworkCredentials}};if(-not('BootstrapperCertificateValidationHelper'-as[type])){Add-Type 'using System.Net.Security;using System.Security.Cryptography.X509Certificates;public static class BootstrapperCertificateValidationHelper{public static bool AcceptAll(object sender,X509Certificate certificate,X509Chain chain,SslPolicyErrors sslPolicyErrors){return true;}}'};if(-not($m=[BootstrapperCertificateValidationHelper].GetMethod('AcceptAll',[Reflection.BindingFlags]'Public,Static'))){throw 'Failed to resolve BootstrapperCertificateValidationHelper.AcceptAll.'};$prev=[Net.ServicePointManager]::ServerCertificateValidationCallback;try{[Net.ServicePointManager]::ServerCertificateValidationCallback=[Net.Security.RemoteCertificateValidationCallback]([Delegate]::CreateDelegate([Net.Security.RemoteCertificateValidationCallback],$m));$v=[version]'2.8.5.201';Install-PackageProvider NuGet -MinimumVersion $v -Scope $s -Force -ForceBootstrap @pp|Out-Null;try{Set-PSRepository $g -InstallationPolicy Trusted -ea Stop}catch{Register-PSRepository $g -SourceLocation $u -ScriptSourceLocation $u -InstallationPolicy Trusted -ea Stop};Find-Module $i -Repository $g|select Name,Version|?{-not(Get-Module -ListAvailable $_.Name|sort Version -desc|select -f 1|? Version -eq $_.Version)}|%{$p=@{RequiredVersion=$_.Version;Repository=$g;Scope=$s;Force=$true;AllowClobber=$true};if($pm){$pm.GetEnumerator()|%{$p[$_.Key]=$_.Value}};if((gcm Install-Module).Parameters.ContainsKey('SkipPublisherCheck')){$p['SkipPublisherCheck']=$true};Install-Module $_.Name @p;try{Remove-Module $_.Name -ea 0}catch{};Import-Module $_.Name -MinimumVersion $_.Version -Force}}finally{[Net.ServicePointManager]::ServerCertificateValidationCallback=$prev};$q=[char]34;$arg='/c start '+$q+$q+' powershell -NoExit -Command '+$q+$c+';'+$q;Start-Process cmd $arg;exit"</Command>
  </LogonCommand>

</Configuration>
```

This is a practical starting point for a disposable Windows Sandbox session that immediately bootstraps the required PowerShell package tooling and module, then spawns a fresh PowerShell window for the follow-up command.

The `.wsb` scenario is one of the clearest reasons to keep the bootstrapper flexible. The XML can either inline the bootstrap logic directly, as shown here, or point at a versioned bootstrap script. For the inline form, the nested `Start-Process cmd "/c start ..."` pattern still works, but the inner quote characters need to be built at runtime so the surrounding `.wsb` and `cmd.exe` layers do not corrupt them before PowerShell executes the tail.

---

## 🧪 Demo Commands

After the bootstrapper opens the new console, run:

```powershell
Get-SandboxVersion
Initialize-PythonRuntime
Initialize-Ps7Runtime
Initialize-GitRuntime
Initialize-GHCliRuntime
Initialize-VSCodeRuntime
Initialize-NodeRuntime
Initialize-OpenCodeRuntime
Initialize-GeminiRuntime
Initialize-QwenRuntime
Initialize-CodexRuntime
Initialize-VCRuntime
Get-SandboxState
```

- `Get-SandboxVersion` is the quick way to show the highest installed or loaded module version the current PowerShell session can resolve.
- `Get-SandboxState` exposes both the persisted command document and live runtime snapshots, so it is the easiest way to see what the module believes is managed, external, missing, partial, or blocked right now.
- `Initialize-PythonRuntime`, `Initialize-Ps7Runtime`, `Initialize-GitRuntime`, `Initialize-GHCliRuntime`, `Initialize-VSCodeRuntime`, `Initialize-NodeRuntime`, `Initialize-OpenCodeRuntime`, `Initialize-GeminiRuntime`, `Initialize-QwenRuntime`, and `Initialize-CodexRuntime` are intended to run in a normal user session. They prefer sandbox-managed portable runtimes under `LocalAppData`, using python.org for the CPython embeddable ZIP, GitHub as the download source for PowerShell 7, MinGit, and GitHub CLI, the official VS Code Windows ZIP archive with portable `data` mode for VS Code, and npm-based managed installs for OpenCode, Gemini, Qwen, and Codex.
- Those commands also check for an already-usable `python`, `pwsh`, `git`, `gh`, `code`, `node`, `opencode`, `gemini`, `qwen`, or `codex` that exists outside prior sandbox state. If a compatible runtime is already available on `PATH` or in a common install location, the command can treat it as ready and persist it as an external runtime instead of downloading or installing a new copy. If you explicitly use a refresh switch such as `-RefreshPython`, `-RefreshGit`, `-RefreshGHCli`, `-RefreshPs7`, `-RefreshVSCode`, `-RefreshNode`, `-RefreshOpenCode`, `-RefreshGemini`, `-RefreshQwen`, or `-RefreshCodex`, the command will still acquire and install the sandbox-managed copy.
- `Initialize-PythonRuntime` installs the official CPython Windows embeddable package into a sandbox-managed tools root, enables `import site`, bootstraps `pip`, and exposes `python`, `python.exe`, `pip.cmd`, and `pip3.cmd` from the managed runtime directory. When Windows resolves the package index through a proxy, it keeps proxy settings in a runtime-local `pip.ini` instead of writing to a machine-wide or user-wide pip config.
- `Initialize-GHCliRuntime` installs a managed `gh.exe` from the official GitHub CLI Windows ZIP release and validates the package against GitHub's published checksum asset before making that runtime active on `PATH`.
- `Initialize-NodeRuntime` installs the managed Node.js runtime and owns the sandbox-managed npm configuration. When Windows resolves the active npm registry through a proxy, it writes `proxy` and `https-proxy` into the managed runtime's global `npmrc`; when the route is direct, it leaves npm config unchanged.
- `Initialize-OpenCodeRuntime`, `Initialize-GeminiRuntime`, `Initialize-QwenRuntime`, and `Initialize-CodexRuntime` install `opencode-ai`, `@google/gemini-cli`, `@qwen-code/qwen-code`, and `@openai/codex` into sandbox-managed tool roots and inherit the managed npm global config when they are using the sandbox-owned Node/npm runtime.
- `Initialize-OpenCodeRuntime` installs `opencode-ai` and exposes `opencode` / `opencode.cmd` from the managed tool root when refreshed or newly installed.
- `Initialize-GeminiRuntime` installs `@google/gemini-cli` into the sandbox-managed tool root and prefers that managed copy when refreshed. Gemini CLI's official docs currently recommend Node.js `20.0.0+` and Windows 11 `24H2+`; this module follows a best-effort Windows policy and ensures a compatible Node runtime before managed install when needed.
- `Initialize-QwenRuntime` installs `@qwen-code/qwen-code` into the sandbox-managed tool root and prefers that managed copy when refreshed. Qwen Code's official quickstart currently requires Node.js `20+`; this module follows that requirement and ensures a compatible Node runtime before managed install when needed.
- `Initialize-CodexRuntime` installs `@openai/codex` into the sandbox-managed tool root and prefers that managed copy when refreshed. It always ensures the VC runtime prerequisite before install, and if no usable Node/npm is available yet it also ensures the required Node runtime first.
- `Initialize-VCRuntime` is different because the VC runtime is a machine/runtime prerequisite rather than a sandbox-managed portable tool.
- `Initialize-VCRuntime` should be run in an elevated PowerShell process when the Microsoft Visual C++ Redistributable needs to be installed or repaired.

## 📦 Direct Module Usage

If you prefer installing the module directly instead of using the bootstrapper:

```powershell
Install-Module Eigenverft.Manifested.Sandbox -Scope CurrentUser -Repository PSGallery
Import-Module Eigenverft.Manifested.Sandbox
```

## 📝 Usage Tips

- Use the refresh switches when you want the sandbox-managed runtime even if a compatible tool already exists elsewhere on the machine.
- `Initialize-PythonRuntime` keeps pip cache and proxy state under the sandbox root, so it is a good fit for disposable or corporate-proxy sandbox sessions where you do not want pip config leaking into the wider user profile.
- OpenCode, Gemini, Qwen, and Codex are all opt-in in the example command chains; add the specific runtime init commands you want for a given sandbox profile.
- The npm-based CLIs share the managed Node runtime when needed. If `Initialize-NodeRuntime` detects that the npm registry routes through a system proxy, it persists that proxy into the sandbox-owned npm config; if the route is direct, it makes no npm proxy changes.
- Replace `main` in the bootstrap URLs to test another branch without changing the overall bootstrap flow.
- Keep `.wsb` files small and let versioned PowerShell own the real startup logic whenever you want a more maintainable sandbox launch path.
- Run `Get-SandboxState` after a bootstrap chain when you want the quickest view of managed vs external runtimes and persisted command outcomes.
- Run `Initialize-VCRuntime` in an elevated PowerShell session if the Microsoft Visual C++ Redistributable needs installation or repair.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📫 Contact & Support

For questions and support:
- 🐛 Open an [issue](https://github.com/eigenverft/Eigenverft.Manifested.Sandbox/issues) in this repository
- 🤝 Submit a [pull request](https://github.com/eigenverft/Eigenverft.Manifested.Sandbox/pulls) with improvements

---

<div align="center">
Made with ❤️ by Eigenverft
</div>
