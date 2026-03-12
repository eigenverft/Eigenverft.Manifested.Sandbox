# Sandbox Init Command Requirements

## Objective

This note defines the meta-flow requirement for any future combined sandbox initialization command, for example `Initialize-Sandbox`.

The main point is not the public name. The main point is that the command must follow a bulletproof orchestration flow built around state discovery, plan derivation, revalidation after each mutation, and persistence from observed final state.

The future combined command should behave like a robust state machine coordinator, not like a one-pass script.

## Public Command Simplicity

Exported commands should stay minimal and user-meaningful.

Required rule:

- Public commands should not expose root-selection or self-elevation plumbing such as `-LocalRoot`, `-SkipSelfElevation`, or `-WasSelfElevated`.
- The public sandbox location should always resolve from the default per-user `LocalAppData` root.
- Path pinning is still required, but it is an internal implementation concern, not a public command option.
- Internal helpers may carry the pinned root across process boundaries, but callers should not need to pass it.

## Runtime Discovery Policy

Portable runtime commands such as `Initialize-Ps7Runtime`, `Initialize-GitRuntime`, and `Initialize-NodeRuntime` should prefer the sandbox-managed copy under the pinned `LocalAppData` root, but they must also detect a compatible runtime that already exists outside prior sandbox state.

Required rule:

- A compatible runtime already visible on `PATH` or in a common default install location should satisfy readiness even if it was not initialized by the sandbox command before.
- A runtime discovered under the sandbox-managed tools root should be treated as `Managed`.
- A runtime discovered outside the sandbox-managed tools root should be treated as `External`.
- Refresh switches may still force acquisition and installation of the sandbox-managed copy even when an external runtime already satisfies readiness.
- Machine/runtime prerequisites such as `Initialize-VCRuntime` are different: they should evaluate the real machine state because they are not portable sandbox-owned tools.

## Core Requirement

The combined init command must use the same meta-flow style as the current init commands:

- get current state first
- derive a plan from that state
- execute at most one logical transition at a time
- re-read state after each transition that can change reality
- only persist from the final observed state

The command must never trust an earlier assumption after repair, download, install, or elevation boundaries have been crossed.

## Required Meta-Flow

The expected control flow is:

1. Resolve the default `LocalAppData` sandbox root and pin it internally immediately.
2. Build the derived layout from the pinned root.
3. Read the initial state from the real system and file layout.
4. Derive `PlannedActions` from the initial state.
5. Decide whether the command is blocked, already satisfied, partial, repairable, or needs acquire/install work.
6. If a repair step is needed, execute only the repair step.
7. Re-read state after repair.
8. Recompute the plan from the refreshed state.
9. If an acquire or refresh step is needed, execute only that step.
10. Revalidate the acquired artifact.
11. Recompute whether elevation is actually required for the next step.
12. If elevation is required and the current process is not elevated, self-reinvoke using the pinned root and the same logical request.
13. Execute the install or apply step.
14. Re-read final state from the real system.
15. Persist invoke state from the final observed state unless running in `-WhatIf`.
16. Return a structured result that includes both the initial and final picture.

This is the baseline. A future combined command may orchestrate multiple subsystems, but it should not skip the re-read and re-plan phases between meaningful transitions.

## State-Machine Rules

The command should be treated as a state-machine driver.

Required rules:

- Each phase must consume a known state and produce either:
  - an unchanged state with a decision, or
  - one bounded mutation followed by a required state refresh.
- A mutation must not be followed by more assumptions based on stale state.
- If a step can change files, registry, installed runtimes, extracted tools, or cache contents, the next phase must use a fresh state read.
- The command should fail closed on ambiguous state instead of guessing.
- The command should remain idempotent: rerunning it against a ready system should produce no destructive work.

## Bulletproofness Requirements

To keep the command safe and predictable:

- Do not combine repair, acquire, validate, and install into one blind action block.
- Do not assume a cached artifact remains valid after repair or refresh.
- Do not assume install succeeded just because a process exited with a nominal code.
- Do not persist state before the final verification pass.
- Do not derive final return values from intended actions; derive them from observed final state.
- Do not cross into an elevated process without carrying the pinned root and the same logical command intent.
- Do not let elevated and non-elevated runs drift into different `state.json`, cache, or tools paths.

## Path and Identity Pinning

The command must pin its execution identity before it mutates anything.

At minimum, the following must stay stable across normal and elevated execution:

- `LocalRoot`
- `CacheRoot`
- `ToolsRoot`
- `NodeToolsRoot`
- `VCRuntimeCacheRoot`
- `StatePath`
- stage directories under the pinned root
- logs written under the pinned root

`state.json` must represent one logical sandbox state document, regardless of whether a privileged child process was used.

The elevated child process must receive the caller's pinned `LocalRoot`. It must not recompute its own root from user profile or process context differences.
This pinning should happen internally. The caller should still experience a simple command surface with no root override option.

## Elevation Requirement

Elevation is a planning concern, not a hardcoded property of the whole command.

Required behavior:

- Determine whether the next real transition requires elevation.
- Skip self-elevation when the process is already elevated.
- Skip self-elevation when the next step does not require it.
- Never trigger elevation in `-WhatIf`.
- After self-reinvoke, continue the same logical flow with the same pinned root and same request intent.

The current shared elevation pattern is the baseline to reuse:

- `Get-ManifestedCommandElevationPlan`
- `Invoke-ManifestedElevatedCommand`

## Return Contract Requirement

The combined command should return a result object that exposes the orchestration clearly.

At minimum, the top-level result should include:

- `LocalRoot`
- `Layout`
- `InitialState`
- `FinalState`
- `PlannedActions`
- `ActionTaken`
- `RestartRequired`
- `Elevation`
- `PersistedStatePath`

If the command coordinates subsystems, it should include their sub-results explicitly, for example:

- `NodeRuntime`
- `VCRuntime`

The result should explain what really happened, not just what the command intended to do.

## Recommended Combined Flow

For a future `Initialize-Sandbox` style command, the preferred shape is:

1. Pin `LocalRoot`.
2. Read top-level combined state.
3. Decide which subsystems need work.
4. For each subsystem, follow the same meta-flow:
   get state -> derive plan -> mutate one phase -> re-read state.
5. If a subsystem requires elevation, reinvoke once with the same pinned root and continue the same logical operation.
6. Aggregate subsystem final states and sub-results.
7. Persist only from the final aggregated state.

The combined command should orchestrate the existing patterns, not invent a separate shortcut path.

## Current Reference Implementations

Use these files as the current baseline references:

- `source/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache.ps1`
- `source/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache.ps1`
- `source/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache.ps1`
- `source/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache.ps1`
- `source/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.Shared.Elevation.ps1`
- `source/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.Shared.Paths.ps1`
- `source/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.Shared.State.ps1`

The future combined command does not need to copy the current code literally, but it should preserve the same orchestration discipline.
