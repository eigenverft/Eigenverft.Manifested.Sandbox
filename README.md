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
    <Command>cmd /c start "" powershell.exe -NoExit -Command "$c='Get-SandboxVersion';$i='PackageManagement','PowerShellGet','Eigenverft.Manifested.Sandbox';function Import-B64Def{[CmdletBinding()]param([Parameter(Mandatory=$true,Position=0)][string]$Text);Add-Type -AssemblyName System.IO.Compression;$z=[Convert]::FromBase64String($Text);$i=New-Object IO.MemoryStream(,$z);$o=New-Object IO.MemoryStream;try{$d=New-Object IO.Compression.DeflateStream($i,[IO.Compression.CompressionMode]::Decompress);try{$b=New-Object byte[] 4096;do{$n=$d.Read($b,0,$b.Length);if($n -gt 0){$o.Write($b,0,$n)}}while($n -gt 0)}finally{$d.Dispose()};[scriptblock]::Create([Text.Encoding]::UTF8.GetString($o.ToArray()))}finally{$o.Dispose();$i.Dispose()}};$s='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';. (Import-B64Def $s)"</Command>
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
