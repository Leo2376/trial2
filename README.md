tests folder contains non reg testcase for the mylittleda.tcl

source run_test.sourceme exexcite test_case and resutlsa rein their respective outputs folder.

## Development environment setup

The tool is written in Tcl/Tk. The sandbox does not ship with it preinstalled,
so install it once per session before running anything (passwordless sudo is
available):

```sh
sudo apt-get update
sudo apt-get install -y tcl tk-dev tcl-dev xvfb
```

Verify the install (note: Tk needs a display, so it only loads with an X server
or `xvfb`; the batch test path below does not require Tk):

```sh
echo 'puts "Tcl [info patchlevel]"; exit' | tclsh
```

## Running the tests (batch mode, no GUI needed)

`mylittleda.tcl` runs in batch mode by default. GUI mode is opt-in via the
`-gui` flag (`tclsh mylittleda.tcl -gui`) and requires a display.

For a quick headless GUI smoke test, run under the X virtual framebuffer
(`xvfb` provides a fake `$DISPLAY` so Tk can initialize without a physical
screen):

```sh
xvfb-run -a tclsh mylittleda.tcl -gui
```

Run the full regression suite:

```sh
bash -c 'source run_test.sourceme'
```

Each test writes `.lef` / `.def` / `.lib` / `.dc_floorplan.tcl` artifacts into
its own `tests/<test>/outputs/` folder (these are gitignored).

## Technology Liberty (`.lib`)

The technology library file `liberty_files/n7_tech.lib` is a static,
minimal Liberty file covering every std cell and SRAM defined in `lef_files/`.
It carries no real timing tables (all scalar `0.1`, units ns / pf / uW). The
only timing intent it encodes is the set of synchronous (clock) pins of
sequential cells, tagged with `clock : true;`:

- `CP` for every flop (e.g. `DFQD0BWP300H8P64PDLVT`).
- `CLK` for every SRAM (e.g. `TS1N7HSLVTA128X33M2WBZHOCP`).

To regenerate the file from the LEFs after editing `lef_files/`:

```sh
tclsh8.6 scripts/gen_tech_lib.tcl lef_files/*.lef > liberty_files/n7_tech.lib
```

`add_lib <file>` loads a `.lib` and stores, per library cell, the set of sync
pins in the `_libsyncpin` attribute. Query it with `get_sync_pins <cell>`.
This is the foundation for the proposed sync-to-sync path report (`R1`).

## Upgrade roadmap

Proposed upgrades for the tool. Status starts at `proposal` and moves to
`started` -> `implemented` -> `verified` as work progresses.

| ID  | Area        | Description                                                                 | Status     |
|-----|-------------|-----------------------------------------------------------------------------|------------|
| P1  | Path tracing| Capture pin directions (INPUT/OUTPUT/INOUT) from LEF in `add_lef`           | implemented |
| P2  | Path tracing| Build a net driver/receiver map (per net: driver pin(s), receiver pins)     | implemented |
| P3  | Path tracing| `report_path -from <pin/net> -to <pin/net>`: text-only connectivity report  | implemented |
|     |             | (report_timing-style listing of crossed cells/pins/nets, no timing)         |            |
| P5  | Path tracing| `report_path ... -layout`: add an (x, y) coordinate column for crossed      | proposal   |
|     |             | cells/pins; nets have no coordinate and stay blank.                        |            |
| P6  | Path tracing| `report_path ... -net`: also print the logical nets crossed; by default only | proposal   |
|     |             | the pins are reported.                                                      |            |
| P4  | Path tracing| `report_path -from <pin/net>` (no `-to`): trace forward to the first sync   | proposal   |
|     |             | endpoint (flop CP / SRAM CK via `_libsyncpin`); stop at first found, not the  |            |
|     |             | longest, and report how many paths reach a sync endpoint. Depends on L2.   |            |
| S1  | Performance | Convert `wiresearch` list to an array/dict map for O(1) net lookup          | implemented |
|     |             | (replaces O(n) `lsearch` in `update_wire_db` / `list_all_pins`)            |            |
| S2  | Performance | Convert `pathlist` / `hpathlist` to index maps for O(1) instance lookup    | proposal   |
| S3  | Performance | Convert `hierlist` / `cataloglist` to refname->index maps                  | proposal   |
| S4  | Performance | Pair `_instpinconn1/2` into single per-instance lists for direct `foreach` | proposal   |
| G1  | Robustness  | Add consistent `_require` guards to all state-touching commands            | proposal   |
| G6  | Robustness  | Better options handling: let multi-arg commands take options in any order  | proposal   |
|     |             | (e.g. `report_path -to <p> -from <p>` same as `-from <p> -to <p>`)           |            |
| G4  | Reporting   | `report_net` / `report_pin` helper (driver, receivers, connected insts)    | proposal   |
| G5  | Robustness  | Harden `read_netlist` `/`-skip parsing                                       | proposal   |
| L1  | Liberty     | Static technology `.lib` for std cells + SRAMs (sync pins only, no timing)  | implemented |
|     |             | (`CP` for flops, `CLK` for SRAMs) via `clock : true;` (see `liberty_files/`)  |            |
| L2  | Liberty     | `add_lib` parser recovers sync (clock) pins only into `_libsyncpin` attr   | implemented |
|     |             | (no timing tables); query with `get_sync_pins <cell>`                     |            |
| R1  | Reporting   | `report_sync`: sync-to-sync `report_path` between flop CP / SRAM CK         | proposal   |
|     |             | endpoints using the `_libsyncpin` attribute                                |            |
| R2  | Reporting   | `trace_clock <pin/net>`: tree-like report tracing from a pin or net to all  | proposal   |
|     |             | branches down to leaf sync pins (flop CP / SRAM CK). Depends on L2.        |            |
| R3  | Reporting   | `all_connected <net or pin>`: report all nets connected to a net/pin;      | proposal   |
|     |             | accepts wildcards (e.g. `all_connected n2*`).                           |            |
| R4  | Reporting   | `get_cell <pattern>`: report all cells matching a pattern (e.g. `*reg*`);   | implemented |
|     |             | handles hierarchy by scope (e.g. `get_cell core0/c0/*reg*` lists cells in  |            |
|     |             | that scope). Add `-hier` for a cross-hierarchy match.                   |            |
| R5  | Reporting   | `get_net <pattern>`: report all nets matching a pattern (e.g. `n2*`);     | implemented |
|     |             | handles hierarchy by scope (e.g. `get_net core0/w0/nv_c0/c0/*` lists nets |            |
|     |             | declared in that scope). Add `-hier` for a cross-hierarchy match.        |            |
| N1  | Netlist I/O | `write_verilog <file>`: dump the loaded netlist back out as Verilog         | proposal   |
|     |             | (modules, ports, wires, leaf-cell instances and hierarchical instances,   |            |
|     |             | `assign` statements). Preserves hierarchy so a `read_netlist` ->           |            |
|     |             | `write_verilog` round-trip is the verification testcase.                   |            |

Notes:
- P1 enables P2, which enables P3. S1 also produces the indexed net map P3
  traverses, so P1 -> S1 -> P2 -> P3 is a sensible execution order.
- L1 + L2 provide the sync-pin attribute that R1 needs, so L1 -> L2 -> R1 is
  the execution order for the timing-intent track.
- Performance items (S*) must preserve exact `lsearch` semantics (first match,
  duplicate handling, rebuild-on-mutation) and be verified by the regression
  suite before their status moves to `verified`.
- N1 (write_verilog) is verified by a read -> dump round-trip: read a design
  with `read_netlist`, write it back with `write_verilog`, then re-read the
  dumped file and check that the module/port/wire/instance/assign structure
  matches. test5_path (flat, with `assign`) and a hierarchical design
  (test4_hierarchical) are the natural round-trip cases.

## Connectivity query commands

After `build_design` (and `update_wire_db` / `build_net_conn` for the net
queries), the following report connectivity. Patterns are globs
(`*`, `?`, `[..]`); a hierarchical prefix scopes the match to one module.

- `report_path -from <pin|net> -to <pin|net>` — text-only connectivity report
  (report_timing-style, no timing) across the net driver/receiver map.
- `all_connected <net or pin>` — for a net pattern, list every matching net
  with its driver and receiver pins; for an `inst/pin`, report that pin's
  net. Net names are scoped by their containing module's path, so a full
  hierarchical net reference reports only that scope's net.
- `get_cell <pattern> ?-hier?` — list cells (leaf and hierarchical) whose
  full instance path matches. Without `-hier` only the direct children of
  the scope implied by the pattern are reported (`get_cell *` = top level
  only); `-hier` matches across the whole hierarchy.
- `get_net <pattern> ?-hier?` — list nets whose scoped name matches, with
  their driver/receiver counts. Without `-hier` only the nets of the single
  scope implied by the pattern are reported (`get_net *` = top-level nets
  only, `get_net core0/w0/nv_c0/c0/*` = nets in that module); `-hier`
  matches across the whole hierarchy.
