# ForgeKitCC — Usage guide

Step-by-step instructions for common situations. Each scenario stands on its own, so jump to the one you need.

> **Two words used throughout**
> - **Menu**: what opens when you double-click `forgekitcc.bat` or run `forgekitcc`.
> - **Build console**: the console where every tool is ready to use. Open it with menu option **1**, by double-clicking `env.bat`, or by running `forgekitcc env`.

---

## Scenarios

1. [Install for the first time](#1-install-for-the-first-time)
2. [Build a CMake project](#2-build-a-cmake-project)
3. [Build a project that has CMake presets](#3-build-a-project-that-has-cmake-presets)
4. [Compile a single file](#4-compile-a-single-file)
5. [Make a release build to share](#5-make-a-release-build-to-share)
6. [Use it on a PC without internet](#6-use-it-on-a-pc-without-internet)
7. [Slow or unstable connection](#7-slow-or-unstable-connection)
8. [Keep updates under control](#8-keep-updates-under-control)
9. [Python and pip packages](#9-python-and-pip-packages)
10. [Rust and other tools that need MSVC](#10-rust-and-other-tools-that-need-msvc)
11. [Work in VS Code](#11-work-in-vs-code)
12. [Use it from scripts](#12-use-it-from-scripts)
13. [Something stopped working](#13-something-stopped-working)
14. [Move or upgrade ForgeKitCC](#14-move-or-upgrade-forgekitcc)

---

## 1. Install for the first time

**You need:** Windows 10 (1803 or newer) or Windows 11, about 4 GB of free space, and internet.

1. Extract the `forgekitcc` folder to a short path without spaces, such as `D:\forgekitcc`.
2. Double-click `forgekitcc.bat`.
3. Press **3** (Install / update), then **1** (Update all).
4. When asked, press **y** to accept the Visual Studio Build Tools license.
5. Wait. Each tool shows one line and ends with `done`. The first install downloads 2–3 GB.
6. Press **4** (Check installation), then **2** (Full check + test build). You should see `test build ok` for both `clang-cl` and `cl`.

**Optional:** to run `forgekitcc` from any console, press **5** (Settings), then **1** (Add to PATH), and open a new console.

---

## 2. Build a CMake project

1. Open the build console.
2. Go to the project folder:
   ```
   cd D:\projects\myproject
   ```
3. Configure and build. With clang-cl:
   ```
   cmake -S . -B build -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl
   cmake --build build
   ```
   With MSVC:
   ```
   cmake -S . -B build -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl
   cmake --build build
   ```
4. The program is inside `build\`.

**Good to know**

- The build console already selects the Ninja generator, so you don't need `-G Ninja`.
- Use a different build folder for each compiler, such as `build-clang` and `build-msvc`. CMake can't switch compilers inside an existing build folder.
- After changing `CMakeLists.txt`, running `cmake --build build` is enough, because CMake reconfigures by itself.

---

## 3. Build a project that has CMake presets

If the project has a `CMakePresets.json` file:

1. Open the build console in the project folder.
2. See which presets the project offers:
   ```
   cmake --list-presets
   ```
3. Pick one that targets Windows and uses Ninja, then build it:
   ```
   cmake --preset <name>
   cmake --build --preset <name>
   ```

- If the project has no build presets, `cmake --build --preset` fails. Run `cmake --build <folder>` instead, using the build folder the configure preset created.
- If a preset uses a "Visual Studio" generator, it won't work. Choose a Ninja preset, or configure the project yourself as in scenario 2.

---

## 4. Compile a single file

For quick tests, you don't need CMake. In the build console, run:

```
cl /EHsc /std:c++20 hello.cpp
hello.exe
```

or:

```
clang-cl /EHsc /std:c++20 hello.cpp
hello.exe
```

Useful flags:

| Flag | Meaning |
|---|---|
| `/O2` | Optimize for speed. |
| `/W4` | More warnings. |
| `/Zi` | Debug information. |
| `/MT` | Standalone `.exe`, with no runtime DLLs needed. |
| `/Fe:name.exe` | Output file name. |

---

## 5. Make a release build to share

1. Configure in Release mode with the static runtime:
   ```
   cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
   cmake --build build-release
   ```
2. Copy the `.exe` from `build-release`, plus any files your program loads.

With `MultiThreaded` (`/MT`), the `.exe` runs on any Windows PC. If you build with the default (`/MD`), the other PC needs the *Microsoft Visual C++ Redistributable* (x64).

---

## 6. Use it on a PC without internet

ForgeKitCC only needs internet to install and update.

**Prepare (on a PC with internet):**
1. Install everything as in scenario 1.
2. Run the full check: menu **4 → 2**.
3. Optionally, free space with menu **5 → 4** (Clean temp files).
4. Copy the whole `forgekitcc` folder to a USB drive or external disk.

**Use (on the offline PC):**
1. Copy the folder to the disk, for example `D:\forgekitcc`. Running it from the USB drive also works, but builds are slower.
2. Double-click `env.bat` and build as usual.
3. Optionally, use menu **5 → 1** to add it to PATH on that PC.

The menu and the build console never wait for the network. The weekly update check skips silently when there is no connection.

---

## 7. Slow or unstable connection

- **Connection lost during an update.** The tool shows `FAILED: connection lost`. When the connection returns, choose the same option again. The download resumes where it stopped.
- **Update only part of it.** Use menu **3 → 2** (Choose tools) and pick one tool at a time, for example the smaller ones first.
- **No internet at all.** ForgeKitCC says so and changes nothing.
- **See what it is doing.** From a console, run `forgekitcc update --verbose`.
- **See what went wrong.** The error line names the log file. Open the folder with menu **5 → 3**.

Approximate download sizes: Python 15 MB, Ninja 0.3 MB, CMake 45 MB, LLVM 1.2 GB, MSVC and the Windows SDK about 1 GB.

---

## 8. Keep updates under control

- **See what is new without changing anything:** `forgekitcc status`.
- **Update one tool:** `forgekitcc update cmake`.
- **Stay on a version:** edit `tools.json` and set `"pin"`. For example, `"pin": "20"` keeps LLVM on 20.x.
- **Stay on Visual Studio 2022:** keep the MSVC pin at `"14.44"`, which is the default.
- **Go back to an older version:** set `"pin"` to that version, for example `"4.0"` for CMake, then run `forgekitcc repair cmake`.

---

## 9. Python and pip packages

The bundled Python works inside the build console, or in every console after **Add to PATH**.

- **Install a package:** `python -m pip install <package>`.
- **Packages with C/C++ code** (they compile when installed): run pip from the build console. It uses the portable MSVC automatically.
- **Updating Python** keeps your packages, because they are reinstalled into the new version.
- **IDEs and editors** don't detect this Python on their own. Give them the path `D:\forgekitcc\python\python.exe`. In VS Code, run *Python: Select Interpreter*, then choose *Enter interpreter path*.
- **Not included:** tkinter and IDLE. If you need them, install the regular Python from python.org.

---

## 10. Rust and other tools that need MSVC

Many tools say they need *"the Visual Studio C++ tools and the Windows SDK"*. ForgeKitCC includes both, but installers look for a full Visual Studio and may not detect the portable one.

**Rust**
1. Run the rustup installer. When it says Visual Studio is missing, choose the option to continue without installing it.
2. Open the build console.
3. Run `cargo build`. Cargo finds `link.exe` through the variables the build console sets.

**Python packages with C code:** see scenario 9.

**node-gyp (Node.js native modules):** run `npm install` from the build console. Some node-gyp versions insist on finding Visual Studio through `vswhere` and fail anyway. In that case, the full Visual Studio Build Tools installer is the reliable option.

**General rule:** if a tool can't find the compiler, start it from the build console.

---

## 11. Work in VS Code

ForgeKitCC can install a portable VS Code. It needs no installer and no admin rights, and its settings and extensions stay in `vscode\data`.

**First time**
1. In the menu, press **2** (Open VS Code). It offers to install VS Code (about 120 MB) together with the Microsoft C/C++ extension.
2. Choose your project folder.
3. When asked, press **y** to add build and debug settings. This creates `.vscode\tasks.json` and `.vscode\launch.json` and never overwrites existing files.

**Every day**
- Menu **2**, choose the folder. Or, from any console: `forgekitcc code D:\path\to\project`. Inside the build console, `code .` also works.
- Open a `.cpp` or `.c` file and press **Ctrl+Shift+B** to build it with `cl`. Use *Terminal → Run Task → build (clang-cl)* to build it with clang-cl.
- Press **F5** to build and debug the open file. Set breakpoints by clicking left of the line numbers.

These settings build **one file** into a program with the same name, which fits exercises and small programs. For projects with several files, use CMake:

1. Install the **CMake Tools** extension and choose the kit **[Unspecified]**. It uses the compilers from the environment. To force one, add this to `.vscode/settings.json`:
   ```json
   {
     "cmake.generator": "Ninja",
     "cmake.configureSettings": { "CMAKE_CXX_COMPILER": "clang-cl", "CMAKE_C_COMPILER": "clang-cl" }
   }
   ```
2. For accurate code completion, add `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` when you configure, and point the C/C++ extension to `build/compile_commands.json`.

**Your own VS Code.** If VS Code is already installed on the PC, start it from the build console (`code .`) so it sees the compilers. Opened from the Start menu, it won't find them.

**If `cl` is not found inside VS Code**, another VS Code window was already open without the build environment, and new windows join it. Close every VS Code window and open it again from ForgeKitCC.

**Updates.** VS Code is updated with the other tools (menu **3**). Its own update check is turned off, because ForgeKitCC handles it.

---

## 12. Use it from scripts

Every command returns exit code `0` on success and `1` on failure.

```bat
@echo off
call D:\forgekitcc\forgekitcc.bat update --quiet --accept-license || exit /b 1
call D:\forgekitcc\forgekitcc.bat env || exit /b 1
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build || exit /b 1
```

- `--quiet` prints only errors and the summary, and the log keeps everything.
- `--accept-license` avoids the license question, so the script doesn't stop.
- `forgekitcc verify` is a quick check you can run before a build.

---

## 13. Something stopped working

Work through these steps in order:

1. **Look at the menu header.** A tool marked `missing` or `broken` points to the problem.
2. **Quick check:** menu **4 → 1**. It lists missing or changed files and offers to repair them.
3. **Full check:** menu **4 → 2**. It also builds a test program, which shows whether the compilers really work.
4. **Repair a tool:** accept the repair offer, or run `forgekitcc repair <tool>`.
5. **Read the log:** menu **5 → 3**. Each line has the time and the step, and errors are marked `[ERROR]`.

| Message | What to do |
|---|---|
| `STL1000: Unexpected compiler version` | LLVM is too old for this MSVC. Run `forgekitcc update llvm`. |
| CMake can't find `cl` or `clang-cl` | You aren't in the build console. Open it with menu **1**. |
| `cannot replace '...'` | A console or program is using that tool. Close it and try again. |
| `MSVC 14.44 is no longer offered` | Microsoft removed that version. Change `"pin"` in `tools.json`. |
| `GitHub refused the request (rate limit)` | Wait an hour, or set the `GITHUB_TOKEN` variable. |
| `license not accepted` | Run the update again and answer **y**. |
| `'forgekitcc' is not recognized` | Run it from its folder, or use menu **5 → 1** and open a new console. |

---

## 14. Move or upgrade ForgeKitCC

**Move the folder:**
1. Before moving it, use menu **5 → 2** (Remove from PATH).
2. Move the folder.
3. In the new location, use menu **5 → 1** (Add to PATH).

**Upgrade ForgeKitCC itself:**
1. Extract the new version over the old folder, replacing `forgekitcc.bat`, `forgekitcc.ps1`, `env.bat` and the `lib\` folder.
2. Keep your `tools.json` if you changed it. Compare it with the new one for added tools.
3. The installed tools stay in place, so nothing is downloaded again.
4. Run the quick check. If a tool shows "no manifest", repair it once to create the manifest.
