# Daily soil P pool output per soil layer (`output.snu`) – how to change the source

**Goal:** for every HRU, **every soil layer** and **every simulated day**, print the six SWAT soil P pools
(3 inorganic + 3 organic) in kg P/ha. Layers are **not summed**; no year column; no mg/kg concentrations.

> **Status (checked 2 Oct 2026):** the changes below are **not yet in `src/`**. `src/soil_write.f` and the
> `output.snu` header in `src/readfile.f` (lines 492–500) are still the original SWAT2012 code. The code in
> section 4 was built into the full model and run on `baseline_calibrated` (10 years, 51 HRUs) – see
> section 8 for the results.

---

## 1. The six P pools – theory ↔ code

Neitsch et al. (2011), section 3:2 ("SWAT monitors six different pools of phosphorus in the soil … three
pools are inorganic … the other three pools are organic"):

| # | Pool (theory, Fig. 3:2‑2) | Type | SWAT variable (kg P/ha, layer `l`, HRU `j`) | Equation / where it changes |
|---|---------------------------|------|-------------------------------------------|-----------------------------|
| 1 | Solution P | inorganic | `sol_solp(l,j)` | init. 5 mg/kg (3:2.1); `pminrl`/`pminrl2`, `solp`, `nminrl`, `fert` |
| 2 | Active mineral P | inorganic | `sol_actp(l,j)` | init. eq. 3:2.1.1; solution↔active sorption (3:2.3) in `pminrl`/`pminrl2` |
| 3 | Stable mineral P | inorganic | `sol_stap(l,j)` | init. in `soil_chem.f:265–279`: `SOL_P_MODEL = 1` → eq. 3:2.1.2 (= 4 × active); `SOL_P_MODEL = 0` (default) → White et al. (2009), stable = SSP × (active + solution) with SSP = 25.044 (actP + solP)^‑0.3833 limited to 1–7; active↔stable in `pminrl`/`pminrl2` |
| 4 | Fresh organic P (residue + microbial) | organic | `sol_fop(l,j)` | init. eq. 3:2.1.4 (layer 1 only); decay eq. 3:2.2.10–11 in `nminrl` |
| 5 | Active (humic) organic P | organic | **not stored** – derived: `sol_orgp × sol_aorgn / (sol_aorgn + sol_orgn)` | eq. 3:2.2.3 |
| 6 | Stable (humic) organic P | organic | **not stored** – derived: `sol_orgp × sol_orgn / (sol_aorgn + sol_orgn)` | eq. 3:2.2.4 |

All of these arrays are dimensioned `(mlyr, mhru)` (`modparm.f`, `allocate_parms.f`), i.e. **each value is the
amount in one soil layer**. A profile total only exists if the layers are summed, which this version
deliberately does not do.

About pools 5–6: the code keeps **one** humic organic P array, `sol_orgp` (initialised as 0.125 × humic org N,
eq. 3:2.1.3, `soil_chem.f:232`). The active/stable split of eq. 3:2.2.3–3:2.2.4 is done only during
mineralization (`nminrl.f:232–234`: `hmp = 1.4 * hmn * sol_orgp / (sol_orgn + sol_aorgn)`), using the active
(`sol_aorgn`) and stable (`sol_orgn`) humic organic N pools of the same layer. The output routine reproduces
that split per layer, so `AORGP + SORGP = sol_orgp` exactly.

Effect of `CSWAT` (`basins.bsn`, `subbasin.f:326–337`):

| `CSWAT` | Organic routine | Pools printed |
|---------|-----------------|---------------|
| 0 (default, baseline) | `nminrl.f` (theory ch. 3:1–3:2) | all six exactly as in the theory |
| 1 | `carbon_new.f` | humic split not used → `AORGP` = 0, all humic P in `SORGP`. The extra manure organic P pool `sol_mp` is **not** printed. |
| 2 | `carbon_zhang2.f90` | humic split not used → `AORGP` = 0, all humic P in `SORGP` |

Inorganic P transformations use `pminrl.f` when `SOL_P_MODEL = 1` and `pminrl2.f` otherwise
(`subbasin.f:342–346`, `readbsn.f:586`). The output works for both.

## 2. Where the output comes from in the current source

| What | File : line | Notes |
|------|-------------|-------|
| `ISOL` read from `file.cio`; `output.snu` opened on unit 121 and header written | `readfile.f:488–500` | Arnold et al. (2013): "ISOL – Code for printing phosphorus/nitrogen in soil profile, 0 = no print, 1 = print" |
| Daily call | `simulate.f:273` `if (isol == 1) call soil_write` | Inside the **daily** loop, after `command` and `writed`, inside `if (curyr > nyskip)` |
| Writing routine | `soil_write.f` | Loops over all HRUs |
| Pool arrays | `modparm.f:382–392` | `sol_actp, sol_stap, sol_solp, sol_orgp, sol_fop`; `sol_aorgn`, `sol_orgn` for the split |
| Layer depth | `sol_z(l,j)` (`modparm.f:384`) | Depth from the surface to the **bottom** of layer `l` (mm) |
| 10 mm surface layer | `soil_par.f:80–97` | Inserts a 10 mm layer 1 when the first input layer is > 10.1 mm |

So **daily, per‑HRU output already exists**: `soil_write` is called every day for every HRU once
`curyr > nyskip`. Only `soil_write.f` and the header in `readfile.f` change; `simulate.f` does **not**.

Printed values are **end‑of‑day** states: the call comes after `command` → `subbasin` → (`nminrl`,
`pminrl`/`pminrl2`, `psed`, `solp`, …) for every HRU on that day.

## 3. Summary of changes

| File | Routine | Change |
|------|---------|--------|
| `src/soil_write.f` | `soil_write` | Replace the whole file with section 4.1. Writes one line per HRU **per layer** with `DAY`, `GISnum`, `LAYER`, `SOL_Z` and the six P pools of that layer. |
| `src/readfile.f` | `readfile` | Replace the header format `12222` (lines 495–499) with section 4.2. |
| `src/simulate.f` | – | **No change.** Already daily. |

**The original `output.snu` columns are no longer written** (`SOL_RSD`, `SOL_P`, `NO3`, `ORG_N`, `ORG_P`, `CN`).
`SOL_P` and `ORG_P` were profile sums, and the other four are HRU‑level values that do not fit a per‑layer
line. Scripts that read the old `output.snu` must be updated.

No model state is modified: values are only read into a local array (unlike the Muenich et al. SI
`soil_write2`, which clamped `sol_solp/actp/stap` to ≥ 1e‑6 inside the output routine and therefore changed the
simulation).

## 4. Code

### 4.1 New `src/soil_write.f` (complete file)

All code lines are ≤ 72 columns and contain no tab characters, so it compiles with any of the line‑length flags
in `CMakeLists.txt`.

```fortran
      subroutine soil_write

!!    ~ ~ ~ PURPOSE ~ ~ ~
!!    this subroutine writes daily soil P pool output to output.snu
!!    (unit 121, opened in readfile.f when ISOL = 1).
!!    One line per HRU per soil layer per day with the six SWAT soil
!!    P pools (Neitsch et al., 2011, section 3:2, Fig. 3:2-2) of that
!!    layer in kg P/ha. Layers are NOT summed.

!!    ~ ~ ~ LOCAL DEFINITIONS ~ ~ ~
!!    name        |units         |definition
!!    ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
!!    lyr_p(6)    |kg P/ha       |P pools in soil layer l of HRU j
!!    pool order: 1 solution P          (sol_solp)       inorganic
!!                2 active mineral P    (sol_actp)       inorganic
!!                3 stable mineral P    (sol_stap)       inorganic
!!                4 fresh organic P     (sol_fop)        organic
!!                5 active humic org P  eq. 3:2.2.3      organic
!!                6 stable humic org P  eq. 3:2.2.4      organic
!!    xx          |kg N/ha       |active + stable humic organic N
!!    ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

!!    ~ ~ ~ ~ ~ ~ END SPECIFICATIONS ~ ~ ~ ~ ~ ~

      use parm

      integer :: j, l
      real*8 :: lyr_p(6), xx

      do j = 1,nhru
        do l = 1,sol_nly(j)
          !! P pools of layer l (read only, no state change)
          lyr_p(1) = sol_solp(l,j)
          lyr_p(2) = sol_actp(l,j)
          lyr_p(3) = sol_stap(l,j)
          lyr_p(4) = sol_fop(l,j)
          !! humic org P split with active/stable org N (eq 3:2.2.3-4)
          lyr_p(5) = 0.
          xx = sol_aorgn(l,j) + sol_orgn(l,j)
          if (cswat == 0 .and. xx > 1.e-6) then
            lyr_p(5) = sol_orgp(l,j) * sol_aorgn(l,j) / xx
          end if
          lyr_p(6) = sol_orgp(l,j) - lyr_p(5)

          write (121,1000) i, subnum(j), hruno(j), l, sol_z(l,j),
     &      lyr_p
        end do
      end do
      
      return
 1000 format ('SNU   ',i4,1x,a5,a4,i6,f10.1,6f12.4)
      end
```

### 4.2 `src/readfile.f` – new header (replace lines 495–499)

Replace **lines 495 to 499** (the 5 lines of the old `12222` format statement). Keep line 494 above them and
line 500 (`end if`) below them unchanged.

Current code (`src/readfile.f`, lines 492–500, unmodified source). Line numbers are shown on the left; they are
not part of the file:

```fortran
492        if (isol == 1) then
493           open (121,file='output.snu')
494           write (121,12222)                                          <- keep
495  12222   format (t25,'SURFACE',t39,'-------  SOIL PROFILE  -------',/,   <- replace from here
496       &  t8,'DAY',t15,'GISnum',t25,'SOL_RSD',t37,'SOL_P',t48,
497       &  'NO3',t57,'ORG_N',t67,'ORG_P',t80,'CN'/,t26,
498       &  '(t/ha)',t35,'(kg/ha)',t45,
499       &  '(kg/ha)',t55,'(kg/ha)',t66,'(kg/ha)')                     <- ... to here
500        end if                                                         <- keep
```

Replace lines 495–499 with these 4 lines:

```fortran
12222 format (t7,'DAY',t15,'GISnum',t22,'LAYER',t32,'SOL_Z',
     &  t45,'SOLP',t57,'ACTP',t69,'STAP',t80,'FRSHP',t92,'AORGP',
     &  t104,'SORGP',/,t33,'(mm)',t42,'(kg/ha)',t54,'(kg/ha)',
     &  t66,'(kg/ha)',t78,'(kg/ha)',t90,'(kg/ha)',t102,'(kg/ha)')
```

After the change the new format ends on line 498 and `end if` moves up from line 500 to line 499 (the new format
is one line shorter). Fortran fixed form: the label `12222` starts in column 1, the `&` continuation character is
in column 6, and no line may go past column 72 (all four lines above are within that limit).

## 5. Output layout (`output.snu`)

Two header lines, then **one line per HRU per soil layer per day** (108 characters). For each day the lines
are ordered HRU 1 layer 1…n, HRU 2 layer 1…n, etc. A new year starts when `DAY` goes back to 1.

| Characters | Column | Meaning | Unit |
|------------|--------|---------|------|
| 7–10 | `DAY` | Julian day | |
| 12–20 | `GISnum` | Subbasin (5) + HRU (4) | |
| 21–26 | `LAYER` | Soil layer number (1 = surface, normally 10 mm) | |
| 27–36 | `SOL_Z` | Depth to the bottom of the layer | mm |
| 37–48 | `SOLP` | Solution P (`sol_solp`) | kg P/ha |
| 49–60 | `ACTP` | Active mineral P (`sol_actp`) | kg P/ha |
| 61–72 | `STAP` | Stable mineral P (`sol_stap`) | kg P/ha |
| 73–84 | `FRSHP` | Fresh organic P (`sol_fop`) | kg P/ha |
| 85–96 | `AORGP` | Active humic organic P (eq. 3:2.2.3) | kg P/ha |
| 97–108 | `SORGP` | Stable humic organic P (eq. 3:2.2.4) | kg P/ha |

Example (mock data):

```
      DAY     GISnum LAYER     SOL_Z        SOLP        ACTP        STAP       FRSHP       AORGP       SORGP
                                (mm)     (kg/ha)     (kg/ha)     (kg/ha)     (kg/ha)     (kg/ha)     (kg/ha)
SNU      5 000010001     1      10.0      1.0000      2.0000      8.0000      0.5000      0.2000      9.8000
SNU      5 000010001     2     300.0      1.0000      2.0000      8.0000      0.5000      0.2000      9.8000
```

Pool columns are `f12.4` (4 decimals so very small pools in a no‑P scenario are not rounded to zero). The file
is whitespace‑delimited, so it can be read with e.g. `pandas.read_csv(..., sep=r"\s+", skiprows=2, header=None)`.

## 6. How to apply and check

1. Back up `src/soil_write.f` and `src/readfile.f` (or commit first – the folder is a git repo).
2. Replace `soil_write.f` with 4.1; replace the `12222` format in `readfile.f` with 4.2.
3. Rebuild (see `COMPILE_GUIDE.md`): in PowerShell
   `$env:Path = "C:\msys64\mingw64\bin;" + $env:Path` then `cmake --build build`.
4. In `file.cio` set `ISOL = 1`; set `NYSKIP = 0` if the warm‑up years should be printed too.
5. Checks on the output:
   - number of data lines per day = Σ over HRUs of the number of layers (`sol_nly`); every line 108 characters;
   - `SOL_Z` increases with `LAYER` within each HRU, and layer 1 is 10 mm (unless the soil's first input layer
     is already ≤ 10.1 mm);
   - first printed day (no warm‑up): with `SOL_P_MODEL = 1`, `STAP ≈ 4 × ACTP` in every layer (eq. 3:2.1.2); with
     `SOL_P_MODEL = 0` (default) `STAP / (ACTP + SOLP)` is between 1 and 7 (`soil_chem.f:265–275`);
   - `CSWAT = 0`: `AORGP / (AORGP + SORGP)` ≈ `NACTFR` (default 0.02, `readbsn.f:734`) early in the run;
   - `FRSHP` is non‑zero only in layer 1 at the start (eq. 3:2.1.4) and moves deeper after tillage/residue input.

## 7. Things to be aware of

- **Layer thickness** of layer `l` = `SOL_Z(l) − SOL_Z(l−1)` (layer 1: `SOL_Z(1)`).
- **Profile or top‑layer totals** are not printed; compute them afterwards by summing the rows of one HRU/day
  (profile) or taking `LAYER = 1` (10 mm surface layer).
- **Concentrations (mg P/kg)** are not printed. If needed later, mg/kg = kg/ha ÷ `conv_wt(l,j)` × 10⁶
  (`soil_chem.f:207`), and it must be done per layer.
- **File size.** ≈ 109 bytes × HRUs × layers × days. For 51 HRUs with ~5 layers that is ≈ 10 MB per simulated
  year (≈ 100 MB for 10 years). Use `NYSKIP` to skip warm‑up years.
- **Active/stable humic organic P are diagnostic.** They are computed for output from the N ratio exactly as the
  model uses them in `nminrl.f`; they are not separate state variables in the code.

## 8. Test run (2 Oct 2026)

The code in section 4 was built and run in a copy of the project (the files in `src/` and
`baseline_calibrated/` on disk were **not** changed).

- **Build:** gfortran 13.3 (Linux) with the project `CMakeLists.txt`, once with the unmodified `src/` and once with
  `soil_write.f` and the `readfile.f` header replaced. Both built with no errors. Note: this compiler needed
  `-DCMAKE_Fortran_FLAGS="-ffree-line-length-none"` for `carbon_zhang2.f90` line 329 (unrelated to these
  changes; the Windows/MSYS2 build does not need it).
- **Run:** `baseline_calibrated`, full 10 years (2014–2023, `NYSKIP = 0`, `ISOL = 1`, `CSWAT = 0`,
  `SOL_P_MODEL = 0`). Both runs: "Execution successful".
- **`output.snu` changed as intended:** 2 header lines + 850,916 data lines = 233 layer rows/day (51 HRUs with
  4, 5 or 6 layers) × 3,652 days; every line 108 characters; layer 1 is 10 mm in every HRU. File size 92.8 MB
  (original format: 15.3 MB).
- **Simulation unchanged:** `output.hru`, `output.rch`, `output.sub`, `output.sed`, `output.std` and `watout.dat`
  are byte‑identical between the original and modified builds.
- **Values agree with the original output:** for every HRU and day, Σ layers `SOLP` = original `SOL_P` and
  Σ layers (`AORGP + SORGP`) = original `ORG_P` (max difference 0.005 = 2‑decimal rounding of the original file).
- **Plausibility:** no negative pools; on day 1 `AORGP / (AORGP + SORGP)` = 0.020 (= `NACTFR`) in every layer;
  `FRSHP` is 0 on day 1 and rises after residue input (max 16.6 kg/ha); HRU 1 layer 1 `SOLP` goes from 4.86
  (day 1, 2014) to 7.70 kg/ha (end of 2023).
- **Platform note:** the unmodified Linux build reproduces the existing Windows `baseline_calibrated/output.snu`
  exactly for the first ~470 simulated days, after which small floating‑point differences between compilers
  appear (e.g. `SOL_P` within 0.85 kg/ha). This is a compiler difference, not caused by the change.

## References

- Neitsch, S.L., Arnold, J.G., Kiniry, J.R., Williams, J.R. (2011). *SWAT Theoretical Documentation, Version
  2009*, Chapter 3:2 "Phosphorus" (`markitdown/Neitsch_2011.md`): pools (Fig. 3:2‑2), initialization
  eq. 3:2.1.1–3:2.1.5, humus mineralization eq. 3:2.2.3–3:2.2.4, residue decomposition eq. 3:2.2.10–3:2.2.11,
  sorption 3:2.3.
- Arnold, J.G. et al. (2013). *SWAT 2012 Input/Output Documentation* (`markitdown/Arnold_2013.md`): `ISOL`
  in `file.cio`.
- Muenich et al., Supporting Information, section 3 "Estimating the SWAT soil test phosphorus value".
