# ✦ Notes

A bare-bones, lightweight, ultra-functional note-taking app for Windows 11. Always-on-top overlay, autosave, markdown files, zero dependencies. Completely made with Claude Opus 4.6.

![Windows 11](https://img.shields.io/badge/Windows%2011-0078D4?style=flat&logo=windows11&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=flat&logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=flat)

---

## Why?

Because sometimes you just need a notepad that **stays on top of everything**, saves automatically, and doesn't get in the way. No Electron. No Node. No install. Just double-click and write.

## Quick Start

```
git clone https://github.com/egosashimi/notes-claude.git
cd notes-claude
run.bat
```

Or just double-click **`run.bat`**. That's it.

> **Requirements:** Windows 10/11 with PowerShell 5.1+ (pre-installed on all modern Windows machines). Nothing else to install.

---

## Features

| Feature | Description |
|---|---|
| **Always-on-top** | Persistent overlay — stays above your browser, IDE, everything. Toggle with the pin `•` button. |
| **Zen Mode** | `Ctrl+M` strips the UI to just a text editor + thin drag strip. Pure focus. |
| **Autosave** | Saves 1.5 seconds after you stop typing. Never lose a thought. |
| **Tabs** | Multiple notes open at once. `Ctrl+Tab` to cycle. |
| **Folders** | Organize notes in the sidebar. Create, rename, delete via right-click. |
| **Sort** | Sort by name (A→Z, Z→A), date modified, or date created. |
| **Markdown** | All files saved as `.md` in the `/notes` subfolder. Edit them anywhere. |
| **Movable** | Drag the title bar to position anywhere — essential for multi-monitor setups. |
| **Resizable** | Drag any edge or corner. Works in both normal and zen mode. |
| **Smart file creation** | New notes are virtual until you type. Empty untitled files are auto-cleaned. |

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl+N` | New note |
| `Ctrl+W` | Close tab |
| `Ctrl+S` | Force save |
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Ctrl+M` | Toggle Zen mode |
| `Ctrl+B` | Toggle tab bar |
| `Escape` | Exit Zen mode |

---

## Zen Mode

Press `Ctrl+M` to enter Zen mode. Everything disappears except your text and a thin purple drag strip at the top.

```
┌─────────────────────────────────┐  ← 6px accent strip (drag to move)
│                                 │
│  Your notes here...             │
│                                 │
│                                 │
└─────────────────────────────────┘
```

- **Drag** the strip to reposition the window
- **Resize** from the sides, bottom, and corners
- **Exit** with `Ctrl+M` or `Escape`
- All shortcuts still work — `Ctrl+Tab`, `Ctrl+N`, `Ctrl+S`, etc.

---

## File Structure

```
notes-claude/
├── run.bat              # Double-click to launch
├── notes-app.ps1        # Application source (single file, ~600 lines)
├── README.md
└── notes/               # Auto-created on first run
    ├── Welcome.md
    ├── My Project/
    │   ├── ideas.md
    │   └── todo.md
    └── journal.md
```

All notes are plain `.md` files. Edit them with any text editor, sync them with Git, back them up however you want.

---

## UI Overview

**Normal Mode** — full interface with sidebar, tabs, and status bar:

```
┌──────────────────────────────────────────┐
│ ✦ Notes              □ ≡ ▽ • — ✕        │  ← Title bar
├────────┬─────────────────────────────────┤
│        │  Tab 1  │  Tab 2  │  +          │  ← Tab bar (Ctrl+B to hide)
│EXPLORER├─────────────────────────────────┤
│ ▸ Work │                                 │
│   todo │  # My Notes                    │
│   ideas│                                 │
│ ○ draft│  Write here...                 │
│        │                                 │
├────────┴─────────────────────────────────┤
│ Saved                    Ln 4 | 12 words │  ← Status bar
└──────────────────────────────────────────┘
     ↑
  Sidebar (≡ to hide)
```

**Title bar buttons:**
| Button | Function |
|---|---|
| `□` | Zen mode |
| `≡` | Toggle sidebar |
| `▽` | Toggle tab bar |
| `•` | Toggle always-on-top (purple = on) |
| `—` | Minimize |
| `✕` | Close |

---

## How It Works

The app is a single PowerShell script that creates a native WPF (Windows Presentation Foundation) window. No compilation step, no runtime to install, no package manager.

- **WPF** handles the UI rendering natively through Windows
- **WindowChrome** provides the custom dark title bar while keeping native resize/drag behavior
- **DispatcherTimer** powers the autosave debounce
- **Always-on-top** uses the `Topmost` window property
- Files are read/written with `System.IO.File` for reliability

---

## Customization

Edit the top of `notes-app.ps1` to change:

```powershell
$script:NotesDir   = Join-Path $PSScriptRoot "notes"  # Where files are saved
$script:AutoSaveMs = 1500                              # Autosave delay (ms)
```

The color scheme is defined in the XAML section — search for hex color values like `#151528` to customize the dark theme.

---

## License

MIT — do whatever you want with it.
