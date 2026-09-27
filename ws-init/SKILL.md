---
name: ws-init
description: Initialize and publish a development Workspace.
disable-model-invocation: true
---

# Workspace initialization

Act as a thin invocation adapter. The Bash interface remains the sole authority for validation, mutation, successful completion, and recovery.

1. **Arguments:** Resolve `--path` from the requested Workspace root. Use the current directory only when the user identifies it as the target; otherwise ask for the Workspace root. Forward explicitly requested `--repo` and `--visibility` values unchanged, plus one `--allowed-root` for each additional Allowed root. Leave omitted optional arguments to the Bash interface. Completion: every supplied value is represented once, except repeatable Allowed roots.

2. **Authorization gate:** Before invoking the script or probing GitHub, request one elevated execution for the final command that covers Workspace writes and network access for all GitHub CLI operations. If permission is denied, stop and report: `Workspace initialization did not start because required permission was not granted.` Completion: permission was granted and the authorized final command started, or permission was denied and no restricted attempt or Bash invocation occurred.

3. **Invocation:** After authorization, run `scripts/ws-init.sh` from this skill's directory with the resolved arguments. Invoke this governing interface directly and capture its exit status and output. Completion: the script has exited.

4. **Result:** When the script succeeds, relay its output without interpreting it. When the script exits non-zero, report `Workspace initialization failed:` followed by its exit status and output. Completion: the user received either the script's successful output or its true failure unchanged.
