(** Frequency levels calculated for one audio window*)
type band_levels = {
  bass: float; (** Low frequency level *)
  mid: float; (** Mid frequency level *)
  treble: float; (** High frequency level *)
}

(** [frequency_of_bin ~sample_rate ~fft_size bin] is the frequency in
    hertz represented by [bin]. *)
val frequency_of_bin :
  sample_rate:int -> fft_size:int -> int -> float

(** [magnitude value] is the magnitude of a complex FFT value. *)
val magnitude : Complex.t -> float

(** [analyze ~sample_rate fft_output] calculates the average magnitude
    of the positive-frequency bins in each band.
    Raises [Invalid_argument] if [sample_rate] is not positive or
    [fft_output] is empty. *)
val analyze :
  sample_rate:int -> Complex.t array -> band_levels

  