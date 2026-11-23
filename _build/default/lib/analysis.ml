type band_levels = {
  bass : float;
  mid : float;
  treble : float;
}

type frame = {
  time : float;
  bass : float;
  mid : float;
  treble : float;
}

let window_size = 1024

let check_sample_rate sample_rate =
  if sample_rate <= 0 then
    invalid_arg "Analysis: sample_rate must be positive"

let frequency_of_bin ~sample_rate ~fft_size bin =
  check_sample_rate sample_rate;
  if fft_size <= 0 then invalid_arg "Analysis: fft_size must be positive";
  if bin < 0 || bin >= fft_size then
    invalid_arg "Analysis: bin is outside the FFT array";
  float_of_int bin *. (float_of_int sample_rate /. float_of_int fft_size)

let magnitude (value : Complex.t) : float = Complex.norm value

let analyze ~sample_rate (spectrum : Complex.t array) : band_levels =
  check_sample_rate sample_rate;
  if Array.length spectrum <> window_size then
    invalid_arg "Analysis.analyze: expected 1024 FFT bins";
  let average_band low high =
    let total = ref 0.0 in
    let count = ref 0 in
    (* Real audio has mirrored negative frequencies in the second half.
       Skip DC, but include Nyquist if it falls within a requested band. *)
    for bin = 1 to window_size / 2 do
      let frequency =
        frequency_of_bin ~sample_rate ~fft_size:window_size bin
      in
      if frequency >= low && frequency < high then begin
        total := !total +. magnitude spectrum.(bin);
        incr count
      end
    done;
    if !count = 0 then 0.0 else !total /. float_of_int !count
  in
  {
    bass = average_band 20.0 250.0;
    mid = average_band 250.0 4000.0;
    treble = average_band 4000.0 16000.0;
  }

let frame_of_spectrum ~sample_rate ~time spectrum : frame =
  let levels = analyze ~sample_rate spectrum in
  { time; bass = levels.bass; mid = levels.mid; treble = levels.treble }

let analyze_track ~sample_rate spectra =
  check_sample_rate sample_rate;
  spectra
  |> List.mapi (fun i spectrum ->
         let time =
           float_of_int i *. float_of_int window_size /. float_of_int sample_rate
         in
         frame_of_spectrum ~sample_rate ~time spectrum)
  |> Array.of_list

let normalize (frames : frame array) =
  let peak =
    Array.fold_left
      (fun peak (frame : frame) ->
        max peak (max frame.bass (max frame.mid frame.treble)))
      0.0 frames
  in
  if peak = 0.0 then Array.copy frames
  else
    Array.map
      (fun (frame : frame) ->
        { frame with
          bass = frame.bass /. peak;
          mid = frame.mid /. peak;
          treble = frame.treble /. peak })
      frames

let smooth ?(alpha = 0.3) (frames : frame array) =
  if not (alpha > 0.0 && alpha <= 1.0) then
    invalid_arg "Analysis.smooth: alpha must be in (0, 1]";
  let result = Array.copy frames in
  let blend previous current =
    alpha *. current +. (1.0 -. alpha) *. previous
  in
  for i = 1 to Array.length result - 1 do
    let previous = result.(i - 1) in
    let current = frames.(i) in
    result.(i) <-
      { current with
        bass = blend previous.bass current.bass;
        mid = blend previous.mid current.mid;
        treble = blend previous.treble current.treble }
  done;
  result
