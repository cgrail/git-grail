# git-grail

Git Grail is a native macOS git client for work with worktrees.
It runs the `git` and `gh` command-line tools for every action and keeps no credentials of its own.
Fetch, push, clone and pull requests use the login that `git` and `gh` already have.

## Requirements

- macOS 14 or later
- `git` 2.38 or later (the app uses `git merge-tree --write-tree`)
- `gh` with `gh auth login` done, for clone and pull requests
- Visual Studio Code, for "Open in VS Code"

## Build and run

```sh
./scripts/bundle.sh          # builds dist/GitGrail.app
open dist/GitGrail.app
```

To install the app, copy `dist/GitGrail.app` to `/Applications`.
The build needs only the Xcode Command Line Tools. For development, `swift run GitGrail` also starts the app.

Run the tests:

```sh
swift test --enable-code-coverage
```

## How it works

### Projects and worktrees

- Add an existing repo with **+ → Add Existing Repo…**, or clone one with **+ → Clone with gh…**.
- The sidebar shows a tree: project → worktrees. Each row has a status icon, the number of changed files, and ↑ahead ↓behind.
- One worktree always has the main branch. If no worktree has it, the app creates `<repo>.worktrees/main` next to the repo.
- **New Worktree** creates a feature branch from `origin/main` in `<repo>.worktrees/<branch>`.

### Sync

Every 90 seconds the app runs `git fetch --prune origin` for each project.
Then it runs `git reset --hard origin/main` in the main worktree.
If the main worktree has changes, the app does not reset it and shows a warning on the project page.
**Sync** in the toolbar (⇧⌘R) starts a sync at once. ⌘R refreshes the selected project.

### Status

| Icon | Meaning |
|------|---------|
| Green check | The branch is up to date with `origin/main` |
| Yellow triangle | The branch is behind `origin/main`, and a rebase has no conflicts |
| Red octagon | A rebase on `origin/main` has conflicts |

The app checks for conflicts with `git merge-tree`, in memory. It does not change your worktree.
**Rebase on main** runs `git rebase --autostash origin/main`. If the rebase stops on a conflict, the app aborts it, so your branch stays as it was.

### Files, diff and commit

- The worktree page lists the changed files. Select a file to see its diff.
- Clear the checkbox of a file to leave it out of the commit.
- The reset button of a file removes its changes.
- **Undo All** removes all changes of the worktree. **Redo** brings back the last removed changes.
  Undo and reset save the changes with `git stash`, so Redo can always restore them.
- **Push** runs `git push -u origin HEAD`. **Pull Request** pushes and runs `gh pr create --fill`.

### Action log

The **Action Log** button shows each action you did, with its result.
The app keeps the last 500 entries in `~/Library/Application Support/GitGrail/actions.jsonl`.
