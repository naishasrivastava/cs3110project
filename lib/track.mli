(** The whole pipeline in one place: file -> Audio -> windows -> Fft -> Analysis -> frames for Visuals.
    Frame [i] covers samples [i * window_size, (i + 1) * window_size) of the audio. *)

val window_size : int
(** 1024 samples per analysis window. Windows do not overlap. *)

val raw : Audio.t -> Analysis.frame array
(** One frame per window, straight from the FFT (not normalized or smoothed). *)

val of_audio : Audio.t -> Analysis.frame array
(** [raw], then {!Analysis.normalize}, then {!Analysis.smooth}: what Visuals draws from. *)

val of_file : string -> (Analysis.frame array, Audio.error) result
(** [of_file path] loads a WAV or MP3 (MP3 goes through ffmpeg) and analyzes it. *)

val frame_at : Analysis.frame array -> float -> Analysis.frame option
(** The frame whose window contains the given time in seconds (times before the start give the first frame,
    times past the end the last), or [None] for an empty array. *)
