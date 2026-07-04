# Simple Calculator

A minimal Android calculator app built with Kotlin and View Binding.

## Features

- Addition, subtraction, multiplication, division
- Percent (%) and sign toggle (+/-)
- Chained operations (e.g. `12 + 8 ×`)
- Clear (AC)
- Division-by-zero shown as `Error`

## Project structure

- `app/src/main/java/com/example/simplecalculator/MainActivity.kt` — calculator logic and UI wiring
- `app/src/main/res/layout/activity_main.xml` — display + button grid layout
- `app/src/main/res/values/` — colors, strings, button styles/theme

## Requirements

- Android Studio (Koala or newer recommended)
- JDK 17
- Android SDK 34 (compile/target), min SDK 24

## Build & run

Open the project root in Android Studio and let it sync, or from the command line:

```bash
./gradlew assembleDebug
```

The debug APK will be at `app/build/outputs/apk/debug/app-debug.apk`.
