# CLAUDE.md

## Read the vision first

Before proposing features, behaviors, or implementation, **read [VISION.md](VISION.md)**.

ZenTab is **very opinionated** and the full focus is on two co-equal pillars: **feel and
performance**. It is not about configurability or feature count. The default answer to
"should this be a setting?" is **no**. Performance is first-class, not a later optimization
— imperceptible summon latency, a keyboard hook that never adds input lag, GPU-based
visuals, smoothness at the real refresh rate, and near-zero idle cost. When a request or
idea conflicts with VISION.md, surface the tension instead of silently implementing it.

## Project basics

- C# / WPF on .NET 10, with a thin Win32/DWM interop layer (`Native.cs`).
- See [README.md](README.md) for how to build/run (`dotnet run`, `./dev.ps1`, etc.).
