## [0.5.2](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.5.1...v0.5.2) (2026-07-09)


### Bug Fixes

* **android:** skip metadata upload on beta builds and fix path resolution in promote ([54cffd0](https://github.com/MaybeItsSoftware/open-parliament/commit/54cffd0461fbd5d0b773441881ff38fd62249bd0))

## [0.5.1](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.5.0...v0.5.1) (2026-07-09)


### Bug Fixes

* **android:** remove automatic alpha promotion from beta lane ([a1b545f](https://github.com/MaybeItsSoftware/open-parliament/commit/a1b545f2a59c684606d6a3eef4462181dca59ac8))

# [0.5.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.4.0...v0.5.0) (2026-07-09)


### Bug Fixes

* **calendar:** prevent debate card overflow ([806ef72](https://github.com/MaybeItsSoftware/open-parliament/commit/806ef7248e10ac92ac043e1e026bae46b7ed6349))


### Features

* **calendar:** content-aware lookback to skip empty sitting dates ([13950d3](https://github.com/MaybeItsSoftware/open-parliament/commit/13950d3dcc3582f5c54a16594354d7b193d3ec4e))
* **calendar:** show top speakers in debate cards ([b72c4c7](https://github.com/MaybeItsSoftware/open-parliament/commit/b72c4c7e2d0df3539f8845ddff2a4dc447c53e50))
* control history ribbon painting and fixes ([d3a2f56](https://github.com/MaybeItsSoftware/open-parliament/commit/d3a2f56650eaa851ae21a0dfe6e053a2d477a590))
* highlight search queries in transcript view ([a68cbac](https://github.com/MaybeItsSoftware/open-parliament/commit/a68cbac523b4ec6e9ff5853f6165cf20c80578ae))
* **ios:** arrange and scale iOS screenshots for App Store Connect ([3529cb6](https://github.com/MaybeItsSoftware/open-parliament/commit/3529cb6f631b821c493cb19adb1b249f4b294d58))
* **search:** show person avatars in search results ([999d9ec](https://github.com/MaybeItsSoftware/open-parliament/commit/999d9ecce8e55cb820b6d468aff49eb0a1daacce))


### Performance Improvements

* simplify map boundaries and split selection overlay ([303f23d](https://github.com/MaybeItsSoftware/open-parliament/commit/303f23d46b72d29fe8206b0a0379b8a5e1c77487))

# [0.4.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.3.2...v0.4.0) (2026-07-08)


### Bug Fixes

* updated disclaimer ([dc41814](https://github.com/MaybeItsSoftware/open-parliament/commit/dc418149667268730c846606e814be881a0ff7b5))


### Features

* replace app icon and generate Play Store screenshots from live data ([44a6ba0](https://github.com/MaybeItsSoftware/open-parliament/commit/44a6ba0480cb02111bdca99100c02ca3c079f6f0))

## [0.3.2](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.3.1...v0.3.2) (2026-07-05)


### Bug Fixes

* **android:** upload+promote to alpha in a single edit to avoid a race ([6617b0f](https://github.com/MaybeItsSoftware/open-parliament/commit/6617b0fbd97eaec03ca77bc4a2dc1b00a1b16d43))

## [0.3.1](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.3.0...v0.3.1) (2026-07-05)


### Bug Fixes

* **android:** use draft release_status for the first alpha promotion ([af4511f](https://github.com/MaybeItsSoftware/open-parliament/commit/af4511f2ac6254da18c15bf73c12819db53a632a))

# [0.3.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.2.1...v0.3.0) (2026-07-05)


### Features

* **android:** promote every beta build to closed (alpha) testing too ([b400fc4](https://github.com/MaybeItsSoftware/open-parliament/commit/b400fc482a64f44e443f1c46084f65c7129ce6e7))

## [0.2.1](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.2.0...v0.2.1) (2026-07-05)


### Bug Fixes

* **ci:** switch deploy.yml to workflow_run so it actually fires ([cf9cdc8](https://github.com/MaybeItsSoftware/open-parliament/commit/cf9cdc87182308a96e1acc75e937d984434d6b2e))

# [0.2.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.1.0...v0.2.0) (2026-07-05)


### Bug Fixes

* **fastlane:** require BUILD_NUMBER env var instead of silently falling back ([cb66f6a](https://github.com/MaybeItsSoftware/open-parliament/commit/cb66f6a87cac5d1e31723be9323a70399e9f607d))
* **release:** correct version baseline after erroneous 1.0.0/1.1.0 releases ([f8c7fa5](https://github.com/MaybeItsSoftware/open-parliament/commit/f8c7fa5e5f5fbccc454f140992057247b3fb813c))


### Features

* bump iOS minimum deployment target to 13.0 and update project for Flutter 3.44 ([ff1d60d](https://github.com/MaybeItsSoftware/open-parliament/commit/ff1d60db28e1b6af27331dcf8058f96e907ff7eb))

# [1.1.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v1.0.0...v1.1.0) (2026-07-04)


### Features

* bump iOS minimum deployment target to 13.0 and update project for Flutter 3.44 ([ff1d60d](https://github.com/MaybeItsSoftware/open-parliament/commit/ff1d60db28e1b6af27331dcf8058f96e907ff7eb))

# 1.0.0 (2026-06-25)


### Bug Fixes

* add cocoapods to the bundle for ios builds ([d17e7f6](https://github.com/MaybeItsSoftware/open-parliament/commit/d17e7f678795e53468fd1ef2dca719c9462cd48c))
* align SankeyFlowPainter coordinates with column stacking order ([f1d3291](https://github.com/MaybeItsSoftware/open-parliament/commit/f1d3291f1818e9b99cf8381a7209e59d362c56b5))
* inject monotonic CI build number for store uploads ([9e39001](https://github.com/MaybeItsSoftware/open-parliament/commit/9e39001e887c7bac4da5ef1df4fecc386ab404a5))
* **tests:** removed redundant design test ([4f3f8ff](https://github.com/MaybeItsSoftware/open-parliament/commit/4f3f8ff37971af8bc41e9e79451574499361328e))
* use ssh deploy key for match and set android package_name ([83c9ea7](https://github.com/MaybeItsSoftware/open-parliament/commit/83c9ea771850385226858117bdd756c6748f6bf5))


### Features

* calendar selection dates greyed out on dates when hansard has no debates ([594dae9](https://github.com/MaybeItsSoftware/open-parliament/commit/594dae9e8673cb65374272852db30c45b8043b11))
* **calendar:** grey out inactive dates ([f9b710b](https://github.com/MaybeItsSoftware/open-parliament/commit/f9b710b805b2b8a3e4d93705555bfd57329d90fb))
* generate iOS and Android launcher icons ([1d2ccae](https://github.com/MaybeItsSoftware/open-parliament/commit/1d2ccaeef2824eb5a655738591d2d4c4702dc536))
* implement SankeyFlowPainter and unit tests ([b8351ea](https://github.com/MaybeItsSoftware/open-parliament/commit/b8351eac532af7b94601c7222e82809f8a380273))
* Integrate SankeyFlowPainter into CouncilControlHistoryChart ([b604f36](https://github.com/MaybeItsSoftware/open-parliament/commit/b604f362f61eaf60ae5f53fa74ee369065d365a0))
* **map:** constituency and council more control indication ([92abdfe](https://github.com/MaybeItsSoftware/open-parliament/commit/92abdfe508898cfae654d677a6a521e5b607daa2))
* transparent background for full-screen video player ([b880686](https://github.com/MaybeItsSoftware/open-parliament/commit/b8806865e4929800901ece23b08f1950430051b9))
* transparent background for inline video player ([0467351](https://github.com/MaybeItsSoftware/open-parliament/commit/046735167aabf4aa07a0806e2e9e404cc8460b6c))
* **video player:** put the parliamentlive video player into a dropdown and tidied up ui ([0f5c21e](https://github.com/MaybeItsSoftware/open-parliament/commit/0f5c21e97d97e03d363c158a9d35a9516da521fb))

# 1.0.0 (2026-06-24)


### Bug Fixes

* use ssh deploy key for match and set android package_name ([83c9ea7](https://github.com/MaybeItsSoftware/open-parliament/commit/83c9ea771850385226858117bdd756c6748f6bf5))
