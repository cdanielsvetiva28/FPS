# FPS

A single-player, story-driven first-person shooter built with **Godot 4.7** and **GDScript**.
Windows only, no online play.

## Current state: core combat loop

A walled compound split into a spawn yard and an enemy-held area. Clear out
five hostiles to win the area.

- **Player:** mouse look, walk/sprint, jump, head bob, 100 health, death and restart
- **Weapon:** hitscan rifle with fire rate, magazine and reserve ammo, reload, recoil,
  muzzle flash and bullet impacts. Headshots do 2.5x damage. Gunfire is loud: enemies nearby hear it.
- **Enemy AI:**
  - Guards hold a post; patrollers walk a route
  - See in a 120° cone with line-of-sight checks
  - Hear your gunfire and come to investigate (`?` above their head)
  - In combat (`!`) they face you, keep their distance, strafe, and fire in bursts.
    Accuracy drops with distance and when you're moving.
  - Spotting you alerts nearby allies
  - Lose track of you: hunt your last known position, then search, then give up
  - Pathfind around walls using a navigation mesh baked when the level loads
  - Drop ammo or health when killed
- **Pickups:** health packs and ammo boxes (ignored if you're already full)
- **HUD:** health bar, ammo, crosshair, hit marker (red on kill), red damage flash with an
  arrow toward the attacker, low-health tint, objective counter, pickup messages
- **Pause menu** (Esc or alt-tab), and a death screen with click-to-restart

## Running it

1. Open Godot 4.7, click **Import**, and pick this folder's `project.godot`.
2. Press **F5** (Run Project).

## Controls

| Action | Key |
|---|---|
| Move | W A S D or arrow keys |
| Sprint | Shift (while moving forward) |
| Jump | Space |
| Fire | Left mouse |
| Reload | R |
| Pause | Esc (click or Esc to resume) |
| Fullscreen | F11 |

Rebind keys under **Project → Project Settings → Input Map**. At startup `Game` adds any
missing default bindings, so movement always works. If it had to add any, it prints them
to Godot's **Output** panel.

## Project layout

```
project.godot              Project settings, input map, autoloads
scenes/
  main.tscn                Test level (entry scene)
  player.tscn              Player body, camera and weapon
  enemy.tscn               Enemy soldier
  hud.tscn                 On-screen UI, pause and death screens
  target.tscn              Practice dummy (not currently placed in the level)
  pickups/
    health_pickup.tscn
    ammo_pickup.tscn
scripts/
  game.gd                  Autoload "Game": input defaults, pause, restart, noise, messages
  main.gd                  Level logic: navmesh bake, HUD wiring, objective, death/restart
  player.gd                Movement, mouse look, health
  weapon.gd                Shooting, ammo, reload, recoil
  enemy.gd                 Enemy AI state machine
  pickup.gd                Health/ammo pickups
  hud.gd                   HUD updates
  target.gd                Practice dummy
assets/
  grid.svg                 Placeholder grid texture for the grey-box level
```

## Tuning

Most gameplay values are exported variables, so you can change them in the Inspector without
touching code. Select the `Player` node, `Player/Head/Camera3D/Weapon`, or any enemy.
Examples: walk/sprint speed, mouse sensitivity, damage, fire rate, magazine size, reload time,
enemy health, sight range, reaction time, accuracy and burst size.

### Building levels

- **Add an enemy:** instance `scenes/enemy.tscn`.
- **Make it patrol:** create a `Node3D` with `Marker3D` children as waypoints, then set the
  enemy's **Patrol Route** to it. With no route, the enemy guards its spawn spot and faces
  the way it was placed.
- **Level geometry:** put it under the `Level` node (a `NavigationRegion3D`) so enemies can
  pathfind on it. The navmesh is baked automatically when the level loads.

To make something shootable, give its script a
`take_damage(amount: float, from_position := Vector3.ZERO, hit_position := Vector3.ZERO) -> bool`
method. Return `true` when the hit kills it.

## Exporting a Windows build

1. **Editor → Manage Export Templates → Download and Install** (one time).
2. **Project → Export → Add… → Windows Desktop**.
3. Set the export path (for example `builds/FPS.exe`) and click **Export Project**.

`builds/` is git-ignored.

## Roadmap

1. ~~Prototype: controller, test level, hitscan weapon~~
2. ~~Core loop: enemy AI, player health and damage, pickups, pause, death/restart~~
3. Story layer: dialogue (e.g. Dialogic or Dialogue Manager), scripted triggers, checkpoints, save/load
4. Vertical slice: one fully polished level with real art, sound and story beats
5. Expand: more levels and weapons, menus, settings, Windows export
