# Compiling SWAT on Windows (gfortran + CMake)

> **Acknowledgment:** This workflow was inspired by the work of Dr. Liang-Jun Zhu and his unofficial SWAT repository, [Unofficial collection of SWAT code](https://github.com/crazyzlj/SWAT).

## What this guide is for

SWAT (the Soil and Water Assessment Tool) is distributed as **source code**: text files written in the Fortran language.
To run it you must first turn that text into a program (an `.exe` file).
This is called **compiling**.
This guide shows how to do that on Windows with free tools, with no programming knowledge needed.
You only copy and paste the commands.

A full compile takes about one minute and gives you one file, for example `swat695.mingw64.rel.exe`, that you run inside your model folder (the one with `file.cio`).

**You received three files:**

| File | What it is |
|------|------------|
| `COMPILE_GUIDE.md` | This guide |
| `CMakeLists.txt` | The build recipe. It tells the tools which files to compile and how. You do not edit it. |
| `apply-gfortran-fixes.ps1` | A small script that makes a few text edits to the SWAT source so the free compiler accepts it (section 2) |

**You also need** the SWAT source files (`.f` and `.f90`), which you get from the official SWAT download (<https://swat.tamu.edu>) or their [official GitHub repository](https://github.com/swat-model/swat2012).

**Tested with:** Windows 11 · MSYS2 gfortran 15.2.0 · CMake 4.2.3 · SWAT rev. 695 and 693.

### Quick start

1. Install the tools (section 1).
2. Put the files in a short folder, such as `C:\swat\rev695` and the SWAT sources in its `src\` sub-folder (section 2).
3. Run the patch script once (section 2).
4. Configure and build (section 4).
   The result is in `build\executable\`.

### Words used in this guide

| Word | Meaning |
|------|---------|
| **Compiler** (gfortran) | The program that turns Fortran source text into an `.exe` |
| **CMake** | Reads `CMakeLists.txt` and writes the detailed build instructions |
| **make** (`mingw32-make`) | Carries out those instructions, one source file at a time |
| **MSYS2** | An installer that supplies gfortran, CMake and make in one go |
| **PowerShell** | The Windows command window where you paste the commands |
| **Configure** | Step 1 of a build: CMake checks your tools and prepares the instructions. Nothing is compiled yet. |
| **Build** | Step 2: the compiler actually builds the `.exe` |
| **PATH** | The list of folders Windows searches for programs. Section 1 shows how to add the MSYS2 folder to it. |
| **Warning / Error** | Warnings (thousands appear) are harmless. An `Error` means the build failed. |

## 1. Install the tools

| Tool | Purpose | Tested |
|------|---------|--------|
| MSYS2 | Package manager supplying the tools below | current |
| gfortran | Fortran compiler | 15.2.0 |
| CMake | Build coordinator (≥ 3.15) | 4.2.3 |
| mingw32-make | Runs the compile steps | with MSYS2 |

1. Install MSYS2 from <https://www.msys2.org> into the default `C:\msys64`.
2. Open **MSYS2 MINGW64** (not UCRT64, CLANG64 or plain MSYS2) and run `pacman -Syu`.
   If the window closes, reopen it and run it again.
3. Install the tools:

   ```
   pacman -S mingw-w64-x86_64-gcc-fortran mingw-w64-x86_64-cmake mingw-w64-x86_64-make
   ```

Everything after this runs in **PowerShell**, not Git Bash.

**How to run the commands in this guide:** each grey code block is one step.
Open PowerShell in the project folder (see below), copy the whole block, paste it into the window and press Enter.
Run the blocks in order, and wait for each one to finish before pasting the next.

### Set the PATH (every new PowerShell window)

```powershell
$env:Path = "C:\msys64\mingw64\bin;" + $env:Path
```

Without this you get `cmake : The term 'cmake' is not recognized`.

### Check for competing copies

Strawberry Perl, Anaconda, MATLAB and Git for Windows bundle their own gfortran/CMake.
Verify the MSYS2 copies come first:

```powershell
(Get-Command gfortran -All).Source
(Get-Command cmake -All).Source
```

The first line of each must start with `C:\msys64\mingw64\bin\`.
If not, rerun the `$env:Path` line.

### Open PowerShell in the project folder

- **File Explorer:** open the folder, type `powershell` in the address bar, press Enter.
- **VS Code:** open the project folder itself (not a parent), then *Terminal → New Terminal* and choose **PowerShell**.

## 2. Folder layout

```
C:\swat\rev695\                    <-- project folder (you create this)
├── COMPILE_GUIDE.md               <-- this guide
├── CMakeLists.txt                 <-- build recipe (do not edit)
├── apply-gfortran-fixes.ps1       <-- patches stock sources for gfortran
├── src\                           <-- you create this and copy ALL the SWAT .f and .f90 files into it
└── build\                         <-- created automatically by the compile; safe to delete
    └── executable\swat695.mingw64.rel.exe   <-- the finished program
```

Set it up like this: create the project folder, copy the three files (COMPILE_GUIDE.md, CMakeLists.txt, and apply-gfortran-fixes.ps1), create the `src\` folder, and copy the SWAT source files into `src\`.
Do not create `build\`; the compile does that.

Rules:

- **Short path, no spaces** (e.g. `C:\swat\rev695`).
  Windows limits object-file paths to about 250 characters.
  Configuring failed in a ~160-character project path.
- **No sub-folders in `src\`.**
  The build only collects `src\*.f` and `src\*.f90`.
- **Keep an untouched copy** of the original download.
  The patch script edits `src\` in place.
- **Keep model inputs elsewhere.**
  SWAT reads inputs from the folder it runs in (your `TxtInOut`, containing `file.cio`).

The SWAT revision is read from `main.f`, not the folder name.

### Patch the sources (once per source version)

**In plain words:** the official SWAT source was written for a commercial compiler (Intel).
The free compiler used here (gfortran) is stricter and refuses a few lines.
The script `apply-gfortran-fixes.ps1` makes small text edits to the files in `src\` so gfortran accepts them.
It changes nothing else, and it does not change the model results by itself.

- Run it **once per new copy of the SWAT source**, before the first compile.
- If your `src\` was already patched, you can skip it.
  Running it again is harmless: it just says `nothing to fix`.
- It edits the files in `src\` in place, so keep an untouched copy of the original download.
- To see what it would change without changing anything, add `-DryRun`.

The three problems it fixes (one only appears when the program runs):

| # | Problem | Fix |
|---|---------|-----|
| 1 | Eight files collide with the `parm` module | `use parm` → `use parm, except_this_one => <name>` |
| 2 | Output-heading list has unequal text lengths | Pad items to one width |
| 3 | Print format missing a comma. **Compiles, then crashes in year 1.** | Insert the comma |

Run this in PowerShell, from the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\apply-gfortran-fixes.ps1
```

Windows blocks scripts by default; `-ExecutionPolicy Bypass` lets this one run.
If you see *"is not digitally signed"*, run `Unblock-File .\apply-gfortran-fixes.ps1` and retry.
See [Appendix A](#appendix-a--the-three-source-fixes).

## 3. Options (optional; defaults give a standard optimized build)

Pass options to the configure command as `-DNAME=value`.

| Option | Default | Effect |
|--------|---------|--------|
| `CMAKE_BUILD_TYPE` | `Release` | `Release` is fast; `Debug` is slower but easier to debug |
| `SWAT_EXTRA_FLAGS` | empty | Extra compiler flags, e.g. `-static` |
| `SWAT_SRC_DIR` | `src` | Source folder name |
| `SWAT_VERSION` | detected | Revision in the `.exe` name |
| `SWAT_EXE_NAME` | `swat` | Start of the `.exe` name |
| `SWAT_PREFLIGHT` | `ON` | Warn about the section 2 problems before compiling |
| `SWAT_ZERO_HEAP` | `ON` | Zero-fill all allocated memory so results are repeatable (see below) |
| `SWAT_LEN72_SRCS` | `grow;tran` | Files read with the old 72-column rule |
| `SWAT_LENLONG_SRCS` | `subbasin;modparm` | Files with very long lines |

The executable name is `swat<revision>.mingw64.<rel|dbg>.exe`.

**Zero-filled heap (`SWAT_ZERO_HEAP`, on by default).**
SWAT reads some allocated arrays before assigning them (for example `sdnco` in `readhru.f`).
Intel's runtime hands back zeroed memory, so the bug is invisible there.
gfortran hands back whatever the heap held, so results change with the `libgfortran` DLL that gets loaded and even with the size of the environment.
gfortran has no flag to zero allocatable arrays, so the build wraps `malloc` at link time (`-Wl,--wrap=malloc`) with a small Fortran shim, `build\swat_zero_malloc.f90`, that clears every block.
No C compiler is needed.
It applies to GNU Fortran only (not macOS).
The configure summary shows `Zero-fill heap: ON`.
Turn it off only for debugging, with `-DSWAT_ZERO_HEAP=OFF`.

**Standalone `.exe`.**
A normal build needs `libgfortran-5.dll` from `C:\msys64\mingw64\bin` and fails elsewhere with exit code `-1073741515`.
A static build avoids this (about 3.2 MB instead of 2.5 MB):

```powershell
cmake -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -DSWAT_EXTRA_FLAGS="-static" -S . -B build
cmake --build build
```

**Debug build with run-time checks:**

```powershell
cmake -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Debug -DSWAT_EXTRA_FLAGS="-fcheck=all -fbacktrace" -S . -B build
cmake --build build
```

CMake remembers options in `build\`.
To change them, delete it: `Remove-Item -Recurse -Force build`.

## 4. Compile

### 4.1 Confirm you are in the project folder

The most common mistake is running from the wrong folder.
Check:

```powershell
if ((Test-Path .\CMakeLists.txt) -and (Test-Path .\src)) { "OK: $(Get-Location)" } else { Write-Warning "Wrong folder: $(Get-Location)" }
```

If you opened a parent folder, `cd` into the project folder.

### 4.2 Configure

Run in PowerShell, from the project folder:

```powershell
$env:Path = "C:\msys64\mingw64\bin;" + $env:Path
cmake -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -S . -B build
```

This compiles nothing; it takes a few seconds.
Check the output:

| Line | Good | Otherwise |
|------|------|-----------|
| `Preflight` | `no known gfortran blockers found` | Run the patch script, then reconfigure |
| `main.f variant` | `manual ordering active` | Revisions without this line are untested |
| `Fortran compiler` | path under `C:/msys64/mingw64/bin/` | Wrong toolchain; see the PATH check above |
| `SWAT revision` | expected number | `unknown` is harmless (add `-DSWAT_VERSION=695`) |
| `Sources found` | about 300 `.f` | `0` means files are not directly in `src\` |
| Last line | `Build files have been written to: …` | `CMake Error` is a failure |

A warning that the object file directory exceeds 250 characters means the path is too long; move the project.

### 4.3 Build

Run in PowerShell, from the project folder:

```powershell
cmake --build build
```

Takes about one minute.
**Thousands of `Warning:` lines are normal** (tabs, unused variables, truncated text).
Only `Error:` or `Error 1`/`Error 2` means failure.

### 4.4 Verify

A successful build ends with `[100%] Built target swat`.
Also check:

```powershell
Get-ChildItem .\build\executable    # one .exe, about 2.4–2.5 MB
$LASTEXITCODE                       # run immediately after the build; should be 0
```

On failure, scroll up to the first `Error:` line, which names the file and line.

### 4.5 Rebuilding

| Situation | Action |
|-----------|--------|
| Edited, added or removed a source file | `cmake --build build` (only changed files recompile) |
| Changed an option, or something odd | Delete `build`, then configure and build again |
| New PowerShell window | Run the `$env:Path` line first |

## 5. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `cmake` not recognized | Run the `$env:Path` line; check install (section 1) |
| `does not appear to contain CMakeLists.txt`, or `-File parameter does not exist` | Wrong folder; move into the project folder (4.1) |
| `Source directory not found: …\src` | Create `src\` and copy the sources in |
| `No .f or .f90 files found` | Sources are in a sub-folder; put them directly in `src\` |
| Preflight collisions or `malformed FORMAT descriptor` | Run the patch script, reconfigure |
| `Different CHARACTER lengths (12/13) in array constructor` | Fix #2 missing; run the patch script |
| `Missing comma between descriptors` while running | Fix #3 missing; run the patch script, **rebuild** |
| `Error 1` while CMake tests the compiler | Git Bash or a long path; use PowerShell, shorten the path |
| Object file directory exceeds 250 characters | Move the project to a shorter path |
| `running scripts is disabled` | Use `-ExecutionPolicy Bypass -File …` as in section 2 |
| `not digitally signed` | `Unblock-File .\apply-gfortran-fixes.ps1` |
| `.exe` won't start; `-1073741515` or `libgfortran-5.dll was not found` | Run after the `$env:Path` line, or rebuild with `-static` |
| Wrong compiler version | Another tool is first on the PATH; see section 1 |
| `SWAT revision: unknown` | Harmless; add `-DSWAT_VERSION=695` |
| Run stops immediately, no `fin.fin` | Run from inside your `TxtInOut` folder |
| Output like `0.6056-310`, or results that change between runs or shells | Uninitialized memory. Reconfigure so the summary shows `Zero-fill heap: ON`, and rebuild |
| Changes have no effect | Delete `build` and rebuild |

## Appendix A — The three source fixes

All three are in the **original** SWAT files (revisions 693 and 695).
You don't need this to compile.

1. **Name collisions (8 files: `atri.f`, `regres.f`, `tair.f`, `vbl.f`, `ndenit.f`, `rsedaa.f`, `layersplit.f`, `HQDAV.f90`).**
   `modparm.f` ends with interfaces for about fifteen routines.
   Eight are also written in files starting with `use parm`, so each imports a description of itself.
   Intel accepts this; gfortran refuses.
   The fix renames the import: `use parm, except_this_one => atri`.
2. **Unequal text lengths (`header.f`).**
   Fortran requires equal-length items in an array constructor.
   Intel pads silently; gfortran stops.
   The fix pads with spaces, keeping headings aligned.
3. **Missing comma (`std3.f`).**
   `t97'---'` should be `t97,'---'`.
   The compile succeeds, but gfortran stops in year 1 with `Missing comma between descriptors`.

## Appendix B — Cheat sheet

From the project folder.
Full compile (does nothing if you are in the wrong folder):

```powershell
if (Test-Path .\CMakeLists.txt) {
    $env:Path = "C:\msys64\mingw64\bin;" + $env:Path
    powershell -ExecutionPolicy Bypass -File .\apply-gfortran-fixes.ps1
    cmake -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -S . -B build
    cmake --build build
} else {
    Write-Warning "CMakeLists.txt not found in $(Get-Location). Open PowerShell in the project folder."
}
```

- **Standalone `.exe`:** add `-DSWAT_EXTRA_FLAGS="-static"` to the configure line.
- **Zero-filled heap:** on by default; check for `Zero-fill heap: ON` in the configure output.
- **After editing a source file:** `cmake --build build`
- **Start over:** `Remove-Item -Recurse -Force build`
- **Output location:** `build\executable\`
