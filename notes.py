#!/usr/bin/env python3
"""
Native Notes for Ubuntu.

Plain Markdown notes in ./notes, edited through a small Tk desktop app.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from tkinter import font, messagebox, simpledialog, ttk
import tkinter as tk


APP_DIR = Path(__file__).resolve().parent
DEFAULT_NOTES_DIR = APP_DIR / "notes"
AUTOSAVE_MS = 1500


WELCOME_TEXT = """# Welcome to Notes

This is a native Ubuntu notes app.

- Pin the window to keep it above other apps.
- Resize it like any normal desktop window.
- Use the sidebar for your notes folder.
- Use tabs for notes you are actively editing.
- Press Ctrl+M for zen mode.
"""


THEME = {
    "paper": "#fff6c7",
    "paper_alt": "#fff0a3",
    "ink": "#2b2616",
    "muted": "#706741",
    "faint": "#9b905f",
    "line": "#dfcc76",
    "line_soft": "#eadb96",
    "button": "#f5de83",
    "button_hover": "#edcf65",
    "active": "#2f5942",
    "active_text": "#f8f4df",
    "danger": "#9d392f",
    "sidebar": "#fff2b3",
    "sidebar_select": "#ecd073",
}


SORT_MODES = {
    "Name A-Z": "name",
    "Name Z-A": "name_desc",
    "Modified": "modified",
    "Created": "created",
}


@dataclass
class NoteTab:
    path: Path
    title: str
    content: str
    dirty: bool = False


class NotesApp:
    def __init__(self, root: tk.Tk, notes_dir: Path, pinned: bool = True) -> None:
        self.root = root
        self.notes_dir = notes_dir.resolve()
        self.pinned = pinned
        self.sidebar_visible = True
        self.zen_mode = False
        self._sidebar_was_visible_before_zen = True
        self.sort_label = tk.StringVar(value="Name A-Z")
        self.status_text = tk.StringVar(value="Ready")
        self.info_text = tk.StringVar(value="")
        self.tabs: list[NoteTab] = []
        self.active_index = -1
        self.save_after_id: str | None = None
        self.info_after_id: str | None = None
        self._loading_text = False
        self._sidebar_width = 240
        self._selected_item: tuple[str, Path] | None = None

        self.notes_dir.mkdir(parents=True, exist_ok=True)
        self._ensure_initial_note()
        self._configure_root()
        self._configure_styles()
        self._build_ui()
        self._bind_shortcuts()
        self.refresh_sidebar()
        self.open_latest_note()

    def _configure_root(self) -> None:
        self.root.title("Notes")
        self.root.geometry("900x620")
        self.root.minsize(360, 220)
        self.root.configure(background=THEME["paper"])
        self.root.resizable(True, True)
        self.apply_pin_state()
        self.root.after(250, self.apply_pin_state)
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

    def _configure_styles(self) -> None:
        self.style = ttk.Style(self.root)
        try:
            self.style.theme_use("clam")
        except tk.TclError:
            pass

        self.style.configure(
            "Notes.Treeview",
            background=THEME["sidebar"],
            fieldbackground=THEME["sidebar"],
            foreground=THEME["ink"],
            borderwidth=0,
            rowheight=26,
            font=("TkDefaultFont", 10),
        )
        self.style.map(
            "Notes.Treeview",
            background=[("selected", THEME["sidebar_select"])],
            foreground=[("selected", THEME["ink"])],
        )
        self.style.configure(
            "Notes.Treeview.Heading",
            background=THEME["sidebar"],
            foreground=THEME["muted"],
        )
        self.style.configure(
            "Notes.TCombobox",
            fieldbackground=THEME["paper_alt"],
            background=THEME["paper_alt"],
            foreground=THEME["ink"],
            arrowcolor=THEME["ink"],
        )

    def _build_ui(self) -> None:
        self.root.grid_rowconfigure(1, weight=1)
        self.root.grid_columnconfigure(0, weight=1)

        self.topbar = tk.Frame(self.root, bg=THEME["paper_alt"], height=42)
        self.topbar.grid(row=0, column=0, sticky="ew")
        self.topbar.grid_columnconfigure(1, weight=1)

        self.left_tools = tk.Frame(self.topbar, bg=THEME["paper_alt"])
        self.left_tools.grid(row=0, column=0, sticky="w", padx=(8, 4), pady=6)

        self.btn_sidebar = self._tool_button(self.left_tools, "Sidebar", self.toggle_sidebar)
        self.btn_new = self._tool_button(self.left_tools, "New", self.new_note)
        self.btn_pin = self._tool_button(self.left_tools, "", self.toggle_pin)
        self.btn_zen = self._tool_button(self.left_tools, "Zen", self.toggle_zen)
        self.btn_sidebar.pack(side="left", padx=(0, 4))
        self.btn_new.pack(side="left", padx=(0, 4))
        self.btn_pin.pack(side="left", padx=(0, 4))
        self.btn_zen.pack(side="left")

        self.tab_bar = tk.Frame(self.topbar, bg=THEME["paper_alt"])
        self.tab_bar.grid(row=0, column=1, sticky="ew", padx=4, pady=6)

        self.right_tools = tk.Frame(self.topbar, bg=THEME["paper_alt"])
        self.right_tools.grid(row=0, column=2, sticky="e", padx=(4, 8), pady=6)
        self.btn_save = self._tool_button(self.right_tools, "Save", self.save_active)
        self.btn_close_tab = self._tool_button(self.right_tools, "Close", self.close_active_tab)
        self.btn_save.pack(side="left", padx=(0, 4))
        self.btn_close_tab.pack(side="left")

        self.main = tk.PanedWindow(
            self.root,
            orient="horizontal",
            sashwidth=5,
            sashrelief="flat",
            bg=THEME["line"],
            bd=0,
            showhandle=False,
        )
        self.main.grid(row=1, column=0, sticky="nsew")

        self.sidebar = tk.Frame(self.main, bg=THEME["sidebar"], width=self._sidebar_width)
        self.sidebar.grid_propagate(False)
        self._build_sidebar()

        self.editor_frame = tk.Frame(self.main, bg=THEME["paper"])
        self._build_editor()

        self.main.add(self.sidebar, minsize=150, width=self._sidebar_width)
        self.main.add(self.editor_frame, minsize=220)

        self.statusbar = tk.Frame(self.root, bg=THEME["paper_alt"], height=24)
        self.statusbar.grid(row=2, column=0, sticky="ew")
        self.statusbar.grid_columnconfigure(1, weight=1)
        tk.Label(
            self.statusbar,
            textvariable=self.status_text,
            bg=THEME["paper_alt"],
            fg=THEME["muted"],
            anchor="w",
            padx=8,
            font=("TkDefaultFont", 9),
        ).grid(row=0, column=0, sticky="w")
        tk.Label(
            self.statusbar,
            textvariable=self.info_text,
            bg=THEME["paper_alt"],
            fg=THEME["muted"],
            anchor="e",
            padx=8,
            font=("TkDefaultFont", 9),
        ).grid(row=0, column=1, sticky="e")

        self.context_menu = tk.Menu(self.root, tearoff=False)
        self.context_menu.add_command(label="Open", command=self.open_selected_from_tree)
        self.context_menu.add_command(label="New note here", command=self.new_note_in_selected_folder)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="Rename", command=self.rename_selected)
        self.context_menu.add_command(label="Delete", command=self.delete_selected)

        self._update_pin_button()

    def _build_sidebar(self) -> None:
        header = tk.Frame(self.sidebar, bg=THEME["sidebar"])
        header.pack(fill="x", padx=8, pady=(8, 6))

        tk.Label(
            header,
            text="NOTES",
            bg=THEME["sidebar"],
            fg=THEME["muted"],
            font=("TkDefaultFont", 9, "bold"),
            anchor="w",
        ).pack(side="left")

        tk.Button(
            header,
            text="Folder",
            command=self.new_folder,
            bg=THEME["button"],
            activebackground=THEME["button_hover"],
            fg=THEME["ink"],
            relief="flat",
            padx=8,
            pady=2,
            cursor="hand2",
        ).pack(side="right")

        sort_row = tk.Frame(self.sidebar, bg=THEME["sidebar"])
        sort_row.pack(fill="x", padx=8, pady=(0, 8))
        self.sort_combo = ttk.Combobox(
            sort_row,
            textvariable=self.sort_label,
            values=list(SORT_MODES.keys()),
            state="readonly",
            style="Notes.TCombobox",
            width=12,
        )
        self.sort_combo.pack(fill="x")
        self.sort_combo.bind("<<ComboboxSelected>>", lambda _event: self.refresh_sidebar())

        tree_frame = tk.Frame(self.sidebar, bg=THEME["sidebar"])
        tree_frame.pack(fill="both", expand=True)
        self.tree = ttk.Treeview(
            tree_frame,
            show="tree",
            selectmode="browse",
            style="Notes.Treeview",
        )
        scrollbar = ttk.Scrollbar(tree_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.pack(side="left", fill="both", expand=True, padx=(6, 0), pady=(0, 8))
        scrollbar.pack(side="right", fill="y", pady=(0, 8))

        self.tree.bind("<<TreeviewSelect>>", self.on_tree_select)
        self.tree.bind("<Double-1>", self.on_tree_open)
        self.tree.bind("<Return>", self.on_tree_open)
        self.tree.bind("<Button-3>", self.on_tree_menu)

    def _build_editor(self) -> None:
        self.editor_frame.grid_rowconfigure(0, weight=1)
        self.editor_frame.grid_columnconfigure(0, weight=1)
        self.text = tk.Text(
            self.editor_frame,
            wrap="word",
            undo=True,
            maxundo=80,
            bg=THEME["paper"],
            fg=THEME["ink"],
            insertbackground=THEME["ink"],
            selectbackground="#d8c161",
            selectforeground=THEME["ink"],
            relief="flat",
            bd=0,
            padx=24,
            pady=22,
            font=self._editor_font(14),
            tabs=("2c",),
        )
        self.text.grid(row=0, column=0, sticky="nsew")
        yscroll = ttk.Scrollbar(self.editor_frame, orient="vertical", command=self.text.yview)
        self.text.configure(yscrollcommand=yscroll.set)
        yscroll.grid(row=0, column=1, sticky="ns")
        self.text.bind("<<Modified>>", self.on_text_modified)

    def _editor_font(self, size: int) -> font.Font:
        preferred = ["Cascadia Code", "JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono"]
        available = set(font.families(self.root))
        family = next((item for item in preferred if item in available), "TkFixedFont")
        return font.Font(family=family, size=size)

    def _tool_button(self, parent: tk.Widget, text: str, command) -> tk.Button:
        return tk.Button(
            parent,
            text=text,
            command=command,
            bg=THEME["button"],
            activebackground=THEME["button_hover"],
            fg=THEME["ink"],
            activeforeground=THEME["ink"],
            relief="flat",
            padx=10,
            pady=4,
            cursor="hand2",
            highlightthickness=0,
        )

    def _bind_shortcuts(self) -> None:
        bindings = {
            "<Control-n>": lambda _e: self.new_note(),
            "<Control-s>": lambda _e: self.save_active(),
            "<Control-w>": lambda _e: self.close_active_tab(),
            "<Control-m>": lambda _e: self.toggle_zen(),
            "<Control-b>": lambda _e: self.toggle_sidebar(),
            "<Escape>": lambda _e: self.exit_zen_if_needed(),
            "<Control-Tab>": lambda _e: self.next_tab(),
            "<Control-ISO_Left_Tab>": lambda _e: self.previous_tab(),
            "<Control-Shift-Tab>": lambda _e: self.previous_tab(),
        }
        for sequence, action in bindings.items():
            self.root.bind_all(sequence, self._break_after(action))

    def _break_after(self, action):
        def wrapped(event):
            action(event)
            return "break"

        return wrapped

    def _ensure_initial_note(self) -> None:
        if not any(self.notes_dir.rglob("*.md")):
            (self.notes_dir / "Welcome.md").write_text(WELCOME_TEXT, encoding="utf-8")

    def title_for_path(self, path: Path) -> str:
        return path.stem

    def rel_path(self, path: Path) -> str:
        return path.resolve().relative_to(self.notes_dir).as_posix()

    def sorted_entries(self, entries: list[Path]) -> list[Path]:
        mode = SORT_MODES.get(self.sort_label.get(), "name")
        if mode == "name_desc":
            return sorted(entries, key=lambda item: item.name.lower(), reverse=True)
        if mode == "modified":
            return sorted(entries, key=lambda item: item.stat().st_mtime, reverse=True)
        if mode == "created":
            return sorted(entries, key=lambda item: item.stat().st_ctime, reverse=True)
        return sorted(entries, key=lambda item: item.name.lower())

    def unique_note_path(self, folder: Path) -> Path:
        folder.mkdir(parents=True, exist_ok=True)
        candidate = folder / "Untitled.md"
        index = 1
        while candidate.exists():
            candidate = folder / f"Untitled ({index}).md"
            index += 1
        return candidate

    def read_note(self, path: Path) -> str:
        return path.read_text(encoding="utf-8-sig", errors="replace")

    def write_note(self, path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def latest_note(self) -> Path | None:
        files = [path for path in self.notes_dir.rglob("*.md") if path.is_file()]
        if not files:
            return None
        return max(files, key=lambda path: path.stat().st_mtime)

    def refresh_sidebar(self) -> None:
        opened = {
            self.tree.item(item_id, "values")[0]
            for item_id in self.tree.get_children("")
            if self.tree.item(item_id, "values")
        } if hasattr(self, "tree") else set()
        self.tree.delete(*self.tree.get_children(""))
        root_id = self._insert_folder("", self.notes_dir, "notes", open_state=True)
        self._populate_folder(root_id, self.notes_dir)
        self.tree.item(root_id, open=True)
        self.highlight_active_tree_item()

    def _insert_folder(self, parent: str, path: Path, text: str, open_state: bool = True) -> str:
        iid = f"dir:{self.rel_path(path) if path != self.notes_dir else ''}"
        return self.tree.insert(parent, "end", iid=iid, text=text, values=("folder", str(path)), open=open_state)

    def _insert_file(self, parent: str, path: Path) -> str:
        iid = f"file:{self.rel_path(path)}"
        return self.tree.insert(parent, "end", iid=iid, text=path.stem, values=("file", str(path)))

    def _populate_folder(self, parent_id: str, folder: Path) -> None:
        dirs: list[Path] = []
        files: list[Path] = []
        for child in folder.iterdir():
            if child.name.startswith(".") or child.is_symlink():
                continue
            if child.is_dir():
                dirs.append(child)
            elif child.is_file() and child.suffix.lower() == ".md":
                files.append(child)

        for directory in self.sorted_entries(dirs):
            item_id = self._insert_folder(parent_id, directory, directory.name)
            self._populate_folder(item_id, directory)
        for file_path in self.sorted_entries(files):
            self._insert_file(parent_id, file_path)

    def highlight_active_tree_item(self) -> None:
        if self.active_index < 0:
            return
        active_path = self.tabs[self.active_index].path
        item_id = f"file:{self.rel_path(active_path)}"
        if self.tree.exists(item_id):
            self.tree.selection_set(item_id)
            self.tree.see(item_id)

    def on_tree_select(self, _event=None) -> None:
        selection = self.tree.selection()
        if not selection:
            self._selected_item = None
            return
        values = self.tree.item(selection[0], "values")
        if len(values) >= 2:
            self._selected_item = (values[0], Path(values[1]))

    def on_tree_open(self, _event=None) -> None:
        self.open_selected_from_tree()

    def on_tree_menu(self, event) -> None:
        item_id = self.tree.identify_row(event.y)
        if item_id:
            self.tree.selection_set(item_id)
            self.on_tree_select()
        selected_type = self._selected_item[0] if self._selected_item else ""
        self.context_menu.entryconfig("Open", state="normal" if selected_type == "file" else "disabled")
        self.context_menu.entryconfig("New note here", state="normal" if selected_type == "folder" else "disabled")
        can_edit = bool(self._selected_item and self._selected_item[1] != self.notes_dir)
        self.context_menu.entryconfig("Rename", state="normal" if can_edit else "disabled")
        self.context_menu.entryconfig("Delete", state="normal" if can_edit else "disabled")
        self.context_menu.tk_popup(event.x_root, event.y_root)

    def selected_folder(self) -> Path:
        if self._selected_item:
            item_type, path = self._selected_item
            if item_type == "folder":
                return path
            return path.parent
        if self.active_index >= 0:
            return self.tabs[self.active_index].path.parent
        return self.notes_dir

    def open_selected_from_tree(self) -> None:
        if not self._selected_item:
            return
        item_type, path = self._selected_item
        if item_type == "file":
            self.open_note(path)

    def open_latest_note(self) -> None:
        latest = self.latest_note()
        if latest:
            self.open_note(latest)
        else:
            self.new_note()

    def open_note(self, path: Path) -> None:
        path = path.resolve()
        for index, tab in enumerate(self.tabs):
            if tab.path == path:
                self.switch_tab(index)
                return

        try:
            content = self.read_note(path)
        except OSError as exc:
            messagebox.showerror("Notes", f"Could not open note:\n{exc}")
            return

        self.tabs.append(NoteTab(path=path, title=self.title_for_path(path), content=content))
        self.switch_tab(len(self.tabs) - 1)

    def switch_tab(self, index: int) -> None:
        if index < 0 or index >= len(self.tabs):
            return
        self.capture_active_text()
        self.save_dirty_tab(self.active_index)
        self.active_index = index
        self._loading_text = True
        self.text.delete("1.0", "end")
        self.text.insert("1.0", self.tabs[index].content)
        self.text.edit_modified(False)
        self._loading_text = False
        self.render_tabs()
        self.highlight_active_tree_item()
        self.update_info()
        self.set_status(f"Editing {self.tabs[index].title}")
        self.text.focus_set()

    def capture_active_text(self) -> None:
        if 0 <= self.active_index < len(self.tabs):
            self.tabs[self.active_index].content = self.text.get("1.0", "end-1c")

    def render_tabs(self) -> None:
        for child in self.tab_bar.winfo_children():
            child.destroy()

        for index, tab in enumerate(self.tabs):
            active = index == self.active_index
            label = f"* {tab.title}" if tab.dirty else tab.title
            frame = tk.Frame(
                self.tab_bar,
                bg=THEME["active"] if active else THEME["button"],
                bd=0,
                highlightthickness=1,
                highlightbackground=THEME["active"] if active else THEME["line"],
            )
            frame.pack(side="left", padx=(0, 4), fill="y")
            tab_button = tk.Button(
                frame,
                text=label,
                command=lambda idx=index: self.switch_tab(idx),
                bg=THEME["active"] if active else THEME["button"],
                activebackground=THEME["active"] if active else THEME["button_hover"],
                fg=THEME["active_text"] if active else THEME["ink"],
                activeforeground=THEME["active_text"] if active else THEME["ink"],
                relief="flat",
                padx=9,
                pady=4,
                cursor="hand2",
                width=min(max(len(label), 8), 22),
                anchor="w",
            )
            tab_button.pack(side="left")
            close_button = tk.Button(
                frame,
                text="x",
                command=lambda idx=index: self.close_tab(idx),
                bg=THEME["active"] if active else THEME["button"],
                activebackground=THEME["button_hover"],
                fg=THEME["active_text"] if active else THEME["muted"],
                relief="flat",
                padx=5,
                pady=4,
                cursor="hand2",
            )
            close_button.pack(side="left")

    def new_note(self) -> None:
        self.new_note_in_folder(self.selected_folder())

    def new_note_in_selected_folder(self) -> None:
        self.new_note_in_folder(self.selected_folder())

    def new_note_in_folder(self, folder: Path) -> None:
        try:
            path = self.unique_note_path(folder)
            self.write_note(path, "")
        except OSError as exc:
            messagebox.showerror("Notes", f"Could not create note:\n{exc}")
            return
        self.refresh_sidebar()
        self.open_note(path)

    def new_folder(self) -> None:
        parent = self.selected_folder()
        name = simpledialog.askstring("New Folder", "Folder name:", parent=self.root)
        if not name:
            return
        name = name.strip()
        if not self.valid_name(name):
            messagebox.showerror("Notes", "Folder names cannot contain slashes.")
            return
        folder = parent / name
        if folder.exists():
            messagebox.showerror("Notes", "That folder already exists.")
            return
        try:
            folder.mkdir()
        except OSError as exc:
            messagebox.showerror("Notes", f"Could not create folder:\n{exc}")
            return
        self.refresh_sidebar()

    def rename_selected(self) -> None:
        if not self._selected_item:
            return
        item_type, path = self._selected_item
        if path == self.notes_dir:
            return
        current = path.stem if item_type == "file" else path.name
        name = simpledialog.askstring("Rename", "New name:", initialvalue=current, parent=self.root)
        if not name:
            return
        name = name.strip()
        if not self.valid_name(name):
            messagebox.showerror("Notes", "Names cannot contain slashes.")
            return
        if item_type == "file" and not name.lower().endswith(".md"):
            name = f"{name}.md"
        new_path = path.with_name(name)
        if new_path.exists():
            messagebox.showerror("Notes", "That name already exists.")
            return
        try:
            path.rename(new_path)
        except OSError as exc:
            messagebox.showerror("Notes", f"Could not rename:\n{exc}")
            return

        for tab in self.tabs:
            if item_type == "file" and tab.path == path:
                tab.path = new_path
                tab.title = self.title_for_path(new_path)
            elif item_type == "folder" and self.is_relative_to(tab.path, path):
                tab.path = new_path / tab.path.relative_to(path)
        self.refresh_sidebar()
        self.render_tabs()
        self.set_status("Renamed")

    def delete_selected(self) -> None:
        if not self._selected_item:
            return
        item_type, path = self._selected_item
        if path == self.notes_dir:
            return
        name = path.name
        if not messagebox.askyesno("Delete", f"Delete {name}?", parent=self.root):
            return
        try:
            if item_type == "file":
                path.unlink()
            else:
                import shutil

                shutil.rmtree(path)
        except OSError as exc:
            messagebox.showerror("Notes", f"Could not delete:\n{exc}")
            return

        self.tabs = [
            tab
            for tab in self.tabs
            if not (tab.path == path or (item_type == "folder" and self.is_relative_to(tab.path, path)))
        ]
        if self.active_index >= len(self.tabs):
            self.active_index = len(self.tabs) - 1
        self.refresh_sidebar()
        if self.tabs:
            self.switch_tab(max(self.active_index, 0))
        else:
            self.text.delete("1.0", "end")
            self.active_index = -1
            self.render_tabs()
            self.set_status("Ready")

    def valid_name(self, name: str) -> bool:
        return bool(name and "/" not in name and "\\" not in name and name not in {".", ".."})

    def is_relative_to(self, path: Path, parent: Path) -> bool:
        try:
            path.resolve().relative_to(parent.resolve())
            return True
        except ValueError:
            return False

    def on_text_modified(self, _event=None) -> None:
        if self._loading_text:
            self.text.edit_modified(False)
            return
        if not self.text.edit_modified():
            return
        self.text.edit_modified(False)
        if not (0 <= self.active_index < len(self.tabs)):
            return
        tab = self.tabs[self.active_index]
        tab.content = self.text.get("1.0", "end-1c")
        tab.dirty = True
        self.render_tabs()
        self.set_status("Unsaved")
        self.schedule_save()
        self.schedule_info()

    def schedule_save(self) -> None:
        if self.save_after_id:
            self.root.after_cancel(self.save_after_id)
        self.save_after_id = self.root.after(AUTOSAVE_MS, self.save_active)

    def schedule_info(self) -> None:
        if self.info_after_id:
            self.root.after_cancel(self.info_after_id)
        self.info_after_id = self.root.after(200, self.update_info)

    def save_active(self) -> None:
        if self.save_after_id:
            self.root.after_cancel(self.save_after_id)
            self.save_after_id = None
        self.capture_active_text()
        self.save_dirty_tab(self.active_index, force=True)

    def save_dirty_tab(self, index: int, force: bool = False) -> None:
        if index < 0 or index >= len(self.tabs):
            return
        tab = self.tabs[index]
        if not tab.dirty and not force:
            return
        try:
            self.write_note(tab.path, tab.content)
        except OSError as exc:
            self.set_status("Save failed")
            messagebox.showerror("Notes", f"Could not save note:\n{exc}")
            return
        tab.dirty = False
        self.render_tabs()
        self.refresh_sidebar()
        self.set_status(f"Saved {tab.title}")

    def close_active_tab(self) -> None:
        self.close_tab(self.active_index)

    def close_tab(self, index: int) -> None:
        if index < 0 or index >= len(self.tabs):
            return
        self.capture_active_text()
        self.save_dirty_tab(index, force=self.tabs[index].dirty)
        self.tabs.pop(index)
        if not self.tabs:
            self.active_index = -1
            self.text.delete("1.0", "end")
            self.render_tabs()
            self.set_status("Ready")
            self.update_info()
            return
        next_index = min(index, len(self.tabs) - 1)
        self.active_index = -1
        self.switch_tab(next_index)

    def next_tab(self) -> None:
        if len(self.tabs) < 2:
            return
        self.switch_tab((self.active_index + 1) % len(self.tabs))

    def previous_tab(self) -> None:
        if len(self.tabs) < 2:
            return
        self.switch_tab((self.active_index - 1) % len(self.tabs))

    def toggle_pin(self) -> None:
        self.pinned = not self.pinned
        self.apply_pin_state()
        self._update_pin_button()
        self.set_status("Pinned overlay" if self.pinned else "Pin off")

    def apply_pin_state(self) -> None:
        self.root.attributes("-topmost", 1 if self.pinned else 0)
        if self.pinned:
            self.root.lift()

    def _update_pin_button(self) -> None:
        self.btn_pin.configure(
            text="Pinned" if self.pinned else "Pin",
            bg=THEME["active"] if self.pinned else THEME["button"],
            activebackground=THEME["active"] if self.pinned else THEME["button_hover"],
            fg=THEME["active_text"] if self.pinned else THEME["ink"],
            activeforeground=THEME["active_text"] if self.pinned else THEME["ink"],
        )

    def toggle_sidebar(self) -> None:
        if self.zen_mode:
            return
        if self.sidebar_visible:
            try:
                self._sidebar_width = max(self.sidebar.winfo_width(), 160)
                self.main.forget(self.sidebar)
            except tk.TclError:
                pass
            self.sidebar_visible = False
            self.btn_sidebar.configure(text="Show")
        else:
            self.main.add(self.sidebar, minsize=150, width=self._sidebar_width, before=self.editor_frame)
            self.sidebar_visible = True
            self.btn_sidebar.configure(text="Sidebar")

    def toggle_zen(self) -> None:
        self.zen_mode = not self.zen_mode
        if self.zen_mode:
            self._sidebar_was_visible_before_zen = self.sidebar_visible
            if self.sidebar_visible:
                self._sidebar_width = max(self.sidebar.winfo_width(), 160)
                self.main.forget(self.sidebar)
                self.sidebar_visible = False
            self.tab_bar.grid_remove()
            self.right_tools.grid_remove()
            self.statusbar.grid_remove()
            self.btn_sidebar.configure(state="disabled")
            self.btn_zen.configure(text="Exit")
            self.text.configure(font=self._editor_font(16), padx=34, pady=30)
            self.set_status("")
        else:
            if self._sidebar_was_visible_before_zen and not self.sidebar_visible:
                self.main.add(self.sidebar, minsize=150, width=self._sidebar_width, before=self.editor_frame)
                self.sidebar_visible = True
                self.btn_sidebar.configure(text="Sidebar")
            elif not self.sidebar_visible:
                self.btn_sidebar.configure(text="Show")
            self.tab_bar.grid()
            self.right_tools.grid()
            self.statusbar.grid()
            self.btn_sidebar.configure(state="normal")
            self.btn_zen.configure(text="Zen")
            self.text.configure(font=self._editor_font(14), padx=24, pady=22)
        self.text.focus_set()

    def exit_zen_if_needed(self) -> None:
        if self.zen_mode:
            self.toggle_zen()

    def update_info(self) -> None:
        if self.info_after_id:
            self.info_after_id = None
        text = self.text.get("1.0", "end-1c")
        lines = text.count("\n") + 1
        words = len(text.split())
        self.info_text.set(f"{lines} lines | {words} words")

    def set_status(self, text: str) -> None:
        self.status_text.set(text)

    def on_close(self) -> None:
        if self.save_after_id:
            self.root.after_cancel(self.save_after_id)
            self.save_after_id = None
        self.capture_active_text()
        for index in range(len(self.tabs)):
            self.save_dirty_tab(index, force=self.tabs[index].dirty)
        self.root.destroy()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the native Ubuntu notes app.")
    parser.add_argument("--notes-dir", default=str(DEFAULT_NOTES_DIR), help="Directory for Markdown notes")
    parser.add_argument("--unpinned", action="store_true", help="Start without always-on-top pinning")
    parser.add_argument("--no-browser", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--port", type=int, help=argparse.SUPPRESS)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        print("Notes needs a graphical desktop session.", file=sys.stderr)
        return 1
    root = tk.Tk()
    NotesApp(root, Path(args.notes_dir).expanduser(), pinned=not args.unpinned)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
