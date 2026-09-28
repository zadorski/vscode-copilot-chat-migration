# Safety and Recovery

## Safety properties

- Export and import check for running VS Code processes immediately before copying. `-SkipPrompts` cannot bypass this check.
- Import validates the complete plan before writing anything.
- A target backup is created before state replacement. Explicit backup paths are never overwritten; automatic names include a timestamp and GUID.
- Replacement preserves the target `workspace.json`, removes stale target state, copies source files, and rewrites only mapped `chatSessions/*.json` URI references. Database and other files remain binary copies.
- Running the same import again converges the target state to the same source snapshot, apart from the newly created backup archive.
- Preparation is resumable: records already present are skipped, while missing records remain visible for a later `-Open` run.

## Rollback

Keep the export ZIP, separate chat exports, and target backup until the migrated workspaces have been checked. Close VS Code before restoring a backup.

```powershell
$restore = Join-Path $env:TEMP 'vscode-copilot-target-restore'
Remove-Item $restore -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive "$backup\target-before-import.zip" -DestinationPath $restore
Get-Content "$restore\backup-manifest.json"
```

The manifest lists the original target IDs and folders. Restore each listed target folder from the archive, then reopen the target workspace through your normal VS Code command.

For individual conversations, use `Chat: Export Chat...` before migration and `Chat: Import Chat...` after validation. Settings Sync is useful for settings, extensions, and keybindings, but it is not the transport for workspace-local storage.
