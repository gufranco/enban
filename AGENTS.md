# enban

Guidance for anyone, human or agent, changing enban. What enban is and how to use it lives in [README.md](README.md).

[FAMILY.md](FAMILY.md) holds everything enban shares with the rest of the kodougu family, and it is the same in every member. This file holds only what is exclusive to enban, under the same headings as the agent guide of every member. Read both before changing anything; a rule that would serve the other members goes into `FAMILY.md` instead of here.

## Layout

| Path | Holds |
|:-----|:------|
| [`bin/enban`](bin/enban) | The entry point: usage and command routing |
| [`lib/`](lib) | The modules. [`lib/state.sh`](lib/state.sh) declares every global; [`lib/app.sh`](lib/app.sh) runs the full-screen loop, [`lib/frame.sh`](lib/frame.sh) draws each frame and [`lib/drive.sh`](lib/drive.sh) reads the drive and the disc |
| [`man/enban.1`](man/enban.1) | The man page |
| [`completions/`](completions) | bash, zsh and fish completions |
| [`test/`](test) | The `bats` suite, its helpers, the pseudo-terminal driver in [`test/app.bats`](test/app.bats), the stand-in drive in [`test/drive.sh`](test/drive.sh) and the Linux container script |
| [`scripts/`](scripts) | Coverage, the coverage gate, the Linux coverage run and the name check, which `make` runs |
| [`.github/scripts/`](.github/scripts) | The toolset helper and the release version stamp, which only CI and the release run |

## Names

- Globals carry `DISK_`, and function-scoped variables a per-function `disk_` prefix, the same names as the disk tools kiyome, kakikomi and nisemono, so the shared helpers move between them unchanged.
- App globals carry `DISK_APP_`, such as `DISK_APP_TAB` and `DISK_APP_KEY`.
- Settings come from `ENBAN_<NAME>`, such as `ENBAN_THEME`; test switches are `ENBAN_TEST_SHELLS`, `ENBAN_TEST_RECORD` and `ENBAN_TEST_GUM`.

## Behaviour

- enban is the family's first full-screen member: a bare `enban` on a terminal opens the app, never a menu.
- The app restores the screen, cursor and echo on `q`, Ctrl+D and an interrupt, and warns when echo is still off afterwards.
- `enban info --json` prints one JSON object with the drive, profile, status, sessions, free sectors, write speeds and `media`, the short names of the profiles `xorriso -list_profiles all` reports, which a `stdio:` drive leaves empty.
- `enban write` burns only a blank disc with room for the image, writes only after the drive's name is typed, verifies by reading back exactly the image's sectors, because cdrecord pads the end of a track, and ejects unless told not to.
- `enban read` copies the readable sectors that `xorriso -toc` reports, refuses a disc with no data and an existing file, reads again to compare unless told not to, and prints the SHA-256 with `sha256sum`, which doctor checks on Linux.
- `enban verify` reads the sectors `xorriso -toc` reports, or exactly the image's sectors when an image is given, streams them through `cmp -l` without a temporary copy, and counts the sectors read from the `records in` line of `dd`; it names the first sector that differs, then the first that could not be read.
- `enban build` writes ISO9660 always, through `hdiutil makehybrid` on macOS, which appends `.iso` to an output name without it, and through xorriso on Linux, or genisoimage when UDF is asked for, since libisofs has no UDF. It builds into a hidden temporary file beside the output and renames it, so a failed build leaves nothing. The ISO9660 volume name is uppercase `A-Z0-9_`, derived by enban so both platforms agree.
- `enban erase` accepts only the rewritable profiles CD-RW, DVD-RAM, DVD-RW in both modes, DVD+RW, DVD+RW DL and BD-RE, refuses a blank disc, and runs `xorriso -blank fast` or `-blank all` only after the drive's name is typed; a wrong name prints `cancelled, nothing was touched.` A `stdio:` image blanks the same 64 KiB in both modes, so tests read the mode from the stand-in drive's log.
- `enban checksum` reads its source once and feeds MD5 and SHA-1 through FIFOs while SHA-256 reads the pipe, using `md5` and `shasum` on macOS and the coreutils `*sum` tools on Linux.
- Closing an appendable disc is not possible through libburnia: xorriso and cdrskin both ignore `-fix`, so Close waits for the raw SCSI tools.
- The Build tab keeps its layout as rows of disc name, source path, KiB, files and folders, and caches its right pane when the layout or the type changes, because the name checks walk every source. A layout builds through graft points on Linux and through a staging folder of APFS clones on macOS, falling back to a plain copy across volumes. With Target on the disc, the layout builds into the job's own folder and then runs the write steps, so a cancel removes the temporary image with that folder.
- The Write, Read, Verify and Build tabs run the same steps as their commands in a background subshell, which writes its log and exit status to a temporary folder. While a job runs, the app reads keys with a half-second timeout so it can redraw and notice the end of the job, refuses to quit, refuses to start a second job, and cancels on `c` by killing the job's whole process tree, since a reader inside a pipeline is a grandchild of the job. A field is edited by handing the screen to one gum input, or to a plain line when gum is missing.

## Domain rules

- Keys are read with `dd` one byte at a time and decoded from hex, because a command substitution strips the newline Enter sends.
- Ctrl+D arrives as byte `04` inside a terminal, never as an empty read, so both mean the end of the session.
- After Escape the app waits a tenth of a second for the rest of an arrow sequence.
- GNU `stty` on macOS reports a false failure on `stty echo icanon`; the app checks `stty -a` instead of trusting the exit status.
- Tests drive the app through `script`, and send keys only once the first frame is on screen, because keys typed before the terminal leaves line mode can be lost.
- On Linux the drive is read through `xorriso -toc` and `-list_speeds`, parsing only their result lines on stdout. No optical drive runs on a CI runner, so [`test/drive.sh`](test/drive.sh) is the stand-in drive: it runs the real xorriso on a `stdio:` image file and replaces only the two things a file cannot report, the `Media current` profile and code and the `-list_speeds` lines, written in libisoburn's own formats.

## Release

- `ENBAN_VERSION` lives in [`lib/core.sh`](lib/core.sh).
- Every release asks the tap to bump `Formula/enban.rb`, and that bump fails until the formula exists. The formula waits for the first disc job to ship.

## Gaps against FAMILY.md

- The README is in English only; the Japanese, Simplified Chinese and Hong Kong Traditional Chinese READMEs are not written yet (as of 2026-11-10).
- v1.0.0 ships the app frame, its tabs and its keys, but no disc job, so it has no Homebrew formula yet (as of 2026-11-11).
- `enban info` stops on macOS: the drive is read through `drutil`, and no `drutil -xml` output from a real drive has been captured to build the parser and its stand-in from (as of 2026-11-11).
