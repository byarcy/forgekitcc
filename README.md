# ForgeKitCC

**A portable C/C++ toolchain for Windows.** It puts the **Visual Studio 2022 compiler (MSVC v143)**, the **Windows SDK**, **clang-cl (LLVM)**, **CMake**, **Ninja** and **Python** in one folder. You don't install Visual Studio, and you don't need admin rights.

Version **0.2.0**. For step-by-step help with common tasks, see **[GUIDE.md](GUIDE.md)**.

---

## Contents

1. [Requirements](#1-requirements)
2. [Quick start](#2-quick-start)
3. [The menu](#3-the-menu)
4. [Commands](#4-commands)
5. [The build console](#5-the-build-console)
6. [Updates, interrupted downloads and logs](#6-updates-interrupted-downloads-and-logs)
7. [Checking and repairing the installation](#7-checking-and-repairing-the-installation)
8. [Configuration (tools.json)](#8-configuration-toolsjson)
9. [Folder layout](#9-folder-layout)
10. [Limitations](#10-limitations)
11. [Uninstalling](#11-uninstalling)
12. [Changes](#12-changes)

---

## 1. Requirements

- Windows 10 version 1803 or newer, or Windows 11, 64-bit. These versions include `curl.exe` and `tar.exe`.
- About 4 GB of free space.
- An internet connection to install and update. Everything else works offline.
- No admin rights.

---

## 2. Quick start

1. Extract the `forgekitcc` folder to a path **without spaces or accents**, for example `D:\forgekitcc`.
2. Double-click `forgekitcc.bat` to open the menu.
3. Press **2** (Install / update), then **1** (Update all). When asked, accept the Visual Studio Build Tools license.
4. Press **3** (Check installation), then **2** (Full check + test build) to confirm everything works.
5. Press **1** to open the build console and start working.

The first install downloads about 2–3 GB.

---

## 3. The menu

Run `forgekitcc` with no command, or double-click `forgekitcc.bat`. The menu opens straight away. It doesn't touch the network and waits for you to press a key.

```
 ForgeKitCC v0.2.0
 ----------------------------------------------------------
 python ok   ninja ok   cmake ok   llvm UPDATE   msvc ok

  1  Open build console
  2  Install / update
  3  Check installation
  4  Settings
  0  Exit

 Press a number:
```

The top line shows the state of each tool: `ok`, `UPDATE` (a newer version was found in the last check), `missing` or `broken` (it is installed but won't run).

| Menu | Options |
|---|---|
| **1 Open build console** | Opens a new console window with every tool loaded. |
| **2 Install / update** | `1` Update all · `2` Choose tools |
| **3 Check installation** | `1` Quick check · `2` Full check + test build. If problems are found, it offers to repair them. |
| **4 Settings** | `1` Add to PATH · `2` Remove from PATH · `3` Open log folder · `4` Clean temp files |

You only press the number; there's no need to press Enter. `0` or `Esc` goes back.

---

## 4. Commands

Every menu option also exists as a command, which is useful for scripts.

| Command | What it does |
|---|---|
| `forgekitcc` | Opens the menu. |
| `forgekitcc status` | Shows the installed and available version of each tool. |
| `forgekitcc update [tools]` | Installs missing tools and updates the rest. |
| `forgekitcc install [tools]` | Installs missing tools only. |
| `forgekitcc repair [tools]` | Reinstalls tools, which fixes damaged installs. |
| `forgekitcc verify [tools]` | Checks that every installed file is present and the right size. |
| `forgekitcc verify --full` | Also checks the file contents and builds a test program. |
| `forgekitcc env` | Loads the build environment into the current console. |
| `forgekitcc path add` / `remove` | Adds the tools to your user PATH, or removes them. |
| `forgekitcc clean` | Deletes downloads and temporary folders. |
| `forgekitcc version` | Shows the version. |
| `forgekitcc help` | Shows the help. |

**Tools:** `python`, `ninja`, `cmake`, `llvm`, `msvc`, or `all`, which is the default. For example: `forgekitcc update llvm cmake`.

**Options:**

| Option | Effect |
|---|---|
| `--verbose`, `-v` | Shows more detail on screen. |
| `--quiet`, `-q` | Shows only errors and the final summary. |
| `--accept-license` | Accepts the Visual Studio Build Tools license without asking. |

---

## 5. The build console

To open it, use menu option **1**, double-click `env.bat`, or run `forgekitcc env` in a console you already have open.

Inside it you can use `cl`, `link`, `clang-cl`, `cmake`, `ninja`, `python` and `pip`. MSVC's `INCLUDE` and `LIB` variables are also set.

The console also sets variables that help other tools find the portable MSVC:

| Variable | Helps |
|---|---|
| `VCINSTALLDIR`, `VCToolsInstallDir`, `VSCMD_ARG_TGT_ARCH`… | Rust (`cargo`) and other tools that look for MSVC |
| `WindowsSdkDir`, `WindowsSDKVersion`, `UCRTVersion` | Tools that look for the Windows SDK |
| `DISTUTILS_USE_SDK=1`, `MSSdk=1` | `pip` when it compiles packages that contain C code |
| `CMAKE_GENERATOR=Ninja` | CMake uses Ninja when a project doesn't choose a generator |

Once a week, opening the console also checks for updates. Without internet it skips the check silently.

---

## 6. Updates, interrupted downloads and logs

**What you see.** Each tool gets one line, followed by a short summary:

```
 [1/2] llvm   21.1.5      downloading  612/1180 MB  52%
 [1/2] llvm   21.1.5      done
 [2/2] cmake  4.1.2       done

2 updated, 0 failed.
```

**Interrupted downloads.** If the connection drops, run the same option again. The download resumes where it stopped instead of starting over. MSVC resumes file by file.

**No internet.** ForgeKitCC checks the connection before it starts. Without internet, nothing is changed.

**Safe replacement.** Each tool is downloaded and checked first, and only then does it replace the installed version. If anything fails, the installed version stays as it was.

**Checksums.** GitHub downloads are verified with their SHA-256 checksum when GitHub provides one. A damaged download is deleted automatically.

**Logs.** Every action is written to `logs\YYYY-MM-DD.log` with full detail: commands, output and errors. When something fails, the screen shows the name of the log file. Logs older than 30 days are deleted automatically. To open the folder, use menu **4 → 3**.

**GitHub limit.** Without signing in, GitHub allows 60 requests per hour, which is plenty for normal use. If you reach the limit, set a `GITHUB_TOKEN` environment variable with a personal access token.

---

## 7. Checking and repairing the installation

When a tool is installed, ForgeKitCC saves a list of its files with their sizes and SHA-256 checksums in `manifests\`.

| Check | What it does | Time |
|---|---|---|
| Quick (`verify`) | Checks that each tool runs, and that every file exists and has the right size. | Seconds |
| Full (`verify --full`) | Also compares the checksum of every file, then builds and runs a test program with clang-cl and with cl. | 1–3 minutes |

If something is damaged, the menu offers to repair it. From the command line, run `forgekitcc repair <tool>`.

Files that change during normal use are not checked, for example pip packages in `python\Lib\site-packages`.

---

## 8. Configuration (tools.json)

### Pinning versions

`"pin"` limits which versions can be installed:

| Value | Result |
|---|---|
| `""` | Always the newest version. |
| `"3.12"` | The newest 3.12.x. |
| `"20"` | The newest LLVM 20.x. |
| `"14.44"` | MSVC 14.44, the last **VS 2022** toolset. |

The defaults pin MSVC to `14.44` and Python to `3.12`. LLVM, CMake and Ninja track their newest version.

> If you clear the MSVC pin, you get the newest toolset, which comes from VS 2026. Projects that require VS 2022 may not accept it.

### Adding a tool

Add an entry to `tools`. This example is for a tool published on GitHub Releases:

```json
{
  "name": "mytool",
  "type": "github",
  "repo": "owner/repository",
  "asset": "^mytool-.*-windows-x64\\.zip$",
  "pin": "",
  "dir": "mytool",
  "subdir": "*",
  "exe": "bin\\mytool.exe",
  "versionArgs": ["--version"],
  "bin": ["bin"]
}
```

| Field | Meaning |
|---|---|
| `name` | Name used in commands. |
| `type` | `github` for GitHub Releases, `nuget` for a NuGet package, or `msvc`. |
| `repo` / `package` | GitHub `owner/repository`, or the NuGet package id. |
| `asset` | Regular expression that matches the file to download from GitHub. |
| `pin` | Version prefix to stay on. Empty means the newest version. |
| `dir` | Destination folder. |
| `subdir` | `""` if the archive has no top folder. `"*"` if it has exactly one top folder. Any other value uses that subfolder. |
| `exe` / `versionArgs` | Program and arguments used to read the installed version. |
| `bin` | Folders added to PATH. `""` means the tool folder itself. |
| `verifyExclude` | Optional. Patterns for files the check should ignore. |

Supported archive formats: `.zip`, `.nupkg`, `.tar.xz`, `.tar.gz` and `.tar.bz2`.

---

## 9. Folder layout

| Item | Purpose |
|---|---|
| `forgekitcc.bat` | Main command. Double-click it to open the menu. |
| `env.bat` | Double-click it to open the build console. |
| `forgekitcc.ps1`, `lib\` | Program code. |
| `tools.json` | Tools and pinned versions. |
| `python\`, `ninja\`, `cmake\`, `llvm\`, `msvc\` | The installed tools. |
| `manifests\` | File lists used by the installation check. |
| `logs\` | Daily logs. |
| `state.json` | Result of the last update check. |
| `_downloads\`, `_tmp_*` | Temporary files. Clean them with `forgekitcc clean`. This also deletes unfinished downloads. |

---

## 10. Limitations

- **Not included:** an IDE, the Visual Studio debugger, MSBuild (so `.sln` and `.vcxproj` files won't open), MFC, ATL, UWP and C++/CLI.
- **CMake generator:** use the **Ninja** generator. The "Visual Studio 17 2022" generator doesn't work.
- **Tools that require a full Visual Studio:** installers and tools that look for Visual Studio with `vswhere`, such as node-gyp, Qt Creator and some installers, may still not detect it. Run them from the build console. See GUIDE.md for each case.
- **Global PATH:** `path add` doesn't include MSVC, because `cl` also needs `INCLUDE` and `LIB`. Compile from the build console.
- **Distributing programs:** with `/MD`, the default, the target PC needs the *Visual C++ Redistributable*. Build with `/MT` to get a standalone `.exe`.
- **License:** the Visual Studio Build Tools license applies. Personal and academic use are fine; commercial use inside a company may require a Visual Studio license.

---

## 11. Uninstalling

1. Run `forgekitcc path remove`, or use menu **4 → 2**.
2. Delete the folder.

Nothing else is left on the system.

---

## 12. Changes

**0.2.0**

- New menu that is short and opens instantly, with submenus.
- Downloads resume after a dropped connection, and ForgeKitCC checks for internet before it starts.
- One status line per tool and a final summary. Added `--verbose` and `--quiet`.
- Daily logs in `logs\`.
- New `verify`, `verify --full` and `repair` commands that check installed files against their manifest.
- The build console sets variables for Rust, pip and CMake.
- The code is split into modules in `lib\`.
- Added GUIDE.md with common scenarios.

**0.1.0** — First version: update, status, env, PATH and doctor.

---

## Credits

- MSVC and the Windows SDK are © Microsoft. They are downloaded with [portable-msvc.py](https://gist.github.com/mmozeiko/7f3162ec2988e81e56d5c4e22cde9977) by Mārtiņš Možeiko.
- [LLVM](https://github.com/llvm/llvm-project), [CMake](https://github.com/Kitware/CMake), [Ninja](https://github.com/ninja-build/ninja) and [Python](https://www.python.org), which comes from the official NuGet package.
