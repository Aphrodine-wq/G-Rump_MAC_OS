# Launching G-Rump

## Double-click `G-Rump.command`

The script builds in a **local** `.build` folder (no `~/Library` access), so you shouldn’t see permission or “stuck at step 2/5” build issues. First build may take 1–2 minutes.

---

If you see **"The file could not be executed because you do not have appropriate access privileges"**:

1. **Fix permissions (one-time):**  
   Open **Terminal**, then run:
   ```bash
   cd "$(dirname "$0")"   # or: cd ~/Desktop/G-Rump
   chmod +x G-Rump.command
   ```
   Then double-click `G-Rump.command` again.

2. **Or use Finder:**  
   Select `G-Rump.command` → **File → Get Info** → under **Sharing & Permissions**, ensure your user has **Read & Write**. If there’s a lock, click it and authenticate, then ensure "Execute" (or read) is allowed for your user.

3. **Or run from Terminal:**
   ```bash
   cd /path/to/G-Rump
   ./G-Rump.command
   ```
   Or build and run manually:
   ```bash
   swift build -c release && swift run -c release --skip-build GRump
   ```

After `chmod +x`, double-click should work. If your Mac has strict security (e.g. Gatekeeper or management profiles), running once from Terminal is the most reliable.
