# FPS

A single-player, story-driven first-person shooter built with **Godot 4.7** and **GDScript**.
Windows only, no online play.

## Current state: core combat loop

A walled compound split into a spawn yard and an enemy-held area. Clear out
five hostiles to win the area.

- **Player:** mouse look, walk/sprint/crouch, jump, head bob, footsteps, 100 health,
  death and restart
  - **Crouching** makes you slower, quieter and more accurate, and lets you hide behind
    low cover: enemies aim at your actual height. You can't stand up under a ceiling.
  - **Sprinting** is loud: nearby enemies hear your footsteps.
- **Weapons:** rifle (automatic), pistol (semi-auto) and pump shotgun (9 pellets)
  - Aim down sights with right click
  - Spread grows when moving, jumping and firing, and shrinks when crouching or aiming.
    The crosshair shows it.
  - Camera recoil, damage falloff over distance, and headshots for 2.5x damage
  - Weapon sway, bob and a sprint pose; the gun never pokes through walls
  - Muzzle flashes, bullet-hole decals, sparks and dust
  - Gunfire is loud: enemies nearby hear it
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
- **Pickups:** health packs, and ammo boxes that give every weapon a magazine
  (ignored if you're already full)
- **Art & audio:** textured concrete, block walls, metal and wooden crates, a detailed
  soldier model, and synthesized sound effects for everything
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
| Crouch | Ctrl (hold) or C (toggle) |
| Jump | Space |
| Fire | Left mouse |
| Aim down sights | Right mouse |
| Reload | R |
| Switch weapon | 1 / 2 / 3, mouse wheel, Q for last weapon |
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
  player.tscn              Player body, camera and weapon holder
  enemy.tscn               Enemy soldier
  hud.tscn                 On-screen UI, pause and death screens
  weapons/                 rifle.tscn, pistol.tscn, shotgun.tscn
  effects/impact.tscn      Bullet hole, sparks and dust
  pickups/                 health_pickup.tscn, ammo_pickup.tscn
  target.tscn              Practice dummy (not currently placed in the level)
scripts/
  game.gd                  Autoload "Game": input defaults, pause, restart, noise, messages, sounds
  main.gd                  Level logic: navmesh bake, HUD wiring, objective, death/restart
  player.gd                Movement, crouch, mouse look, footsteps, recoil, health
  weapon_holder.gd         Weapon switching, aiming down sights, sway and bob
  weapon.gd                One gun: firing, spread, recoil, ammo, reload
  enemy.gd                 Enemy AI state machine
  impact.gd                Bullet impact effect
  pickup.gd                Health/ammo pickups
  hud.gd, crosshair.gd     HUD and dynamic crosshair
  target.gd                Practice dummy
assets/
  textures/                Generated PBR textures (albedo + normal maps)
  materials/               Materials for the level, guns and enemy
  sounds/                  Generated sound effects (.wav)
tools/                     Python scripts that generate the textures and sounds
```

## Tuning

Most gameplay values are exported variables, so you can change them in the Inspector without
touching code. Select the `Player` node, `Player/Head/Camera3D/Weapon`, or any enemy.
Examples: walk/sprint speed, mouse sensitivity, damage, fire rate, magazine size, reload time,
enemy health, sight range, reaction time, accuracy and burst size.

### Weapons

Each gun is its own scene in `scenes/weapons/`. Select its root node to tune damage,
fire rate, spread, recoil, ammo, aim position and sounds. To add a gun, duplicate one of
these scenes and add it as a child of `Player/Head/Camera3D/WeaponHolder`.

The `WeaponHolder` is scaled to 0.4, which keeps the gun from clipping through walls.
Positions inside the weapon scenes are in normal (unscaled) units.

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

## Art and sound

All current textures and sounds are generated by the Python scripts in `tools/`. Tweak
the numbers and re-run them to change the look or sound:

```
pip install numpy pillow
python tools/generate_textures.py
python tools/generate_sounds.py
```

Godot re-imports changed files automatically. (`tools/` has a `.gdignore`, so Godot
doesn't try to import the scripts.)

### Swapping in real assets

Everything is set up so you can replace the placeholders with downloaded art:

- **Textures:** free CC0 PBR sets from Poly Haven or ambientCG. Replace the PNGs in
  `assets/textures/` (keep the file names), or point the materials in
  `assets/materials/` at the new files.
- **Gun models:** `.glb` files, e.g. Quaternius or Kenney packs. In a weapon scene, delete
  the parts under `Model` (keep `Muzzle` and `CyclePart`), drop the `.glb` in as a child of
  `Model`, then adjust **Hip Position** and **Aim Position** until the sights line up.
- **Enemy model:** replace the meshes under `Body` in `enemy.tscn`. Keep the `Gun/Muzzle`
  node, since shots and muzzle flashes come from it.
- **Sounds:** replace the `.wav` files in `assets/sounds/` (same names), or assign new
  ones on each weapon's **Sounds** settings.

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
