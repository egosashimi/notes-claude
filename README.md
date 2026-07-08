# Notes

A lightweight native notes app for Ubuntu. It behaves like a small desktop
sticky note: resizable, pinnable above other windows, and backed by plain
Markdown files in `notes/`.

The old Windows PowerShell/WPF files are still here as legacy source. Ubuntu
uses `notes.py` and `run.sh`.

## Run

```bash
./run.sh
```

The app opens as a normal Ubuntu desktop window. Use the `Pinned` button in the
top bar to keep it above other apps. Drag the window edges or corners to resize
it.

Useful options:

```bash
./run.sh --unpinned
./run.sh --notes-dir ~/Notes
```

## Features

- Native resizable desktop window.
- `Pinned` button for always-on-top overlay behavior.
- Sidebar navigation for the notes folder, including nested folders.
- Top-bar tabs for open notes.
- Autosave after you pause typing.
- Minimal zen mode for a cleaner editor surface.
- New note, new folder, rename, delete, and sort controls.
- Plain Markdown files that can be edited by any text editor.

## Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl+N` | New note |
| `Ctrl+S` | Save now |
| `Ctrl+W` | Close active tab |
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Ctrl+M` | Toggle zen mode |
| `Ctrl+B` | Toggle sidebar |
| `Escape` | Exit zen mode |

## Files

```text
notes-claude/
├── run.sh          # Ubuntu launcher
├── notes.py        # Native Ubuntu app
├── notes/          # Markdown notes
├── notes-app.ps1   # Legacy Windows app
└── run.bat         # Legacy Windows launcher
```
