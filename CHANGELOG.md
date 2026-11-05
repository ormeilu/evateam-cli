# Changelog

## [0.4.0](https://github.com/ormeilu/evateam-cli/compare/v0.3.0...v0.4.0) (2026-11-05)


### Features

* agent skill and Claude Code plugin ([21fe0e6](https://github.com/ormeilu/evateam-cli/commit/21fe0e6f28ebfd8168c24e43baf9975fd9056c80))
* drop Python: HTTPS in Mojo with a bundled OpenSSL ([38dfa79](https://github.com/ormeilu/evateam-cli/commit/38dfa7924e79197f3ff9d61a6f748eff6a56a581))
* eva auth login with the OS keychain, and setups that leak a token refused ([ac6db0b](https://github.com/ormeilu/evateam-cli/commit/ac6db0b47926c355bb54982b0037bf397c1b1895))
* show the parent task and subtasks in task get ([3deabd3](https://github.com/ormeilu/evateam-cli/commit/3deabd3234fd1310ae49839db4f8793e744ba2d8))


### Bug Fixes

* case-insensitive -q and --fields that prints only what was asked ([1e73ced](https://github.com/ormeilu/evateam-cli/commit/1e73cedd05ce063965f4b5e826d6f2e3bde7dfde))
* IPv6 sockaddr layout and credentials on redirects in the HTTP client ([05f9848](https://github.com/ormeilu/evateam-cli/commit/05f984846f642ea07b5b5f2f2818ef187985894d))
* keyring reads hanging on Linux after a write ([a3138d3](https://github.com/ormeilu/evateam-cli/commit/a3138d346d1958f6eb6f62e71ad93c9e152df1bc))
* pin release builds to Mojo's CPU floor and ship libstdc++ on Linux ([84fe58f](https://github.com/ormeilu/evateam-cli/commit/84fe58f11b242ae3267071ad3f45db9250364ddc))
* resolve hostnames on Linux ([d55d1ec](https://github.com/ormeilu/evateam-cli/commit/d55d1ec52cbdd36d00732ed100f6d4528502cba1))
* trim whitespace around task and document names in headers ([fee369f](https://github.com/ormeilu/evateam-cli/commit/fee369f3538f11f02eba395882acabc31df1a066))

## [0.3.0](https://github.com/ormeilu/evateam-cli/compare/v0.2.0...v0.3.0) (2026-11-05)


### Features

* install.sh installs the release binary directly ([ac99d2a](https://github.com/ormeilu/evateam-cli/commit/ac99d2a7762988e10d7828f0e419a2d29f110d42))


### Bug Fixes

* fetch Modular's licence files when the package cache lacks them ([e387075](https://github.com/ormeilu/evateam-cli/commit/e38707542d636a9e802f6045d7dd7475431c89ee))
* run the release builds when release-please is skipped ([ac0ab2b](https://github.com/ormeilu/evateam-cli/commit/ac0ab2bd9228205cb1e0c47e977c351b8d79d35b))

## [0.2.0](https://github.com/ormeilu/evateam-cli/compare/v0.1.0...v0.2.0) (2026-11-05)


### Features

* release archives for three platforms, cut by release-please ([0f572fb](https://github.com/ormeilu/evateam-cli/commit/0f572fba5d5644c101c283ac98358ecf6d2f7f8d))


### Bug Fixes

* accept the unquoted recipe version release-please writes ([3aa29f4](https://github.com/ormeilu/evateam-cli/commit/3aa29f4445811c669ce2f68406369fd0120526d4))
* attach only the archives to GitHub releases ([b8c7f39](https://github.com/ormeilu/evateam-cli/commit/b8c7f39abe83ee97df19a93be25591d60ae2ad8c))
* publish conda packages to the namespaced channel ormeilu/ormeilu ([35d3387](https://github.com/ormeilu/evateam-cli/commit/35d3387cee9cbb1c506d6f72ff6de013adb9d19f))
