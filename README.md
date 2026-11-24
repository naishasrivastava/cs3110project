# CS 3110 Project
Group 8 - Ate  
Naisha Srivastava - ns2229  
Duncan Park - dcp253  
Phoebe Deimler - pmd222  
Suhana Kumar - sk3487  

Takes a song (MP3 or WAV), cuts it into short windows, takes the Fourier transform of each, measures how much bass, mid and treble each window has, and returns that as the data a visualization will draw from. The command-line program prints it as a table.  

## Requirements
- OCaml 4.14 or newer, dune 3.0 or newer (only the compiler's own `unix` library).  
- `ffmpeg` on the PATH for MP3 input. WAV files and `dune test` do not need it (MP3 tests print `SKIP` without it).  
- Python 3 + numpy only for `scripts/reference.py` (independent check of expected values).  

## Build, Rest, Run
```
dune build
dune test --force                 # prints PASS / FAIL / SKIP lines; non-zero exit on any FAIL  

dune exec bin/main.exe -- samples/bass_then_treble.mp3  
dune exec bin/main.exe -- samples/dance_128.mp3 --every 0.25 --csv frames.csv  
dune exec bin/main.exe -- samples/sine440_stereo.wav  
```
