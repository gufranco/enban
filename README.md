<div align="center">

<h1>enban</h1>

<strong>Write, read, build and verify CD, DVD and Blu-ray discs in a full-screen terminal app.</strong>

[![ci](https://img.shields.io/github/actions/workflow/status/gufranco/enban/ci.yml?branch=main&style=flat-square&label=ci)](https://github.com/gufranco/enban/actions/workflows/ci.yml)
[![license](https://img.shields.io/github/license/gufranco/enban?style=flat-square&label=license)](LICENSE)

<p align="center">
  <a href="#quick-start"><strong>Quick start</strong></a> |
  <a href="#how-it-works">How it works</a> |
  <a href="#development">Development</a>
</p>

</div>

`enban`, 円盤, is Japanese for a disc. It aims at the jobs a disc burner does: write an image, write files, read a disc to an image, build an image, verify a disc against an image, and stress-test a drive. Today it ships the app itself, with its full-screen frame, tabs and keys, `enban info`, which describes the drive and the disc in it, and `enban write`, which burns an image and verifies it, and `enban read`, which copies a disc to an image, all on Linux. The other jobs arrive in the coming releases, each as a tab and as a plain command for scripts.

---

<p align="center">
  <img src="screens/hero.gif" alt="enban opening its full-screen app, moving between the jobs on Home, showing its keys, opening a job's tab and quitting" width="800">
</p>

```console
$ enban doctor
gum                ok       /opt/homebrew/bin/gum
dd                 ok       /opt/homebrew/opt/coreutils/libexec/gnubin/dd, gnu 9.12
cmp                ok       /opt/homebrew/opt/diffutils/bin/cmp, gnu 3.12
od                 ok       /opt/homebrew/opt/coreutils/libexec/gnubin/od, gnu 9.12
awk                ok       /opt/homebrew/opt/gawk/libexec/gnubin/awk, gnu 5.4.1
sed                ok       /opt/homebrew/opt/gnu-sed/libexec/gnubin/sed, gnu 4.10
head               ok       /opt/homebrew/opt/coreutils/libexec/gnubin/head, gnu 9.12
tr                 ok       /opt/homebrew/opt/coreutils/libexec/gnubin/tr, gnu 9.12
sudo               ok       /usr/bin/sudo
drutil             ok       /usr/bin/drutil
hdiutil            ok       /usr/bin/hdiutil
```

<a id="quick-start"></a>

## Quick start

### Prerequisites

| Tool | Why | Install |
|:-----|:----|:--------|
| [`gum`](https://github.com/charmbracelet/gum) | The family look for doctor, version and help | `brew install gum` |
| POSIX `sh`, `stty`, `dd`, `od`, `awk` | The app and its key reading | Preinstalled on macOS and Linux |
| `drutil` and `hdiutil` | The drive and images on macOS | Preinstalled |
| `xorriso` and `cdrskin`, optionally `cdrdao` | The drive and images on Linux | `apt install xorriso cdrskin cdrdao` |

### Install

```bash
git clone https://github.com/gufranco/enban.git
cd enban
make install
```

`make install` copies the tool, its man page and its bash, zsh and fish completions under `~/.local`, and puts `enban` in `~/.local/bin`; set `PREFIX` to change that.

### Verify

`enban doctor` lists every tool and whether it is installed, as in the sample above.

## Usage

| Command | Purpose |
|:--------|:--------|
| `enban --drive /dev/sr0` | Open the full-screen app on a terminal, with the disc in that drive on the right; `ENBAN_DRIVE` sets the drive too |
| `enban info --drive /dev/sr0` | Describe the drive and the disc: profile, blank or appendable, sessions, free sectors and write speeds. `--json` prints one object for scripts. Linux only for now |
| `enban write image.iso --drive /dev/sr0` | Burn the image to a blank disc once you type the drive's name, read it back to compare, then eject. `--speed 8`, `--no-verify` and `--no-eject` change that. Linux only for now |
| `enban read --drive /dev/sr0 backup.iso` | Copy the disc into a new image file, read it again to compare, and print the SHA-256. `--no-verify` skips the second read. Linux only for now |
| `enban doctor` | List the tools enban needs and whether they are installed |
| `enban version`, `enban help` | Print the version or the full usage page |

| Key | In the app |
|:----|:-----------|
| Arrows | Move between the six jobs on Home, or the fields on Write and Read |
| Enter | Open the focused job's tab, or edit the focused field |
| Space | Turn verify or eject on or off on Write, or verify on Read |
| `w` | Write the chosen image, after you type the drive's name |
| `r` | Read the disc into the chosen new file |
| `c` | Cancel a running write or read |
| Tab | Next tab |
| `0` to `9` | Switch to that tab |
| `?` | Show the keys; the next key closes them |
| `q` or Ctrl+D | Quit and give the terminal back; refused while a write or read runs |

`--theme <name>` picks the colours; `ENBAN_THEME`, then `KODOUGU_THEME`, set the same, and `NO_COLOR` turns colour off. enban follows the shared command-line contract of its family, described in [FAMILY.md](FAMILY.md).

<a id="how-it-works"></a>

## How it works

gum draws one widget per process and has no event loop, so enban runs its own loop and keeps gum for the moments a field is edited.

```mermaid
graph LR
    A["enter the alternate screen"] --> B["draw the whole frame"]
    B --> C["read one key"]
    C --> D{"q or Ctrl+D?"}
    D -->|no| B
    D -->|yes| E["restore the screen, cursor and echo"]
```

- The frame is drawn with escape sequences in the theme's colours. A full frame at 140 columns, with both panes, took 77 ms on the owner's Mac while other test suites ran, against a budget of 250 ms; drawing each box through gum took 524 ms in the mockups.
- Below 100 columns the jobs and the disc pane stack, and the six jobs become one list.
- Keys are read one byte at a time with `dd` and decoded from hex, so arrows, Escape, Enter and Ctrl+D are told apart.
- The terminal is restored on `q`, on Ctrl+D and on an interrupt. GNU `stty` on macOS reports a false failure when echo is turned back on, so enban checks `stty -a` itself and warns only when typing is really still hidden.
- Without a terminal the app never opens; enban names the problem and exits 1.

<a id="portability"></a>

## Portability

Everything is POSIX `sh` with ShellCheck `-o all` at zero findings. The suites drive the app through a pseudo-terminal with `script`, under every shell and toolset in [FAMILY.md](FAMILY.md).

<a id="screens"></a>

## Screens

<details>
<summary>Every screen, recorded from a real run with <code>make screens</code></summary>
<br>

<table>
<tr>
<td width="50%" valign="top"><img src="screens/home.png" alt="enban: Home, with the six jobs and the disc pane"><br><sub>Home, with the six jobs and the disc pane</sub></td>
<td width="50%" valign="top"><img src="screens/keys.png" alt="enban: The key list that ? opens"><br><sub>The key list that ? opens</sub></td>
</tr>
<tr>
<td width="50%" valign="top"><img src="screens/write.png" alt="enban: The Write tab, with its image, speed, verify and eject fields"><br><sub>The Write tab, with its image, speed, verify and eject fields</sub></td>
<td width="50%" valign="top"><img src="screens/read.png" alt="enban: The Read tab, with its image and verify fields"><br><sub>The Read tab, with its image and verify fields</sub></td>
</tr>
<tr>
<td width="50%" valign="top"><img src="screens/doctor.png" alt="enban: doctor checks every tool it needs"><br><sub>doctor checks every tool it needs</sub></td>
<td width="50%" valign="top"><img src="screens/themes.png" alt="enban: The version badge in six themes"><br><sub>The version badge in six themes</sub></td>
</tr>
<tr>
<td width="50%" valign="top"><img src="screens/error.png" alt="enban: An error"><br><sub>An error</sub></td>
<td width="50%" valign="top"><img src="screens/help.png" alt="enban: The help page"><br><sub>The help page</sub></td>
</tr>
</table>

</details>

<a id="development"></a>

## Development

| Command | Description |
|:--------|:------------|
| `make fmt` | Formats every script with shfmt |
| `make lint` | shfmt, ShellCheck on every script, test and completion, and mandoc on the man page |
| `make test` | The `bats` tests under the system `sh` |
| `make test-all` | The same tests under every shell |
| `make test-linux` | The same tests in an Ubuntu container |
| `make coverage` | bashcov line coverage on this Mac and in the Ubuntu container, merged, with the 100% gate CI enforces |

## License

[MIT](LICENSE)
