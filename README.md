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

<!-- Auto-start: PowerShell startup invokes the proxy management function. The Initialize-Compact implementation from Eigenverft.Manifested.Drydock is embedded here in compressed form so it remains within the 8 KB console command-line limit. -->
  <LogonCommand>
    <Command>cmd /c start "" powershell.exe -NoExit -Command "$prxy='http://test.corp.com:8080';$c='Get-SandboxVersion';$i='PackageManagement','PowerShellGet','Eigenverft.Manifested.Sandbox';function Import-B64Def{[CmdletBinding()]param([Parameter(Mandatory=$true,Position=0)][string]$Text);Add-Type -AssemblyName System.IO.Compression;$z=[Convert]::FromBase64String($Text);$i=New-Object IO.MemoryStream(,$z);$o=New-Object IO.MemoryStream;try{$d=New-Object IO.Compression.DeflateStream($i,[IO.Compression.CompressionMode]::Decompress);try{$b=New-Object byte[] 4096;do{$n=$d.Read($b,0,$b.Length);if($n -gt 0){$o.Write($b,0,$n)}}while($n -gt 0)}finally{$d.Dispose()};[scriptblock]::Create([Text.Encoding]::UTF8.GetString($o.ToArray()))}finally{$o.Dispose();$i.Dispose()}};$s='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';. (Import-B64Def $s)"</Command>
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
