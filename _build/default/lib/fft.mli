(** The Fast Fourier Transform: turns audio samples into frequency bins. Audio
    gives this module samples, and Analysis uses its output. *)

val window_size : int
(** Samples per window: 1024. *)

val is_power_of_two : int -> bool
(** is_power_of_two n is whether n is 1, 2, 4, 8, and so on. *)

val fft : float array -> Complex.t array
(** fft samples is the FFT of samples, the same length n as samples. The input
    is not changed. Raises Invalid_argument if n is not a power of two. *)

val windows : int -> float array -> float array list
(** windows size samples splits samples into windows of size samples, in order,
    padding the last one with 0.0. Raises Invalid_argument if size is not
    positive. *)

val spectra : float array -> Complex.t array list
(** spectra samples is the fft of each window_size window, in time order. *)