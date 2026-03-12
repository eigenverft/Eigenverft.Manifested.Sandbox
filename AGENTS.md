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

## General PowerShell source/modulename Requirements
- All code must be compatible with PowerShell 5.1, if there is a way to keep it working with PS5.1 and PS7 this is prefered.
- This project is a PowerShell NuGet package intended for the PowerShell Gallery.
- Files that are meant to be published are located in `source/modulename`.
- Be careful not to place unrelated files in `source/modulename`, because that directory is part of the published package.

## Directory Structure
- The `resources` directory contains assets such as `.ico` and `.png` files that are referenced by the module manifest.
- `iwr/bootstrapper.ps1` contains a one-liner bootstrap script that can be executed through an `iwr | iex` chain.
- The root of the `source` directory must contain a file named `.TestImports.ps1`.
- `.TestImports.ps1` is intended to be run manually from Visual Studio Code for testing specific import scenarios.
- The behavior and expectations of `.TestImports.ps1` should stay aligned with `Eigenverft.Manifested.Sandbox.psm1`.
