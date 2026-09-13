# Game-dev primer for experienced developers

You know architecture, testing and versioning. This is the vocabulary and the mental-model shifts you need for *this* project. Skim it once; come back when something feels alien.

## 1. The frame loop replaces request/response

A game is `while running: read input → update world(dt) → draw`. Sixty times a second. There is no request; state lives in memory and mutates continuously. Two consequences:

- **Two clocks.** Godot calls `_process(delta)` every rendered frame (variable rate) and `_physics_process(delta)` at a fixed rate (60 Hz by default). Movement, collisions and anything that must be reproducible go in `_physics_process`. Animations and UI polish go in `_process`. Our simulation clock (`Commands.tick`) advances once per physics step, which is why `Evaluation.TICKS_PER_SECOND = 60`.
- **`delta` is your integrator.** Never `position.x += 1`; always `position.x += speed * delta`, or movement speed depends on frame rate.

## 2. Nodes and scenes = a tree of components

Godot's unit of composition is the **Node**. A **Scene** is a saved subtree (`.tscn`) you can instantiate many times — think "prefab" or "component". The running game is one big tree. Rules of thumb:

- A node does one thing: `MeshInstance3D` draws, `CollisionShape3D` defines a shape, `Camera3D` looks, `Label3D` writes text in space. You build behaviour by composing them under a parent that has a script.
- `@onready var mesh: MeshInstance3D = $Mesh` grabs a child by name once the tree is ready.
- Node lifecycle: `_init` (constructor, no tree yet) → `_ready` (children exist, safe to touch them) → per-frame callbacks → `queue_free()` to delete at end of frame.
- **Autoloads** are singletons auto-added to the tree root (`GameSession`, `GameEvents`). Use them for glue, not for logic.

## 3. Signals = observer pattern, first class

`signal item_placed(item_id: String, ...)` declares; `item_placed.emit(...)` fires; `node.item_placed.connect(callable)` subscribes. Signals are how features stay decoupled. Our `GameEvents` bus is just a node full of signals. Connecting in `_ready` and forgetting to disconnect is fine when the subscriber is freed (Godot disconnects automatically).

## 4. 3D coordinates and transforms

- Right-handed, **Y up**, **−Z is forward**. A camera looks down its local −Z. That is why `player.gd` uses `-camera.global_transform.basis.z` for "the direction I'm facing".
- `Transform3D = basis (rotation+scale, 3×3) + origin (position)`. `global_position` vs `position` (local to parent) — mixing them is the classic bug.
- Units are metres. A person is ~1.8 m; keep the world at real scale so physics constants make sense.

## 5. Physics bodies (Godot 4, Jolt)

| Body | Moves by | Use for |
|---|---|---|
| `StaticBody3D` | never | ground, walls, our placeholder items/containers |
| `CharacterBody3D` | your code via `move_and_slide()` | the player |
| `RigidBody3D` | the physics engine | thrown/tumbling props (non-deterministic — presentation only!) |
| `Area3D` | n/a, detects overlaps | trigger zones, "near a container" |

`RayCast3D` is a laser from a point along a direction that reports the first collider — our interaction pointer. Collision **layers** (what I am) and **masks** (what I see) are bitmasks; we haven't needed them yet but you will for "ray ignores the player's own body".

## 6. First-person controller in 30 lines

Yaw rotates the body (`rotate_y`), pitch rotates only the camera (clamped so you can't flip). Gravity is manual: `velocity.y -= g * delta` when not on floor. Horizontal velocity comes from `Input.get_vector` mapped through the body's basis so "forward" follows where you look. `move_and_slide()` does collision response. That is all of `player.gd`; the rest is feel (acceleration curves, head bob, coyote time) which is phase-1 polish.

## 7. Input map

Never read raw keys. `project.godot` maps actions (`interact`, `jump`) to keys/buttons; code asks `Input.is_action_pressed("jump")`. Rebinding, gamepads and touch become configuration, not code.

## 8. Resources and imports

Anything under `res://` is a resource. Non-native files (PNG, glTF, CSV) get an `.import` sidecar and are converted into `.godot/imported/`. **Commit the `.import`, ignore `.godot/`.** After cloning, run `godot --headless --import` once.

## 9. Determinism and why we care before we have multiplayer

Floating-point physics, unordered dictionaries and wall-clock time all produce different results on different machines. For co-op, every peer must agree on *what is where*. Our answer: the authoritative truth is discrete (item → slot), decided by pure functions, driven by explicit commands, and replicated as events. Physics and positions are cosmetic. Read `ARCHITECTURE.md §5` — it is the single most important architectural constraint in the repo.

## 10. "Game feel" is a real engineering discipline

Players judge the game by the 200 ms around each action: anticipation, the hit, the feedback (sound, flash, tiny screen shake, particle), and the recovery. It cannot be unit tested, so every WP with visible behaviour ends with a *playtest checklist*. Budget time for it; it is where a correct prototype becomes a game.

## 11. Vocabulary

**HUD** on-screen UI · **Prefab/Scene** reusable subtree · **Spawn** instantiate into the world · **Tick** one fixed simulation step · **Authority** the peer allowed to mutate state · **Lockstep / rollback** netcode families we deliberately avoid · **Gray-box** placeholder geometry to test mechanics before art · **Vertical slice** one thin path through every layer, end to end (that's what phase 0 built) · **Juice** feedback polish that makes actions feel good.

## 12. Further reading (when you want it)

Godot docs "Step by step" and "Your first 3D game"; the "Game Programming Patterns" book (free online) — the Command, Observer, Game Loop and Update Method chapters map 1:1 onto this codebase; GDC talk "Juice it or lose it" (10 min) for §10.
