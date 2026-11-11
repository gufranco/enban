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
- `enban queue` turns the queue file into tab-separated rows of line, image, drive, speed and copies, with `-` for a missing drive, because a tab in `IFS` collapses empty fields. One background worker per drive writes that drive's rows in order and records each row's state in the work folder; the table and the final count read those files after every worker ends. The stand-in drive's `swap` flag keeps each ejected disc as `FILE.N` and leaves a blank one, which is how tests supply a fresh disc for each copy.
- `enban discovery` streams a pattern of 32-byte lines that name their sector, 64 to a sector, into `xorriso -as cdrecord ... tsize=BYTES -`, so no image is stored. It reads the disc back in a hundred stretches, regenerates each stretch to compare, and takes each stretch's seconds from the `copied, X s` line GNU and uutils dd print; busybox dd prints none, so those CSV cells stay empty. Runs are listed in `ENBAN_DATA/discovery/runs.tsv`.
- The app writes a session log to a temporary file: what it found in the drive and every job's start, finish, failure and cancel, each stamped in UTC. It is appended to `ENBAN_DATA/logs/DAY.log` when the app quits or is interrupted, and a log that cannot be kept is named in a warning. The Settings tab writes the whole settings file on every change and leaves out the theme when an environment variable sets it.
- The Discovery tab reads `runs.tsv` on every frame: the last row names the CSV its read-rate graph scales against the fastest stretch, and the last five rows fill the Compare table.
- The Queue tab keeps its rows as image, drive, speed and copies, the same columns a queue file holds, so `o` saves a file `enban queue` reads. Its job runs the queue workers inside the job folder, and the table reads each row's state file there on every tick.
- The Tools tab lists every tool in the mockup. Erase disc, Tray, Capabilities and Checksum work; each other tool names the part of enban that brings it: the raw SCSI tools, audio CD and CUE support, the log and settings, or a coming release.
- `enban checksum` reads its source once and feeds MD5 and SHA-1 through FIFOs while SHA-256 reads the pipe, using `md5` and `shasum` on macOS and the coreutils `*sum` tools on Linux.
- xorriso and cdrskin both ignore `-fix`, so close, speed, region and raw sectors send MMC commands through `sg_raw`, with the byte layouts of libburn's `mmc.c` and the kernel's `cdrom.c`; book type runs `dvd+rw-booktype` and needs root; macOS has no shell route to raw MMC, so these stop there. Tests check every byte through the stand-in `test/sg_raw.sh`; decisions D7 and D8 in the plan folder hold the evidence.
- `enban layerbreak` reads each `VTS_nn_0.IFO` where xorriso's `report_lba` places it, takes the title VOB start at offset 0xC4 and the cell address table at 0xE0, as libdvdread's `vtsi_mat_t` lays them out, and picks the first cell start at or past half the image and at most 2,086,912 sectors, the layer 0 of a DVD+R DL. Tests pad a small real image with a sparse tail to reach dual-layer sizes.
- `hdiutil makehybrid` on macOS 26 writes an El Torito catalog with an empty default entry and leaves the boot image out, and it has no field for the system, volume set, dates or ISO level; so a macOS build that asks for any of those goes through xorriso when it is installed, without UDF. The publisher, preparer, application and system are uppercased before the build, since both backends store them in capitals.
- `--dvd-video` needs genisoimage or cdrtools `mkisofs`, since makehybrid writes VIDEO_TS files in an arbitrary order and xorriso has no UDF; genisoimage finds VIDEO_TS only in its root source folder, so a layout is staged first. `--bdmv` and `--udf-version` 1.50 and later go through enban's own UDF writer, [`lib/udf.awk`](lib/udf.awk) driven by [`lib/udf_write.sh`](lib/udf_write.sh), the same on Linux and macOS, since no Linux tool writes UDF 2.50 into an image: mkudffs refuses 2.50 for a plain image and udfclient's `newfs_udf` writes 2.01 only. The awk lays out the volume recognition sequence, both volume descriptor sequences, the integrity descriptor, a metadata partition and its mirror from 2.50 on, file entries and identifiers, and prints the descriptors as `printf '%b'` escapes and the file copies for `dd`; files of 1 MiB and more start on a 1 MiB boundary so they copy in 1 MiB blocks. Names are OSTA CS0, 8-bit when every character fits and 16-bit otherwise; a name outside Unicode's first plane, or with a tab or a line break, is refused. Tests read the result back through the kernel on Linux and `hdiutil` on macOS.
- A boot image is copied beside the partial image and grafted from the copy, because genisoimage's `-boot-info-table` patches the file it reads. xorrisofs hides it by its disk path and genisoimage by its image path; the load segment is not offered, since only genisoimage can set it.
- write passes `-dao` or `-tao`, `-multi` for an open disc and `--perform_opc` to xorriso, and the same but OPC to cdrskin, which has no such option. BURN-Proof needs no switch, since libburn enables buffer underrun protection whenever the drive has it, and neither backend can overburn, so enban offers neither.
- `enban label` rewrites UDF the way udftools' `udflabel` does: the PVD volume identifier, 30 characters at most, and the logical volume identifier in the LVD, the IUVD and the FSD, in the main and reserve descriptor sequences, then each descriptor's CRC-16, polynomial 0x1021 from zero over `descCRCLength` bytes after the tag, and its tag checksum. Tests check the result with `udfinfo` and with `udflabel --force`, which refuses a damaged descriptor.
- `enban mount` uses `hdiutil attach -readonly -nobrowse` on macOS and `udisksctl loop-setup` then `mount` on Linux, and detaches what attached without a mount point. CI has no udisks daemon, so [`test/udisksctl.sh`](test/udisksctl.sh) stands in with `losetup` and `mount` under sudo.
- Speed memory keys on the drive's vendor and product and the `Media product` ID from xorriso's full `-toc`, kept in `ENBAN_DATA/speeds.tsv` behind a `set -C` lock file. Never lock with `mkdir`: the uutils `mkdir` 0.10.0 that Ubuntu 26.04 ships let two processes create the same directory 82 to 98 times in 400 contended takes, where GNU `mkdir` and `set -C` gave none. A remembered speed applies only when no `--speed` and no `write_speed` setting chose one.
- Read bytes from an image through `disk_file_text`, never a bare `$(dd ...)`: bash 5 prints `ignored null byte in input` when a command substitution meets a NUL, which lands in the output, while the `/bin/sh` of a plain macOS test run stays silent; only the bash coverage leg catches it.
- busybox awk has no `^` operator, so bit masks are read by halving.
- `enban cue` reads each WAV's RIFF chunks from its first 4 KiB with `od`, counts a track's sectors as its data bytes over 2352 rounded up, adds 75 sectors a second for each pregap after the first track, and refuses more than 360000 sectors, the 80 minutes of a CD-R.
- `enban sector` and the Sector viewer read 2048-byte user data with `dd` and format it from `od -An -tx1 -v`, which prints 16 bytes a line on GNU, BSD and busybox.
- The Build tab keeps its layout as rows of disc name, source path, KiB, files and folders, and caches its right pane when the layout or the type changes, because the name checks walk every source. A layout builds through graft points on Linux and through a staging folder of APFS clones on macOS, falling back to a plain copy across volumes. With Target on the disc, the layout builds into the job's own folder and then runs the write steps, so a cancel removes the temporary image with that folder.
- The Write, Read, Verify and Build tabs run the same steps as their commands in a background subshell, which writes its log and exit status to a temporary folder. While a job runs, the app reads keys with a half-second timeout so it can redraw and notice the end of the job, refuses to quit, refuses to start a second job, and cancels on `c` by killing the job's whole process tree, since a reader inside a pipeline is a grandchild of the job. A field is edited by handing the screen to one gum input, or to a plain line when gum is missing.

## Domain rules

- Settings resolve as option, then `ENBAN_` variable, then `ENBAN_CONFIG/settings`, then the built-in default. The file is read before the options are parsed and only fills what no variable set; a line enban cannot use is named in a warning and skipped, so a broken file never stops a job.
- No loop redirects a numbered file descriptor such as `done 9<file`: bashcov traces through a pipe whose descriptor number varies, so the redirect can swallow the trace and the loop's lines count as never run. Loops that must read stdin inside walk a file by line number instead.
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
- On macOS every disc command and drive pane runs against an image target, `--drive stdio:FILE`, through the same xorriso code as Linux, and both test legs drive it, but a real drive is refused: Homebrew's xorriso has no macOS drive adapter, libburn reports sg-dummy, so real drives need a backend over `drutil`, `hdiutil`, cdrtools, cdrdao and dvd+rw-tools, checked on the owner's drive. `sg_raw` has no macOS build, so close, speed, region and raw sectors need another route there (as of 2026-11-11).
- macOS images carry no Rock Ridge, since hdiutil makehybrid cannot write it, so an ISO9660-only build shows 8.3 names on macOS where Linux keeps the full names (as of 2026-11-11).
