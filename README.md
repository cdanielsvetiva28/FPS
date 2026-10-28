# FPS

A single-player, story-driven first-person shooter built with **Godot 4.7** and **GDScript**.
Windows only, no online play.

## Current state: prototype

The first milestone: a test arena where you can move around and shoot targets.

- First-person controller: mouse look, walk/sprint, jump, head bob
- Hitscan weapon: fire rate, magazine and reserve ammo, reload, recoil, muzzle flash, bullet impacts
- Shootable practice targets that flash on hit, die, and respawn (some move)
- HUD: crosshair, hit marker (red on kill), ammo counter, reload indicator
- Grey-box test level built from CSG shapes: walls, crates, cover, a ramp and a platform

## Running it

1. Open Godot 4.7, click **Import**, and pick this folder's `project.godot`.
2. Press **F5** (Run Project).

## Controls

| Action | Key |
|---|---|
| Move | W A S D |
| Sprint | Shift (while moving forward) |
| Jump | Space |
| Fire | Left mouse |
| Reload | R |
| Release mouse | Esc (click to recapture) |
| Fullscreen | F11 |

Rebind keys under **Project → Project Settings → Input Map**.

## Project layout

```
project.godot        Project settings and input map
scenes/
  main.tscn          Test level (entry scene)
  player.tscn        Player body, camera and weapon
  target.tscn        Practice dummy
  hud.tscn           On-screen UI
scripts/
  player.gd          Movement and mouse look
  weapon.gd          Shooting, ammo, reload, recoil
  target.gd          Health, hit flash, death/respawn
  hud.gd             HUD updates
  main.gd            Connects weapon signals to the HUD; fullscreen toggle
assets/
  grid.svg           Placeholder grid texture for the grey-box level
```

## Tuning

Most gameplay values are exported variables, so you can change them in the Inspector without
touching code. Select the `Player` node, or `Player/Head/Camera3D/Weapon`, or any `Target`.
Examples: walk/sprint speed, mouse sensitivity, damage, fire rate, magazine size, reload time,
and target health.

To make something shootable, give its script a `take_damage(amount: float) -> bool` method.
Return `true` when the hit kills it.

## Exporting a Windows build

1. **Editor → Manage Export Templates → Download and Install** (one time).
2. **Project → Export → Add… → Windows Desktop**.
3. Set the export path (for example `builds/FPS.exe`) and click **Export Project**.

`builds/` is git-ignored.

## Roadmap

1. ~~Prototype: controller, test level, hitscan weapon~~
2. Core loop: enemy AI (state machine + `NavigationAgent3D`), player health and damage, ammo pickups
3. Story layer: dialogue (e.g. Dialogic or Dialogue Manager), scripted triggers, checkpoints, save/load
4. Vertical slice: one fully polished level with real art, sound and story beats
5. Expand: more levels and weapons, menus, settings, Windows export
