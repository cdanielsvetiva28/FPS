# STORMLINE

A single-player, story-driven shooter that crosses Call of Duty-style ground combat
with Ace Combat-style air combat. Built with **Godot 4.7** and **GDScript**.
Windows only, no online play. The story is in [docs/STORY.md](docs/STORY.md).

The game starts on a main menu with two test missions:

- **AIR: Flight Test "First Light"**: a preview of Mission 2
- **GROUND: Combat Test "The Compound"**

## Air combat

Wren and Lantern Lead (an AI wingman) intercept a Sevrin fighter sweep over an island.
Shoot down the first wave and a second arrives with a Stormcrow ace.

- **Arcade flight model:** mouse flight via a self-centring virtual stick, throttle with
  afterburner, stalls at low speed, climbing bleeds speed and diving builds it
- **Weapons:** cannon with glowing tracers; lock-on missiles from two alternating wing
  pylons (lock tone, then a solid tone when locked); flares that decoy incoming missiles
- **AI pilots** (enemies and your wingman share one AI): patrol, chase with lead pursuit,
  fire missiles and guns, break hard and pop flares when a missile is on them, and
  always avoid terrain
- **HUD:** speed, altitude, throttle, ammo, airframe health, target brackets, a lock ring
  that closes as the lock builds, an arrow to off-screen targets, radar, MISSILE /
  PULL UP / STALL warnings, and radio chatter subtitles
- **World:** a procedural island with mountains, sea and clouds, plus Weatherline pylons
  with blinking beacons
- **Feel:** chase and cockpit cameras, FOV widens with speed, engine sound follows
  throttle, Doppler on passing jets, smoke trails, explosions

| Action | Key |
|---|---|
| Pitch and roll | Mouse |
| Roll | Q / E |
| Rudder (yaw) | A / D |
| Throttle | W / S (full throttle = afterburner) |
| Cannon | Left mouse |
| Missile | Right mouse (lock on first for a guided shot) |
| Switch target | Space or Tab |
| Flares | F |
| Cockpit / chase camera | V |
| Pause / main menu | Esc, then M |

## Ground combat

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
| Pause | Esc (click or Esc to resume; M for main menu) |
| Fullscreen | F11 |

Rebind keys under **Project → Project Settings → Input Map**. At startup `Game` adds any
missing default bindings, so movement always works. If it had to add any, it prints them
to Godot's **Output** panel.

## Project layout

```
project.godot              Project settings, input map, autoloads
docs/STORY.md              The story bible
scenes/
  main_menu.tscn           Title screen (entry scene)
  flight/                  Flight test mission, jets, missile, explosion, flight HUD
  main.tscn                Ground test level
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
  main_menu.gd             Title screen
  flight/aircraft.gd       Shared flight model, health, destruction
  flight/player_jet.gd     Player controls, cannon, missiles, flares, cameras
  flight/ai_jet.gd         AI pilot for enemies and wingmen
  flight/missile.gd        Guided missile; flare.gd: decoy flares
  flight/bullet_manager.gd All cannon rounds, simulated and drawn together
  flight/terrain.gd        Procedural island; clouds.gd, landmarks.gd
  flight/flight_hud.gd     Flight HUD and radio subtitles
  flight/flight_mission.gd The "First Light" test mission: waves, radio, win/lose
assets/
  models/                  Jets exported from Blender (.glb)
  textures/                Generated PBR textures (albedo + normal maps)
  materials/               Materials for the level, guns and enemy
  sounds/                  Generated sound effects (.wav)
tools/                     Python scripts that generate textures, sounds and (via Blender) jets
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

### Jets (Blender)

The jets are built by a Blender Python script, so they're easy to modify: change
the numbers (wing shapes, fuselage sections, colours) and re-run it.

```
blender --background --python tools/blender/build_jets.py
```

Or open `tools/blender/build_jets.py` in Blender's **Scripting** tab and press
**Run Script**. It writes `assets/models/jet_halvard.glb` (the player's twin-tail
fighter) and `assets/models/jet_sevrin.glb` (the enemy delta-wing with canards).
You can also open the `.glb` files in Blender and edit them by hand. Keep the part
names `Afterburner_*`, `Missile_L`, `Missile_R` and `Canopy`, since the game looks them up.

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
3. ~~Story: see [docs/STORY.md](docs/STORY.md)~~
4. ~~Flight combat prototype~~
5. Mission framework: objectives, checkpoints, saving, radio dialogue for ground missions
6. Vertical slice: Mission 3 "Voice on the Radio", the first combined air + ground mission
7. Expand: the rest of the campaign, menus, settings, Windows export
