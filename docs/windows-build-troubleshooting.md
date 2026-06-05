# Windows build troubleshooting

Flutter creates Windows desktop build support files locally under
`windows/flutter/ephemeral` and caches generated Visual Studio projects under
`build/windows`. These folders are intentionally not committed to source
control.

If the project is moved, copied, restored from source control, or partially
cleaned, MSBuild can still point at stale absolute paths for generated wrapper
sources, which can produce errors like:

```text
Cannot open source file: '...\windows\flutter\ephemeral\cpp_client_wrapper\flutter_engine.cc'
Cannot open source file: '...\windows\flutter\ephemeral\cpp_client_wrapper\flutter_view_controller.cc'
```

## Repair steps

From a Flutter-enabled PowerShell terminal at the repository root, run:

```powershell
.\tool\repair_windows_build.ps1
flutter run -d windows
```

To repair and launch in one step, run:

```powershell
.\tool\repair_windows_build.ps1 -Run
```

The script removes stale generated Windows artifacts, runs `flutter clean`,
restores packages with `flutter pub get`, enables Windows desktop support, and
then optionally launches the app. Flutter will regenerate the missing
`cpp_client_wrapper` files from the installed SDK during the next Windows build.
