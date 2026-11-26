# Changelog

## Unreleased

- Git Grail is a native macOS git client. It runs the `git` and `gh` tools and uses their login.
- The sidebar shows projects and their worktrees with a status: up to date, behind main, or conflict with main.
- One worktree always has the main branch. Every 90 seconds the app fetches and resets it to `origin/main`.
- You can create a feature worktree, rebase it on main, push it, and create a pull request.
- The project page shows how many commits each worktree is ahead of and behind main, and lists the commits ahead.
- The worktree page shows the changed files and their diff. You can leave a file out of the commit or reset it.
- Undo All removes all changes of a worktree. Redo brings them back.
- You can open a worktree in VS Code.
- The action log shows each action you did.
