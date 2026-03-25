# Multi-Agent Workflow Cheat Sheet

## Setup (open 4 terminals)

```bash
# Terminal 1 - Planner
cd /Users/harry/Documents/apps/NimbusGlide && claude

# Terminal 2 - Worker A
cd /Users/harry/Documents/apps/NimbusGlide-workerA && claude

# Terminal 3 - Worker B
cd /Users/harry/Documents/apps/NimbusGlide-workerB && claude

# Terminal 4 - Reviewer/Tester
cd /Users/harry/Documents/apps/NimbusGlide && claude
```

## Workflow

1. **Planner terminal** — describe what you want to build
2. Planner gives you scoped tasks for each worker
3. **Copy each task** to the matching worker terminal
4. Workers code and commit
5. **Reviewer terminal** — say "review Worker A's changes" or "review Worker B's changes"
   - It can run: `git diff main..feature-workerA`
   - It can run tests, spot bugs, suggest fixes
6. When approved, merge from the Planner terminal:
   ```bash
   git merge feature-workerA
   git merge feature-workerB
   ```

## Cleanup (when done)

```bash
cd /Users/harry/Documents/apps/NimbusGlide
git worktree remove ../NimbusGlide-workerA
git worktree remove ../NimbusGlide-workerB
git branch -d feature-workerA feature-workerB
```
