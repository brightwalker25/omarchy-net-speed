# Installing Net Speed Colour

The plugin is a bar widget for the Omarchy shell. It ships its own collector,
so there is no separate binary to place on `PATH` and no service to enable.

For what the bar and the panel show and why the widget measures the physical
link rather than following the default route, see the [README](../README.md).

## Requirements

| Needed | Used for |
|---|---|
| Omarchy shell with plugin support | The bar widget and panel |
| Python 3 | The collector, standard library only |
| Linux `/sys` and `/proc` | The interface counters, the routing table and the boot id |

Nothing else is needed. The collector runs no other programs and makes no
network calls.

## Installing

```bash
omarchy plugin add https://github.com/brightwalker25/omarchy-net-speed.git --enable
```

`omarchy plugin add` clones the repository into `~/.config/omarchy/plugins/`,
and `--enable` writes the widget into `bar.layout` in
`~/.config/omarchy/shell.json`, prompting for the section. Without `--enable`,
enable it separately:

```bash
omarchy plugin enable brightwalker25.net-speed --section right
```

## Placing it in the bar

To move the widget once it is enabled, for example next to the stock network
widget:

```bash
omarchy bar move brightwalker25.net-speed --section right --before omarchy.network
```

`--after <id>` and `--index <n>` work the same way. The section must be `left`,
`center` or `right`.

## Installing for development

Working on the plugin means running it from your own checkout of this
repository rather than from the copy that `omarchy plugin update` will
overwrite. With the checkout at `~/src/omarchy-net-speed`, two steps outside it
install it:

```bash
ln -s ~/src/omarchy-net-speed ~/.config/omarchy/plugins/brightwalker25.net-speed
omarchy plugin enable brightwalker25.net-speed --section right
```

The symlink is what makes edits live: the plugin id is the link name, so it has
to be exactly `brightwalker25.net-speed` whatever the checkout is called.
Changes to the collector take effect on the next sample, and changes to the QML
on the next shell restart.

Validate the manifest after editing it, and run the collector's tests after
changing it:

```bash
omarchy plugin validate ~/src/omarchy-net-speed
python3 -m unittest discover -s ~/src/omarchy-net-speed/tests
```

The tests build made-up `/sys/class/net` and `/proc` trees in a temporary
directory, so they pass on any machine whatever its interfaces are called.

## Running the collector from a terminal

The collector decides which interface is the link and which is the tunnel, so
anything the bar shows can be reproduced at the command line:

```bash
~/.config/omarchy/plugins/brightwalker25.net-speed/bin/net-speed --no-record
```

| Flag | Effect |
|---|---|
| `--iface auto` | Pick the physical link automatically (the default) |
| `--iface <name>` | Measure the named interface, for example `--iface enp0s1` |
| `--no-record` | Leave the usage file untouched |

It prints one JSON object and always exits 0. A problem, such as a pinned
interface that does not exist, is reported in the `error` field, and the bar
shows `--` in place of a figure.

## Settings

Settings are changed through the widget's settings in the Omarchy shell, with
`omarchy bar set`, or by hand in the widget's entry in
`~/.config/omarchy/shell.json`.

| Key | Default | Effect |
|---|---|---|
| `intervalMs` | 1000 | How often the collector runs, from 500 to 5000 milliseconds |
| `interface` | `auto` | `auto` picks the physical link; an interface name pins it |
| `units` | `bits` | `bits` for Kb/s and Mb/s on a 1000 base, as broadband speeds are quoted; `bytes` for KB/s and MB/s on a 1024 base |

```bash
omarchy bar set brightwalker25.net-speed intervalMs 2000 --json
omarchy bar set brightwalker25.net-speed interface wlp0s0
omarchy bar set brightwalker25.net-speed units bytes
```

`--json` stores the interval as a number rather than a string. Set
`interface` back to `auto` to return to automatic selection.

## Troubleshooting

The bar shows `--`. The collector could not run, or found no physical link that
is up. Run it by hand with `--no-record` and read the `error` field and the
`ifaces` list.

The bar shows 0 while the machine is clearly busy. Check which interface the
panel header names. If it is not the one carrying traffic, pin the right one
with the `interface` setting, and please report the `ifaces` list from the
collector so automatic selection can be fixed.

The panel says "VPN down" while a VPN is connected. The tunnel is recognised by
its interface type, and by name for WireGuard (`wg`), `tun`, Proton, Tailscale,
NordVPN (`nordlynx`) and Mullvad. A VPN that creates an interface outside those
is worth reporting with the collector's `ifaces` list.

Overhead does not appear. It needs a tunnel that is up and has averaged at least
1 KB/s over the last minute.

## Uninstalling

```bash
omarchy plugin disable brightwalker25.net-speed
omarchy plugin remove brightwalker25.net-speed
```

`disable` takes the widget out of the bar layout and leaves the files in place;
`remove` deletes the plugin directory too. For a development install, remove the
symlink rather than the checkout:

```bash
omarchy plugin disable brightwalker25.net-speed
rm ~/.config/omarchy/plugins/brightwalker25.net-speed
```

Neither command touches the usage history. To delete it:

```bash
rm -rf ~/.local/state/omarchy-net-speed
```
