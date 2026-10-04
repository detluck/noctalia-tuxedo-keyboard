# TUXEDO Keyboard

Control keyboard backlight brightness, RGB colors, dynamic animations, and desktop theme synchronization on TUXEDO and Clevo laptops via Linux sysfs.

## Plugin

| Field      | Value                                                       |
| ---------- | ----------------------------------------------------------- |
| ID         | `detluck/tuxedo-keyboard`                                   |
| Entries    | Bar widget: `backlight`; panel: `panel`; service: `monitor` |
| Plugin API | 31                                                          |

## Requirements

The keyboard backlight interface is provided by the `tuxedo-drivers` package (specifically the `tuxedo_keyboard` driver module):

- **Arch Linux**: `sudo pacman -S tuxedo-drivers-dkms` (or `yay -S tuxedo-drivers-dkms`)
- Ensure the module is loaded: `sudo modprobe tuxedo_keyboard`
- The driver exposes `/sys/class/leds/rgb:kbd_backlight/` (with write permissions for user session), requiring no background daemons or root privileges at runtime.

## Usage

Add the bar widget (`detluck/tuxedo-keyboard:backlight`) in **Settings → Bar → Widgets** or by editing your bar configuration in `settings.toml`.

### Interactions

- **Left-Click Widget**: Toggle the Keyboard Backlight Control panel.
- **Right-Click Widget**: Instantly synchronize keyboard RGB lighting with the active desktop theme accent color.
- **Scroll on Widget**: Smoothly adjust keyboard brightness up or down.
- **CLI / Keybind**: Toggle the floating panel anytime via:

```sh
noctalia msg panel-toggle detluck/tuxedo-keyboard:panel
```

## IPC

Dispatch events to the background monitor service:

```sh
# Force immediate RGB sync with current desktop theme color:
noctalia msg plugin detluck/tuxedo-keyboard:monitor all sync_theme

# Set brightness percentage (0-100):
noctalia msg plugin detluck/tuxedo-keyboard:monitor all set_brightness 100

# Set static hex color:
noctalia msg plugin detluck/tuxedo-keyboard:monitor all set_color "#FF0055"

# Force immediate state poll & refresh:
noctalia msg plugin detluck/tuxedo-keyboard:monitor all refresh
```

## Notes

- **Direct Linux Sysfs**: Hardware communication is handled directly through `/sys/class/leds/rgb:kbd_backlight/` using Linux's standard multicolor LED subsystem (`multi_intensity` and `brightness`). No background daemons or network requests are involved.
- **Theme Synchronization**: Uses Noctalia's native host API (`noctalia.getColor(role)`) to resolve the exact hex color of any of the 16 theme palette roles (`primary`, `surface`, `secondary`, `tertiary`, `hover`, etc.). Users can select their preferred role directly in the control panel dropdown with interactive color swatches. Defaults cleanly to Tuxedo Blue (`#0080FF`) if unavailable.
- **Dynamic Animations**: Includes built-in smooth spectrum cycling (Rainbow Wave) and breathing pulse animations managed directly by the background service.
- **Multi-Zone & Single-Zone Support**: Automatically detects whether the hardware features a single-zone RGB backlight or 3-zone RGB illumination (Left, Center, Right), enabling per-zone color customization when supported.
