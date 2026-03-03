## Purge leaked token & rotate credentials (safe steps)

If you committed a secret (personal access token) to the repository, follow these steps immediately:

1) Revoke the token now on GitHub
   - Go to GitHub → Settings → Developer settings → Personal access tokens and revoke the token shown.

2) Remove the file from working tree and commit the deletion
   ```bash
   git rm --cached "path/to/NeoOptimize git token new.txt"
   git commit -m "chore(secrets): remove leaked token file"
   git push
   ```

3) Purge the token from Git history (recommended: `git filter-repo`)
   - Install `git-filter-repo` (https://github.com/newren/git-filter-repo)
   - Example: remove a file entirely from history
   ```bash
   git filter-repo --invert-paths --paths "NeoOptimize git token new.txt"
   ```

   - Example: replace a specific secret string everywhere (use a plaintext file mapping)
   ```bash
   # Create a replacements file 'replacements.txt' with lines like:
   # SECRET_STRING==>REDACTED
   git filter-repo --replace-text replacements.txt
   ```

If `git filter-repo` is not available, you can use BFG Repo Cleaner:

```bash
# Using BFG to remove a file
bfg --delete-files "NeoOptimize git token new.txt"
git reflog expire --expire=now --all && git gc --prune=now --aggressive
```

4) Force-push cleaned history to remote

```bash
git push --force --all
git push --force --tags
```

5) Rotate other credentials if the token had broad scopes.

6) Add secret scanning & pre-commit hooks to avoid future leaks (e.g., `git-secrets`, `pre-commit`).

Note: Purging history rewrites commit SHAs and will require collaborators to re-clone or carefully rebase. Communicate changes to your team before force pushes.
