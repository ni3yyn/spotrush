# SpotRush EOS Android Gradle integration — v46.4

EOSG 2.3.1's bundled `eossdk-StaticSTDC-release.aar` declares the following
metadata requirements:

- `coreLibraryDesugaringEnabled=true`
- `desugarJdkLib=com.android.tools:desugar_jdk_libs:2.0.3`

The patcher therefore configures both the dependency and the Android
`compileOptions` flag. It also includes Epic's documented AndroidX WebKit
runtime dependency alongside appcompat, constraintlayout, security-crypto,
and browser dependencies.

The patch is idempotent: repeated runs do not duplicate Gradle declarations.

Run in GitHub Actions after generating/extracting the Godot 4.7.2 Android
Gradle template:

```bash
python3 tools/patch_eos_android_template.py --android-build android/build
```

The script expects the official EOSG 2.3.1 addon under
`addons/epic-online-services-godot` and reads the Client ID from
`scripts/networking/EOSLocalConfig.gd.example`. Do not commit
`EOSLocalConfig.gd` or place the Client Secret in the Gradle script.
