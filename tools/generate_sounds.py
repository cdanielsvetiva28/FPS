"""Synthesize the game's placeholder sound effects.

Everything is built from filtered noise, sine waves and envelopes, so no
recordings are needed. Re-run after tweaking:

    pip install numpy
    python tools/generate_sounds.py

Output goes to assets/sounds/ as 16-bit mono WAV files.
"""

import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"
rng = np.random.default_rng(42)


# --- Building blocks -------------------------------------------------------

def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(RATE * seconds)) / RATE


def noise(seconds: float) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, int(RATE * seconds))


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    """One-pole low-pass filter."""
    a = 1.0 - np.exp(-2.0 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    return x - lowpass(x, cutoff)


def bandpass(x: np.ndarray, low: float, high: float) -> np.ndarray:
    return highpass(lowpass(x, high), low)


def decay(seconds: float, time_constant: float, attack: float = 0.001) -> np.ndarray:
    t = t_axis(seconds)
    env = np.exp(-t / time_constant)
    attack_samples = max(1, int(RATE * attack))
    env[:attack_samples] *= np.linspace(0.0, 1.0, attack_samples)
    return env


def sine_sweep(seconds: float, f_start: float, f_end: float) -> np.ndarray:
    t = t_axis(seconds)
    freq = f_end + (f_start - f_end) * np.exp(-t * 30.0)
    return np.sin(2 * np.pi * np.cumsum(freq) / RATE)


def mix(length: float, *parts: tuple[float, np.ndarray]) -> np.ndarray:
    """Place each (start_time, signal) into a buffer `length` seconds long."""
    out = np.zeros(int(RATE * length))
    for start, sig in parts:
        i = int(RATE * start)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += sig[:n]
    return out


def save(name: str, x: np.ndarray, peak: float = 0.9, fade_out: bool = True) -> None:
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    if fade_out:  # Short fade to avoid a click at the end. Loops skip it.
        fade = min(len(x), int(RATE * 0.01))
        x[-fade:] *= np.linspace(1.0, 0.0, fade)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((x * 32767).astype(np.int16).tobytes())
    print(f"wrote {name}")


# --- Sounds ----------------------------------------------------------------

def gunshot(length: float, crack: float, body_cutoff: float, body_decay: float,
            thump_hz: float, thump_level: float, tail_decay: float) -> np.ndarray:
    crack_sig = highpass(noise(0.02), 2000) * decay(0.02, 0.003) * crack
    body = lowpass(noise(length), body_cutoff) * decay(length, body_decay) * 3.0
    thump = sine_sweep(length, thump_hz * 2.5, thump_hz) * decay(length, 0.06) * thump_level
    tail = lowpass(noise(length), 900) * decay(length, tail_decay, attack=0.02) * 1.5
    return mix(length, (0, crack_sig), (0, body), (0, thump), (0.01, tail))


def click(length: float, cutoff_low: float, cutoff_high: float, time_constant: float) -> np.ndarray:
    return bandpass(noise(length), cutoff_low, cutoff_high) * decay(length, time_constant, 0.0005)


def rifle_shot() -> None:
    save("rifle_shot", gunshot(0.6, 1.0, 3500, 0.03, 70, 0.8, 0.18))


def pistol_shot() -> None:
    save("pistol_shot", gunshot(0.45, 1.2, 4500, 0.02, 110, 0.5, 0.12))


def shotgun_shot() -> None:
    save("shotgun_shot", gunshot(0.9, 0.8, 2200, 0.06, 55, 1.2, 0.3))


def enemy_shot() -> None:
    # Heard from a distance: duller, less crack, more tail.
    x = gunshot(0.7, 0.3, 1800, 0.04, 80, 0.6, 0.25)
    save("enemy_shot", lowpass(x, 2500), peak=0.8)


def dry_fire() -> None:
    save("dry_fire", click(0.08, 1500, 6000, 0.006), peak=0.5)


def reload() -> None:
    mag_out = click(0.1, 800, 4000, 0.01)
    mag_in = click(0.12, 400, 3000, 0.015) * 1.3
    bolt_back = click(0.08, 1200, 6000, 0.008)
    bolt_fwd = click(0.1, 600, 5000, 0.012) * 1.2
    save("reload", mix(1.3, (0.05, mag_out), (0.55, mag_in), (0.95, bolt_back), (1.08, bolt_fwd)), peak=0.6)


def shotgun_pump() -> None:
    back = click(0.12, 500, 3500, 0.02)
    fwd = click(0.12, 700, 4500, 0.015) * 1.2
    save("shotgun_pump", mix(0.4, (0.0, back), (0.2, fwd)), peak=0.6)


def weapon_switch() -> None:
    cloth = bandpass(noise(0.25), 300, 2500) * decay(0.25, 0.06, 0.03) * 0.5
    latch = click(0.06, 1500, 6000, 0.005)
    save("weapon_switch", mix(0.3, (0.0, cloth), (0.18, latch)), peak=0.45)


def footsteps() -> None:
    for i in range(4):
        heel = lowpass(noise(0.12), 900 + 150 * i) * decay(0.12, 0.018)
        grit = bandpass(noise(0.1), 2000, 6000) * decay(0.1, 0.02) * 0.25
        save(f"footstep_{i + 1}", mix(0.15, (0.0, heel), (0.01, grit)), peak=0.35)


def land() -> None:
    thud = lowpass(noise(0.25), 400) * decay(0.25, 0.05) * 2
    save("land", thud + sine_sweep(0.25, 120, 50) * decay(0.25, 0.05) * 0.5, peak=0.5)


def hitmarker() -> None:
    t = t_axis(0.06)
    tick = np.sin(2 * np.pi * 2400 * t) * decay(0.06, 0.012)
    save("hitmarker", tick, peak=0.35)


def kill_confirm() -> None:
    t = t_axis(0.14)
    tone = (np.sin(2 * np.pi * 1800 * t) + 0.5 * np.sin(2 * np.pi * 2700 * t)) * decay(0.14, 0.04)
    save("kill_confirm", tone, peak=0.4)


def pickup() -> None:
    t = t_axis(0.12)
    note_a = np.sin(2 * np.pi * 880 * t) * decay(0.12, 0.05)
    note_b = np.sin(2 * np.pi * 1320 * t) * decay(0.12, 0.06)
    save("pickup", mix(0.25, (0.0, note_a), (0.08, note_b)), peak=0.4)


def player_hurt() -> None:
    thud = lowpass(noise(0.3), 300) * decay(0.3, 0.06) * 2
    grunt = bandpass(noise(0.25), 150, 700) * decay(0.25, 0.08, 0.02)
    save("player_hurt", mix(0.3, (0.0, thud), (0.0, grunt)), peak=0.6)


def bullet_impact() -> None:
    for i in range(3):
        crack = bandpass(noise(0.15), 1500 + 800 * i, 7000) * decay(0.15, 0.012)
        debris = bandpass(noise(0.2), 800, 4000) * decay(0.2, 0.04, 0.01) * 0.3
        save(f"impact_{i + 1}", mix(0.2, (0.0, crack), (0.0, debris)), peak=0.4)


def enemy_death() -> None:
    fall = lowpass(noise(0.6), 350) * decay(0.6, 0.08, 0.25) * 2
    gear = click(0.15, 600, 4000, 0.02)
    save("enemy_death", mix(0.7, (0.0, fall), (0.3, gear)), peak=0.6)


# --- Flight ----------------------------------------------------------------------

def make_loop(x: np.ndarray, crossfade: float = 0.25) -> np.ndarray:
    """Crossfade the end into the start so the sound loops seamlessly."""
    n = int(RATE * crossfade)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    fade = np.linspace(0.0, 1.0, n)
    return np.concatenate([tail * (1 - fade) + head * fade, body])


def jet_engine() -> None:
    """Looping turbine roar: low rumble, mid roar and a high whine."""
    length = 3.0
    t = t_axis(length)
    rumble = lowpass(noise(length), 120) * 6.0
    roar = bandpass(noise(length), 200, 1400) * 1.5
    whine = (np.sin(2 * np.pi * 2900 * t) * 0.05 + np.sin(2 * np.pi * 4350 * t) * 0.025)
    wobble = 1.0 + 0.08 * np.sin(2 * np.pi * 0.7 * t)
    save("jet_engine", make_loop((rumble + roar + whine) * wobble), peak=0.7, fade_out=False)


def cannon_shot() -> None:
    pop = bandpass(noise(0.07), 300, 5000) * decay(0.07, 0.012)
    thump = sine_sweep(0.07, 160, 70) * decay(0.07, 0.02) * 0.6
    save("cannon_shot", pop + thump, peak=0.6)


def missile_launch() -> None:
    length = 1.6
    ignition = lowpass(noise(0.3), 600) * decay(0.3, 0.06) * 2.0
    hiss = bandpass(noise(length), 800, 7000) * decay(length, 0.6, attack=0.05)
    save("missile_launch", mix(length, (0.0, ignition), (0.0, hiss)), peak=0.7)


def explosion() -> None:
    length = 2.8
    blast = lowpass(noise(length), 500) * decay(length, 0.35, attack=0.004) * 3.0
    crack = bandpass(noise(0.15), 1000, 6000) * decay(0.15, 0.03)
    boom = sine_sweep(length, 90, 35) * decay(length, 0.4) * 1.5
    rumble = lowpass(noise(length), 120) * decay(length, 0.9, attack=0.1) * 3.0
    save("explosion", mix(length, (0.0, blast), (0.0, crack), (0.0, boom), (0.05, rumble)), peak=0.9)


def tone(name: str, freq: float, length: float, peak: float, loop: bool = False) -> None:
    t = t_axis(length)
    x = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 2 * t)
    if not loop:
        x *= np.minimum(1.0, np.minimum(t / 0.005, (length - t) / 0.01))
    save(name, x, peak=peak, fade_out=not loop)


def flare() -> None:
    pop = bandpass(noise(0.08), 500, 4000) * decay(0.08, 0.015)
    fizz = bandpass(noise(0.8), 2000, 9000) * decay(0.8, 0.25, attack=0.02) * 0.4
    save("flare", mix(0.9, (0.0, pop), (0.02, fizz)), peak=0.5)


if __name__ == "__main__":
    rifle_shot()
    pistol_shot()
    shotgun_shot()
    enemy_shot()
    dry_fire()
    reload()
    shotgun_pump()
    weapon_switch()
    footsteps()
    land()
    hitmarker()
    kill_confirm()
    pickup()
    player_hurt()
    bullet_impact()
    enemy_death()
    jet_engine()
    cannon_shot()
    missile_launch()
    explosion()
    tone("lock_seek", 950, 0.07, 0.3)
    tone("lock_solid", 1250, 0.5, 0.25, loop=True)
    tone("missile_alert", 1750, 0.09, 0.35)
    flare()
