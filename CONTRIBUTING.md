# Contributing to Axial

## Repository layout

| Path | Contents |
| --- | --- |
| `app/` | SwiftUI/AppKit settings, SceneKit test view, native bridge and bundle manifests |
| `src/` | Objective-C++ service and compatibility frameworks; C++ CLI |
| `include/axial/` | Shared HID decoder, device catalog, event transport and navigation logic |
| `tests/` | Native C++ and Swift regression tests, mock service and attributed fixtures |
| `cmake/` | Resource generation, bundle assembly, tests and installation rules |
| `tools/` | Build-time asset converters, benchmark launcher and uninstaller |
| `third_party/` | Pinned interface declarations and source assets with license notices |

All generated binaries, assets, caches, packages and benchmark results belong under
`build/`. The application icon and SceneKit model are generated from source by
CMake; do not commit their outputs. `CMakeLists.txt` and `cmake/Tests.cmake` are the
source lists for production targets and tests. There is no parallel shell build.

## Configure, build and test

Install the Apple Command Line Tools with a macOS 26+ SDK, then `mise install`
for the pinned CMake and Ninja versions. [mise tasks](https://mise.jdx.dev/tasks/toml-tasks.html)
provide shortcuts and run prerequisites automatically:

| Command (`mise run …`) | Purpose |
| --- | --- |
| `configure` / `cfg` | Configure the native build |
| `build` / `b` | Configure and build the native product and tests |
| `test` / `t` | Build and run the native test suite |
| `test:headless` | Exclude GUI startup tests |
| `build:intel`, `test:intel` | Build/test x86_64; execution on Apple Silicon needs Rosetta |
| `build:sanitizers`, `test:sanitizers` / `sanitize` | Build/run memory and undefined-behavior checks |
| `configure:xcode`, `xcode` | Generate the universal project; `xcode` also opens it |
| `build:xcode`, `test:xcode` | Build/test the universal Release configuration |
| `benchmark` / `bench` | Run mock input latency checks, including CPU contention |
| `package` / `pkg`, `package:xcode` | Build and verify native/universal installer payloads |
| `stage`, `stage:xcode` | Stage native/universal installation under `build/` |
| `install`, `install:xcode` | Build and install native/universal bundles with administrator access |
| `uninstall` | Remove installed bundles, retaining profiles |
| `run` | Build and open the development app; quit installed Axial first |
| `clean` | Delete all of `build/`, including packages and benchmark results |

Use `mise tasks` to list the tasks. They run from the project root, including when
invoked from a source subdirectory. Run tests, GUI checks and benchmarks separately
so their workloads do not interfere. Installation and removal use `sudo`; quit
Axial and CAD clients first. Disable Start at login before uninstalling.

CMake also works directly. Commands below assume the tools are on PATH;
alternatively prefix them with `mise exec --`:

```sh
cmake --preset native
cmake --build --preset native
ctest --preset native
```

Presets keep their outputs in separate directories:

| Preset | Purpose |
| --- | --- |
| `native` | Optimized development build for the host architecture |
| `intel` | x86_64 build; executing it on Apple Silicon requires Rosetta |
| `sanitizers` | C++/Objective-C++ memory and undefined-behavior checks |
| `xcode` | Xcode project with ARM64 and x86_64 slices; requires full Xcode |

Use the same configure/build/test commands with the desired preset name. For
Xcode, open `build/xcode/Axial.xcodeproj` and build `ALL_BUILD`, or run
`cmake --build --preset xcode`. Test and package presets select Release there.
Native Intel and Apple Silicon machines remain necessary for release timing;
Rosetta is an ABI compatibility check.

CTest covers raw HID replay, sparse device buttons, malformed reports, key
release, IPC, framework callbacks, camera math, configuration, logging and app
lifecycle. The integration tests use private mock-service sockets and temporary
settings. They do not inject input into CAD applications. The `startup` test needs
a logged-in GUI session; headless runners can use `ctest --preset native -LE gui`.

For UI changes, check the app manually at its minimum window size with long
device names, two-button and sparse-button devices,
light/dark/high-contrast appearances, and the bounded Test event log. Preserve
native control behavior and accessibility labels; consult Apple's
[materials](https://developer.apple.com/design/human-interface-guidelines/materials)
and [buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) guidance.

For performance checks, use the `benchmark` target. Timing runs must not overlap
builds or other tests.

## Signing, packaging and installation

Local builds use ad-hoc signing. For distribution configure a Developer ID
Application identity before building:

```sh
cmake --preset xcode -DAXIAL_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
cmake --build --preset xcode
cpack --preset xcode
```

Packages are written under the preset's `packages/` directory. CPack expands each
installer and verifies that its signed app, helper, resources and both frameworks
are present. A locally built package is not a notarized release. Sign the installer with a Developer ID
Installer identity and notarize/staple it with Apple's tools before distribution.
Do not commit signing keys, profiles or notarization credentials.

`cmake --install build/native` installs into `/Applications` and
`/Library/Frameworks` and requires administrator privileges. Quit Axial and CAD
clients first. The install rules reject bundles with another vendor's identifier.
Inspect an installation without affecting the system by staging it:

```sh
cmake --install build/native --prefix "$PWD/build/stage"
```

Native builds contain one CPU architecture; universal releases use the Xcode
preset. The public framework names and ABI must remain compatible with clients.
Custom developer settings belong in ignored `CMakeUserPresets.json`.

## Releases

CI and releases share `.github/workflows/build.yml`. The macOS 15 ARM build is
the canonical universal package; other jobs validate toolchains and run the exact
canonical payload. GUI startup is a separate advisory check. Homebrew installation
tests run only on disposable GitHub runners, never on a developer machine.

Update the CMake project version and `tools/release-notes.md`, push to `main`, and
wait for CI before pushing the matching `vMAJOR.MINOR.PATCH` tag. Releases reject
version mismatches and commits outside `main`. The release job publishes the
verified package and SHA256SUMS, then a separate job updates `consi/homebrew`.
Release automation uses Bash and runner-provided jq; Python is not required.

`HOMEBREW_DEPLOY_KEY` must contain the private half of a writable deploy key scoped
to `consi/homebrew`. The built-in GitHub token publishes Axial releases. No Apple
signing credentials are needed for the current ad-hoc releases.

Retry a failed job through Actions. Published assets are immutable: differing
bytes fail instead of being overwritten. For a Homebrew-only failure, rerun that
job to reuse the original artifacts. Older tags cannot downgrade the tap. A full
rebuild may produce different package bytes; do not replace an existing release.
