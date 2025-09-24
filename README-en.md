# 🔎 Project Scanner

`project-scanner` is a cross‑platform PowerShell script for automatic analysis of a project's source code.  
It recursively walks through a directory, builds a file tree, gathers statistics, and optionally adds file contents to the report.

📄 The result is saved to a plain‑text or markdown‑style file (default — `project_analysis.txt`).

---

## ✨ Features
- 🚫 Exclude directories (`-ExcludeDirs`) and individual files (`-ExcludeFiles`; `*` and `?` wildcards are supported).
- ✅ Include only specific extensions (`-IncludeExtensions`).
- 📏 Limit the size of files whose content is output (`-MaxFileSize`, default — 50 KB).
- 🌳 Build a project tree (using the `tree` utility on Windows or an internal generator).
- 📊 (Optional) Statistics: number of files, number of lines, distribution by type.
- 🖥️ Cross‑platform – works with PowerShell 7 (Windows, Linux, macOS).
- ⚡ Handy output‑control flags:
  - `-TreeOnly` — output only the project tree  
  - `-NoContent` — do not output file contents  
  - `-ShowStats` — add a statistics block  
  - `-Help` — display help  

---

## 📦 Installation
1. Make sure **PowerShell 7+** is installed ([instructions](https://learn.microsoft.com/powershell/)).
2. Clone the repository:

```bash
git clone https://github.com/mirninec/project-scanner.git
cd project-scanner
```

3. Make the script executable (Linux/macOS):

```bash
chmod +x project_scanner.ps1
```

---

## 🚀 Usage

Run with parameters:

```powershell
./project_scanner.ps1 -ProjectDir ./my_project -OutputFile report.txt -ShowStats
```

Examples:

* 🔹 Scan the current directory:

```powershell
./project_scanner.ps1
```

* 🔹 Only the project tree:

```powershell
./project_scanner.ps1 -TreeOnly
```

* 🔹 Include statistics and save to `analysis.md`:

```powershell
./project_scanner.ps1 -ShowStats -OutputFile analysis.md
```

---

## 📊 Sample Report

````
# PROJECT ANALYSIS

**Project:** my_project  
**Scan date:** 2025-09-25 10:30:12  
**Scanned directory:** C:\Users\me\my_project

---

# PROJECT STRUCTURE

├── src
│   ├── index.ts
│   └── utils.ts
└── package.json

---

# FILE CONTENTS
## src/index.ts
```typescript
import { start } from "./utils";
start();
```
````

---

## 🛠️ Parameters
| Parameter            | Description |
|----------------------|--------------|
| `-ProjectDir`        | Path to the project (default `.`) |
| `-OutputFile`        | File to save the result |
| `-MaxFileSize`       | Maximum file size for full output |
| `-ExcludeDirs`       | Directories to exclude |
| `-IncludeExtensions` | File extensions to analyze |
| `-ExcludeFiles`      | Files / patterns to exclude |
| `-AdditionalExclude`| Additional directories to exclude |
| `-AdditionalInclude`| Additional extensions to include |
| `-TreeOnly`          | Output only the project tree |
| `-NoContent`         | Omit file contents |
| `-ShowStats`         | Add statistics |
| `-Help`              | Show help |

---

## 🤖 Using with LLMs
The script can be used to prepare data before feeding it to an LLM (e.g., ChatGPT or via a RAG approach):  
- 🔹 The report gathers the whole project into a single document;  
- 🔹 Unnecessary files (node_modules, .git, etc.) are excluded;  
- 🔹 The output can be converted to JSON/JSONL and used for indexing.  

---

## 📜 License
The project is released under the **MIT** license.

---

Happy scanning! 🎉  

👨‍💻 Author: [mirninec](https://github.com/mirninec)
