# NEON BEAT LIVE

Original five-lane rhythm-game prototype built in Godot 4.7.

## Play

Open `project.godot` in Godot, then press **F6/F5**. Select one of the 30 courses and start the live after a short countdown.

- Lanes: `A` `S` `D` `F` `G` `H`
- Mouse/touch: tap the appropriate lane
- Hold notes: keep the key pressed until the tail ends
- Flick notes: use the matching lane key (the arrow is a visual cue)
- Results screen: press any key or click to restart
- Key config: press `Tab`, click a lane, then press the desired key. Bindings persist between launches.
- Pause: press `Esc` during a live; press it again to resume.

## Optional streak rewards

Every 25-combo gives a small score bonus and restores 4 life. This is deliberately isolated in the `OPTIONAL FEATURE: STREAK REWARDS` block in `rhythm_game.gd`; set `FEATURE_STREAK_REWARDS` to `false` to disable it, or remove that marked block later without affecting lanes, courses, key config, or pause.

Balance adjustment: a miss now reduces life by 5.5 instead of 8, which makes the dense upper-level charts recoverable while still rewarding accuracy.

## Courses

There are 30 original courses. Each has its own title, BPM, level, chart length, and note-density profile. Levels 1–10 progressively introduce denser timing, simultaneous notes, holds, flicks, and six-lane patterns.

The project contains a fully original procedural backing track, procedural visual effects, and no third-party game assets.

## Validation status

The project has passed Godot 4.7 headless parse/startup validation. The Windows export preset is included in `export_presets.cfg`; the local Godot installation still needs its official Windows export templates installed before the `.exe` can be produced.
