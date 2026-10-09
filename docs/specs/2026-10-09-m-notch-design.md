# m_notch: design spec

Date: 2026-10-09
Status: built and public. Released as v0.1.0 at https://github.com/thanmay-strativ/m-notch-app (section 14), installed on the author's Mac from that release.

## 1. Goal

A small native macOS app that lives in the notch (or a small bar at the top of a screen without a notch) and shows live Claude Code sessions running in **PyCharm** and **VS Code**, with **Codex** as a second agent. It lets you approve permissions, answer Claude's questions and read diffs without leaving what you are doing.

It copies the look, feel and animation timings of [coucou](https://github.com/Louis-CFM/coucou) (MIT code), but with far less scope.

Example: Claude, running in the PyCharm terminal for `web-app`, wants to run `rm -rf build`. The island opens with a red card ("risky: rm -rf"), you press Allow, Touch ID confirms, Claude continues. You never left your browser.

### In scope

- macOS only, macOS 15 or later.
- Claude Code (main) and Codex CLI (secondary).
- Hosts: PyCharm (Community and Professional) and VS Code. Anything else still shows, but "jump" only brings that app to the front.
- Features: sessions, approvals, questions, live diffs, Codex, plus ideas 1 to 10 (section 6).

### Out of scope

API keys and chat, iPhone, Windows/Linux, integrations (GitHub, Stripe, ...), music, file drop, wardrobe, desktop character, weekly recap, dictation, demo mode, translations, sounds, launch at login, a settings window, custom shortcut keys, other agents.

### Licensing

coucou's **code** is MIT: copied files keep the copyright notice (`LICENSES/coucou-MIT.txt`). The **Mochi character, the names "Coucou"/"Mochi", the icon and the sounds** are all rights reserved by their author, so m_notch uses none of them. Its six characters are its own designs (Momo replaced an earlier private copy of Mochi before the repo went public), and its sounds are macOS system sounds. That is what lets the repo and its releases be public.

## 2. Architecture

```
Claude Code --(http hook: POST JSON + Bearer token + X-Host header)--+
Codex CLI   --(command hook: curl ... same JSON)----------------------+
                                                                      v
                                  HookServer (in app, 127.0.0.1:47823)
                                                                      |
                                  SessionStore (sessions by session_id, request queue)
                                                                      |
                                  IslandController (panel + state machine) -> SwiftUI views
User clicks -> SessionStore resolves request -> HookServer writes the HTTP reply -> agent continues
```

### Package layout

```
Package.swift                 one library (MNotchCore), one tiny executable (MNotch), one test target
Sources/MNotch/main.swift     starts NSApplication with AppDelegate
Sources/MNotchCore/
  App/        AppDelegate, MenuBarController
  Island/     IslandPanel, IslandGeometry, IslandStateMachine, IslandShape, IslandRootView, IslandController
  Views/      SessionListView, SessionRowView, ApprovalCardView, QuestionCardView, DiffView, PlanView
  Character/  BotEngine, BotCanvasView (copied from coucou, trimmed, recolored)
  Hooks/      HookServer, HTTPMessage, HookPayload, HookReply, HookInstaller, SettingsFileWriter
  Sessions/   Session, SessionStore, PendingRequest
  Features/   IDEJump, ProjectRoot, KeepAwake, RiskGuard, HotKeys, ContextMeter, LineDiff, QuietMode
Tests/MNotchCoreTests/
scripts/bundle.sh             swift build -c release, wrap into build/m_notch.app, ad-hoc sign, launch
```

### Rules

- Zero third-party packages. Only Apple frameworks: SwiftUI, AppKit, Network, LocalAuthentication, IOKit, Carbon (hot keys), Foundation.
- No macOS privacy permissions (Accessibility, Screen Recording). An ad-hoc signed app gets a new signature on every rebuild, and macOS forgets those grants each time.
- Swift 6 language mode. UI and `SessionStore` are `@MainActor`. `HookServer` runs on its own dispatch queue and hands events to the main actor.
- Never block an agent: if the app is down, the hook fails as a non-blocking error.
- Never approve anything without an explicit click, shortcut or Touch ID.
- Never overwrite `~/.claude/settings.json` blindly: preview, dated backup, merge, atomic write, only after Confirm.
- 0% CPU when hidden: the character timeline is paused, and mouse polling drops to 8 Hz.

## 3. The island

### Window

- `IslandPanel` is an `NSPanel` subclass, 720 x 560, transparent, never resized, never ordered out.
- Style: `[.borderless, .nonactivatingPanel]`, level `mainMenuWindow + 3`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, `hasShadow = false`, `isOpaque = false`, clear background.
- `canBecomeKey = true`, `becomesKeyOnlyIfNeeded = true`, `hidesOnDeactivate = false`, `canBecomeMain = false`, and `constrainFrameRect` returns the frame unchanged so it can sit over the menu bar. The hosting view accepts the first click (`acceptsFirstMouse`), because the app is never active.
- Placement: x = screen.midX - 360, y = screen.maxY - 560.
- Click-through: a main run loop timer polls `NSEvent.mouseLocation`. It runs at 60 Hz while the island is visible or the pointer is within 120 pt, otherwise at 8 Hz. It sets `ignoresMouseEvents` to false only while the pointer is inside the current island rect, inset by -6 pt on notch screens.

### Geometry

- A screen has a notch when `safeAreaInsets.top > 0`. Notch width = `frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width` (fallback 184). Height = `safeAreaInsets.top`.
- On a screen without a notch, the "notch" is an 80 x min(24, menu bar height) bar. Menu bar height = `frame.maxY - visibleFrame.maxY`, or `NSStatusBar.system.thickness` when that is 0. In the hidden state on a screen without a notch, the shape has opacity 0.
- Display choice (menu): **Follow mouse** (default), **Built-in screen**, **Main screen**. Follow mouse moves the island only while it is not expanded. The island is re-placed on `NSApplication.didChangeScreenParametersNotification`.

### States

| State | Size | Content |
|---|---|---|
| hidden | notch size | nothing |
| compact | (notch width + 160) x notch height | character left, status summary right ("2 working", or an orange "needs you") |
| expanded | 640 x content height (160 min, 560 max) | session list, or the card of the oldest pending request |

Transitions:

- hover while hidden: compact (peek).
- click while hidden or compact: expanded.
- pointer leaves expanded: compact after 15 s.
- compact with no pointer and nothing working: hidden after 60 s.
- hook activity (thinking/working): compact, unless quiet mode applies.
- pending request: expanded, and nothing auto-closes while any request is pending.
- session finished: compact for 5.2 s with a happy character jump, unless quiet mode applies.
- There is no Esc and no click-to-close (clicks in the open island belong to its buttons). The panel never takes keyboard focus (`becomesKeyOnlyIfNeeded`), so clicking Allow never steals typing from the IDE. The open island folds 15 s after the pointer leaves, or 1 s after the last request is answered.

### Animation (copied exactly from coucou)

- Open: `.spring(response: 0.5, dampingFraction: 0.72)`.
- Close: `.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)`.
- `IslandShape`: `animatableData` is width, height and bottom radius (14 compact, 22 expanded). The top edge stays square, hidden under the screen edge. Filled black, and content is clipped by the same shape.
- Content switching: every content view stays in a ZStack. The active one appears with opacity 0 to 1 and scale 0.97 to 1, using `.spring(response: 0.4, dampingFraction: 0.8).delay(0.16)`. Inactive ones fade out with `.easeIn(duration: 0.16)`, with hit testing disabled.
- Buttons and hover: `.spring(response: 0.3, dampingFraction: 0.8)` and `.spring(response: 0.2, dampingFraction: 0.7)`.
- Character: `TimelineView(.animation(paused: mode == .hidden))` plus `Canvas`. Each frame calls `engine.update(dt)` with dt capped at 0.05, then `draw`.

### Character

Copied from coucou's `BotEngine`/`BotCanvasView`, with outfits, sounds, desktop mode and mini bots removed. The body color changes to Claude-like terracotta `#D97757`. It keeps eyes that follow the cursor, blinks, emotes, working/thinking/finished/needs-you states, and annoyed/dizzy on clicks.

## 4. Hooks

### Endpoints

- `POST /m_notch/claude` and `POST /m_notch/codex` on `127.0.0.1:47823`.
- Each request must carry `Authorization: Bearer <token>`, or the reply is 401. Any request with an `Origin` header gets 403. Bodies over 1 MB get 413. Unknown paths get 404.
- The token is 32 random bytes in hex, created on first launch and stored in `UserDefaults`.
- Headers `X-Term` (`$TERM_PROGRAM`), `X-Emulator` (`$TERMINAL_EMULATOR`) and `X-Entry` (`$CLAUDE_CODE_ENTRYPOINT`) identify the IDE for Claude. Codex sends `X-Host` (`$__CFBundleIdentifier`) too. See section 11 for why Claude cannot send `X-Host`.

### Claude settings entries (`~/.claude/settings.json`)

All entries are `{"type":"http","url":...,"timeout":N,"headers":{...},"allowedEnvVars":[...]}`, without a matcher, except AskUserQuestion:

| Event | Timeout |
|---|---|
| SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, Notification, Stop | 10 |
| PermissionRequest | 300 |
| PreToolUse, matcher `AskUserQuestion`, URL `/m_notch/claude/ask` | 300 |

The AskUserQuestion entry has its own URL because both PreToolUse entries send the same payload: the generic one is answered at once, only `/ask` is held.

Install removes any old entry whose URL contains `/m_notch/` before adding the new ones, so reinstalling never duplicates entries. The file is rewritten with sorted keys.

### Codex entries (`~/.codex/hooks.json`)

These are command hooks: `curl -s -m 300 --data-binary @- -H 'Authorization: Bearer <token>' -H "X-Host: $__CFBundleIdentifier" -H "X-Term: $TERM_PROGRAM" -H "X-Emulator: $TERMINAL_EMULATOR" http://127.0.0.1:47823/m_notch/codex || true`, for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop and PermissionRequest. The user must trust the hook once in Codex (`/hooks`). There is no "Always" for Codex.

### Event handling

| Event | Reaction |
|---|---|
| SessionStart | create the session: name = last path component of the project root, host from headers |
| UserPromptSubmit | state thinking, clear the finished line |
| PreToolUse | state working, step text (for example "Edit views.py", "Bash: npm test"). For `AskUserQuestion` on the matcher entry: hold. |
| PostToolUse | Edit/MultiEdit/Write: record a diff. Dismiss a pending approval with the same session, tool and input. |
| Notification | `idle_prompt`: state needsYou |
| Stop | state done, finished line = first line of `last_assistant_message`; dismiss the session's pending requests |
| SessionEnd | remove the session and dismiss its pending requests |
| PermissionRequest | hold: queue a request, show the card |

An event for an unknown `session_id` creates the session on the fly.

### Replies

- Non-holding events: `200` with an empty body.
- Allow: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
- Always: Allow plus `"updatedPermissions": <permission_suggestions>`. The button is shown only if suggestions exist and the agent is Claude.
- Deny: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from m_notch"}}}`
- Reply in terminal / timeout / dismiss: `200` with an empty body.
- Question: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"questions":<original>,"answers":{"<question text>":"<label>"}}}}`. Multi-select answers are a list of labels (coucou's tested behavior on Claude Code 2.1.136 and later). This needs a manual check, see section 11.
- Plan (ExitPlanMode through PermissionRequest): Approve plan = Allow. Keep planning = Deny with the message "Keep planning, the user wants changes."

### Request lifetime

- Held requests stay open until answered, until 290 s pass (then an empty reply), or until the client disconnects (the card is dismissed).
- Requests form a FIFO queue. The card shows "1 of N".

## 5. Sessions

`Session`: id, agent (claude/codex), name, projectRoot, cwd, host (pycharm/vscode/other(bundleId)/unknown), state (thinking, working, needsYou, done, error), stepText, finishedLine, lastChange, diffs (last 20), contextPercent, transcriptPath.

Rows sort as: needsYou, working, thinking, done; newest change first within each group. Done sessions with no event for 30 min are removed.

## 6. Features

### Jump to window (IDEJump + ProjectRoot)

- Host detection: X-Host has a `com.jetbrains.pycharm` prefix, or X-Emulator is `JetBrains-JediTerm`: PyCharm. X-Host is `com.microsoft.VSCode`, X-Term is `vscode`, or X-Entry contains `vscode`: VS Code. Otherwise the project root decides: `.idea` means PyCharm, `.vscode` means VS Code.
- Project root: walk up from cwd to the first folder containing `.idea` (PyCharm) or `.vscode`/`.git` (VS Code). Stop at the home folder. Fallback: cwd.
- Action: `NSWorkspace.open([rootURL], withApplicationAt: appURL)`, which brings that project's window forward. Other hosts: activate the app by bundle id.

### Live diffs, and idea 5: open at line (LineDiff)

- Edit: old_string to new_string. MultiEdit: each edit. Write: compared with `tool_response.originalFile` when present, otherwise all lines added.
- Counts and rendering use Swift's `CollectionDifference` on lines.
- Line number: `tool_response.structuredPatch[0].newStart` when present, otherwise the first line of new_string searched in the file on disk, otherwise 1.
- Open: PyCharm `<app>/Contents/MacOS/pycharm --line N <file>`, VS Code `<app>/Contents/Resources/app/bin/code -g <file>:N`.

### Idea 1: multi-session and queue

See sections 4 and 5.

### Idea 2: quiet mode (QuietMode)

If the session's host app is `NSWorkspace.shared.frontmostApplication`, then thinking/working/done do not reveal the island. Pending requests always expand it.

### Idea 3: keep awake (KeepAwake)

While any session is thinking or working, and had an event in the last 30 min, hold `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, ...)`. Release it 10 s after the last one stops. There is a menu toggle, on by default.

### Idea 4: risky-command guard (RiskGuard)

- Bash patterns: `rm -rf`/`rm -fr`/`rm -r -f`, `sudo`, `git push --force`/`-f`/`--force-with-lease`, `git reset --hard`, `git clean -f`, `drop table`/`drop database`/`truncate` (case-insensitive), `curl|wget ... | sh|bash|zsh`, `chmod -R 777`, `dd if=`, `mkfs`, `> /dev/sd`.
- Edit/Write/MultiEdit: path inside `~/.ssh`, basename `.env` or `.env.*`, or path outside the session's project root.
- Effect: a red card with the reason. Allow requires `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`. Always is hidden.

### Idea 8: shortcuts (HotKeys)

Carbon `RegisterEventHotKey`, which needs no permission: Option+Cmd+Y Allow (or Approve plan), Option+Cmd+N Deny (or Keep planning), Option+Cmd+A Always, and Option+Cmd+1 to 4 to pick a question option, all acting on the oldest request. Registered only while a request is pending.

### Idea 6: context meter (ContextMeter)

Claude only. After Stop, and at most every 5 s on PostToolUse, read the last 64 KB of `transcript_path`, find the last line whose `message.usage` exists, and sum `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`. Percent = sum / 200k, or sum / 1M when the sum is over 200k. Shown as "ctx 82%", orange at 80% or above. Hidden when parsing fails.

### Idea 7: waiting timer and nudge

Rows show the age ("needs you · 3m", "done · 12m"). After 2 min with the same pending request or needsYou state, there is one bounce plus a character emote, once per wait. (2 min, not 5: held requests expire at 290 s.)

### Idea 9: plan viewer (PlanView)

PermissionRequest with tool `ExitPlanMode`: show `tool_input.plan` rendered with `AttributedString(markdown:)` line by line, in a scroll view, with Approve plan / Keep planning.

### Idea 10: hook health

On launch, and on file-system change events for `~/.claude/settings.json` and `~/.codex/hooks.json` (`DispatchSource` watch on the parent folder), check that our entries exist with the current token. The menu shows "Claude hooks: OK" or "Claude hooks: missing, Install...", plus "last event 2m ago".

## 7. Settings

The open island always has a header band (at least 28 pt tall): a sessions tab on the left and a settings gear on the right, visible on every page, including over request cards. While the Claude hooks are not installed, an orange "Install hooks" pill sits next to the gear. The gear opens a settings page inside the island: Claude and Codex hook status with Install/Repair, server status, screen choice, keep awake, and Quit. If a new request arrives while settings are open, the request card comes back.

The menu bar icon stays as a backup, with the same items. Status item menu, in this order:

1. Claude hooks status, then Install/Repair (preview window, then Confirm)
2. Codex hooks status, then Install/Repair
3. Last event time
4. Screen: Follow mouse / Built-in screen / Main screen
5. Keep Mac awake while working
6. Quit

The install preview is a small `NSAlert` with a scrollable text view showing the resulting JSON and the backup path, plus Confirm and Cancel buttons.

## 8. Error handling

| Case | Behavior |
|---|---|
| App not running | Connection refused. Claude treats it as a non-blocking error and continues. Codex: `|| true`. |
| Port in use | The menu shows "Port 47823 is used by another app". Hooks still install. |
| settings.json invalid | Install is refused with "~/.claude/settings.json is not valid JSON: <error>". |
| settings.json changed after preview | Refused: "~/.claude/settings.json changed since the preview, try again." |
| Malformed hook body | 400, logged with the path and byte count. |
| Touch ID fails or is cancelled | The request stays pending. |
| IDE app not found | Falls back to activating by bundle id, and logs the bundle id. |

Logging uses `os.Logger(subsystem: "local.mnotch", category: ...)` and every message names the offending value.

## 9. Testing

Swift Testing (`swift test`). Unit tests cover: geometry, state machine (injected clock), payload decoding, reply encoding, session store (queue and dismiss rules), installer merge (temp folder), risk guard, line diff, context meter, project root, and the HTTP server (random port: 401/403/200/held reply).

Manual: animation feel compared with coucou's demo, and end-to-end runs in PyCharm, VS Code and Codex.

## 10. Milestones

- **M0**: verify the unknowns with a throwaway logging server. Results are in section 11.
- **M1, the feel**: package, bundle script, panel, geometry, state machine, shape and animations, character, server (events), sessions, rows, jump, installer, menu.
- **M2, act from the notch**: approvals, queue, Always, risk guard and Touch ID, shortcuts, questions, plan viewer, Codex.
- **M3, extra info**: diffs and open at line, context meter, waiting timer and nudge, keep awake, quiet mode, hook health.
- **M4, extras** (section 13): calendar tab, now playing with seeking, terminal hook, own characters and outfits.
- **M5, publish** (section 14): Momo replaces the copied Mochi, demo media, README, built-in updater, public repo, release v0.1.0.

All six milestones are done. What is left is in section 14, "Open items".

## 11. M0 results

Tested with Claude Code 2.1.295, using a throwaway Python logging server and `claude -p --settings <file>`, inside the PyCharm terminal.

| Question | Result | Design impact |
|---|---|---|
| Do http hooks reach the app, and does an "allow" reply work? | Yes. PermissionRequest arrived and the allow decision was obeyed. | none |
| Does `permission_suggestions` arrive? | Yes, for example `[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch x"}],"behavior":"allow","destination":"localSettings"}]` | Always works as designed. |
| Does SessionStart arrive over http? | **No.** It never fired as an http hook. | Sessions are created on their first event (already in the design). SessionStart is not installed. |
| Does `$__CFBundleIdentifier` expand in headers? | **No.** Only `[A-Z_]` names are read: it became `undleIdentifier`. `${...}` is not expanded at all. `$TERMINAL_EMULATOR` works (`JetBrains-JediTerm`). | Host detection uses `X-Emulator: $TERMINAL_EMULATOR`, `X-Term: $TERM_PROGRAM` and `X-Entry: $CLAUDE_CODE_ENTRYPOINT`, with a project-folder fallback (`.idea` means PyCharm, `.vscode` means VS Code). Codex uses curl in a shell, so `$__CFBundleIdentifier` works there. |
| App down | Claude logs `connect ECONNREFUSED`, continues, and finishes normally. | Never blocks (confirmed). |
| Edit PostToolUse | `tool_response` has `filePath`, `oldString`, `newString`, `originalFile` and `structuredPatch[{oldStart,oldLines,newStart,newLines,lines}]`. | Diffs use `structuredPatch` lines directly. The line number is `newStart` plus the offset of the first changed line. |
| Write PostToolUse | `tool_response.type` is `create` or `update`, with `content`, `originalFile` (null on create) and `structuredPatch` (empty on create). | Create counts all lines as added. Update uses structuredPatch. |
| PermissionRequest has `tool_use_id`? | No. PostToolUse has it. | Dismiss matching uses session plus tool plus input (as designed). |
| AskUserQuestion and ExitPlanMode | Not available in `-p` mode, so not testable headless. | Built from the docs: multi-select answers are one `", "`-joined string. Manual check in a real session. |
| Concurrent terminal prompt while the hook holds | Not testable headless. | Manual check. The client-disconnect dismiss covers the case. |

Header set used by the installer: `Authorization`, `X-Term: $TERM_PROGRAM`, `X-Emulator: $TERMINAL_EMULATOR`, `X-Entry: $CLAUDE_CODE_ENTRYPOINT`, with `allowedEnvVars: ["TERM_PROGRAM", "TERMINAL_EMULATOR", "CLAUDE_CODE_ENTRYPOINT"]`.

## 12. Build notes (found during implementation)

- Only the Command Line Tools are installed (no Xcode). The macOS 27 SDK declares SwiftUI's `@State` as a macro whose plugin (`SwiftUIMacros`) ships only with Xcode, so `scripts/dev.sh` builds against the macOS 26 SDK when Xcode is missing.
- `swift test` loses the Swift Testing macro plugin on incremental builds with the Command Line Tools. `scripts/dev.sh test` passes `-plugin-path .../host/plugins/testing` and uses its own scratch folder.
- `os.Logger` values are marked `privacy: .public` (ids, paths, tool names, counts). Commands and the token are never logged.

## 13. Iteration 2 (user feedback, 2026-10-09)

- **Closing:** when the pointer leaves, the island settles back to its resting size after `closeDelay` (default 0.5 s, setting): compact while an agent is busy or within `activityHold` (default 60 s) after activity, hidden otherwise. A waiting request keeps it open. This replaces the 15 s / 60 s timers of section 3.
- **Jump fix:** asking PyCharm to open a project folder that is already open made it create an empty black project frame and hang. Jump now only activates the IDE (`NSRunningApplication.activate`). With the opt-in "Raise the exact project window" setting and the Accessibility permission, it also raises the window whose title contains the project name (PyCharm `name \u{2013} file`, VS Code `file \u{2014} name`).
- **Settings:** the gear opens a quick card in the island (close delay, open on hover, keep awake, sounds, stats, character color, status badges, Settings..., Quit). Settings... opens a window with a sidebar: General, Appearance, Agents, Sounds, Shortcuts, About. All values live in `Preferences` (UserDefaults).
- **Stats:** each session row has a third line `Opus 5.5  ctx 465k/1000k  tools 150  up 1h 05m`, and the header shows `5h 39% \u{00b7} 2h 33m` and `7d 37% \u{00b7} 4d 12h` pills (green, yellow from 50%, red from 80%).
  - Model, context and plan usage come from the **status line relay**: `statusLine.command` becomes `input=$(cat) && printf '%s' "$input" | curl ... /m_notch/statusline; printf '%s' "$input" | <previous command>`. The user's own status line output is byte-for-byte identical (checked). Remove restores the previous command exactly.
  - Without the relay, model and context are estimated from the transcript tail, and plan usage is hidden.
  - Tools: counted once from the transcript (`"type":"tool_use"`), then +1 per PreToolUse. Uptime: transcript creation time, like the user's status line script.
- **New settings:** reveal on activity / on finish, quiet mode, nudge, answer in the notch (off sends requests straight to the terminal), Touch ID for risky commands, raise exact window, keep awake, launch at login (`SMAppService`), character show / color (8 palettes) / glow, stats line, plan pills, diff chips, macOS system sounds for "needs you" and "finished", approval shortcuts, and Option+Command+M to open or close the island.
- **Back on request cards:** every card (permission, plan, question) has a `<` back button at the start of its title line, and the house tab does the same. The card hides and the session list shows. The request keeps waiting: the island no longer holds open, rests compact with the orange count, and the answer shortcuts are off. The header pill `N waiting` brings the card back. A new request shows its card again. "Reply in terminal" stays the way to hand a request to the terminal.
- **Two-step close:** when the pointer leaves, the island shrinks to compact after `closeDelay`, then stays compact for `compactHold` (default 5 s, choices 3 to 60 s) before hiding. `compactHold` only offers values longer than `closeDelay`, and raising `closeDelay` past it bumps it up, so the small island never just blinks.
- **Outfits (our own):** propeller cap (spins faster while working), headphones (music notes while working), flower crown (petals sway), graduation cap (tassel swings), halo (floats, glows), devil horns, antlers with a blinking red nose, heart glasses (shine sweeps), chef hat (puffs squash), ninja headband (tails flutter), None, or Auto (seasonal: devil horns in October, antlers in December, propeller cap at New Year, flower crown at Easter, heart glasses in summer). Caps, horns and antlers hide the character's head part. coucou's 12 outfits and their drawing code are removed; old saved values fall back to Auto. Settings > Appearance shows each outfit as a live card on the current character.
- **Click reactions:** clicking the character plays a random reaction, never the same twice in a row: spin, hearts, wave, or star jump. Three clicks within 1.7 s still make it dizzy. The Settings preview reacts to clicks too.
- **Long permission requests:** the card counts wrapped lines (about 60 characters per line) when sizing the island, the command box grows up to 16 lines, and anything longer scrolls. Nothing is truncated any more.
- **Gaze fix:** the thinking pose glanced up-right and followed the pointer at 35%, so the eyes sat right of the pointer. Now a moving pointer always wins; the pose only comes back after the pointer rests for 2 s.
- **Own characters:** Pip (bean with a wobbling sprout), Neko (cat: ears that twitch, whiskers, swishing tail), Bun (bunny: floppy ears on the hat spring), Boo (ghost: scalloped rippling hem, floats), Beep (robot: dark visor, cyan eyes, antenna bulb in the state color) and Momo (steamed dumpling: pleats up to a pinched knot, rosy cheeks, steam while it works; a saved "classic" choice turns into Momo). Default Pip. Each design sets the body outline, eye size, sparkle glints, resting blush and a mood mouth ("o" when it needs you, a grin when done). Head parts sit on the shared 3D head, turn with it, roll rigidly, and hide under hats that cover the head. Settings > Appearance shows a live preview (eyes follow the mouse on hover) and a grid of live character cards; quick settings has a Character row.
- **Uninstall:** Claude and Codex hooks, and the relay, each have a Remove button with the same preview, backup and confirm flow.
- **Session row click:** a row whose session has a waiting request opens that request's card (shown as "2 of 3" when others wait too), even after Back. A row with nothing waiting switches to the IDE; the small arrow on each row always switches. When the IDE is already in front, only "Raise the exact project window" (Accessibility) can bring a different project window forward.
- **Gaze from the screen center:** in the small island the character measures the pointer from the screen's center (`IslandLayout.lookOrigin`), so a pointer in the middle of the screen gets a straight look and the eyes follow it in any direction. In the open island it measures from itself, so hovering it gets a straight look.
- **Calendar (Settings > Extras, off by default):** `CalendarWatcher` reads EventKit every 60 s and on `EKEventStoreChanged`: the next meeting (the earliest timed event that starts within the hour or started under 10 minutes ago) and every event of the week shown in the calendar tab (declined and canceled events never count). The open island shows a next-meeting row (a click opens the tab) with a Join button when a Zoom, Meet, Teams or Webex link is found in the event's URL, location or notes. The calendar tab (header icon next to the house) has a week strip on the user's first weekday with up to three calendar-color dots per day, a day title with a Today button, all-day chips, timed rows (start time, calendar color bar, title, length and calendar name, countdown on the next one, Join), a red now line placed by `DayAgenda`, a progress fill on the meeting in progress and dimmed past events. Switching days pushes the agenda sideways and the selected-day highlight glides (`matchedGeometryEffect`); the direction is set one runloop before the day so the leaving view slides the right way. The island height follows the day's rows. It is display only: no pop-out, sound or countdown in the small island (the user asked for just the UI). Needs `NSCalendarsFullAccessUsageDescription` in Info.plist and the Calendars permission.
- **Now playing (Settings > Extras, on by default):** MediaRemote (the Control Center Now Playing source) answers only Apple's own processes since macOS 15.4: called from m_notch it returns 0 fields, called from inside `/usr/bin/perl` it returns everything (checked on this Mac, including YouTube in Chrome). `Adapters/NowPlayingAdapter.m` is compiled by `scripts/dev.sh` into `Contents/Resources/NowPlayingAdapter.dylib`; `NowPlayingWatcher` runs `/usr/bin/perl -e <loader> <dylib>`, which loads it with DynaLoader and calls `m_notch_now_playing_stream`. The helper registers for MediaRemote notifications and writes one JSON line per change (title, artist, album, duration, elapsed with its timestamp, rate, playing, app bundle id, and the artwork as base64 only when it changes), 150 ms after a burst. It reads `toggle`, `next`, `previous` and `seek <seconds>` (`MRMediaRemoteSetElapsedTime`) on stdin and exits when stdin closes, so it never outlives the app. If it stops, the watcher restarts it after 5 s, doubling up to 5 min. The island shows a row above the sessions while a track is loaded (dimmed when paused) and a music tab: artwork (smaller when paused) over a glow of its average color, title with a dancing equalizer, artist and album, the app's icon and name, a progress bar computed from elapsed plus time since at the reported rate (gliding every 0.5 s), and previous, play/pause (morphing symbol, flips at once) and next. Dragging or clicking the progress bar seeks: the bar jumps at once (`NowPlayingTrack.seeked`) and the helper moves the player (checked with YouTube in Chrome). This is a private API: a future macOS could close the perl route.
- **Terminal hook (Settings > Extras):** a zsh script in `~/Library/Application Support/m_notch/terminal-hook.zsh` (holds the port and token, mode 600) records the start of each command (`preexec`) and, at the next prompt (`precmd`, placed first so `$?` is the command's), posts `command`, `exit`, `seconds` and `cwd` as a form body to `/m_notch/shell` when the command ran 30 s or more. It skips Ctrl-C and Ctrl-Z exits (130, 146, 148), editors, pagers, ssh, tmux, agents and bare REPLs. `~/.zshrc` only gets a marked 3-line block that sources the script if it exists, written with the usual preview, backup and confirm flow; Remove takes the block out and deletes the script. The island shows a check or a cross with the duration on its small right side for a minute, a command row in the list for 10 minutes, and the character celebrates (success) or shows its error face (failure).
- **Layer sizing fix:** every island layer (list, request, diff, settings, calendar, music) is framed `minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity`. With only a maximum, the hidden quick settings layer (about 220 pt) grew the stack and a short permission card centered itself below the visible area, hiding its buttons. Found while making the screenshots.
- **Updates:** `Updater` asks `api.github.com/repos/thanmay-strativ/m-notch-app/releases/latest` 15 s after launch and once a day (Settings > About, on by default), and on "Check for Updates..." in the menu. A newer tag (numeric compare, `v` ignored) is offered in an alert. Install downloads `m_notch.zip` and `m_notch.zip.sha256`, compares SHA-256, unzips with `ditto` next to the running app, checks the bundle id and version, swaps it in with `replaceItemAt`, and a small `/bin/sh` loop reopens the app once this process has quit. It refuses a translocated copy (opened from Downloads) and a folder the user cannot write to. `scripts/release.sh <version>` sets `VERSION`, tags, builds, zips and uploads with `gh`. The app is ad-hoc signed, so each update is a new signature: macOS may ask for Accessibility and Calendars again.

## 14. Publishing (2026-10-09)

- **Repo:** https://github.com/thanmay-strativ/m-notch-app, public. One commit on `main` on top of GitHub's "Initial commit" (fast-forward, no force push, no extra branch). `.gitignore` is GitHub's Swift template plus `build/`, `dist/`, `.swiftpm/`, `.idea/`, `.vscode/`, `.DS_Store`.
- **Before publishing:** the copied Mochi ("Classic") became Momo, an own design; the "private use only" notes left the About page, `BotEngine.swift` and section 1; the work project name in tests and docs became `web-app`; a scan of the staged files found no tokens, keys or personal paths.
- **Media** (`docs/media/`): `hero.gif`, `calendar.gif`, `music.gif`, `characters.gif` and 7 screenshots, all demo data (sessions web-app, api-server, docs-site; track "Midnight Drive" by Neon Coast; a demo week). Made by a throwaway generator in the session scratchpad that compiles all of MNotchCore and renders the real views offscreen (`cacheDisplay` in a borderless window at -20000, frames paced on the wall clock, GIFs written with ImageIO at 720 px wide). `cacheDisplay` does not render blur.
- **README:** simple words, hero GIF first, then install (including Open Anyway or `xattr -dr com.apple.quarantine`), first use with an example, features with media, shortcuts, updates, privacy, collapsible build-from-source and manual checks, and credits: coucou (ported, MIT), mediaremote-adapter (the perl technique, no code copied), boring.notch (inspiration, no code copied).
- **Releases:** `VERSION` holds the version; `scripts/dev.sh build` puts it in Info.plist. `scripts/release.sh <version> [notes]` needs a clean tree, commits `VERSION` if it changed, builds, zips with `ditto --keepParent`, writes the `shasum -a 256` file, tags `v<version>`, pushes and runs `gh release create`. v0.1.0: `m_notch.zip` (1 MB, arm64) and `m_notch.zip.sha256`.
- **Checked:** 95 unit tests pass. The release download matches its checksum, has bundle id `local.mnotch` 0.1.0 and a valid signature. A test build that reports 0.0.9 found v0.1.0 on GitHub and updated a throwaway copy to 0.1.0 (no quarantine flag); one that reports 0.1.0 said up to date. The relaunch loop was checked alone, including a path with a space.
- **Installed:** the dev copy in `build/` was deleted and v0.1.0 from the release installed to `/Applications`. The hook server is back on 127.0.0.1:47823 with the same token, so installed hooks keep working.

## 15. Iteration 3: own look, settings, simple install (2026-10-09, v0.2.0)

- **Why the characters changed:** coucou's `LICENSE-ASSETS.md` reserves the names Coucou and Mochi and "the Mochi character: its design, look, expressions and animations as a character", and asks forks to ship "your own name, icon, character and sounds". Mochi is a white squircle with dark eyes, pink blush and a small mouth. Rendered side by side, Pip, Neko, Bun and Momo were that face with parts added. MIT still covers the engine code; the look is now ours.
- **New family look:** eyes get a dark rim, a colored iris that is lighter at the bottom (`CharacterDesign.iris`: Pip green, Neko amber, Bun berry, Boo violet, Momo soy brown), a round pupil and one glint (`drawDesignEye`); Beep keeps its glowing screen eyes, and the small island keeps plain eyes. No resting blush except a hint on Bun, and the state tint no longer adds blush. Each design has its own proportions (`bodyScale`, applied to the body and both hand passes) and outline: Pip an upright bean (ellipse, wider bottom), Bun a round ball, Neko a rounder loaf, Beep a squarer screen, Momo a steamed bun (`dumplingPath`: flat bottom, dome that rises to a gathered peak where the pleats meet; no pink tongue).
- **Pearl:** the color "Mochi" is now "Pearl"; a saved "mochi" reads as Pearl.
- **Settings folders:** Settings > Agents has a folder field (with Choose and Reset) for Claude and for Codex. Empty uses `HookTarget.defaultFolder`: `$CLAUDE_CONFIG_DIR` or `~/.claude`, `$CODEX_HOME` or `~/.codex` (a Finder-launched app rarely sees those variables, hence the field). Install, removal, status, the relay and the folder watchers all use `Preferences.configFolder(for:)`; the row says which file it uses or that the folder is missing. `HookInstaller` and `StatusLineRelay` take `folder:` instead of `home:`.
- **Settings window redesign:** a hand-drawn solid sidebar (accent-filled selection, hover tint, version at the bottom) and a page header with icon and subtitle, then grouped forms like System Settings: switches with a second line, menus on the right, status pills (OK, not installed, server, calendar access), footnotes, links in a "Thanks to" section. Appearance is compact: a small live hero, 60 pt tiles for characters and outfits in a wrapping grid, a row of color swatches. Accessibility and hook status refresh when the app becomes active. The sidebar is solid on purpose: offscreen captures cannot draw macOS materials, so the README screenshots match the real window.
- **Simple install:** `install.sh` at the repo root (`curl -fsSL .../install.sh | sh`) checks Apple silicon and macOS 15, downloads the latest `m_notch.zip` and `.sha256`, checks the hash, quits a running copy, puts the app in `/Applications` and opens it. curl downloads carry no quarantine flag, so there is no Gatekeeper prompt. On first launch, if Claude's hooks are missing, an alert offers **Connect Claude Code…** (the usual preview and backup), **Settings…** (opens Agents) or Later; it is shown once (`welcomeShown`).
- **License notice in the app:** `scripts/dev.sh` copies `LICENSES/coucou-MIT.txt` into `Contents/Resources`, as MIT asks for every copy.
- **Media:** all GIFs and screenshots re-rendered with the new look, plus `settings-appearance.png` and `settings-agents.png`.

### Open items

- Launch at login was registered for the deleted `build/` copy: turn it off and on once in Settings > General.
- Accessibility and Calendars may need allowing again after every update (ad-hoc signature).
- m_notch has no license of its own yet, so others may read the code but not reuse it.
- The manual checks in the README.
