(** Average raw FFT magnitudes for one audio window. *)
type band_levels = {
  bass : float; (** Frequencies satisfying [20 <= f < 250] Hz. *)
  mid : float; (** Frequencies satisfying [250 <= f < 4000] Hz. *)
  treble : float; (** Frequencies satisfying [4000 <= f < 16000] Hz. *)
}

(** Band levels with the window's start time, in seconds. *)
type frame = {
  time : float;
  bass : float;
  mid : float;
  treble : float;
}

val window_size : int
(** 1024 samples per FFT window, producing 1024 complex bins. *)

val frequency_of_bin : sample_rate:int -> fft_size:int -> int -> float
(** [frequency_of_bin ~sample_rate ~fft_size bin] is
    [bin * sample_rate / fft_size] in Hz. For mirrored negative-frequency bins,
    this is the unwrapped frequency rather than a signed frequency.
    Raises [Invalid_argument] if either size or rate is nonpositive, or [bin]
    does not satisfy [0 <= bin < fft_size]. *)

val magnitude : Complex.t -> float
(** The complex magnitude, with no amplitude scaling. *)

val analyze : sample_rate:int -> Complex.t array -> band_levels
(** Analyze one full, unshifted 1024-bin FFT of real audio. The sample rate
    comes from Audio. Bin 0 (DC) and mirrored negative-frequency bins are
    excluded. Nyquist is included if it lies in a band. All bins in a band,
    including zero-valued bins, contribute to its average magnitude.
    A band with no bins has level [0.0]. No window function or FFT amplitude
    normalization is applied.
    Raises [Invalid_argument] if [sample_rate <= 0] or the array length is
    not 1024. *)

val frame_of_spectrum :
  sample_rate:int -> time:float -> Complex.t array -> frame
(** [frame_of_spectrum ~sample_rate ~time spectrum] adds the window's start
    time in seconds to the raw levels from {!analyze}.
    Has the same input requirements and exceptions as {!analyze}. *)

val analyze_track : sample_rate:int -> Complex.t array list -> frame array
(** Analyze a chronological list of consecutive, non-overlapping windows.
    Frame [i] starts at [i * 1024 / sample_rate] seconds. Returns raw frames
    in the same order; an empty list produces an empty array.
    Raises [Invalid_argument] for a nonpositive sample rate or any window
    whose FFT array length is not 1024. *)

val normalize : frame array -> frame array
(** Return a new array with all band levels divided by the single largest
    level across all frames and bands. For raw analysis levels, the results
    lie in [0, 1] and preserve relative levels between bands. Empty and silent
    tracks are supported. Timestamps and the input array are unchanged.
    This is optional display processing, separate from raw FFT analysis. *)

val smooth : ?alpha:float -> frame array -> frame array
(** Return a new array using exponential smoothing independently per band:
    [output[i] = alpha * input[i] + (1 - alpha) * output[i - 1]].
    The first frame is unchanged. [alpha] defaults to [0.3]; [1.0] leaves
    levels unchanged. Timestamps and the input array are unchanged.
    Empty arrays are supported.
    Raises [Invalid_argument] unless [0 < alpha <= 1]. *)
