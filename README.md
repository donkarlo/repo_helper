# repotool

A lightweight set of developer tools for managing multiple Python repositories under the same folder.

This toolkit includes:

- **Editable package installation** for Python packages found in subdirectories
- **Git commit and push helper** for syncing local changes across multiple repositories

---

## 📁 Folder Structure

This script suite assumes the following structure:

```
~/repos/
├── repo1/
│   ├── setup.py or pyproject.toml
│   └── ...
├── repo2/
│   ├── setup.py or pyproject.toml
│   └── ...
└── ...
```

---

## 🚀 Usage

### 1. Install All Editable Python Packages

This script finds all valid Python packages in `repos` and installs them using pip in editable mode (`-e`).

```bash
./install_python_packages.sh
```

Output will include which packages were installed or skipped.

---

### 1. Uninstall All Editable Python Packages

This script finds all valid Python packages in `repos` and installs them using pip in editable mode (`-e`).

```bash
./install_python_packages.sh
```

Output will include which packages were installed or skipped.

---

### 2. Commit & Push Changes in All Git Repositories

This script loops over all Git repositories in `~/repos`, stages all changes, shows them, and lets you choose to commit & push to the `main` branch.

```bash
./add_commit_push.sh
```

> 💡 You will be prompted for commit messages and confirmation before pushing.

---

## 🔧 Requirements

- Bash
- Python (>= 3.9)
- Git
- Pip
- Proper `origin` or `mghub` remote in each repository (you can change `mghub` to `origin` in the script if needed)

---

## 📦 License

This project is personal utility code — no license restrictions, use freely.
