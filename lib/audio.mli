(** Audio.ml: load a song as mono float samples plus the sample rate, and
    cut it into windows for the FFT.*)

type t = {
  samples : float array;  (** mono, each value in [-1.0, 1.0] *)
  sample_rate : int;      (** samples per second, e.g. 44100 *)
}

type error =
  | File_not_found of string
  | Unsupported_format of string
  | Invalid_wav of string
  | Ffmpeg_not_found
  | Ffmpeg_failed of string

val error_to_string : error -> string
(** Human-readable message suitable for showing in the UI. *)

(** {1 Loading} *)

val load : string -> (t, error) result
(** [load path] loads a [.wav] directly, or converts [.mp3 .m4a .flac .ogg .aac]
    to a temporary WAV with ffmpeg first (the temp file is always deleted).
    Stereo/multichannel audio is averaged down to one channel. *)

val of_wav_bytes : string -> (t, error) result
(** Decode the bytes of a WAV file already in memory. Supports PCM 8/16/24/32
    bit and IEEE float 32/64 bit, any channel count, and skips unknown chunks
    (ffmpeg writes a LIST chunk before the data chunk). *)

val convert_to_wav : ?sample_rate:int -> string -> (string, error) result
(** [convert_to_wav src] runs [ffmpeg] to make a mono 16-bit WAV and returns
    the path of a new temp file. The caller must delete it. *)

(** {1 Size and windows (what Fft needs)} *)

val num_samples : t -> int
val duration : t -> float
(** Length in seconds. *)

val window : t -> start:int -> size:int -> float array
(** [size] samples beginning at index [start], zero-padded outside the track,
    so the FFT always receives exactly [size] values. *)

val num_windows : t -> size:int -> int
(** Number of non-overlapping windows of [size] samples covering the track. *)
