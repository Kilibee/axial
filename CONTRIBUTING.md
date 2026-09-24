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

Additional isolated workloads are available after a native build:

```sh
AXIAL_TEST_SCENE="$PWD/build/native/generated/ToyCar.scn" build/native/bin/scene-performance
build/native/bin/navlib-bench build/native/bin/axial-service build/native/bin/3DconnexionNavlib.framework/3DconnexionNavlib
build/native/bin/axial-web-setup --prepare "$PWD/build/web-benchmark-credentials"
build/native/bin/web-bench "$PWD/build/web-benchmark-credentials"
```

The scene workload requires an unlocked desktop and fails if it cannot sustain
visible movement or schedules idle delegate frames. It reports idle, moving,
stopped and hidden phases. Navlib reports separate client/service CPU and input
age at the camera callback (not transport latency). Web reports combined server
and synthetic client CPU; it does not install certificates or change trust.
Run three repetitions on an otherwise idle machine. Keep the window visible and
record OS, architecture, display refresh rate and build configuration with results.
The existing Client benchmark reports callback latency and event loss.

For scene comparisons, save the previous `SceneTest.swift` under `build/`, add
the instrumentation-only weak `motionSource: TestRenderer?` and
`frameDelegate: SCNSceneRendererDelegate?` properties to its `TestSceneView`, then
configure with `-DAXIAL_SCENE_BASELINE=/absolute/path/to/SceneTest.swift`. Run
`scene-performance-baseline` with `AXIAL_BENCH_BASELINE=1` and the same scene and
duration as the updated executable. Synthetic Navlib/web workloads do not replace
profiling the user's Fusion version, document and navigation operation.

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

Installation ownership and busy-process checks are shared in
`tools/install-guard.sh`, embedded into generated casks and package preinstall
scripts. Published v0.1.0, v0.2.0 and v0.2.1 manifests can recover a missing
identifier, including incomplete installs: every surviving entry must match one
release and at least one original Axial executable must remain. A valid Axial
identifier also permits replacement/removal when binaries are missing. Unknown
or modified contents without an identity are rejected. Regenerate the allowlist
with `tools/generate-legacy-files.py` and checksum-pinned published packages. To exercise that recovery
check locally without installing anything, run `tests/legacy_install_guard.sh`
with the source directory and published v0.1.0 package as arguments.

`tools/ci-cask.sh` covers fresh install, reinstall, upgrade, removal, reinstall
after removal, mapped-framework and service blockers, profile retention and web
setup preservation/cleanup. It must run on a disposable macOS runner. Homebrew
uses cached uninstall hooks, so the new hook cannot protect an upgrade initiated
through the old 0.1.0–0.2.1 hook. Homebrew 7 routes `brew install --cask --force`
through upgrade logic, so it cannot replace an old cached hook. A cached-hook
repair needs separate verification and explicit operator authorization; do not
recommend force-install as recovery. CI tests the standalone package's guard
against actual published releases, including damaged 0.1.0 metadata.
Do not publish the cask until the lifecycle job passes; local guard and package
tests alone do not validate Homebrew recovery.
No test edits the user's installed Homebrew metadata. The standalone uninstaller
removes web setup; Homebrew keeps it unless `--zap` is requested.

## Releases

CI and releases share `.github/workflows/build.yml`. The macOS 15 ARM build is
the canonical universal package; other jobs validate toolchains and run the exact
canonical payload. GUI startup is a separate advisory check.
The destructive Homebrew CI suite runs only on disposable GitHub runners.
Local lifecycle checks require the operator to explicitly choose to replace and
remove their installation; preserve profiles and existing web setup throughout.

Update `tools/release-notes.md`, push to `main`, and wait for CI before pushing a
`vMAJOR.MINOR.PATCH` tag. The tag is authoritative: release CI passes its version
as `AXIAL_VERSION` to CMake, and the artifact's `VERSION` file supplies runtime
and Homebrew checks. Local builds use CMake's default or `-DAXIAL_VERSION=x.y.z`.
Framework compatibility versions remain independent. Releases reject malformed
tags and commits outside `main`. The release job publishes the
verified package and SHA256SUMS, then a separate job updates `consi/homebrew`.
The installer component plist pins every bundle to its intended location;
package verification rejects relocation metadata. Homebrew CI registers an older
development copy and checks that install/reinstall leaves it untouched while
placing the released app in `/Applications`.
Release automation uses Bash and runner-provided jq; Python is not required.

`HOMEBREW_DEPLOY_KEY` must contain the private half of a writable deploy key scoped
to `consi/homebrew`. The built-in GitHub token publishes Axial releases. No Apple
signing credentials are needed for the current ad-hoc releases.

Retry a failed job through Actions. Published assets are immutable: differing
bytes fail instead of being overwritten. For a Homebrew-only failure, rerun that
job to reuse the original artifacts. Older tags cannot downgrade the tap. A full
rebuild may produce different package bytes; do not replace an existing release.

The original `v0.1.1` tag used the old workflow and declared CMake version 0.1.0.
Rerunning that tag does not pick up the tag-derived version fix. Publish a new,
unused tag containing the fix; existing tags and published assets stay unchanged.

Web compatibility uses hash-pinned Boost 1.90.0 and OpenSSL 3.5.8 LTS. CMake builds
static TLS libraries and a bundled certificate utility for each target architecture.
No Homebrew OpenSSL paths are embedded. Keep the pins/checksums and bundled notices
current. Web tests use temporary credentials and an ephemeral loopback port,
without installing trust or changing network configuration. Public protocol references:
[3DconnexionJS/WAMP](https://forum.3dconnexion.com/viewtopic.php?t=39934),
[spacenav-ws](https://github.com/RmStorm/spacenav-ws), and
[certificate lifecycle](https://3dconnexion.com/us/support/faq/certification-practice-statement/).
The bridge implementation is independent; no reference-project GPL code or keys
are redistributed. Server credentials are generated by the app's native helper, the CA private key
is discarded, and uninstallation removes Axial-owned trust and loopback setup.
TLS leaf certificates last two years to satisfy [macOS certificate requirements](https://support.apple.com/en-us/103769).
The running app checks setup every minute and offers renewal approval when fewer
than 90 days remain. Trust authorization runs in the GUI app's login session via
Security.framework; never modify authorizationdb to bypass it. No setup runs from
installer scripts or a privileged background certificate-renewal service.
