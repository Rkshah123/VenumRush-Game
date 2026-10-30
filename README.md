# VenomRush (SERPENTIS 3D)

An original **3D snake arena survival game** built with **Godot 4.7** and GDScript.
Evolve, hunt and dominate: eat real food to grow, outmanoeuvre an AI roster of
personality-driven rivals, grab power orbs and survive the boss.

- **Engine:** Godot 4.7 (`gl_compatibility` renderer, desktop + mobile)
- **Language:** GDScript (100% of gameplay code)
- **Version:** 1.5.0
- **Package (Android):** `com.venomrush.game`
- **Main scene:** [`serpentis3d/scenes/main.tscn`](serpentis3d/scenes/main.tscn)

> The game project lives in **`serpentis3d/`**. The repository root also holds
> reference art packs, a spec document and export tooling.

---

## Repository layout

```
.
├── serpentis3d/              # ← the Godot project (open this folder in Godot)
│   ├── project.godot         #    app config, autoloads, display/physics/rendering
│   ├── scenes/main.tscn      #    single entry scene → scripts/core/game.gd
│   ├── scripts/
│   │   ├── core/             #    game.gd (orchestrator), save_manager, audio_manager
│   │   └── gameplay/         #    snake, AI, arena, food, HUD, cameras, menus
│   ├── shaders/              #    snake body, terrain, water, sky, foliage, menu stage
│   ├── models/, textures/    #    food models + snake/food sprites
│   ├── export/               #    Windows + Android build outputs
│   ├── keys/                 #    release/debug keystores (git-ignored)
│   └── tests/probe_snake.gd  #    headless Snake lifecycle probe
├── export_android.ps1        # one-shot Android build + zipalign + sign script
├── make_ico.ps1              # icon generation helper
├── game.txt                  # original master design/spec document
├── LowPolyFoodPack/,         # third-party food models (FBX/GLB/OBJ)
├── 3Dfruits/, friuts/,       # reference fruit models and sprites
├── reference_assets/, demo/, # reference scenes / screenshots
└── addons/terrain_3d/        # Terrain3D plugin source (reference only — not
                              # enabled by serpentis3d/project.godot)
```

The world is **procedurally generated at runtime** by
`scripts/gameplay/environment_builder.gd` (court disc, terraces, mountains,
river/lake/waterfall, instanced trees, grass, rocks, animated water, sky and
lighting) — no Terrain3D plugin is required to run the game.

---

## Running the game

1. Install **Godot 4.7.x** (standard build; the Android export script expects
   `Godot_v4.7.2-stable_win64_console.exe` at `C:\Godot\`).
2. Open the **`serpentis3d/`** folder in the Godot project manager.
3. Press **F5** (main scene `scenes/main.tscn`).

Headless logic probe:

```bash
godot --headless --path serpentis3d --script tests/probe_snake.gd
```

### Autoloads

| Name       | Script                              | Purpose                                        |
|------------|-------------------------------------|------------------------------------------------|
| `SaveMgr`  | `scripts/core/save_manager.gd`      | Versioned JSON settings/progress (`user://save.json`) |
| `AudioMgr` | `scripts/core/audio_manager.gd`     | Fully procedural sound effects (no audio assets) |

### Controls

| Action           | Desktop                                  | Android / touch |
|------------------|------------------------------------------|-----------------|
| Steer            | Mouse or `A`/`D` / arrow keys            | PUBG-style virtual joystick (bottom-left), or drag anywhere |
| Boost            | `Space` / `Shift` / Left mouse           | Second finger anywhere |
| Pause            | `Esc`                                    | Pause button |
| Quit confirm     | `Esc` on menu                            | Back button |

---

## Features

- **Two presentation modes:** true 3D TPS chase camera and a 2D top-down
  orthographic board (switchable in Settings, persisted per player).
- **Four biomes** (`scripts/gameplay/arena_presets.gd`): Verdant Valley,
  Autumn Hills, Golden Savanna, Midnight Grove — each drives its own terrain
  palette, lighting, fog, sky, water and vegetation.
- **Snake simulation** (`scripts/gameplay/snake.gd`): kinematic head, path-history
  spine, GPU-deformed continuous tube body (257 rings), turn banking, boost with
  energy cost, spawn protection and procedural head.
- **AI roster** (`scripts/gameplay/ai_snake.gd`): FSM wander/seek/chase/flee with
  weighted steering, wall & obstacle avoidance, cut-ahead interception and
  risk-limited boosting across 13 personalities (desktop) / 10 (mobile), plus a
  **boss** that enters after 60 s.
- **Food economy** (`scripts/gameplay/food_spawner.gd`): basic / rare / golden
  food with S/M/L tiers, power orbs (**magnet**, **shield**), death drops from
  fallen snakes, spatial-hash grid culling, mobile budgeting.
- **Match rules** (`scripts/gameplay/match_world.gd`): offline authoritative
  simulation — spawning, spatial-hash collisions, kills, respawns, feed events,
  demo mode reusing the same systems behind the menu.
- **Cinematic menu** (`scripts/gameplay/menu_world.gd`): real snakes on wander
  paths, dust motes, glowing orbs and a glowing stage — its own environment,
  fully dormant during a match.
- **UI** (`scripts/gameplay/hud.gd`, `ui_theme.gd`): light/dark themes,
  settings, how-to-play, skins shop, pause and game-over flows, safe-area
  handling, minimap radar, virtual joystick.
- **11 unlockable skins** (`scripts/gameplay/skin_catalog.gd`) earned by personal
  best score, rendered on the real snake mesh.
- **Persistence:** best score/length, runs, kills, volume, fullscreen, theme,
  graphics mode, selected skin and tutorial state (with type-coercion-safe
  migration from older saves).
- **Quality tiers:** automatic GPU/device tiering (mobile → lower AI count, food
  caps and detail) and physics interpolation for 90/120 Hz screens.

---

## Building releases

### Windows (portable)

Export preset **Windows Desktop** → `serpentis3d/export/windows/VenomRush.exe`
(plus `VenomRush_Portable.zip`, `icon.ico` and an Inno Setup script
`venomrush.iss`). The portable bundle ships `README-Portable.txt` with controls
and requirements; settings/progress are written next to the executable in
`user-data/`.

```powershell
godot --headless --path serpentis3d --export-release "Windows Desktop" `
      "export/windows/VenomRush.exe"
```

### Android (build + zipalign + sign)

```powershell
powershell -ExecutionPolicy Bypass -File export_android.ps1
```

The script exports an unsigned APK, then signs and verifies it with
`keys/release.keystore` (alias `serpentis`) using the newest Android
build-tools `apksigner`. Output: `serpentis3d/export/android/VenomRush_signed.apk`.

**Keystore passwords are not stored in this repository.** `export_presets.cfg`
is committed with empty password fields; the script reads the release password
from `$env:VENOMRUSH_KS_PASS` or from `serpentis3d/keys/keystore.env`
(git-ignored), writes it into the preset only while Godot is exporting, and
restores the original file in a `finally` block. To build, create that file as:

```ini
VENOMRUSH_KS_PASS=<release keystore password>
```

Prefer exporting from the GUI? The editor stores whatever you type into the
keystore dialog back into `export_presets.cfg`, so check
`git diff serpentis3d/export_presets.cfg` before committing.

Requirements: `ANDROID_HOME` (or `%LOCALAPPDATA%\Android\Sdk`) with
build-tools installed, and the keystore present in `serpentis3d/keys/`.
`.gitignore` excludes `keys/`, `export/`, `.godot/` — keystores, local secrets
and build outputs are never committed.

---

## Dev / QA harness

`scripts/core/game.gd` reads command-line flags for automated testing and
screenshot capture, e.g.:

```
--autoplay --no-death --solo --hud-off --quit          # headless-ish run
--shot-menu --shot-skins --shot-settings --shot-game   # capture screens
--mode-test --theme-test --uix-test --joy-test         # UI checks
--arena-test --touch-test --spawntest --powertest      # world checks
--eat-test --skins-test --body-test --climb-test       # snake checks
--villain-test --ai-loop --drop-test --turn-test       # AI checks
--dir-test --ctrl-test --touchlog --closeup            # input / diagnostics
```

Example:

```bash
godot --path serpentis3d -- --autoplay --shot-game --quit
```

---

## Third-party assets

| Asset | Location | License / terms |
|-------|----------|-----------------|
| Low Poly Food Pack (by reodesuxz) | `LowPolyFoodPack/` | Free for personal & commercial use, no attribution required; **may not be redistributed as an asset pack or used to train AI models** — see [`LowPolyFoodPack/LICENSE.txt`](LowPolyFoodPack/LICENSE.txt) |
| Terrain3D plugin (TokisanGames) | `addons/terrain_3d/` | MIT — reference copy, not enabled by the game project |
| Fruit model/sprite references | `3Dfruits/`, `friuts/`, `reference_assets/` | Reference material for the in-repo food assets |

All audio is **generated procedurally at startup** and all snake/arena visuals
are code-built, so the shipped game carries no unlicensed media.

---

## Screenshots

Stored at the repository root and in `serpentis3d/shots/`:

- `qa_v13_menu.png`, `qa_v13_3d.png`, `qa_v13_2d.png`, `qa_v13_final.png`
- `serpentis3d/shots/shot_game.png`, `serpentis3d/shots/shot_mid.png`
