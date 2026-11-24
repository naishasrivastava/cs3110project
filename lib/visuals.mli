(* visuals.mli *)
type palette = Ocean | Sunset | Neon
type style = Circles | Bars
type settings = { palette : palette; style : style; intensity : float }

type shape =
  | Circle of { x : float; y : float; r : float; color : int * int * int }
  | Rect of { x : float; y : float; w : float; h : float; color : int * int * int }

val clamp01 : float -> float
(** [clamp01 x] is [x] limited to [0., 1.]; NaN becomes [0.]. *)

val levels_of_frames : Analysis.frame array -> Analysis.band_levels array
(** Drop the timestamps from [Track]'s frames, giving what {!level_at} and
    {!run} take. *)
    
val level_at :
  Analysis.band_levels array -> seconds_per_frame:float -> float -> Analysis.band_levels
(** [level_at frames ~seconds_per_frame t] is the frame playing at time [t].
    Times before the start or past the end give the first or last frame.
    Raises [Invalid_argument] if [frames] is empty. *)

val shapes_of_levels : settings -> Analysis.band_levels -> shape list
(** What to draw for one frame. Pure: no drawing happens here. *)

val run :
  settings -> Analysis.band_levels array -> seconds_per_frame:float -> unit
(** Opens a window and animates [frames] until it is closed.  Loops when the
    frames run out. *)