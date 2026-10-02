<#
.SYNOPSIS
    Apply the three known gfortran portability fixes to a stock SWAT source tree.

.DESCRIPTION
    Stock SWAT sources are maintained against Intel Fortran, which is more permissive
    than gfortran in three specific ways. This script finds and fixes all three.
    See COMPILE_GUIDE.md section 6 for the full explanation of each.

      1. parm INTERFACE collisions   -> use parm, except_this_one => <name>
      2. Unequal CHARACTER lengths   -> pad literals in a (/ ... /) constructor
         in an array constructor        to a common width, whitespace only
      3. FORMAT descriptor missing   -> insert the comma:  t97,'---'
         a comma after tN

    The script is idempotent: running it on an already-fixed tree changes nothing.
    Only whitespace inside string literals is ever adjusted; no other characters
    are added or removed except the inserted commas and rename clauses.

.PARAMETER SrcDir
    Source folder to patch. Defaults to 'src' next to this script.

.PARAMETER DryRun
    Report what would change without writing any files.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\apply-gfortran-fixes.ps1

    The -ExecutionPolicy Bypass form works even where PowerShell blocks scripts.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\apply-gfortran-fixes.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$SrcDir,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not $SrcDir) { $SrcDir = Join-Path $PSScriptRoot 'src' }
if (-not (Test-Path -PathType Container $SrcDir)) {
    throw "Source directory not found: $SrcDir"
}
$SrcDir = (Resolve-Path $SrcDir).Path

Write-Host "Source directory: $SrcDir"
if ($DryRun) { Write-Host "DRY RUN - no files will be written" -ForegroundColor Yellow }
Write-Host ""

$files = Get-ChildItem -Path $SrcDir -File | Where-Object { $_.Extension -in '.f', '.f90' }
if ($files.Count -eq 0) { throw "No .f or .f90 files found in $SrcDir" }

$changed = [System.Collections.Generic.HashSet[string]]::new()
$report  = [System.Collections.Generic.List[string]]::new()

function Save-File([string]$Path, [string]$Text) {
    if (-not $DryRun) {
        # keep CRLF line endings and write without a BOM, as the sources use
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }
    [void]$changed.Add($Path)
}

# ----------------------------------------------------------------------------
# Fix 1 - procedures that collide with the parm INTERFACE block
# ----------------------------------------------------------------------------
Write-Host "[1/3] parm INTERFACE collisions" -ForegroundColor Cyan

$modparm = Join-Path $SrcDir 'modparm.f'
$n1 = 0
if (Test-Path $modparm) {
    $mpText = [System.IO.File]::ReadAllText($modparm)

    # isolate the INTERFACE ... END INTERFACE block
    $ifMatch = [regex]::Match($mpText, '(?is)\n[ \t]*interface[ \t]*\r?\n(.*?)\n[ \t]*end[ \t]*interface')
    if ($ifMatch.Success) {
        $ifBody = $ifMatch.Groups[1].Value

        # procedure names declared inside it
        $names = [regex]::Matches($ifBody,
            '(?im)^[ \t]*(?:real\*8[ \t]+)?(?:function|subroutine)[ \t]+([A-Za-z]\w*)') |
            ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

        foreach ($nm in $names) {
            # match the implementing file case-insensitively (e.g. HQDAV.f90)
            $impl = $files | Where-Object { $_.BaseName -ieq $nm } | Select-Object -First 1
            if (-not $impl) { continue }

            $text = [System.IO.File]::ReadAllText($impl.FullName)

            # a bare `use parm` on its own line - no rename clause present
            $bare = [regex]::Match($text, '(?im)^([ \t]*use[ \t]+parm)[ \t]*(\r?)$')
            if (-not $bare.Success) { continue }

            # use the real basename so the symbol keeps its original casing
            $sym = $impl.BaseName
            $new = $text.Remove($bare.Index, $bare.Length).Insert(
                       $bare.Index, $bare.Groups[1].Value + ", except_this_one => $sym" + $bare.Groups[2].Value)

            Save-File $impl.FullName $new
            $line = ($text.Substring(0, $bare.Index) -split "`n").Count
            $report.Add("  $($impl.Name):$line  use parm, except_this_one => $sym")
            $n1++
        }
    }
    else { Write-Host "  (no INTERFACE block found in modparm.f)" }
}
else { Write-Host "  (modparm.f not found - skipped)" }

if ($n1 -eq 0) { Write-Host "  nothing to fix" } else { $report | ForEach-Object { Write-Host $_ } }
$report.Clear()

# ----------------------------------------------------------------------------
# Fix 2 - unequal CHARACTER lengths inside a (/ ... /) array constructor
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "[2/3] CHARACTER lengths in array constructors" -ForegroundColor Cyan

$n2 = 0
foreach ($f in $files) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    if ($text -notmatch '\(/') { continue }

    $out      = $text
    $fileEdit = $false

    # each (/ ... /) region, processed right-to-left so offsets stay valid.
    # (?!/) rejects Fortran's  (//  FORMAT idiom, which would otherwise match
    # here and run on until some unrelated  /)  far below.
    $regions = [regex]::Matches($text, '(?s)\(/(?!/)(.*?)/\)') | Sort-Object { $_.Index } -Descending
    foreach ($rg in $regions) {
        $body = $rg.Groups[1].Value
        $lits = [regex]::Matches($body, '"[^"]*"')
        if ($lits.Count -lt 2) { continue }

        # Only touch a PURE character array constructor: once the literals are
        # removed, nothing may be left but separators and continuation markers.
        # Anything else means we matched executable code, not a constructor.
        $skeleton = [regex]::Replace($body, '"[^"]*"', '')
        if ($skeleton -match '[^\s,&]') { continue }

        $lens = $lits | ForEach-Object { $_.Value.Length - 2 }
        if (($lens | Select-Object -Unique).Count -le 1) { continue }   # already uniform

        # target = most common length (ties -> longest), matching the column layout
        $target = ($lens | Group-Object | Sort-Object Count, Name -Descending |
                   Select-Object -First 1).Name -as [int]

        # verify every literal can reach the target using whitespace only
        $plan = @()
        $ok   = $true
        foreach ($lit in $lits) {
            $inner = $lit.Value.Substring(1, $lit.Value.Length - 2)
            $delta = $target - $inner.Length
            if ($delta -eq 0) { $plan += $inner; continue }
            if ($delta -gt 0) {
                $plan += ($inner + (' ' * $delta))            # pad right
            }
            else {
                $need = -$delta
                $lead = $inner.Length - $inner.TrimStart(' ').Length
                $trail = $inner.Length - $inner.TrimEnd(' ').Length
                if ($lead + $trail -lt $need) { $ok = $false; break }
                $takeLead = [Math]::Min($lead, $need)
                $s = $inner.Substring($takeLead)
                $need -= $takeLead
                if ($need -gt 0) { $s = $s.Substring(0, $s.Length - $need) }
                $plan += $s
            }
        }
        if (-not $ok) {
            Write-Host "  $($f.Name): literals cannot be equalised by whitespace alone - SKIPPED" -ForegroundColor Yellow
            continue
        }

        # rebuild the region body, replacing literals right-to-left
        $newBody = $body
        for ($i = $lits.Count - 1; $i -ge 0; $i--) {
            $lit = $lits[$i]
            $newBody = $newBody.Remove($lit.Index, $lit.Length).Insert($lit.Index, '"' + $plan[$i] + '"')
        }

        $lineNo = ($text.Substring(0, $rg.Index) -split "`n").Count
        $out = $out.Remove($rg.Index, $rg.Length).Insert($rg.Index, '(/' + $newBody + '/)')
        $fileEdit = $true
        $report.Add("  $($f.Name): array constructor near line $lineNo -> all literals padded to $target chars")
        $n2++
    }

    if ($fileEdit) { Save-File $f.FullName $out }
}
if ($n2 -eq 0) { Write-Host "  nothing to fix" } else { $report | ForEach-Object { Write-Host $_ } }
$report.Clear()

# ----------------------------------------------------------------------------
# Fix 3 - FORMAT descriptor missing a comma after tN
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "[3/3] FORMAT descriptors missing a comma" -ForegroundColor Cyan

$n3 = 0
foreach ($f in $files) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    if ($text -notmatch "[,(][tT]\d+'") { continue }

    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $text -split "`r?`n"
    $edit = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($ln -match '^[cC*!]') { continue }                 # fixed-form comment
        if ($ln -notmatch "[,(][tT]\d+'") { continue }
        $lines[$i] = [regex]::Replace($ln, "([,(][tT]\d+)'", "`$1,'")
        $report.Add("  $($f.Name):$($i+1) -> comma inserted after tN")
        $edit = $true
        $n3++
    }

    if ($edit) { Save-File $f.FullName ($lines -join $nl) }
}
if ($n3 -eq 0) { Write-Host "  nothing to fix" } else { $report | ForEach-Object { Write-Host $_ } }

# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "Summary: $n1 rename(s), $n2 array constructor(s), $n3 FORMAT comma(s) - $($changed.Count) file(s) touched" -ForegroundColor Green
if ($DryRun) { Write-Host "DRY RUN - nothing was written" -ForegroundColor Yellow }
if (-not $DryRun -and $changed.Count -gt 0) {
    Write-Host "Next, compile (see COMPILE_GUIDE.md, section 4):"
    Write-Host '  cmake -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -S . -B build'
    Write-Host '  cmake --build build'
}
