# Axial Xcode project

Open `Axial.xcodeproj` and build the `Axial` scheme. The project has native
targets for the app, both compatibility frameworks, the service, the CLI, and
the web setup helper. It references the original source files in the repository;
generated files and third-party dependencies stay under `Build/` here.

The minimum deployment target is macOS 13. Xcode 27 with the macOS 26 SDK,
CMake 3.29 or later, Perl, and network access for the first dependency
build are required. Boost 1.90.0 and OpenSSL 3.5.8 are fetched and built using
the repository's pinned CMake definitions into `Build/External/` with Unix
Makefiles. Later builds reuse those local outputs.

For a command-line build:

```sh
xcodebuild -project Project/AxialXcode/Axial.xcodeproj \
  -scheme Axial -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath Project/AxialXcode/DerivedData build
```

`3DconnexionClient` and `3DconnexionNavlib` can also be built separately.
Build products are in `DerivedData/Build/Products/Release/` (or `Debug/`).
The app bundle contains its service, CLI, setup helper, icon, model, and
license notices. Frameworks are separate products, as in the CMake build.

`generate_project.rb` recreates the checked-in project with the `xcodeproj`
Ruby gem. The generated CMake Xcode project in `build/xcode/` is independent.
