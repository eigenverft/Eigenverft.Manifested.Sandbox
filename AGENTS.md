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