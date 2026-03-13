# AGENTS.md

## Execution behavior
- For any non-trivial request, first decompose the work into a short executable task list before making code changes.
- If the work naturally splits into distinct chains, phases, or concern areas, organize the plan into task groups instead of one flat list.
- Create task groups when separable workstreams are clearly identifiable, such as setup, refactoring, implementation, validation, documentation, or follow-up fixes.
- Keep task lists concrete and action-oriented. Prefer 3-7 total tasks for smaller efforts, and use grouped subtasks only when they improve clarity.
- Keep exactly one task in progress at a time unless parallel work is clearly safe and beneficial.
- Update the task list whenever scope changes, new dependencies are discovered, or a task is completed, blocked, or no longer relevant.
- Preserve execution momentum: task tracking should support implementation, not delay it.
- For trivial, localized, single-file edits, skip task decomposition and execute directly.
- Before finishing, reconcile the full task structure so every task or subtask is marked as completed, blocked, cancelled, or intentionally deferred.

## General PowerShell Requirements
- All code must remain compatible with PowerShell 5.1.
- When there is a reasonable choice, prefer implementations that work in both Windows PowerShell 5.1 and PowerShell 7+.
- Treat this repository as a PowerShell module project intended for PowerShell Gallery distribution.

## Directory Structure
- `source` is the project source area. Files directly under `source` can be part of the repository without being part of the published PowerShell module.
- `source/<ModuleName>` is the publishable module directory. Its folder name must match the module name, and files that should ship in the PowerShell Gallery package belong in that directory.
- Keep unrelated project files out of `source/<ModuleName>`. Repository-only notes, helper scripts, and other project files can live elsewhere under `source` or at the repo root.
- `source/<ModuleName>.TestImports.ps1` is a manual import-validation script intended to be run from Visual Studio Code for testing import scenarios. Its behavior and expectations should stay aligned with `source/<ModuleName>/<ModuleName>.psm1`.
- `resources` contains assets referenced by the module manifest, such as icons or images.
- `iwr` contains bootstrapper scripts, including the entry point intended for `iwr | iex` usage.
- `.agents` contains repo-specific agent instructions and reusable skills. It is for repository workflow guidance, not for the published module payload.
