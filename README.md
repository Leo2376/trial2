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
| P5  | Path tracing| `report_path ... -layout`: add an (x, y) coordinate column for crossed      | implemented |
|     |             | cells/pins; nets have no coordinate and stay blank.                        |            |
| P6  | Path tracing| `report_path ... -net`: also print the logical nets crossed; by default only | implemented |
|     |             | the pins are reported.                                                      |            |
| P4  | Path tracing| `report_path -from <pin/net>` (no `-to`): trace forward to the first sync   | implemented |
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
| G4  | Reporting   | `report_net` / `report_pin` helper (driver, receivers, connected insts)    | implemented |
| G5  | Robustness  | Harden `read_netlist` `/`-skip parsing                                       | proposal   |
| L1  | Liberty     | Static technology `.lib` for std cells + SRAMs (sync pins only, no timing)  | implemented |
|     |             | (`CP` for flops, `CLK` for SRAMs) via `clock : true;` (see `liberty_files/`)  |            |
| L2  | Liberty     | `add_lib` parser recovers sync (clock) pins only into `_libsyncpin` attr   | implemented |
|     |             | (no timing tables); query with `get_sync_pins <cell>`                     |            |
| R1  | Reporting   | `report_sync`: sync-to-sync `report_path` between flop CP / SRAM CK         | proposal   |
|     |             | endpoints using the `_libsyncpin` attribute                                |            |
| R2  | Reporting   | `trace_clock <pin/net>`: tree-like report tracing from a pin or net to all  | implemented |
|     |             | branches down to leaf sync pins (flop CP / SRAM CK). Depends on L2.        |            |
| R3  | Reporting   | `all_connected <net or pin>`: report all nets connected to a net/pin;      | implemented |
|     |             | accepts wildcards (e.g. `all_connected n2*`).                           |            |
| R4  | Reporting   | `get_cell <pattern>`: report all cells matching a pattern (e.g. `*reg*`);   | implemented |
|     |             | handles hierarchy by scope (e.g. `get_cell core0/c0/*reg*` lists cells in  |            |
|     |             | that scope). Add `-hier` for a cross-hierarchy match.                   |            |
| R5  | Reporting   | `get_net <pattern>`: report all nets matching a pattern (e.g. `n2*`);     | implemented |
|     |             | handles hierarchy by scope (e.g. `get_net core0/w0/nv_c0/c0/*` lists nets |            |
|     |             | declared in that scope). Add `-hier` for a cross-hierarchy match.        |            |
| R6  | Reporting   | `get_lib_cell <refname>`: report library-cell references whose name matches | implemented |
|     |             | the glob pattern (e.g. `get_lib_cell BUFF*`, `get_lib_cell *DFF*`); an    |            |
|     |             | exact name is a single-cell lookup. Reports name, class, LEF size and the |            |
|     |             | pin list with directions. Queries the loaded library, not the netlist,   |            |
|     |             | so it works as soon as a LEF is imported.                                  |            |
| N1  | Netlist I/O | `write_verilog <file>`: dump the loaded netlist back out as Verilog         | implemented |
|     |             | (modules, ports, wires, leaf-cell instances and hierarchical instances,   |            |
|     |             | `assign` statements). Preserves hierarchy so a `read_netlist` ->           |            |
|     |             | `write_verilog` round-trip is the verification testcase.                   |            |
| N2  | Netlist I/O | `write_db <file>`: dump a binary database containing 100% of the in-memory | implemented |
|     |             | design state - instances, wires, positions, the net connectivity map,    |            |
|     |             | the loaded library (LEF) info, ports, assigns - everything, ready to be   |            |
|     |             | reloaded. The goal is to skip the slow read_netlist / build_design path    |            |
|     |             | and load the whole database faster.                                        |            |
| N3  | Netlist I/O | `restore_db <file>`: reload a binary database written by `write_db`,        | implemented |
|     |             | restoring all variables (instances, wires, positions, connectivity, LEF    |            |
|     |             | library, ports, assigns) so the session is ready immediately without      |            |
|     |             | re-parsing the source netlist or rebuilding the design.                    |            |
| O1  | Optimization| `set_max_fanout <n>`: set a global fanout threshold (max receivers per net)  | implemented |
|     |             | for `fix_max_fanout`.                                                       |            |
| O2  | Optimization| `fix_max_fanout -cell <buffer>`: insert buffers of the given lib cell on   | implemented |
|     |             | nets whose fanout exceeds `set_max_fanout`, splitting the receivers across |            |
|     |             | the buffers so each driver sees at most <n> loads. Uses the netload map     |            |
|     |             | from `build_net_conn`. Depends on P2.                                       |            |
| E1  | ECO         | `create_net <netname>`: create a new net inside a scope (e.g. `create_net   | implemented|
|     |             | core0/w0/c0/n_new`); the trailing token is the net name, the prefix is the  |            |
|     |             | containing hierarchical scope.                                              |            |
| E2  | ECO         | `create_cell <inst_path> <celltype>`: instantiate a lib cell inside a       | implemented|
|     |             | scope (e.g. `create_cell core0/w0/c0/u_buf BUFFD1BWP300H8P64PDLVT`); the   |            |
|     |             | instance path is `<scope>/<instname>`.                                        |            |
| E3  | ECO         | `disconnect_net <net> <pin>`: detach an instance pin from a net; the pin  | implemented|
|     |             | argument is `<inst>/<pin>`. Updates the netload/netdriver map (P2).         |            |
| E4  | ECO         | `connect_net <net> <pin>`: attach an instance pin to a net; the pin         | implemented|
|     |             | argument is `<inst>/<pin>`. Updates the netload/netdriver map (P2).         |            |
| G1  | GUI         | `gui_start`: bring up the Tk GUI after a session that was started in       | proposal   |
|     |             | batch mode (e.g. `tclsh ... -no-gui`), so a design can be loaded and         |            |
|     |             | inspected interactively without relaunching the tool.                        |            |
| H1  | Help        | `help <command>`: print the help/usage of a command; accepts wildcards, so  | proposal   |
|     |             | `help report*` lists every `report_*` command's help and `help *cell*`      |            |
|     |             | lists the help of all commands whose name matches the glob.                  |            |

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
  matches. Implemented in test7_roundtrip: based on test3's medium_design.v
  (hierarchical, with ANSI ports, bus bit-selects and `assign`s), it does a
  read -> `write_verilog` -> re-read -> `write_verilog` round-trip and checks
  the two dumps are byte-identical, so the structure is preserved. Comments
  and line wrapping may differ from the source, but the structural content
  is stable across the round-trip.
- N2 + N3 (binary DB save/restore) are verified by a test that loads a design
  fully (read_netlist -> set_top_design -> build_design -> build_net_conn),
  runs `write_db`, then in a fresh session runs `restore_db` and checks that
  every query command (`get_cell`, `get_net`, `all_connected`, `get_lib_cell`)
  returns identical results to the original session. The saved file must
  contain 100% of the database (instances, wires, positions, the net
  connectivity map, LEF library, ports, assigns) so `restore_db` is a strict
  faster substitute for the parse/build path.
- O1 + O2 (buffer insertion) are verified by a test that builds a net with a
  high-fanout driver, runs `set_max_fanout <n>` then `fix_max_fanout -cell
  <buf>`, and checks via `get_net`/`all_connected` that every net now has at
  most <n> receivers and that the inserted buffers chain the original driver
  to the receivers. Depends on the P2 netload map, so P2 -> O2 is the order.
- E1-E4 (ECO) are verified together: `create_net` a new net, `create_cell` a
  buffer in a scope, `disconnect_net` a pin from its old net and `connect_net`
  it to the new net, then `all_connected`/`get_net` to confirm the old net lost
  the receiver and the new net gained it. E3/E4 mutate the netload map (P2),
  so they require build_net_conn to have run first; the order is P2 -> E4.
  Implemented in test1: the receiver of `core0/w0/nv_c0/c0/iu0/n20719`
  (U28630/A1) is moved to a new net `n_eco` via a freshly created buffer
  `u_eco_buf`, and `all_connected` confirms the old net keeps driver
  U28571/ZN and gains the buffer input while the new net gains the buffer
  output and the moved receiver. A `write_verilog` (N1) dump after the ECO
  will confirm the structural change once N1 is implemented.

## Connectivity query commands

After `build_design` (and `update_wire_db` / `build_net_conn` for the net
queries), the following report connectivity. Patterns are globs
(`*`, `?`, `[..]`); a hierarchical prefix scopes the match to one module.

- `report_path -from <pin|net> -to <pin|net> ?-net? ?-layout?` — text-only
  connectivity report (report_timing-style, no timing) across the net
  driver/receiver map. By default only the crossed pins are listed; `-net`
  also prints the logical nets crossed, and `-layout` adds an `(x, y)`
  coordinate column for placed crossed cells/pins (nets/ports/unplaced cells
  stay blank).
- `report_path -from <pin|net> ?-net? ?-layout?` (no `-to`, P4) — trace
  forward from the start point across all branches and stop each branch at
  the first sync load pin (flop CP / SRAM CK via the `_libsyncpin` map); report
  the path(s) to every reached sync endpoint and the count of sync endpoints
  reached. Requires `build_net_conn` (P2) and `add_lib` (L2).
- `trace_clock <pin|net>` — tree-like report tracing from a pin or net down
  through combinational logic and across hierarchy to all leaf sync load pins
  (flop CP / SRAM CK via the `_libsyncpin` map). Each branch is followed (not
  just one path, unlike `report_path`); the trace stops at a sync load pin. The
  summary reports the number of sync endpoints and combinational branches
  traced. Requires `build_net_conn` (P2) and `add_lib` (L2).
- `all_connected <net or pin>` — for a net, report that net with its driver and
  receiver pins; for an `inst/pin`, report that pin's net. The match is scoped
  like `get_net` (no `-hier`): a bare name (e.g. `all_connected n77`) reports
  only the top-level net `n77`, not same-named nets reused in submodules; a
  hierarchical reference (e.g. `all_connected core0/w0/n77`) reports only that
  scope's net. If the net is not in that hierarchy, nothing is found.
- `get_cell <pattern> ?-hier?` — list cells (leaf and hierarchical) whose
  full instance path matches. Without `-hier` only the direct children of
  the scope implied by the pattern are reported (`get_cell *` = top level
  only); `-hier` matches across the whole hierarchy. Like `get_lib_cell`, it is
  a getter: it prints just the matching instance path (with a `hierarchical`
  marker for hierarchical instances) per line plus a match count; per-cell
  detail lives in `report_cell`.
- `get_net <pattern> ?-hier?` — list nets whose scoped name matches. Without
  `-hier` only the nets of the single scope implied by the pattern are
  reported (`get_net *` = top-level nets only, `get_net core0/w0/nv_c0/c0/*`
  = nets in that module); `-hier` matches across the whole hierarchy. Like
  `get_cell`/`get_lib_cell`, it is a getter: it prints just the matching net
  name per line plus a match count; driver/receiver detail lives in
  `report_net`.
- `get_lib_cell <refname>` — list library-cell references whose name matches
  the glob (`get_lib_cell BUFF*`, `get_lib_cell *DFF*`, or an exact name).
  Reports each cell's class, LEF width x height and pin list with directions.
  Unlike the commands above this queries the loaded library, not the netlist,
  so it works as soon as a LEF is imported and needs no `build_design`.

## ECO commands

After `build_net_conn` (P2), the following mutate the design's net connectivity
in memory. Net and instance paths are scoped the same way as `get_net`/
`get_cell`: the trailing token is the net/instance name and the prefix is the
containing hierarchical scope; a bare name targets the top level.

- `create_net <netname>` — register a new (empty) net in a scope; the net is
  then visible to `get_net`/`all_connected` and can receive pins via
  `connect_net`.
- `create_cell <inst_path> <celltype>` — instantiate a library cell in a scope;
  the new instance's pins start unconnected and can be wired with
  `connect_net`. `<celltype>` must be present in the loaded LEF.
- `disconnect_net <net> <pin>` — detach an instance pin (`<inst>/<pin>`) from a
  net; the pin's direction (from the cell's LEF) selects whether it is removed
  from the net's driver or receiver list.
- `connect_net <net> <pin>` — attach an instance pin (`<inst>/<pin>`) to a net;
  the pin's direction selects the driver or receiver list. The net must exist
  (`create_net` or an existing net).

## Optimization commands

After `build_net_conn` (P2), buffer insertion can fix high-fanout nets:

- `set_max_fanout <n>` (O1) — set the global fanout threshold (max receivers per
  net) used by `fix_max_fanout`. `<n>` must be a positive integer; it is stored
  in the `maxfanout` global and is also saved/restored by `write_db`/`restore_db`.
- `fix_max_fanout -cell <buffer>` (O2) — insert buffers of the given lib cell on
  every net whose receiver count exceeds `maxfanout` and which has at least one
  driver (ports/constants/hierarchical pin nets with no driver are skipped).
  Each over-fanout net's receivers are split into groups of at most `maxfanout`:
  one buffer is created per group in the net's scope, the buffer input loads the
  original net, a new net per buffer is created and driven by the buffer
  output, and the group's receivers are moved from the original net to the new
  net. After insertion every net involved has at most `maxfanout` receivers.
  Uses the `netload` map from `build_net_conn`, so P2 must run first.

## Netlist I/O commands

After `set_top_design`, the design's netlist can be dumped back out:

- `write_verilog <filename>` — dump the loaded netlist as Verilog: modules
  (with ANSI-style ports), `wire` declarations, leaf-cell and hierarchical
  instances (with `.pin ( net )` connections, preserving bus bit-selects),
  and `assign` statements. Comments and line wrapping may differ from the
  source, but the structural content is preserved so a `read_netlist` ->
  `write_verilog` -> `read_netlist` round-trip is structurally equivalent
  (verified byte-identical in test7_roundtrip).
- `write_db <file>` — dump the full in-memory database to a file: every scalar,
  list and array variable holding design state (instances, wires, placement,
  the net connectivity map, the loaded LEF library, ports, assigns) so the
  whole database can be reloaded faster than re-parsing the netlist.
- `restore_db <file>` — reload a database written by `write_db`. Restores all
  variables so the session is ready immediately: `get_cell` / `get_net` /
  `all_connected` / `get_lib_cell` and the placement / library data are all
  available without `read_netlist`, `set_top_design`, `build_design` or
  `build_net_conn` (verified query-identical in test8_db).
