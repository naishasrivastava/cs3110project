open OUnit2

(** How close two floats must be to count as equal. The FFT uses sin and cos, so
    answers are only exact up to tiny rounding errors. *)
let tolerance = 1e-6

(** Whether two floats are equal up to the tolerance. *)
let close a b = Float.abs (a -. b) < tolerance

(** Writes a complex number as text, to show in failed tests. *)
let string_of_complex (z : Complex.t) =
  Printf.sprintf "%.6f + %.6fi" z.Complex.re z.Complex.im

(** Checks that two complex arrays have the same length and every element is
    equal up to the tolerance. *)
let assert_complex_array (expected : Complex.t array) (actual : Complex.t array)
    =
  assert_equal ~printer:string_of_int ~msg:"length" (Array.length expected)
    (Array.length actual);
  for k = 0 to Array.length expected - 1 do
    let e = expected.(k) in
    let a = actual.(k) in
    assert_bool
      ("bin " ^ string_of_int k ^ ": expected " ^ string_of_complex e ^ " got "
     ^ string_of_complex a)
      (close e.Complex.re a.Complex.re && close e.Complex.im a.Complex.im)
  done

(** A complex number from its real and imaginary parts. *)
let c re im = { Complex.re; im }

(** n samples of a sine wave that completes cycles full cycles over the n
    samples. Its energy lands in frequency bin cycles. *)
let sine cycles n =
  Array.init n (fun i ->
      sin (2.0 *. Float.pi *. float_of_int cycles *. float_of_int i
           /. float_of_int n))

(** The index of the bin with the largest size among bins 0 up to n / 2, where
    the useful frequencies are. *)
let peak_bin (spectrum : Complex.t array) =
  let best = ref 0 in
  for k = 1 to (Array.length spectrum / 2) - 1 do
    if Complex.norm spectrum.(k) > Complex.norm spectrum.(!best) then best := k
  done;
  !best

(** The Discrete Fourier Transform computed straight from its definition: bin k
    is the sum over every sample n of x n times e to the power -2 pi i k n / N.
    It is slow but simple, so the tests compare the FFT against it. *)
let slow_dft (samples : float array) : Complex.t array =
  let n = Array.length samples in
  Array.init n (fun k ->
      let total = ref Complex.zero in
      for j = 0 to n - 1 do
        let angle =
          -2.0 *. Float.pi *. float_of_int k *. float_of_int j /. float_of_int n
        in
        let term = Complex.mul (c samples.(j) 0.0) (Complex.polar 1.0 angle) in
        total := Complex.add !total term
      done;
      !total)

(** Worked out by hand from the definition: for 1, 2, 3, 4 the four bins are
    1+2+3+4 = 10, 1-2i-3+4i = -2+2i, 1-2+3-4 = -2, and 1+2i-3-4i = -2-2i. *)
let test_hand_example _ =
  assert_complex_array
    [| c 10.0 0.0; c (-2.0) 2.0; c (-2.0) 0.0; c (-2.0) (-2.0) |]
    (Fft.fft [| 1.0; 2.0; 3.0; 4.0 |])

(** A single click at the start contains every frequency equally, so every bin
    is 1. *)
let test_impulse _ =
  let samples = Array.make 8 0.0 in
  samples.(0) <- 1.0;
  assert_complex_array (Array.make 8 (c 1.0 0.0)) (Fft.fft samples)

(** A constant signal has no change at all, so all of it is in bin 0 (8 samples
    of 1.0 add up to 8) and every other bin is 0. *)
let test_constant _ =
  let expected = Array.make 8 Complex.zero in
  expected.(0) <- c 8.0 0.0;
  assert_complex_array expected (Fft.fft (Array.make 8 1.0))

(** Silence has zero energy in every bin. *)
let test_silence _ =
  let spectrum = Fft.fft (Array.make Fft.window_size 0.0) in
  Array.iteri
    (fun k z ->
      assert_bool ("bin " ^ string_of_int k ^ " is silent")
        (close (Complex.norm z) 0.0))
    spectrum

(** A sine wave with 50 cycles in the window puts its energy in bin 50, with
    size n / 2 = 512, and nothing in the other useful bins. *)
let test_sine_peak _ =
  let spectrum = Fft.fft (sine 50 Fft.window_size) in
  assert_equal ~printer:string_of_int 50 (peak_bin spectrum);
  assert_bool "peak size is n / 2" (close (Complex.norm spectrum.(50)) 512.0);
  assert_bool "neighbor bin is empty" (close (Complex.norm spectrum.(51)) 0.0)

(** A 1000 Hz tone sampled 8000 times per second, in a 1024-sample window,
    belongs in bin 1000 * 1024 / 8000 = 128. This is the known-frequency check
    from our MS1 plan. *)
let test_known_frequency _ =
  let sample_rate = 8000.0 in
  let samples =
    Array.init Fft.window_size (fun i ->
        sin (2.0 *. Float.pi *. 1000.0 *. float_of_int i /. sample_rate))
  in
  assert_equal ~printer:string_of_int 128 (peak_bin (Fft.fft samples))

(** The contract Analysis relies on, checked with a known tone at a real audio
    sample rate. At 44100 samples per second, bin 10 of a 1024-sample window is
    10 * 44100 / 1024 = 430.6640625 Hz. A tone of exactly that frequency with
    amplitude 0.5 should give a full-length spectrum whose largest useful bin
    is 10, whose frequency by the contract formula is 430.6640625 Hz, and whose
    magnitude is 0.5 * 1024 / 2 = 256, because no scaling is applied. *)
let test_contract_known_tone _ =
  let sample_rate = 44100 in
  let freq = 10.0 *. float_of_int sample_rate /. float_of_int Fft.window_size in
  let samples =
    Array.init Fft.window_size (fun i ->
        0.5
        *. sin (2.0 *. Float.pi *. freq *. float_of_int i
               /. float_of_int sample_rate))
  in
  let spectrum = Fft.fft samples in
  let k = peak_bin spectrum in
  let hz =
    float_of_int k *. float_of_int sample_rate /. float_of_int Fft.window_size
  in
  assert_equal ~printer:string_of_int ~msg:"full length" Fft.window_size
    (Array.length spectrum);
  assert_equal ~printer:string_of_int ~msg:"peak bin" 10 k;
  assert_bool "peak frequency in Hz" (close hz 430.6640625);
  assert_bool "magnitude is amplitude * n / 2, no scaling"
    (close (Complex.norm spectrum.(10)) 256.0);
  assert_bool "mirror bin n - k has the same size"
    (close (Complex.norm spectrum.(Fft.window_size - 10)) 256.0)

(** For random inputs of several sizes, the FFT gives the same answer as the
    slow definition. The random seed is fixed so a failure can be repeated. *)
let test_matches_slow_dft _ =
  Random.init 3110;
  List.iter
    (fun n ->
      for _ = 1 to 10 do
        let samples = Array.init n (fun _ -> Random.float 2.0 -. 1.0) in
        assert_complex_array (slow_dft samples) (Fft.fft samples)
      done)
    [ 1; 2; 4; 8; 64; 256 ]

(** The FFT must not change the caller's samples. *)
let test_input_unchanged _ =
  let samples = [| 1.0; 2.0; 3.0; 4.0 |] in
  let _ = Fft.fft samples in
  assert_equal [| 1.0; 2.0; 3.0; 4.0 |] samples

(** Lengths that are not powers of two, including 0, are rejected. *)
let test_bad_length _ =
  List.iter
    (fun n ->
      assert_raises
        (Invalid_argument "Fft.fft: length must be a power of two")
        (fun () -> Fft.fft (Array.make n 0.0)))
    [ 0; 3; 6; 1000 ]

(** Powers of two and some numbers that are not. *)
let test_is_power_of_two _ =
  List.iter
    (fun n -> assert_bool (string_of_int n) (Fft.is_power_of_two n))
    [ 1; 2; 4; 1024 ];
  List.iter
    (fun n -> assert_bool (string_of_int n) (not (Fft.is_power_of_two n)))
    [ 0; -4; 3; 6; 1000 ]

(** 2500 samples make 3 windows of 1024: the last holds samples 2048 to 2499 and
    is filled out with silence. *)
let test_windows_padding _ =
  let samples = Array.init 2500 (fun i -> float_of_int i +. 1.0) in
  let ws = Fft.windows 1024 samples in
  assert_equal ~printer:string_of_int 3 (List.length ws);
  List.iter
    (fun w -> assert_equal ~printer:string_of_int 1024 (Array.length w))
    ws;
  let first = List.nth ws 0 in
  let last = List.nth ws 2 in
  assert_equal ~printer:string_of_float 1.0 first.(0);
  assert_equal ~printer:string_of_float 2049.0 last.(0);
  assert_equal ~printer:string_of_float 2500.0 last.(451);
  assert_equal ~printer:string_of_float 0.0 last.(452);
  assert_equal ~printer:string_of_float 0.0 last.(1023)

(** An exact multiple needs no padding, and no samples give no windows. *)
let test_windows_edges _ =
  assert_equal ~printer:string_of_int 2
    (List.length (Fft.windows 1024 (Array.make 2048 1.0)));
  assert_equal [] (Fft.windows 1024 [||]);
  assert_raises (Invalid_argument "Fft.windows: size must be positive")
    (fun () -> Fft.windows 0 [| 1.0 |])

(** A whole track gives one 1024-bin spectrum per window, in time order: here a
    silent window followed by a window with a 50-cycle tone. *)
let test_spectra _ =
  let samples =
    Array.append (Array.make Fft.window_size 0.0) (sine 50 Fft.window_size)
  in
  let result = Fft.spectra samples in
  assert_equal ~printer:string_of_int 2 (List.length result);
  List.iter
    (fun s -> assert_equal ~printer:string_of_int 1024 (Array.length s))
    result;
  assert_bool "first window is silent"
    (close (Complex.norm (List.nth result 0).(50)) 0.0);
  assert_equal ~printer:string_of_int 50 (peak_bin (List.nth result 1))

let tests =
  "fft"
  >::: [
         "hand example" >:: test_hand_example;
         "impulse" >:: test_impulse;
         "constant" >:: test_constant;
         "silence" >:: test_silence;
         "sine peak" >:: test_sine_peak;
         "known frequency" >:: test_known_frequency;
         "contract known tone" >:: test_contract_known_tone;
         "matches slow dft" >:: test_matches_slow_dft;
         "input unchanged" >:: test_input_unchanged;
         "bad length" >:: test_bad_length;
         "is power of two" >:: test_is_power_of_two;
         "windows padding" >:: test_windows_padding;
         "windows edges" >:: test_windows_edges;
         "spectra" >:: test_spectra;
       ]

let () = run_test_tt_main tests