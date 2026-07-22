#!/usr/bin/env python3
"""Render project-original Pixel Night Shift SFX candidates.

The generator uses only deterministic oscillators and seeded noise. It never
reads source audio. Candidate files intentionally live under ``.godot/`` so a
render cannot replace runtime assets before the sounds have been reviewed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np

try:
    import pedalboard
    from pedalboard import (
        Bitcrush,
        Clipping,
        Compressor,
        HighpassFilter,
        Limiter,
        LowpassFilter,
        Pedalboard,
        Reverb,
    )
except ImportError as exc:  # pragma: no cover - depends on the invoking runtime
    raise SystemExit(
        "Spotify Pedalboard is required. Run this with the bundled workspace "
        "Python; do not install a project runtime dependency."
    ) from exc


SAMPLE_RATE = 22_050
GENERATOR_VERSION = "1.0.0"
DEFAULT_OUTPUT = ".godot/audio-candidates/original-sfx-v1"


@dataclass(frozen=True)
class SoundSpec:
    duration: float
    seed: int
    target_peak: float
    purpose: str


SPECS = {
    "combat_hit": SoundSpec(
        0.145,
        41_057,
        0.68,
        "Soft digital impact for frequent automatic-combat playback.",
    ),
    "enemy_break": SoundSpec(
        0.560,
        41_063,
        0.78,
        "Layered impact and falling fragments for enemy defeat.",
    ),
    "operator_upgrade": SoundSpec(
        0.760,
        41_071,
        0.74,
        "Compact rising arpeggio for a successful operator upgrade.",
    ),
    "boss_warning": SoundSpec(
        0.960,
        41_077,
        0.80,
        "Low, repeating alarm that stays distinct from ordinary combat.",
    ),
}


def _time(duration: float) -> np.ndarray:
    frame_count = int(round(duration * SAMPLE_RATE))
    return np.arange(frame_count, dtype=np.float64) / SAMPLE_RATE


def _fade_edges(signal: np.ndarray, seconds: float = 0.004) -> None:
    frames = min(int(round(seconds * SAMPLE_RATE)), signal.size // 2)
    if frames <= 0:
        return
    fade = np.sin(np.linspace(0.0, math.pi / 2.0, frames, endpoint=True)) ** 2
    signal[:frames] *= fade
    signal[-frames:] *= fade[::-1]


def _exp_event(
    t: np.ndarray,
    start: float,
    length: float,
    attack: float,
    decay: float,
) -> tuple[np.ndarray, np.ndarray]:
    local = t - start
    active = (local >= 0.0) & (local < length)
    envelope = np.zeros_like(t)
    x = local[active]
    rise = 1.0 - np.exp(-x / max(attack, 1e-5))
    fall = np.exp(-x / max(decay, 1e-5))
    edge = np.minimum(1.0, np.maximum(0.0, (length - x) / 0.008))
    envelope[active] = rise * fall * edge
    return local, envelope


def _chirp(
    t: np.ndarray,
    start: float,
    length: float,
    frequency_start: float,
    frequency_end: float,
    attack: float,
    decay: float,
    waveform: str = "sine",
    phase_offset: float = 0.0,
) -> np.ndarray:
    local, envelope = _exp_event(t, start, length, attack, decay)
    progress = np.clip(local / max(length, 1e-5), 0.0, 1.0)
    frequency = frequency_start * np.power(
        max(frequency_end, 1e-5) / max(frequency_start, 1e-5), progress
    )
    phase = 2.0 * math.pi * np.cumsum(frequency, dtype=np.float64) / SAMPLE_RATE
    phase += phase_offset
    sine = np.sin(phase)
    if waveform == "triangle":
        carrier = (2.0 / math.pi) * np.arcsin(sine)
    elif waveform == "soft_square":
        carrier = np.tanh(2.2 * sine)
    else:
        carrier = sine
    return carrier * envelope


def _smoothed_noise(rng: np.random.Generator, frames: int, width: int) -> np.ndarray:
    noise = rng.standard_normal(frames)
    if width <= 1:
        return noise
    kernel = np.hanning(width * 2 + 1)
    kernel /= np.sum(kernel)
    return np.convolve(noise, kernel, mode="same")


def _finish(signal: np.ndarray, board: Pedalboard, target_peak: float) -> np.ndarray:
    signal = np.asarray(signal, dtype=np.float32)
    signal -= float(np.mean(signal))
    processed = np.asarray(board(signal, SAMPLE_RATE, reset=True), dtype=np.float32)
    if processed.ndim == 2:
        processed = np.mean(processed, axis=0, dtype=np.float32)
    processed = processed.reshape(-1)[: signal.size]
    if processed.size < signal.size:
        processed = np.pad(processed, (0, signal.size - processed.size))
    if not np.all(np.isfinite(processed)):
        raise RuntimeError("Rendered candidate contains NaN or infinite samples.")
    processed -= float(np.mean(processed))
    _fade_edges(processed)
    peak = float(np.max(np.abs(processed)))
    if peak <= 1e-8:
        raise RuntimeError("Rendered candidate is silent.")
    processed *= target_peak / peak
    return processed.astype(np.float32, copy=False)


def _combat_hit(spec: SoundSpec) -> np.ndarray:
    t = _time(spec.duration)
    rng = np.random.default_rng(spec.seed)
    signal = 0.55 * _chirp(t, 0.0, 0.120, 285.0, 108.0, 0.0015, 0.040)
    signal += 0.16 * _chirp(t, 0.0, 0.072, 1_480.0, 760.0, 0.0008, 0.018)
    _, transient = _exp_event(t, 0.0, 0.055, 0.0005, 0.012)
    signal += 0.075 * _smoothed_noise(rng, t.size, 2) * transient
    board = Pedalboard(
        [
            HighpassFilter(cutoff_frequency_hz=70.0),
            LowpassFilter(cutoff_frequency_hz=4_600.0),
            Compressor(threshold_db=-20.0, ratio=3.0, attack_ms=0.8, release_ms=35.0),
            Limiter(threshold_db=-3.0, release_ms=30.0),
        ]
    )
    return _finish(signal, board, spec.target_peak)


def _enemy_break(spec: SoundSpec) -> np.ndarray:
    t = _time(spec.duration)
    rng = np.random.default_rng(spec.seed)
    signal = 0.58 * _chirp(t, 0.0, 0.260, 205.0, 62.0, 0.001, 0.080)
    signal += 0.32 * _chirp(t, 0.028, 0.190, 1_420.0, 590.0, 0.001, 0.072, "triangle")
    signal += 0.25 * _chirp(t, 0.118, 0.255, 1_030.0, 430.0, 0.001, 0.094, "triangle")
    signal += 0.20 * _chirp(t, 0.225, 0.270, 730.0, 300.0, 0.001, 0.105, "triangle")
    noise = _smoothed_noise(rng, t.size, 2)
    _, fracture = _exp_event(t, 0.010, 0.230, 0.0008, 0.060)
    signal += 0.15 * noise * fracture
    for _ in range(11):
        start = float(rng.uniform(0.035, 0.330))
        length = float(rng.uniform(0.018, 0.052))
        frequency = float(rng.uniform(950.0, 3_500.0))
        amplitude = float(rng.uniform(0.025, 0.070))
        signal += amplitude * _chirp(
            t,
            start,
            length,
            frequency,
            frequency * float(rng.uniform(0.45, 0.78)),
            0.0005,
            length * 0.38,
            "soft_square",
            float(rng.uniform(0.0, math.tau)),
        )
    board = Pedalboard(
        [
            Bitcrush(bit_depth=11.0),
            HighpassFilter(cutoff_frequency_hz=55.0),
            LowpassFilter(cutoff_frequency_hz=6_600.0),
            Compressor(threshold_db=-17.0, ratio=3.2, attack_ms=1.0, release_ms=65.0),
            Reverb(room_size=0.12, damping=0.72, wet_level=0.055, dry_level=0.945, width=0.0),
            Limiter(threshold_db=-2.5, release_ms=45.0),
        ]
    )
    return _finish(signal, board, spec.target_peak)


def _operator_upgrade(spec: SoundSpec) -> np.ndarray:
    t = _time(spec.duration)
    rng = np.random.default_rng(spec.seed)
    signal = np.zeros_like(t)
    notes = (523.25, 659.25, 783.99, 1_046.50)
    starts = (0.000, 0.135, 0.275, 0.445)
    for index, (start, frequency) in enumerate(zip(starts, notes, strict=True)):
        length = 0.230 if index < 3 else 0.300
        tone = _chirp(t, start, length, frequency * 0.985, frequency, 0.004, 0.120, "triangle")
        overtone = _chirp(t, start, length * 0.82, frequency * 2.0, frequency * 2.01, 0.003, 0.090)
        signal += 0.26 * tone + 0.045 * overtone
    signal += 0.12 * _chirp(t, 0.430, 0.290, 270.0, 545.0, 0.008, 0.170)
    signal += 0.065 * _chirp(t, 0.505, 0.185, 1_550.0, 2_650.0, 0.003, 0.070, "triangle")
    _, sparkle = _exp_event(t, 0.510, 0.170, 0.001, 0.050)
    signal += 0.018 * _smoothed_noise(rng, t.size, 3) * sparkle
    board = Pedalboard(
        [
            Bitcrush(bit_depth=14.0),
            HighpassFilter(cutoff_frequency_hz=105.0),
            LowpassFilter(cutoff_frequency_hz=7_800.0),
            Compressor(threshold_db=-19.0, ratio=2.2, attack_ms=3.0, release_ms=75.0),
            Reverb(room_size=0.16, damping=0.68, wet_level=0.075, dry_level=0.925, width=0.0),
            Limiter(threshold_db=-2.8, release_ms=55.0),
        ]
    )
    return _finish(signal, board, spec.target_peak)


def _boss_warning(spec: SoundSpec) -> np.ndarray:
    t = _time(spec.duration)
    rng = np.random.default_rng(spec.seed)
    signal = np.zeros_like(t)
    for index, start in enumerate((0.000, 0.310, 0.620)):
        low_start = 102.0 - index * 7.0
        signal += 0.48 * _chirp(t, start, 0.285, low_start, 52.0, 0.003, 0.125)
        signal += 0.21 * _chirp(t, start, 0.250, 188.0, 151.0, 0.002, 0.105, "soft_square")
        signal += 0.13 * _chirp(t, start, 0.235, 224.0, 181.0, 0.002, 0.095, "triangle", 0.7)
        _, burst = _exp_event(t, start, 0.150, 0.001, 0.035)
        signal += 0.030 * _smoothed_noise(rng, t.size, 5) * burst
    siren_frequency = 148.0 + 18.0 * np.sin(math.tau * 1.55 * t)
    siren_phase = math.tau * np.cumsum(siren_frequency) / SAMPLE_RATE
    siren_gate = np.minimum(1.0, t / 0.020) * np.minimum(1.0, (spec.duration - t) / 0.035)
    signal += 0.075 * np.tanh(1.8 * np.sin(siren_phase)) * siren_gate
    board = Pedalboard(
        [
            HighpassFilter(cutoff_frequency_hz=38.0),
            LowpassFilter(cutoff_frequency_hz=5_200.0),
            Clipping(threshold_db=-7.0),
            Compressor(threshold_db=-18.0, ratio=3.5, attack_ms=2.0, release_ms=90.0),
            Reverb(room_size=0.14, damping=0.78, wet_level=0.050, dry_level=0.950, width=0.0),
            Limiter(threshold_db=-2.0, release_ms=70.0),
        ]
    )
    return _finish(signal, board, spec.target_peak)


RENDERERS: dict[str, Callable[[SoundSpec], np.ndarray]] = {
    "combat_hit": _combat_hit,
    "enemy_break": _enemy_break,
    "operator_upgrade": _operator_upgrade,
    "boss_warning": _boss_warning,
}


def _write_pcm16(path: Path, signal: np.ndarray, seed: int) -> None:
    # Fixed TPDF dither prevents correlated quantization grit on quiet tails.
    rng = np.random.default_rng(seed ^ 0x5A5A_2C2C)
    dither = (rng.random(signal.size) - rng.random(signal.size)) / 65_536.0
    pcm = np.round(np.clip(signal + dither, -1.0, 1.0) * 32_767.0).astype("<i2")
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.setcomptype("NONE", "not compressed")
        wav.writeframes(pcm.tobytes())


def _read_and_verify(path: Path, expected_frames: int) -> np.ndarray:
    with wave.open(str(path), "rb") as wav:
        header = {
            "channels": wav.getnchannels(),
            "sample_width": wav.getsampwidth(),
            "sample_rate": wav.getframerate(),
            "frames": wav.getnframes(),
            "compression": wav.getcomptype(),
        }
        if header != {
            "channels": 1,
            "sample_width": 2,
            "sample_rate": SAMPLE_RATE,
            "frames": expected_frames,
            "compression": "NONE",
        }:
            raise RuntimeError(f"Unexpected WAV header for {path}: {header}")
        pcm = np.frombuffer(wav.readframes(expected_frames), dtype="<i2")
    return pcm.astype(np.float64) / 32_768.0


def _db(value: float) -> float:
    return 20.0 * math.log10(max(value, 1e-12))


def _oversampled_peak(signal: np.ndarray, factor: int = 4) -> float:
    # Fourier zero-padding is a practical inter-sample peak estimate for these
    # already band-limited, edge-faded sounds; it is not a BS.1770 meter.
    spectrum = np.fft.rfft(signal)
    padded = np.zeros(signal.size * factor // 2 + 1, dtype=np.complex128)
    padded[: spectrum.size] = spectrum
    upsampled = np.fft.irfft(padded, n=signal.size * factor) * factor
    return float(np.max(np.abs(upsampled)))


def _metrics(path: Path, spec: SoundSpec, signal: np.ndarray) -> dict[str, object]:
    peak = float(np.max(np.abs(signal)))
    rms = float(np.sqrt(np.mean(np.square(signal))))
    trueish_peak = _oversampled_peak(signal)
    return {
        "file": path.name,
        "purpose": spec.purpose,
        "seed": spec.seed,
        "duration_seconds": round(signal.size / SAMPLE_RATE, 6),
        "frame_count": int(signal.size),
        "sample_rate_hz": SAMPLE_RATE,
        "channels": 1,
        "bits_per_sample": 16,
        "sample_format": "PCM signed 16-bit little-endian",
        "peak_linear": round(peak, 8),
        "peak_dbfs": round(_db(peak), 3),
        "rms_linear": round(rms, 8),
        "rms_dbfs": round(_db(rms), 3),
        "crest_factor": round(peak / max(rms, 1e-12), 5),
        "crest_db": round(_db(peak / max(rms, 1e-12)), 3),
        "dc_offset": round(float(np.mean(signal)), 9),
        "oversampled_peak_4x_linear": round(trueish_peak, 8),
        "oversampled_peak_4x_dbfs": round(_db(trueish_peak), 3),
        "clipped_sample_count": int(np.count_nonzero(np.abs(signal) >= 1.0)),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def _comparison_plot(output: Path, rendered: dict[str, np.ndarray]) -> tuple[str | None, str]:
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return None, "skipped: matplotlib is not installed in the rendering runtime"

    figure, axes = plt.subplots(len(rendered), 2, figsize=(12, 9), constrained_layout=True)
    for row, (name, signal) in enumerate(rendered.items()):
        seconds = np.arange(signal.size) / SAMPLE_RATE
        axes[row, 0].plot(seconds, signal, color="#32b8c6", linewidth=0.7)
        axes[row, 0].set_title(f"{name} waveform")
        axes[row, 0].set_xlim(0.0, seconds[-1])
        axes[row, 0].set_ylim(-1.0, 1.0)
        axes[row, 0].set_ylabel("amplitude")
        axes[row, 1].specgram(signal, NFFT=512, Fs=SAMPLE_RATE, noverlap=384, cmap="magma")
        axes[row, 1].set_title(f"{name} spectrogram")
        axes[row, 1].set_ylim(0.0, 8_000.0)
        axes[row, 1].set_ylabel("Hz")
    axes[-1, 0].set_xlabel("seconds")
    axes[-1, 1].set_xlabel("seconds")
    plot_path = output / "comparison.png"
    figure.savefig(plot_path, dpi=150)
    plt.close(figure)
    return plot_path.name, "rendered"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1] / DEFAULT_OUTPUT,
        help=f"Candidate output directory (default: {DEFAULT_OUTPUT})",
    )
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    rendered: dict[str, np.ndarray] = {}
    entries: list[dict[str, object]] = []
    for name, spec in SPECS.items():
        path = output / f"{name}.wav"
        floating = RENDERERS[name](spec)
        _write_pcm16(path, floating, spec.seed)
        decoded = _read_and_verify(path, floating.size)
        rendered[name] = decoded
        entries.append(_metrics(path, spec, decoded))

    plot_name, plot_status = _comparison_plot(output, rendered)
    analysis = {
        "schema_version": 1,
        "generator": "tools/generate_original_sfx.py",
        "generator_version": GENERATOR_VERSION,
        "provenance": "Project-original deterministic synthesis; no source audio or external samples.",
        "dependencies": {
            "numpy": np.__version__,
            "pedalboard": pedalboard.__version__,
        },
        "render_format": {
            "sample_rate_hz": SAMPLE_RATE,
            "channels": 1,
            "bits_per_sample": 16,
            "encoding": "PCM signed 16-bit little-endian",
        },
        "oversampled_peak_note": "4x Fourier interpolation estimate; not a BS.1770 true-peak meter.",
        "comparison_png": plot_name,
        "comparison_plot_status": plot_status,
        "files": entries,
    }
    analysis_path = output / "analysis.json"
    analysis_path.write_text(json.dumps(analysis, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"Rendered {len(entries)} original SFX candidates in {output}")
    for entry in entries:
        print(
            "{file}: {duration_seconds:.3f}s, peak {peak_dbfs:.2f} dBFS, "
            "RMS {rms_dbfs:.2f} dBFS, 4x peak {oversampled_peak_4x_dbfs:.2f} dBFS".format(**entry)
        )
    print(f"Analysis: {analysis_path}")
    print(f"Comparison plot: {plot_status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
