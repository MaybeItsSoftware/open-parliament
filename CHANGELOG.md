# [0.11.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.10.0...v0.11.0) (2026-11-19)


### Features

* **member:** amendment text for votes; working speech history ([32f1f08](https://github.com/MaybeItsSoftware/open-parliament/commit/32f1f0864ad592d8e3ef1c5ae67a1320ed76aaa5))

# [0.10.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.9.0...v0.10.0) (2026-11-15)


### Bug Fixes

* **search:** footnote no longer claims debates come from cached days only ([8d70bee](https://github.com/MaybeItsSoftware/open-parliament/commit/8d70bee46ee2f9e4af3cc34a83511bd527e7aa1e))


### Features

* **cache:** evict least recently used sitting days; test the data layer ([c68616f](https://github.com/MaybeItsSoftware/open-parliament/commit/c68616f700af281e8d577b68ee4f4718fca6cec6))
* **nav:** bottom navigation shell, cached-first debate feed, concurrent search ([09dd6e9](https://github.com/MaybeItsSoftware/open-parliament/commit/09dd6e9657de23575e3203825f0f37a0ce490a56))
* **transcripts:** add per-speech "Watch from here" parliamentlive deep-link ([10b29bb](https://github.com/MaybeItsSoftware/open-parliament/commit/10b29bb8ee2c2ee9252d10d285a70a98f116c30a))


### Performance Improvements

* batch SQLite writes, parallel member pages, memoised roster ([6d38840](https://github.com/MaybeItsSoftware/open-parliament/commit/6d388400f1bf0c29a4b6a4e4ff3730ebb96223fa))

# [0.9.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.8.2...v0.9.0) (2026-09-04)


### Features

* **bills:** add full bill text reader, publications feed, and Acts of Parliament timeline ([00432c9](https://github.com/MaybeItsSoftware/open-parliament/commit/00432c9b6a823b772b1180aacaf4ddb10777eba7))
* **standing-orders:** add verbatim Standing Orders reference view and deep-link chips ([3f27992](https://github.com/MaybeItsSoftware/open-parliament/commit/3f2799200dd6aef6c5bb3fbedf101aff648b6082))
* **transcripts:** add text selection, structured procedural cards, and timecode fixes ([e875493](https://github.com/MaybeItsSoftware/open-parliament/commit/e87549307e9a43162043327a2b757179036e0b7a))
* **ui:** add AnimatedPieChart, day-view debate card limits, and hemicycle enhancements ([4c7081e](https://github.com/MaybeItsSoftware/open-parliament/commit/4c7081efecccc1e979c394d4dedacdb7dfb766f2))

## [0.8.2](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.8.1...v0.8.2) (2026-09-04)


### Bug Fixes

* **api:** retry transient connection drops and add User-Agent ([9640a6a](https://github.com/MaybeItsSoftware/open-parliament/commit/9640a6a619b12f6b1c7dcbaa064824285fc8c4e5))

## [0.8.1](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.8.0...v0.8.1) (2026-09-03)


### Bug Fixes

* **ios:** bump minimum deployment target to 15.0 ([f5315cf](https://github.com/MaybeItsSoftware/open-parliament/commit/f5315cfdb8d3b4c462605db250aa6150f859e865))

# [0.8.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.7.2...v0.8.0) (2026-09-03)


### Bug Fixes

* extract exact Royal Assent sitting date and sort timeline items by Royal Assent date ([0d05763](https://github.com/MaybeItsSoftware/open-parliament/commit/0d05763cb73b6dcf2ec101f80ecfab434e73483b))


### Features

* add Bills & Laws timeline page with chronological sorting and filtering ([6667ead](https://github.com/MaybeItsSoftware/open-parliament/commit/6667ead0d2355be54fb828c7098ac1384cdeb907))
* add capability to delete cached bill and law downloads in Settings and Timeline view ([e2922e9](https://github.com/MaybeItsSoftware/open-parliament/commit/e2922e962f562ea0bd060beb372d6ad6a815f3e5))
* add pinch-to-scale vertical timeline gesture and scale controls ([d6013b4](https://github.com/MaybeItsSoftware/open-parliament/commit/d6013b42c2d551d274c58ac033c40db9b00331bc))
* re-architecture timeline view with reverse scroll physics and timeline-first popups ([4c2ad92](https://github.com/MaybeItsSoftware/open-parliament/commit/4c2ad92e75246491e46954ebac3f065742031722))
* start timeline at bottom with latest Royal Assent Acts and scroll UP into history ([f7fab88](https://github.com/MaybeItsSoftware/open-parliament/commit/f7fab882346d082d22775a31a64761703c237610))
* **timeline:** rename to Laws Timeline and space entries by date ([968f797](https://github.com/MaybeItsSoftware/open-parliament/commit/968f79719bd2be85db6f17cbd16954c8c715e640))

## [0.7.2](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.7.1...v0.7.2) (2026-08-01)


### Bug Fixes

* timestamps in debates, concurrency in bills, reccess indicators ([ed6b60b](https://github.com/MaybeItsSoftware/open-parliament/commit/ed6b60b0d39555b0bd3bd6d919a9ec0d4ee28137))

## [0.7.1](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.7.0...v0.7.1) (2026-07-22)


### Bug Fixes

* party colour now considers date for historical accuracy ([ec9f14a](https://github.com/MaybeItsSoftware/open-parliament/commit/ec9f14a87664dcfce1e15836f10df1d807bfd7f0))
* restore and reform's colours ([e6e08c7](https://github.com/MaybeItsSoftware/open-parliament/commit/e6e08c7dbc7f4ceb8e2e47b0c75f212951a5797d))

# [0.7.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.6.0...v0.7.0) (2026-07-21)


### Bug Fixes

* **calendar:** hide future recess days, animate banner at top of tray ([8d08ad1](https://github.com/MaybeItsSoftware/open-parliament/commit/8d08ad1691ea6cf75feafb06567cff7da52393ff))
* **env:** don't crash flutter run/test when .env is missing ([da99a17](https://github.com/MaybeItsSoftware/open-parliament/commit/da99a17d4047e54160dac234750e01a2d26c0f95))


### Features

* **feed:** split papers tab, resolve generic titles, and parse ISO timecodes ([c5e5719](https://github.com/MaybeItsSoftware/open-parliament/commit/c5e57196600e47ba93fa1a40d28771ef5c9bd417))
* **home:** group debates by sitting session and add chamber filter ([fbfec1a](https://github.com/MaybeItsSoftware/open-parliament/commit/fbfec1a523b3884585c28849b430d4806458f7e6))
* **home:** show pending publication state for today's scheduled debates ([b5e52fa](https://github.com/MaybeItsSoftware/open-parliament/commit/b5e52fa3a08a40ecce86ed84d642fd891a883ea0))
* **map:** add search bar to constituency map and wire up search results ([5e4d496](https://github.com/MaybeItsSoftware/open-parliament/commit/5e4d496bf3d67c37c4bca5315bbf4a9005fb34c2))
* redesign chamber seating layout and enhance UI layouts ([7b1269c](https://github.com/MaybeItsSoftware/open-parliament/commit/7b1269cfd695d230b54b8eb8cf1965b3c426bbf1))

# [0.6.0](https://github.com/MaybeItsSoftware/open-parliament/compare/v0.5.2...v0.6.0) (2026-07-18)


### Bug Fixes

* **home:** keep debate titles readable on narrow screens ([ea3b747](https://github.com/MaybeItsSoftware/open-parliament/commit/ea3b7473a4f1937f6c8b6ae2b449442afc2550da))
* **home:** never land on a day with no content ([68d1ccd](https://github.com/MaybeItsSoftware/open-parliament/commit/68d1ccd194e021aa1611c8dcd123e990a502e828))
* **home:** tapping the date label opens the date picker, not a debate ([0875c61](https://github.com/MaybeItsSoftware/open-parliament/commit/0875c613e0cdc7a0d0161288a85adaa6547d0bc7))
* **ios:** use manual code signing with match provisioning profiles ([8ca8b0f](https://github.com/MaybeItsSoftware/open-parliament/commit/8ca8b0f4775f7b377f5d879354670160713fac1c))


### Features

* **calendar:** highlight and name a recess when one of its days is tapped ([0df633f](https://github.com/MaybeItsSoftware/open-parliament/commit/0df633f704976afac39daecfd20f9cd39ac9b5e3))
* **calendar:** mark parliamentary recesses in the sitting-day calendar ([111064e](https://github.com/MaybeItsSoftware/open-parliament/commit/111064ec42ad066598cda3bbae8fae9a85b0dd09))

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
