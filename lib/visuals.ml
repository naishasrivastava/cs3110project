type palette = Ocean | Sunset | Neon
type style = Circles | Bars
type settings = { palette : palette; style : style; intensity : float }

type shape =
  | Circle of { x : float; y : float; r : float; color : int * int * int }
  | Rect of { x : float; y : float; w : float; h : float; color : int * int * int }

let clamp01 x =
  if Float.is_nan x then 0. else if x < 0. then 0. else if x > 1. then 1. else x

let level_at frames ~seconds_per_frame t =
  let n = Array.length frames in
  if n = 0 then invalid_arg "Visuals.level_at: no frames"
  else
    let i = int_of_float (t /. seconds_per_frame) in
    frames.(max 0 (min (n - 1) i))

let shapes_of_levels s (l : Analysis.band_levels) =
  let r = 20. +. (200. *. clamp01 l.bass *. clamp01 s.intensity) in
  [ Circle { x = 400.; y = 300.; r; color = (255, 255, 255) } ]

let draw shapes =
  List.iter
    (function
      | Circle { x; y; r; color = (cr, cg, cb) } ->
          Raylib.draw_circle (int_of_float x) (int_of_float y) r
            (Raylib.Color.create cr cg cb 255)
      | Rect { x; y; w; h; color = (cr, cg, cb) } ->
          Raylib.draw_rectangle (int_of_float x) (int_of_float y)
            (int_of_float w) (int_of_float h)
            (Raylib.Color.create cr cg cb 255))
    shapes

let run settings frames ~seconds_per_frame =
  let duration = float_of_int (Array.length frames) *. seconds_per_frame in
  Raylib.init_window 800 600 "Visualizer";
  Raylib.set_target_fps 60;
  let start = Raylib.get_time () in
  while not (Raylib.window_should_close ()) do
    let t = Float.rem (Raylib.get_time () -. start) duration in
    let levels = level_at frames ~seconds_per_frame t in
    Raylib.begin_drawing ();
    Raylib.clear_background (Raylib.Color.create 0 0 0 255);
    draw (shapes_of_levels settings levels);
    Raylib.end_drawing ()
  done;
  Raylib.close_window ()