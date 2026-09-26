# Changelog

## 0.3.0 - 2026-09-26

### Changed

- The two bar rows set `textFormat: Text.PlainText`, like every text in the
  panel, so nothing shown in the bar can be read as rich text.
- `INSTALL.md` is now `docs/usage.md`, and the README carries the removal
  commands itself.
- Upload is mid blue (#58a6ff) instead of violet. It reads more clearly on
  the bar and sits better beside the green. Blue and green stay easy to tell
  apart with red-green colour blindness; with the rare blue-yellow kind they
  are closer, and the arrows and row order carry the meaning.
- The display name is now Net Speed Colour, since another plugin in the
  directory is already called Net Speed. The id stays brightwalker25.net-speed.
- Added `preview.png`, the bar rows with the panel open and a VPN up, and
  `docs/panel-vpn-down.png`, the panel with the VPN down. Both are shown in
  the README and carry no metadata.

## 0.2.0 - 2026-09-26

### Changed

- Rates are shown in bits by default (b/s, Kb/s, Mb/s, Gb/s on a 1000 base),
  the unit broadband speeds are quoted in, still changing unit with the
  speed. The bits labels are shorter than before (Mb/s rather than Mbit/s).
  Set `units` to `bytes` for the old KB/s and MB/s readout.
- The bar rows are coloured, arrow and figure alike: upload in violet and
  download in green. Red and orange were tried first and dropped, because
  they read as a warning (red and amber mean a problem in the other
  brightwalker25 widgets) and red is hard to tell from green with red-green
  colour blindness. Violet carries no meaning and stays distinct from green.

## 0.1.0 - 2026-09-26

### Added

- A bar readout of upload over download for the physical Wi-Fi or Ethernet
  link, at a fixed width so the bar does not shift as the figures change.
  Clicking it opens the panel; a middle click takes a fresh sample.
- Automatic link selection that ignores tunnels and kill-switch dummy
  interfaces. Only interfaces with a device node are candidates, and among
  those that are up the one with the best default route wins. The
  `interface` setting pins a named interface instead.
- A panel with the link and the VPN tunnel side by side, a green "VPN up" or
  amber "VPN down" marker, an Overhead line comparing link and tunnel traffic
  over the last minute, and a graph of the link's recent download and upload.
- Data used today and on each of the last seven days, counted on physical
  interfaces only and carried across reboots and counter resets. The history
  is kept in `~/.local/state/omarchy-net-speed/usage.json`, for 31 days.
- Settings for the refresh interval (500 to 5000 ms), the interface, and
  whether rates are shown in bytes or bits.
- `bin/net-speed`, the collector: Python 3 standard library only, no
  subprocesses, no network calls, and tests that run on made-up sysfs trees.
