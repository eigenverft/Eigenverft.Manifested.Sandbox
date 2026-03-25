# Sandbox Init Command Requirements

## Objective

This note defines the current orchestration contract for the sandbox init commands and the baseline for any future combined command such as `Initialize-Sandbox`.

The important part is not a specific public command name. The important part is that each init command behaves like a small state-machine coordinator:

- read real state first
- derive a plan from that state
- execute one bounded mutation at a time
- re-read state after each meaningful mutation
- persist only from the observed final state

This currently applies to these exported init commands:

- `Initialize-PythonRuntime`
- `Initialize-Ps7Runtime`
- `Initialize-GitRuntime`
- `Initialize-VSCodeRuntime`
- `Initialize-NodeRuntime`
- `Initialize-GeminiRuntime`
- `Initialize-QwenRuntime`
- `Initialize-CodexRuntime`
- `Initialize-OpenCodeRuntime`
- `Initialize-GHCliRuntime`
- `Initialize-VCRuntime`

The related inspection surface is:

- `Get-SandboxState`

## Public Command Simplicity

Public init commands should stay minimal and user-meaningful.

Required rules:

- Public commands should not expose root-selection or self-elevation plumbing such as `-LocalRoot`, `-SkipSelfElevation`, or `-WasSelfElevated`.
- The sandbox root should resolve from the default per-user `LocalAppData` location and be pinned internally before meaningful work starts.
- Portable runtime commands may expose focused refresh switches such as `-RefreshPython`, `-RefreshPs7`, `-RefreshGit`, `-RefreshVSCode`, and `-RefreshNode`.
- `Initialize-VCRuntime` may expose install-specific tuning, but it should still hide the same internal root and elevation plumbing.
- `SupportsShouldProcess` and `-WhatIf` behavior are part of the public contract.

## Current Command Families

- `Initialize-PythonRuntime`, `Initialize-Ps7Runtime`, `Initialize-GitRuntime`, `Initialize-VSCodeRuntime`, `Initialize-NodeRuntime`, `Initialize-OpenCodeRuntime`, `Initialize-GeminiRuntime`, `Initialize-QwenRuntime`, `Initialize-CodexRuntime`, and `Initialize-GHCliRuntime` manage portable user-scoped runtimes under the sandbox root.
- `Initialize-VCRuntime` manages a machine/runtime prerequisite and evaluates the real installed machine state.
- `Get-SandboxState` is the read-only inspection surface for the persisted command state document plus live runtime snapshots.

## Runtime Discovery Policy

Portable runtime commands should prefer the sandbox-managed copy under the pinned root, but they must also detect a compatible runtime that already exists outside prior sandbox state.

Required rules:

- A compatible runtime already visible on `PATH` or in a common install location may satisfy readiness even if the sandbox command did not install it.
- A runtime discovered under the sandbox-managed tools root should be treated as `Managed`.
- A runtime discovered outside the sandbox-managed tools root should be treated as `External`.
- Refresh switches may still force acquisition and installation of the sandbox-managed copy even when an external runtime already satisfies readiness.
- VS Code follows the same managed-versus-external model, but a managed VS Code runtime must validate as portable-mode capable.
- Machine/runtime prerequisites such as `Initialize-VCRuntime` are different because they are not portable sandbox-owned tools. They should evaluate the real machine state.

## Shared Orchestration Contract

Current init commands should continue to follow this meta-flow:

1. Resolve the default sandbox root and pin it internally immediately.
2. Build the derived layout from the pinned root.
3. Read the initial state from the real system and file layout.
4. Derive `PlannedActions` from the observed initial state.
5. Decide whether the command is blocked, ready, partial, repairable, or needs acquire/install work.
6. If a repair step is needed, execute only the repair step.
7. Re-read state after repair.
8. Recompute acquire/install needs from the refreshed state.
9. If an acquire step is needed, acquire only the package or installer for that phase.
10. Validate the acquired artifact before install.
11. Recompute whether elevation is actually required for the next mutation.
12. If elevation is required and the current process is not elevated, self-reinvoke using the pinned root and the same logical request.
13. Execute the install or apply step.
14. Re-read final state from the real system.
15. For portable runtime commands, synchronize the command-line environment from the final observed runtime state.
16. Persist invoke state from the final observed result unless running in `-WhatIf`.
17. Return a structured result that explains what really happened.

The command must never trust an earlier assumption after repair, download, install, or elevation boundaries have been crossed.

## State-Machine Rules

Required rules:

- Each phase must consume a known state and produce either an unchanged decision or one bounded mutation followed by a required state refresh.
- A mutation must not be followed by more assumptions based on stale state.
- If a step can change files, extracted tools, installed runtimes, registry state, or cache contents, the next phase must use a fresh state read.
- The command should fail closed on ambiguous state instead of guessing.
- The command should remain idempotent. Rerunning it against a ready system should not trigger destructive work.

## Command-Line Environment Synchronization

The portable runtime commands now share command-line environment synchronization as part of the init contract.

Required rules:

- `Initialize-PythonRuntime`, `Initialize-Ps7Runtime`, `Initialize-GitRuntime`, `Initialize-NodeRuntime`, `Initialize-OpenCodeRuntime`, `Initialize-GeminiRuntime`, `Initialize-QwenRuntime`, `Initialize-CodexRuntime`, `Initialize-GHCliRuntime`, and `Initialize-VSCodeRuntime` should derive a desired command directory from the final runtime state.
- They should update both the process `PATH` and the user `PATH` so the desired directory is present and preferred.
- Synchronization must validate actual command resolution after the update. It must not assume a `PATH` write succeeded just because the environment variable changed.
- The expected command set is currently `python` and `python.exe` for Python, plus `pip.cmd` and `pip3.cmd` when the Python runtime source is managed; `pwsh.exe` for PowerShell 7; `git.exe` for Git; `node.exe` and `npm.cmd` for Node.js; `opencode` plus `opencode.cmd` for OpenCode CLI; `gemini` plus `gemini.cmd` for Gemini CLI; `qwen` plus `qwen.cmd` for Qwen CLI; `codex` plus `codex.cmd` for Codex CLI; `gh` plus `gh.exe` for GitHub CLI; and `code` plus `code.cmd` for VS Code.
- The command result and persisted invoke state should surface `CommandEnvironment` for these portable runtime commands.
- `Initialize-VCRuntime` does not participate in command-line environment sync.

## Bulletproofness Requirements

To keep the commands safe and predictable:

- Do not combine repair, acquire, validate, and install into one blind action block.
- Do not assume a cached artifact remains valid after repair or refresh.
- Do not assume install succeeded just because a process exited with a nominal code.
- Do not persist state before the final verification pass.
- Do not derive final return values from intended actions. Derive them from observed final state.
- Do not cross into an elevated process without carrying the pinned root and the same logical command intent.
- Do not let elevated and non-elevated runs drift into different `state.json`, cache, or tools paths.

## Path and Identity Pinning

The commands must pin their execution identity before they mutate anything.

At minimum, the following must stay stable across normal and elevated execution:

- `LocalRoot`
- `CacheRoot`
- `Ps7CacheRoot`
- `PythonCacheRoot`
- `NodeCacheRoot`
- `GeminiCacheRoot`
- `CodexCacheRoot`
- `GHCliCacheRoot`
- `GitCacheRoot`
- `VsCodeCacheRoot`
- `VCRuntimeCacheRoot`
- `ToolsRoot`
- `Ps7ToolsRoot`
- `PythonToolsRoot`
- `NodeToolsRoot`
- `GeminiToolsRoot`
- `CodexToolsRoot`
- `GHCliToolsRoot`
- `GitToolsRoot`
- `VsCodeToolsRoot`
- `StatePath`
- stage directories under the pinned root

`state.json` must represent one logical sandbox state document, regardless of whether a privileged child process was used.

The elevated child process must receive the caller's pinned `LocalRoot`. It must not recompute its own root from user profile or process-context differences.

## State Persistence

Persisted state is part of the current feature set, not just an implementation detail.

Required rules:

- `Save-ManifestedInvokeState` is the baseline persistence path for init commands.
- Persisted command entries should capture `ActionTaken`, `Status`, `RestartRequired`, layout paths, `Elevation`, and command-specific `Details`.
- Portable runtime command entries should also persist `CommandEnvironment`.
- `Get-SandboxState` should continue to expose both the persisted command document and runtime snapshots for `PythonRuntime`, `NodeRuntime`, `OpenCodeRuntime`, `GeminiRuntime`, `QwenRuntime`, `CodexRuntime`, `GHCliRuntime`, `Ps7Runtime`, `GitRuntime`, `VSCodeRuntime`, and `VCRuntime`.
- `PersistedStatePath` should be `$null` in `-WhatIf` results.

## Elevation Requirement

Elevation is a planning concern, not a hardcoded property of every command.

Required behavior:

- Determine whether the next real mutation requires elevation.
- Skip self-elevation when the process is already elevated.
- Skip self-elevation when the next step does not require it.
- Never trigger elevation in `-WhatIf`.
- After self-reinvoke, continue the same logical flow with the same pinned root and same request intent.
- Under the current implementation, `Initialize-VCRuntime` is the command that may require elevation for install or repair work.
- Portable runtime commands should still return an `Elevation` object even when no elevation is required.

The current shared elevation pattern is the baseline to reuse:

- `Get-ManifestedCommandElevationPlan`
- `Invoke-ManifestedElevatedCommand`

## Return Contract Requirement

Init commands should return structured result objects whose final picture comes from observed final state.

At minimum, every init command result should include:

- `LocalRoot`
- `Layout`
- `InitialState`
- `FinalState`
- `ActionTaken`
- `PlannedActions`
- `RestartRequired`
- `Elevation`
- `PersistedStatePath`

Portable runtime commands should also include:

- `Package`
- `PackageTest`
- `RuntimeTest`
- `RepairResult`
- `InstallResult`
- `PipSetupResult` when the command owns a managed pip bootstrap or proxy/config layer
- `CommandEnvironment`

`Initialize-VCRuntime` should return the installer-oriented equivalents:

- `Installer`
- `InstallerTest`
- `RuntimeTest`
- `RepairResult`
- `InstallResult`

The result should explain what really happened, not just what the command intended to do.

## Future Combined Command

If a combined `Initialize-Sandbox` style command is added later, it should orchestrate the existing per-command pattern instead of inventing a shortcut path that bypasses the current guarantees.

Required rules:

- Preserve the same pinned root and path identity across the whole run.
- Reuse the same per-subsystem state -> plan -> mutate -> re-read discipline.
- Preserve current persistence rules and final observed-state return semantics.
- Aggregate sub-results without hiding the underlying runtime-specific outcomes.

## Current Reference Implementations

Use these files as the current baseline references:

- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.PythonRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.VsCodeRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Private/Logic/Eigenverft.Manifested.Sandbox.Shared.CommandEnvironment.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Private/Infra/Eigenverft.Manifested.Sandbox.Shared.Elevation.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Private/Common/Eigenverft.Manifested.Sandbox.Shared.Paths.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Private/Common/Eigenverft.Manifested.Sandbox.Shared.Pip.ps1`
- `src/prj/Eigenverft.Manifested.Sandbox/Public/Eigenverft.Manifested.Sandbox.Shared.State.ps1`

The future combined command does not need to copy the current code literally, but it should preserve the same orchestration discipline and current feature guarantees.
