# Changelog

# [1.9.0](https://github.com/gufranco/enban/compare/v1.8.0...v1.9.0) (2026-11-12)


### Bug Fixes

* calibrate OPC through the drive command ([ff064bb](https://github.com/gufranco/enban/commit/ff064bbca455224d52eda8a09dd19cff97b43b9f))
* keep help within 80 columns ([cf9b8b6](https://github.com/gufranco/enban/commit/cf9b8b6688fd7ff5ae40cd81e2673bb6d5ffa6d6))
* keep od quiet when a UDF checksum stops early ([57f2f27](https://github.com/gufranco/enban/commit/57f2f27c791163daeb19e4032c018aca20db169d))
* keep the help page within 80 columns ([237398e](https://github.com/gufranco/enban/commit/237398ef747ac59a95c2e4a6fa6f6a2f9b4ac271))
* list stat in doctor ([5c98e14](https://github.com/gufranco/enban/commit/5c98e141078f7ec4fcfea44c0e44627b8de95c01))
* pass the native macOS toolset ([e4d1c27](https://github.com/gufranco/enban/commit/e4d1c2754009774710ed10286966d71dc0c5bbd1))
* read file sizes past 4 GiB under BusyBox ([0bd9283](https://github.com/gufranco/enban/commit/0bd928349653ecfd294fc46c2297ff67f4ba945b))
* size a file whose name starts with a dash ([4f8f7e7](https://github.com/gufranco/enban/commit/4f8f7e70ce3b03384b21a62c3d1004997913084d))
* stop a job tree before a cancel kills it ([7799faf](https://github.com/gufranco/enban/commit/7799faf9519f8bcfea6618532b6a7187f2e65e59))


### Features

* add a test mode to write and discovery ([d17eed7](https://github.com/gufranco/enban/commit/d17eed7de096753ab34738264f1ddb77ffc00fa0))
* add label, layerbreak, mount and speeds ([5d46eda](https://github.com/gufranco/enban/commit/5d46eda476247e28db3e6123489c394ad853ca02))
* add read speed, retries and error options ([251b1c4](https://github.com/gufranco/enban/commit/251b1c4ef77fb89327cfd859464462d49fb54966))
* add the drive tools, audio CDs and convert ([060f5d9](https://github.com/gufranco/enban/commit/060f5d91c43dbf1838bda21a7fdaf7df4e68b8a6))
* build Blu-ray BDMV images as UDF 2.50 ([a5768db](https://github.com/gufranco/enban/commit/a5768db9d58c5ba1d8205d91396f8ecd73ffbfd2))
* build bootable El Torito images ([34b569e](https://github.com/gufranco/enban/commit/34b569eefaf404afb0127858806dbbef88b95422))
* build DVD Video images in player order ([d371177](https://github.com/gufranco/enban/commit/d371177f908a3cfa5b5270cc5e33278a1f9508bf))
* choose the UDF revision of a build ([84fb789](https://github.com/gufranco/enban/commit/84fb789207744e21d657a62ccd84aa427020798d))
* choose write mode, finalize and OPC ([9847a1e](https://github.com/gufranco/enban/commit/9847a1e9d42bc40efe5800a1ad4d0bb8d89fe29d))
* close enban after the last copy is written ([1e664ef](https://github.com/gufranco/enban/commit/1e664ef34251e5de3c372660379fc4bad71f58e6))
* colour log levels and export IBG graphs ([f6cbe89](https://github.com/gufranco/enban/commit/f6cbe89ff56e5c0de101d832baa8b20b9232d2a6))
* convert and write CCD, MDS, DI, GI and PDI ([c6e740a](https://github.com/gufranco/enban/commit/c6e740a4325b5eeca2914c7783b6cfceeec58ece))
* list the drive MMC features ([79c9e03](https://github.com/gufranco/enban/commit/79c9e03601ebca4c0c326474b04fd502c8151dc3))
* load, lock and unlock the tray, rezero, sync ([5ee5d21](https://github.com/gufranco/enban/commit/5ee5d2198321f4bd5de018fd8f56b3b2c674273c))
* make audio CDs from FLAC, MP3, OGG and M4A ([3614dee](https://github.com/gufranco/enban/commit/3614deebba1f65a267120733c2765facef3350ab))
* name the layer break of a dual-layer build ([b2e8be2](https://github.com/gufranco/enban/commit/b2e8be203fc34d7dec4d98345dff7eceda1f1317))
* pause the queue, mark images, delete when done ([e6d9049](https://github.com/gufranco/enban/commit/e6d9049893023f666c06f7af50d722c2007db85f))
* reach real macOS drives through cdrtools ([b5db500](https://github.com/gufranco/enban/commit/b5db500f0215d2e8fa93f69eb2dba1ae65180456))
* read a CD raw with a CloneCD layout ([b404903](https://github.com/gufranco/enban/commit/b404903b2d7ea7e1333bd947a320a50c3f223462))
* record publisher, dates and ISO level ([ae842be](https://github.com/gufranco/enban/commit/ae842bea6b46ca0c677c1df805cfaed9c4028ebd))
* rename UDF in label, keeping a backup ([5bee88e](https://github.com/gufranco/enban/commit/5bee88e31c2fdb5f1bf9e8cded9cacb253b10eb5))
* run disc commands on macOS image targets ([3f0d5d2](https://github.com/gufranco/enban/commit/3f0d5d230b9b9c0a0006ff3e8b69853ce173da54))
* run drive tools and Rock Ridge on macOS ([94ab5da](https://github.com/gufranco/enban/commit/94ab5dac22e3fe8d0bc359c4044ed49e65652aff))
* save and open build layouts as projects ([f44db75](https://github.com/gufranco/enban/commit/f44db75ef419a9e0fa06a6323e449034e437d9a5))
* show the subchannel of a raw sector ([2b9b7cd](https://github.com/gufranco/enban/commit/2b9b7cd0a7ae70dac40a46533227a84da96b6671))
* split settings into pages and add job events ([be8fc14](https://github.com/gufranco/enban/commit/be8fc14d6775a8533cd2e7b0e464c64551866142))
* write a CUE sheet for an audio CD ([82920e9](https://github.com/gufranco/enban/commit/82920e9e108940d29213285fb9b12903a1a4a0e2))
* write DVD and MDS files for a layer break ([e30e924](https://github.com/gufranco/enban/commit/e30e924e572683909c1878703cbea8fe38abb389))
* write several copies and delete the image ([665f9db](https://github.com/gufranco/enban/commit/665f9db5a5d6ab62f4a25d4be7ac7328e006a9ad))
* write UDF 1.50 to 2.60 on Linux and macOS ([c3bc4b4](https://github.com/gufranco/enban/commit/c3bc4b46117170e77f7146ebf2ccf31255a7a30f))

# [1.8.0](https://github.com/gufranco/enban/compare/v1.7.0...v1.8.0) (2026-11-11)


### Features

* show a sector as hex with sector ([5aa4399](https://github.com/gufranco/enban/commit/5aa4399edf40e808c566110fb39e17949afe126c))

# [1.7.0](https://github.com/gufranco/enban/compare/v1.6.0...v1.7.0) (2026-11-11)


### Features

* keep a session log and edit settings ([9b84ce4](https://github.com/gufranco/enban/commit/9b84ce4da60054b42dd08b12cbf72852996dad3c))
* keep defaults in a settings file ([cac7578](https://github.com/gufranco/enban/commit/cac757800396c980f883b0832b9634108a53c158))

# [1.6.0](https://github.com/gufranco/enban/compare/v1.5.0...v1.6.0) (2026-11-11)


### Bug Fixes

* draw the key list across the whole screen ([d34c666](https://github.com/gufranco/enban/commit/d34c666ce42d8ca862645724f56a4dcae028df49))


### Features

* build and run a write queue on Queue ([49dbdee](https://github.com/gufranco/enban/commit/49dbdee7dd1e5694378908b2b630235e15edf801))
* run and compare discovery tests in the app ([2eee9f4](https://github.com/gufranco/enban/commit/2eee9f459b3ba6cad02dacf23fb785793192dc31))
* test a drive and disc with discovery ([3b506ec](https://github.com/gufranco/enban/commit/3b506ec027b4189850e95b17ca294e45dbe9c6b1))
* write a queue of images across drives ([cc831c4](https://github.com/gufranco/enban/commit/cc831c437b214ee486850779411772c473e7849f))

# [1.5.0](https://github.com/gufranco/enban/compare/v1.4.0...v1.5.0) (2026-11-11)


### Bug Fixes

* keep a frame inside the terminal height ([2dbda54](https://github.com/gufranco/enban/commit/2dbda54d2c0539d2ef23b5b8c5a698a7e9d1770f))


### Features

* list the kinds of disc a drive handles ([fb5de8e](https://github.com/gufranco/enban/commit/fb5de8e6b6f90aaebca59906a9f4b5beb7e34ffd))
* open the drive and image tools on Tools ([2376a8e](https://github.com/gufranco/enban/commit/2376a8e86123b7bb19a9d33bc1b38698222b5e62))
* print the checksums of an image or disc ([d579aa0](https://github.com/gufranco/enban/commit/d579aa0bdc41115748b146ffc5c86d2f4adb7eb4))

# [1.4.0](https://github.com/gufranco/enban/compare/v1.3.0...v1.4.0) (2026-11-11)


### Bug Fixes

* keep pane bottoms level when a line wraps ([a84f39d](https://github.com/gufranco/enban/commit/a84f39df3968fcafcbd9180e4793d1d5ccdfd9fe))


### Features

* build an image from the Build tab ([8063454](https://github.com/gufranco/enban/commit/806345451a67da03caafd45de13bb1aa36ffe1a2))
* burn the Build layout straight to the disc ([4fa49f1](https://github.com/gufranco/enban/commit/4fa49f1c55395c1a1c5db45a3a612fbe92d815fe))
* erase a rewritable disc with erase ([3ff53c8](https://github.com/gufranco/enban/commit/3ff53c83b68987bc1d663eed3ced8b49f2671091))

# [1.3.0](https://github.com/gufranco/enban/compare/v1.2.0...v1.3.0) (2026-11-11)


### Features

* build an image from a folder ([a29385c](https://github.com/gufranco/enban/commit/a29385c91def6a1fb4bf7864cffa7046cb403784))

# [1.2.0](https://github.com/gufranco/enban/compare/v1.1.0...v1.2.0) (2026-11-11)


### Features

* verify a disc from the CLI and the app ([7fb940c](https://github.com/gufranco/enban/commit/7fb940c4c2aa1125575a61a77deb2c2389bf603f))

# [1.1.0](https://github.com/gufranco/enban/compare/v1.0.0...v1.1.0) (2026-11-11)


### Bug Fixes

* treat a terminal size of zero as unknown ([4992387](https://github.com/gufranco/enban/commit/4992387f4a98f0721e8c9127dad158235fe48b9e))


### Features

* burn and verify an image with write ([70d8277](https://github.com/gufranco/enban/commit/70d8277b0cd8dde2fe971617465ed62d8a9274b1))
* copy a disc to an image with read ([8f4d793](https://github.com/gufranco/enban/commit/8f4d793a5c53d03a69e3e70f94aaa2ad5f3f666b))
* describe the drive and disc in the app ([2d227ca](https://github.com/gufranco/enban/commit/2d227ca99bec1fc0b9ed2476e127914811d80f8b))
* read a disc from the app's Read tab ([48fe077](https://github.com/gufranco/enban/commit/48fe077a11afe8635a9015e7fc2a94b1d64c2dd8))
* write an image from the app's Write tab ([086163e](https://github.com/gufranco/enban/commit/086163e9f8e482dc4049e731b54c6d40acc8be3a))

# 1.0.0 (2026-11-10)


### Features

* open a full-screen disc app ([c6b8351](https://github.com/gufranco/enban/commit/c6b8351875688a3760c00e8d09772f1ada6bfd46))
