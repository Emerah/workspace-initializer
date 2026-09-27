# ws-init

Initialize a macOS development workspace and publish its first commit to a new GitHub repository. The skill passes your arguments to [the Bash script](scripts/ws-init.sh), which performs validation, file creation, Git initialization, and publication.

## Requirements

- macOS, Git, and an authenticated GitHub CLI (`gh auth status`).
- A workspace path beneath `~/Desktop`, `~/Developer`, `~/Documents`, or an existing root supplied with `--allowed-root`.
- An existing immediate parent for the workspace path. The workspace directory itself may be new or already contain files.

## Use

Invoke `$ws-init` with the workspace path, or run the script directly:

```bash
./ws-init/scripts/ws-init.sh --path "$HOME/Developer/my-project"
```

Optional arguments:

| Argument | Default | Purpose |
| --- | --- | --- |
| `--repo NAME` | Workspace directory name | GitHub repository name |
| `--visibility private\|public` | `private` | GitHub repository visibility |
| `--allowed-root PATH` | Desktop, Developer, Documents | Add an allowed parent root; repeat as needed |

The script is non-interactive. Once validation and the staged-secret check pass, it creates the commit and publishes automatically.

## What it does

1. Rejects an existing `.git`, an ancestor Git worktree, an existing GitHub repository with the chosen name, and invalid workspace paths.
2. Preserves existing regular `.gitignore`, `README.md`, and `LICENSE.md` files; creates only the missing ones. Directories and symlinks at these paths are rejected.
3. Initializes `main`, runs `git add --all`, and checks staged content for obvious secrets. It prints `git diff --cached --name-only` for visibility.
4. Commits, creates a repository under the authenticated GitHub user, adds `origin`, and pushes `main` with upstream tracking.

Other existing workspace files are preserved and committed when Git does not ignore them. If a step fails after changes begin, the script keeps those changes and prints manual recovery commands; it does not roll them back.

## How to install

download repository and copy `ws-init` skill directory to `/Users/emerah/.agents/skills`
