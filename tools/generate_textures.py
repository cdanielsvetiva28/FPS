"""Generate the game's placeholder PBR textures.

Every texture is tileable. Each material gets an albedo (colour) map and an
OpenGL-style normal map. Re-run this after tweaking anything below:

    pip install numpy pillow
    python tools/generate_textures.py

Output goes to assets/textures/. Godot re-imports the files automatically.
"""

from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 512
OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
rng = np.random.default_rng(1234)


# --- Noise helpers ---------------------------------------------------------

def fractal_noise(size: int, beta: float = 2.0, seed: int | None = None) -> np.ndarray:
    """Tileable 1/f^beta noise in [0, 1]. Higher beta = smoother."""
    r = np.random.default_rng(seed) if seed is not None else rng
    white = r.standard_normal((size, size))
    fx = np.fft.fftfreq(size)[:, None]
    fy = np.fft.fftfreq(size)[None, :]
    f = np.sqrt(fx**2 + fy**2)
    f[0, 0] = 1.0
    spectrum = np.fft.fft2(white) / f ** (beta / 2.0)
    spectrum[0, 0] = 0.0
    noise = np.real(np.fft.ifft2(spectrum))
    return normalize(noise)


def stretched_noise(size: int, stretch: int, beta: float = 2.0) -> np.ndarray:
    """Noise stretched along x, for wood grain and brushed metal."""
    small = fractal_noise(size, beta)[:: max(1, stretch), :]
    return normalize(np.repeat(small, stretch, axis=0)[:size, :].T)


def normalize(a: np.ndarray) -> np.ndarray:
    lo, hi = a.min(), a.max()
    return (a - lo) / (hi - lo + 1e-9)


def blur(a: np.ndarray, radius: int) -> np.ndarray:
    """Cheap tileable box blur."""
    out = a.copy()
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for offset in range(-radius, radius + 1):
            acc += np.roll(out, offset, axis=axis)
        out = acc / (2 * radius + 1)
    return out


def normal_map(height: np.ndarray, strength: float) -> np.ndarray:
    """OpenGL convention (green = up), as Godot expects."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    n = np.stack([-dx, dy, np.ones_like(height)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def colorize(t: np.ndarray, dark: tuple, light: tuple) -> np.ndarray:
    dark_a = np.array(dark, dtype=float)
    light_a = np.array(light, dtype=float)
    return dark_a + (light_a - dark_a) * t[..., None]


def save(name: str, albedo: np.ndarray, height: np.ndarray, strength: float) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(albedo, 0, 255).astype(np.uint8)).save(OUT / f"{name}_albedo.png", optimize=True)
    Image.fromarray(normal_map(height, strength)).save(OUT / f"{name}_normal.png", optimize=True)
    print(f"wrote {name}")


# --- Materials -------------------------------------------------------------

def concrete_floor() -> None:
    base = fractal_noise(SIZE, 2.2)
    detail = fractal_noise(SIZE, 1.0)
    stains = blur(fractal_noise(SIZE, 3.0), 4)
    t = 0.55 * base + 0.25 * detail + 0.2 * stains
    albedo = colorize(normalize(t), (88, 88, 86), (150, 148, 142))

    # Small pits.
    pits = rng.random((SIZE, SIZE)) > 0.9985
    pits = blur(pits.astype(float), 1) > 0.05
    albedo[pits] *= 0.6

    # Expansion joints along the tile edges.
    height = 0.6 * base + 0.4 * detail
    joint = np.zeros((SIZE, SIZE), dtype=bool)
    joint[:3, :] = True
    joint[:, :3] = True
    albedo[joint] *= 0.55
    height[joint] -= 1.5
    height[pits] -= 0.8
    save("concrete_floor", albedo, height, 2.0)


def block_wall() -> None:
    """Running-bond concrete blocks: 2 blocks per row, 4 rows per tile."""
    rows, cols = 4, 2
    bh, bw = SIZE // rows, SIZE // cols
    mortar = 6
    noise = fractal_noise(SIZE, 1.8)
    fine = fractal_noise(SIZE, 0.8)

    albedo = np.zeros((SIZE, SIZE, 3))
    height = np.zeros((SIZE, SIZE))
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    row = y // bh
    shifted_x = (x + (row % 2) * (bw // 2)) % SIZE
    col = shifted_x // bw
    block_id = row * cols + col
    shade = rng.uniform(0.85, 1.12, size=rows * cols)[block_id]

    in_mortar = ((y % bh) < mortar) | ((shifted_x % bw) < mortar)
    # Bevel: blocks get slightly lower toward their edges.
    edge_y = np.minimum(y % bh, bh - 1 - (y % bh))
    edge_x = np.minimum(shifted_x % bw, bw - 1 - (shifted_x % bw))
    bevel = np.clip(np.minimum(edge_x, edge_y) / 10.0, 0, 1)

    block_color = colorize(normalize(0.7 * noise + 0.3 * fine), (120, 116, 108), (172, 166, 154))
    albedo[:] = block_color * shade[..., None]
    albedo[in_mortar] = colorize(fine, (70, 68, 64), (95, 92, 86))[in_mortar]
    height = bevel * 1.0 + 0.25 * fine
    height[in_mortar] = 0.0
    save("block_wall", albedo, height, 3.0)


def metal_panel() -> None:
    """Painted steel plate with seams, rivets, scratches and worn edges."""
    brushed = stretched_noise(SIZE, 16, 1.5)
    blotches = fractal_noise(SIZE, 2.5)
    t = 0.5 * brushed + 0.5 * blotches
    albedo = colorize(normalize(t), (52, 64, 72), (78, 92, 100))
    height = 0.15 * brushed

    y, x = np.mgrid[0:SIZE, 0:SIZE]
    edge = np.minimum(np.minimum(x, SIZE - 1 - x), np.minimum(y, SIZE - 1 - y))
    seam = edge < 4
    height += np.clip(edge / 14.0, 0, 1)
    albedo[seam] = (30, 34, 38)

    # Rivets near the corners and edge midpoints.
    for cx in (24, SIZE // 2, SIZE - 24):
        for cy in (24, SIZE // 2, SIZE - 24):
            if cx == SIZE // 2 and cy == SIZE // 2:
                continue
            d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            dome = np.clip(1 - d / 9.0, 0, 1)
            height += dome * 1.5
            albedo[dome > 0] = albedo[dome > 0] * (1 + 0.25 * dome[dome > 0, None])

    # Scratches: bare metal shows through the paint.
    for _ in range(45):
        x0, y0 = rng.integers(0, SIZE, size=2)
        angle = rng.uniform(0, np.pi)
        length = rng.integers(10, 70)
        for i in range(length):
            px = int(x0 + np.cos(angle) * i) % SIZE
            py = int(y0 + np.sin(angle) * i) % SIZE
            albedo[py, px] = albedo[py, px] * 0.5 + np.array([120, 122, 120]) * 0.5
            height[py, px] -= 0.2

    # Worn paint near seams.
    wear = (fractal_noise(SIZE, 1.2) > 0.62) & (edge < 20)
    albedo[wear] = albedo[wear] * 0.4 + np.array([120, 118, 112]) * 0.6
    save("metal_panel", albedo, height, 2.5)


def wood_crate() -> None:
    """A crate face: outer frame plus horizontal planks. One tile = one face."""
    grain = stretched_noise(SIZE, 24, 1.2)
    rings = 0.5 + 0.5 * np.sin(grain * 40.0)
    knots = blur((rng.random((SIZE, SIZE)) > 0.99996).astype(float), 6) > 0.01
    t = normalize(0.6 * grain + 0.4 * rings)
    albedo = colorize(t, (104, 72, 40), (168, 126, 76))
    albedo[knots] *= 0.6

    y, x = np.mgrid[0:SIZE, 0:SIZE]
    height = 0.3 * grain
    frame = 48
    in_frame = (x < frame) | (x >= SIZE - frame) | (y < frame) | (y >= SIZE - frame)
    # Vertical grain on the side rails of the frame.
    vertical = stretched_noise(SIZE, 24, 1.2).T
    side_rails = ((x < frame) | (x >= SIZE - frame)) & ~((y < frame) | (y >= SIZE - frame))
    albedo[side_rails] = colorize(vertical, (96, 66, 36), (156, 116, 70))[side_rails]
    height[in_frame] += 1.0

    # Plank seams inside the frame.
    plank_h = (SIZE - 2 * frame) // 4
    seam = ~in_frame & (((y - frame) % plank_h) < 3)
    albedo[seam] *= 0.45
    height[seam] -= 0.8

    # Frame edges and nails.
    border = (
        (np.abs(x - frame) < 2) | (np.abs(x - (SIZE - frame)) < 2)
        | (np.abs(y - frame) < 2) | (np.abs(y - (SIZE - frame)) < 2)
        | (x < 3) | (x >= SIZE - 3) | (y < 3) | (y >= SIZE - 3)
    )
    albedo[border] *= 0.5
    for cx in (frame // 2, SIZE - frame // 2):
        for cy in range(frame // 2, SIZE, SIZE // 6):
            d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            nail = d < 4
            albedo[nail] = (60, 60, 62)
            height[nail] += 0.5
    save("wood_crate", albedo, height, 2.5)


def bullet_hole() -> None:
    """RGBA decal: dark hole, cracked rim, soft dust ring."""
    size = 128
    y, x = np.mgrid[0:size, 0:size] - size / 2 + 0.5
    r = np.sqrt(x**2 + y**2) / (size / 2)
    angle = np.arctan2(y, x)
    jitter = 0.08 * np.sin(angle * 7 + 1.3) + 0.05 * np.sin(angle * 13)
    hole = r < 0.18 + jitter * 0.5
    rim = (r < 0.34 + jitter) & ~hole
    dust = np.clip(1 - r, 0, 1) ** 2

    rgba = np.zeros((size, size, 4))
    rgba[..., :3] = 40
    rgba[..., 3] = dust * 120
    rgba[rim, :3] = 70
    rgba[rim, 3] = 220
    rgba[hole, :3] = 8
    rgba[hole, 3] = 255
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba.astype(np.uint8), "RGBA").save(OUT / "bullet_hole.png", optimize=True)
    print("wrote bullet_hole")


def muzzle_flash() -> None:
    """RGBA star-burst sprite for muzzle flashes."""
    size = 128
    y, x = np.mgrid[0:size, 0:size] - size / 2 + 0.5
    r = np.sqrt(x**2 + y**2) / (size / 2)
    angle = np.arctan2(y, x)
    spikes = np.clip(np.cos(angle * 4) ** 8 + 0.6 * np.cos(angle * 4 + np.pi / 4) ** 16, 0, 1)
    intensity = np.clip(1 - r / (0.35 + 0.65 * spikes), 0, 1) ** 1.5
    core = np.clip(1 - r / 0.25, 0, 1)
    rgba = np.zeros((size, size, 4))
    rgba[..., 0] = 255
    rgba[..., 1] = 170 + 85 * core
    rgba[..., 2] = 60 + 195 * core
    rgba[..., 3] = np.clip(intensity + core, 0, 1) * 255
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba.astype(np.uint8), "RGBA").save(OUT / "muzzle_flash.png", optimize=True)
    print("wrote muzzle_flash")


def save_rgba(name: str, rgba: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA").save(OUT / f"{name}.png", optimize=True)
    print(f"wrote {name}")


def grime() -> None:
    """Near-white dirt/rust overlay, multiplied over painted props."""
    blotch = fractal_noise(SIZE, 2.4)
    speck = fractal_noise(SIZE, 0.6)
    y = np.mgrid[0:SIZE, 0:SIZE][0] / SIZE
    streaks = stretched_noise(SIZE, 32, 1.0).T  # vertical rain streaks
    dirt = np.clip(0.55 * blotch + 0.25 * streaks + 0.2 * speck, 0, 1)
    t = 1.0 - 0.45 * np.clip((dirt - 0.45) * 2.2, 0, 1)
    albedo = np.stack([t * 255, t * 246, t * 232], axis=-1)
    rust = (fractal_noise(SIZE, 1.6) > 0.72) & (blotch > 0.5)
    albedo[rust] = albedo[rust] * np.array([0.85, 0.62, 0.45])
    save("grime", albedo, 0.3 * blotch + 0.3 * speck + 0.1 * y, 1.2)


def wood_planks() -> None:
    grain = stretched_noise(SIZE, 24, 1.2)
    rings = 0.5 + 0.5 * np.sin(grain * 38.0)
    t = normalize(0.6 * grain + 0.4 * rings)
    albedo = colorize(t, (150, 115, 80), (230, 200, 160))
    y = np.mgrid[0:SIZE, 0:SIZE][0]
    seam = (y % (SIZE // 4)) < 3
    albedo[seam] *= 0.45
    height = 0.4 * grain
    height[seam] -= 1.0
    save("wood_planks", albedo, height, 2.0)


def fabric() -> None:
    """Coarse burlap weave."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    weave = (np.sin(x * 2 * np.pi / 6) * np.sin(y * 2 * np.pi / 6))
    fuzz = fractal_noise(SIZE, 1.0)
    t = normalize(0.5 * weave + 0.5 * fuzz)
    albedo = colorize(t, (180, 170, 150), (245, 238, 220))
    save("fabric", albedo, weave * 0.6 + fuzz * 0.4, 1.5)


def rock() -> None:
    base = fractal_noise(SIZE, 1.9)
    cracks = np.abs(fractal_noise(SIZE, 1.4) - 0.5) < 0.012
    strata = 0.5 + 0.5 * np.sin(np.mgrid[0:SIZE, 0:SIZE][0] * 0.08 + base * 6)
    t = normalize(0.65 * base + 0.35 * strata)
    albedo = colorize(t, (95, 90, 84), (168, 160, 150))
    albedo[cracks] *= 0.4
    height = base * 1.0 + strata * 0.3
    height[cracks] -= 0.8
    save("rock", albedo, height, 3.0)


def grass() -> None:
    blades = fractal_noise(SIZE, 0.5)
    patches = fractal_noise(SIZE, 2.6)
    t = normalize(0.5 * blades + 0.5 * patches)
    albedo = colorize(t, (52, 78, 32), (120, 150, 62))
    dry = patches > 0.7
    albedo[dry] = albedo[dry] * 0.6 + np.array([150, 135, 80]) * 0.4
    save("grass", albedo, blades * 0.6 + patches * 0.4, 1.5)


def sand() -> None:
    ripples = 0.5 + 0.5 * np.sin(np.mgrid[0:SIZE, 0:SIZE][1] * 0.15 + fractal_noise(SIZE, 2.2) * 8)
    grain = fractal_noise(SIZE, 0.4)
    t = normalize(0.4 * ripples + 0.6 * grain)
    albedo = colorize(t, (176, 158, 118), (226, 210, 168))
    save("sand", albedo, ripples * 0.6 + grain * 0.3, 1.5)


def snow() -> None:
    drift = fractal_noise(SIZE, 2.2)
    sparkle = fractal_noise(SIZE, 0.3)
    t = normalize(0.7 * drift + 0.3 * sparkle)
    albedo = colorize(t, (205, 214, 228), (250, 252, 255))
    save("snow", albedo, drift, 1.0)


def water_normal() -> None:
    """Tileable small-wave normal map (the water shader scrolls two copies)."""
    waves = fractal_noise(SIZE, 2.0) * 0.7 + fractal_noise(SIZE, 1.2) * 0.3
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(normal_map(waves, 6.0)).save(OUT / "water_normal.png", optimize=True)
    print("wrote water_normal")


def chainlink() -> None:
    """Diamond chain-link mesh with transparency, one tile = 4 x 4 diamonds."""
    size = 256
    y, x = np.mgrid[0:size, 0:size].astype(float)
    period = size / 4
    u = (x + y) % period
    v = (x - y) % period
    wire = (np.minimum(u, period - u) < 2.2) | (np.minimum(v, period - v) < 2.2)
    rgba = np.zeros((size, size, 4))
    rgba[..., :3] = 165
    rgba[wire, 3] = 255
    save_rgba("chainlink", rgba)


def cloud_puff() -> None:
    """Soft round cloud sprite with a lumpy edge and a slightly darker base."""
    size = 256
    y, x = np.mgrid[0:size, 0:size] - size / 2 + 0.5
    r = np.sqrt(x**2 + y**2) / (size / 2)
    lumps = blur(fractal_noise(size, 3.2, seed=3), 3)
    edge = np.clip((1.0 - r) * 1.8 + (lumps - 0.5) * 1.2, 0, 1)
    alpha = blur(edge, 2) ** 1.6
    shade = 0.82 + 0.18 * np.clip(-y / (size / 2) + 0.4, 0, 1)
    rgba = np.zeros((size, size, 4))
    rgba[..., 0] = 255 * shade
    rgba[..., 1] = 255 * shade
    rgba[..., 2] = 255 * np.clip(shade + 0.03, 0, 1)
    rgba[..., 3] = alpha * 255
    save_rgba("cloud_puff", rgba)


if __name__ == "__main__":
    concrete_floor()
    block_wall()
    metal_panel()
    wood_crate()
    bullet_hole()
    muzzle_flash()
    grime()
    wood_planks()
    fabric()
    rock()
    grass()
    sand()
    snow()
    water_normal()
    chainlink()
    cloud_puff()
