let window_size = Analysis.window_size

let raw (a : Audio.t) =
  let count = Audio.num_windows a ~size:window_size in
  Array.init count (fun i ->
      let start = i * window_size in
      let spectrum = Fft.fft (Audio.window a ~start ~size:window_size) in
      Analysis.frame_of_spectrum ~sample_rate:a.Audio.sample_rate
        ~time:(float_of_int start /. float_of_int a.Audio.sample_rate)
        spectrum)

let of_audio a = Analysis.smooth (Analysis.normalize (raw a))
let of_file path = Result.map of_audio (Audio.load path)

let frame_at frames t =
  let n = Array.length frames in
  if n = 0 then None
  else begin
    (* last frame whose start time is <= t, by binary search *)
    let lo = ref 0 and hi = ref (n - 1) in
    while !lo < !hi do
      let mid = (!lo + !hi + 1) / 2 in
      if frames.(mid).Analysis.time <= t then lo := mid else hi := mid - 1
    done;
    Some frames.(!lo)
  end
