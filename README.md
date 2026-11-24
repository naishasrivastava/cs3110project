# CS 3110 Project
Group 8 - Ate  
Naisha Srivastava - ns2229  
Duncan Park - dcp253  
Phoebe Deimler - pmd222  
Suhana Kumar - sk3487  

Takes a song (MP3 or WAV), cuts it into short windows, takes the Fourier transform of each, and measures how much bass, mid and treble each window has. The command-line program prints the results as a table and can export them as CSV.

Audio loading, frequency analysis, and the command-line program are implemented. The visualization module (`lib/visuals.ml`) is currently empty; the program produces data for a future visualization.

## Requirements
 
- OCaml 4.14 or newer and Dune 3.0 or newer. The application uses the compiler's bundled `unix` library.
- OUnit2 for the tests.
- Raylib (the OCaml `raylib` package) for `lib/visuals.ml`. The library will not build without it.
- `ffmpeg` on the PATH for MP3 input. The loader also accepts M4A, AAC, FLAC, and OGG through `ffmpeg`. Supported WAV files load directly without it, and MP3 tests print `SKIP` when it is unavailable.
With OCaml installed and an opam switch using OCaml 4.14 or newer selected, install the build, test, and graphics dependencies:
 
```sh
opam install dune ounit2 raylib
eval $(opam env)
```
 
If `opam install raylib` fails, you may be missing a system graphics library. On Linux, install your distribution's OpenGL and X11 development packages first (for example `libgl1-mesa-dev` and `libx11-dev` on Ubuntu or Debian). On macOS and Windows the OCaml `raylib` package bundles what it needs, but on Windows it is easiest to build inside WSL.
 
Make sure `raylib` is listed in the `libraries` field of `lib/dune`:
 
```text
(library
 (name cs3110project)
 (wrapped false)
 (libraries unix raylib))
```
 
For MP3 input, install `ffmpeg` using your system's package manager. For example, on macOS with Homebrew:
 
```sh
brew install ffmpeg
```
 
On Windows, use `winget install ffmpeg` or download it from https://ffmpeg.org and add it to the PATH.


## Build, Test, Run

Run these commands from the project root:

```sh
dune build
dune test --force
```

`dune build` builds the library and command-line executable. `dune test --force` runs the audio, FFT, and analysis tests even if their results are cached; it does not require building the separate command-line executable. Audio and analysis tests print custom `PASS` / `FAIL` lines, audio tests can also print `SKIP`, and FFT tests use OUnit2's output format. Test failures produce a nonzero exit status.

To check just the command-line executable:

```sh
dune build bin/main.exe
```

Example runs:

```sh
dune exec bin/main.exe -- samples/bass_then_treble.mp3
dune exec bin/main.exe -- samples/dance_128.mp3 --every 0.25 --csv frames.csv
dune exec bin/main.exe -- samples/sine440_stereo.wav
```

## Command-line Options

```text
main.exe FILE [--every SECONDS] [--csv OUT.csv]
```

- `FILE`: path to the input audio file.
- `--every SECONDS`: positive interval between requested table rows, in seconds; defaults to `0.5`. Each row uses the analysis frame containing the requested time, so its printed timestamp can be slightly earlier. This option does not change the analysis windows or CSV output.
- `--csv OUT.csv`: writes every processed analysis frame with the columns `time,bass,mid,treble`. An existing output file is overwritten. The table is still printed.

## Understanding the Output

The table contains:

| Column | Meaning |
| --- | --- |
| `time(s)` | Start time of the analysis window, in seconds. |
| `bass` | Level for frequencies from 20 Hz up to, but excluding, 250 Hz. |
| `mid` | Level for frequencies from 250 Hz up to, but excluding, 4,000 Hz. |
| `treble` | Level for frequencies from 4,000 Hz up to, but excluding, 16,000 Hz. |
| `dominant` | Band with the largest processed level, or `-` if all three are zero. Ties prefer bass, then mid, then treble. |

Each raw band level is the average FFT magnitude of the frequency bins in that band. The program divides all levels by the single largest level across the entire track, then applies exponential smoothing with `alpha = 0.3`. The displayed and exported levels are relative values in `[0, 1]`, not decibels or percentages; they do not necessarily add up to 1. CSV output uses `time` for the timestamp column and does not include `dominant`.

## Analysis Details

Audio channels are averaged into mono. Analysis uses consecutive, non-overlapping windows of 1,024 samples, with zeros added to the final window if necessary. At 44,100 Hz, each window covers approximately 23.2 milliseconds. The FFT uses the samples directly without a window function such as a Hann window.

## Project Structure

- `lib/`: audio decoding (`Audio`), Fourier transforms (`Fft`), frequency-band analysis (`Analysis`), and the complete processing pipeline (`Track`). `Visuals` is a placeholder.
- `bin/`: the command-line entry point, `main.ml`.
- `test/`: the audio, FFT, and analysis tests configured in `test/dune`.
- `samples/`: WAV and MP3 fixtures used by tests and example commands.

## Troubleshooting
 
- `Unbound module Raylib`: install the package with `opam install raylib`, run `eval $(opam env)`, and add `raylib` to the `libraries` field in `lib/dune`.
- `Unbound module OUnit2`: run `opam install ounit2`.
- `git` or `ffmpeg` not recognized on Windows: reopen the terminal (or VS Code) after installing so the PATH refreshes.
