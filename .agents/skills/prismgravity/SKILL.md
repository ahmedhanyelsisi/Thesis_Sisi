---
name: prismgravity
description: Automates the startup sequence for the Prism bidirectional local-to-cloud workspace bridge.
---

# PrismGravity Skill

This skill allows Antigravity to automatically launch and connect to the user's Prism project, establishing a bidirectional bridge between the local repository (`D:\Masters\Thesis_Repo\Thesis_Sisi`) and the cloud-based Prism editor via the Chrome DevTools Protocol.

## Trigger
Use this skill when the user says "Start PrismGravity" or asks to initialize the Prism workflow.

## Actions to perform:
1. Launch a dedicated Chrome debugging instance pointing to the user's specific Prism project URL. Run this exact command in PowerShell using the `run_command` tool:
   ```powershell
   Start-Process "chrome.exe" -ArgumentList "--remote-debugging-port=9222", "--user-data-dir=""C:\ChromeDebug""", "https://prism.openai.com/?u=5b501ed7-9275-4cc0-baf0-dfc8170b16be&pg=1&m=MAIN.tex"
   ```

2. Wait a few seconds for Chrome to launch.

3. Remind the user that the bridge is fully active, and that they can now trigger the bidirectional sync at any time by telling you:
   - **"Fix my active file"**: You will read the active Prism tab, apply fixes via `prism_cli.py apply_and_sync`, and push to Git.
   - **"Sync my manual Prism edits"**: You will read their active Prism tab via `prism_cli.py active` and sync it to the corresponding local file and Git.
   - **"Push my local edits"**: You will run `prism_cli.py push_local <filename>` to push their local IDE edits up to Prism and Git.

4. Inform the user that they must log in to Prism (if they aren't already) in the newly opened Chrome window, and let you know when they are ready to start syncing!
