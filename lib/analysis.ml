type band_levels = {
  bass : float;
  mid : float;
  treble : float;
}

let frequency_of_bin ~sample_rate ~fft_size bin =
  float_of_int bin *. (float_of_int sample_rate /. float_of_int fft_size)

let magnitude (value : Complex.t) : float =
  let open Complex in
  sqrt (re value *. re value +. im value *. im value)

(*TO BE MODIFIED ONCE I KNOW FFT'S RETURN TYPE*)
let analyze ~sample_rate ~fft_size (spectrum : Complex.t array) : band_levels =
  let bin_count = Array.length spectrum in
  let bass_bins = List.init (bin_count / 3) (fun i -> i) in
  let mid_bins = List.init (bin_count / 3) (fun i -> i + bin_count / 3) in
  let treble_bins = List.init (bin_count / 3) (fun i -> i + 2 * bin_count / 3) in

  let sum_magnitude bins =
    List.fold_left (fun acc bin -> acc +. magnitude spectrum.(bin)) 0.0 bins
  in

  let bass_level = sum_magnitude bass_bins /. float_of_int (List.length bass_bins) in
  let mid_level = sum_magnitude mid_bins /. float_of_int (List.length mid_bins) in
  let treble_level = sum_magnitude treble_bins /. float_of_int (List.length treble_bins) in

  { bass = bass_level; mid = mid_level; treble = treble_level }