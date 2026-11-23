let failures = ref 0
let checks = ref 0

let check name condition =
  incr checks;
  if condition then Printf.printf "PASS %s\n" name
  else begin
    incr failures;
    Printf.printf "FAIL %s\n" name
  end

let close a b = abs_float (a -. b) < 1e-9
let spectrum () = Array.make Analysis.window_size Complex.zero
let complex re im : Complex.t = { re; im }

let rejects f =
  try
    ignore (f ());
    false
  with Invalid_argument _ -> true

let frame time bass mid treble : Analysis.frame =
  { time; bass; mid; treble }

let () =
  check "complex magnitude includes real and imaginary parts"
    (close (Analysis.magnitude (complex 3.0 4.0)) 5.0);
  check "bin frequency uses the audio sample rate"
    (close (Analysis.frequency_of_bin ~sample_rate:44100 ~fft_size:1024 1)
       (44100.0 /. 1024.0));

  (* At 44100 Hz the bands contain exactly 5, 87 and 279 bins.
     Fill their edges too, so off-by-one errors change these averages. *)
  let bins = spectrum () in
  for i = 1 to 5 do bins.(i) <- complex 3.0 4.0 done;
  for i = 6 to 92 do bins.(i) <- complex 0.0 7.0 done;
  for i = 93 to 371 do bins.(i) <- complex (-11.0) 0.0 done;
  bins.(0) <- complex 1e6 0.0;
  for i = 372 to 1023 do bins.(i) <- complex 1e6 0.0 done;
  let levels = Analysis.analyze ~sample_rate:44100 bins in
  check "bass bins 1-5 have raw average magnitude 5" (close levels.bass 5.0);
  check "mid bins 6-92 have raw average magnitude 7" (close levels.mid 7.0);
  check "treble bins 93-371 have raw average magnitude 11"
    (close levels.treble 11.0);
  check "analysis does not mutate the FFT array"
    (bins.(1) = complex 3.0 4.0 && bins.(1023) = complex 1e6 0.0);

  let sparse = spectrum () in
  sparse.(1) <- complex 3.0 4.0;
  let sparse_levels = Analysis.analyze ~sample_rate:44100 sparse in
  check "zero-valued bins count toward the band average"
    (close sparse_levels.bass 1.0);

  (* At 32768 Hz each bin is 32 Hz wide. These bins straddle the
     250, 4000 and 16000 Hz boundaries. *)
  let edges = spectrum () in
  edges.(7) <- complex 7.0 0.0;
  edges.(8) <- complex 117.0 0.0;
  edges.(125) <- complex 375.0 0.0;
  edges.(500) <- complex 1e6 0.0;
  let edge_levels = Analysis.analyze ~sample_rate:32768 edges in
  check "bands adapt to a different audio sample rate"
    (close edge_levels.bass 1.0 && close edge_levels.mid 1.0);
  check "4000 Hz enters treble and 16000 Hz is excluded"
    (close edge_levels.treble 1.0);

  let low_rate = spectrum () in
  low_rate.(512) <- complex 1.0 0.0;
  low_rate.(513) <- complex 1e6 0.0;
  let low_levels = Analysis.analyze ~sample_rate:8192 low_rate in
  check "Nyquist is counted once and negative frequencies are excluded"
    (close low_levels.treble (1.0 /. 13.0));
  let empty_bands = Analysis.analyze ~sample_rate:32 (spectrum ()) in
  check "bands with no available frequencies are zero"
    (empty_bands.bass = 0.0 && empty_bands.mid = 0.0
     && empty_bands.treble = 0.0);

  let single = Analysis.frame_of_spectrum ~sample_rate:44100 ~time:1.25 bins in
  check "single frame includes the supplied timestamp and levels"
    (single.time = 1.25 && close single.bass 5.0 && close single.mid 7.0
     && close single.treble 11.0);
  let frames = Analysis.analyze_track ~sample_rate:44100 [bins; spectrum (); sparse] in
  check "whole-track frames preserve window order and raw levels"
    (Array.length frames = 3 && close frames.(0).bass 5.0
     && frames.(1).bass = 0.0 && close frames.(2).bass 1.0);
  check "timestamps use the start sample of each 1024-sample window"
    (frames.(0).time = 0.0
     && close frames.(1).time (1024.0 /. 44100.0)
     && close frames.(2).time (2048.0 /. 44100.0));
  check "empty whole track returns no frames"
    (Analysis.analyze_track ~sample_rate:44100 [] = [||]);

  List.iter
    (fun length ->
      check (Printf.sprintf "reject FFT length %d" length)
        (rejects (fun () ->
             Analysis.analyze ~sample_rate:44100 (Array.make length Complex.zero))))
    [0; 512; 1023; 1025];
  List.iter
    (fun sample_rate ->
      check "reject nonpositive sample rates"
        (rejects (fun () -> Analysis.analyze ~sample_rate bins)
         && rejects (fun () -> Analysis.analyze_track ~sample_rate [])))
    [0; -44100];
  check "whole-track analysis validates every window"
    (rejects (fun () -> Analysis.analyze_track ~sample_rate:44100 [bins; [||]]));
  check "frequency helper rejects invalid inputs"
    (rejects (fun () -> Analysis.frequency_of_bin ~sample_rate:0 ~fft_size:1024 1)
     && rejects (fun () -> Analysis.frequency_of_bin ~sample_rate:44100 ~fft_size:0 0)
     && rejects (fun () -> Analysis.frequency_of_bin ~sample_rate:44100 ~fft_size:1024 (-1))
     && rejects (fun () -> Analysis.frequency_of_bin ~sample_rate:44100 ~fft_size:1024 1024));

  let raw = [|frame 0.0 2.0 4.0 8.0; frame 0.1 4.0 0.0 0.0|] in
  let normalized = Analysis.normalize raw in
  check "normalization uses one peak and preserves relative band levels"
    (close normalized.(0).bass 0.25 && close normalized.(0).mid 0.5
     && normalized.(0).treble = 1.0 && close normalized.(1).bass 0.5);
  check "normalization preserves timestamps and the original array"
    (normalized.(1).time = 0.1 && raw.(0).bass = 2.0);
  check "normalization supports silent and empty tracks"
    (Analysis.normalize [||] = [||]
     && Analysis.normalize [|frame 0.0 0.0 0.0 0.0|]
        = [|frame 0.0 0.0 0.0 0.0|]);

  let steps =
    [|frame 0.0 0.0 2.0 4.0; frame 0.1 8.0 6.0 0.0;
      frame 0.2 8.0 6.0 0.0|]
  in
  let smoothed = Analysis.smooth ~alpha:0.5 steps in
  check "smoothing handles each band and uses the previous output"
    (smoothed.(0) = steps.(0)
     && smoothed.(1) = frame 0.1 4.0 4.0 2.0
     && smoothed.(2) = frame 0.2 6.0 5.0 1.0);
  check "smoothing preserves the original frames"
    (steps.(1) = frame 0.1 8.0 6.0 0.0);
  check "default smoothing factor is 0.3"
    (close (Analysis.smooth steps).(1).bass 2.4);
  check "alpha 1 and empty or single-frame tracks are supported"
    (Analysis.smooth ~alpha:1.0 steps = steps
     && Analysis.smooth [||] = [||]
     && Analysis.smooth [|steps.(0)|] = [|steps.(0)|]);
  List.iter
    (fun alpha ->
      check "reject invalid smoothing factors"
        (rejects (fun () -> Analysis.smooth ~alpha [||])))
    [0.0; -0.1; 1.1; Float.nan];
  Printf.printf "%d checks, %d failures\n" !checks !failures;
  exit (if !failures = 0 then 0 else 1)
