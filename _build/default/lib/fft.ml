let window_size = 1024

(** Whether n is a power of two, by halving it while it is even. *)
let rec is_power_of_two n =
  if n = 1 then true
  else if n <= 0 || n mod 2 = 1 then false
  else is_power_of_two (n / 2)

(** Recursive Cooley-Tukey FFT transforms the even and odd elements, then
    combine them. Requires a power-of-two length. *)
let rec fft_complex (x : Complex.t array) : Complex.t array =
  let n = Array.length x in
  if n = 1 then [| x.(0) |]
  else
    let half = n / 2 in
    let evens = fft_complex (Array.init half (fun i -> x.(2 * i))) in
    let odds = fft_complex (Array.init half (fun i -> x.((2 * i) + 1))) in
    let result = Array.make n Complex.zero in
    for k = 0 to half - 1 do
      let angle = -2.0 *. Float.pi *. float_of_int k /. float_of_int n in
      let t = Complex.mul (Complex.polar 1.0 angle) odds.(k) in
      result.(k) <- Complex.add evens.(k) t;
      result.(k + half) <- Complex.sub evens.(k) t
    done;
    result

(** Makes each sample a complex number, then runs the FFT. *)
let fft (samples : float array) : Complex.t array =
  if not (is_power_of_two (Array.length samples)) then
    invalid_arg "Fft.fft: length must be a power of two"
  else
    fft_complex (Array.map (fun s -> { Complex.re = s; im = 0.0 }) samples)

(** Builds windows from last to first so the list is in time order. Samples
    past the end count as 0.0. *)
let windows (size : int) (samples : float array) : float array list =
  if size <= 0 then invalid_arg "Fft.windows: size must be positive"
  else
    let total = Array.length samples in
    let count = (total + size - 1) / size in
    let result = ref [] in
    for w = count - 1 downto 0 do
      let start = w * size in
      let window =
        Array.init size (fun i ->
            if start + i < total then samples.(start + i) else 0.0)
      in
      result := window :: !result
    done;
    !result

(** Transforms every window. *)
let spectra (samples : float array) : Complex.t array list =
  List.map fft (windows window_size samples)