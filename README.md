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
