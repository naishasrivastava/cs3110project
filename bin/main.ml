(  Loads a WAV or MP3, runs it through Fft and Analysis (via Track), prints a table of the frames, and can save every
   frame as CSV.

     main.exe FILE [--every SECONDS] [--csv OUT.csv]            *)

let usage = "usage: main.exe FILE [--every SECONDS] [--csv OUT.csv]"

let fail msg =
  prerr_endline msg;
  exit 1

let dominant (f : Analysis.frame) =
  let b = f.Analysis.bass and m = f.Analysis.mid and t = f.Analysis.treble in
  if b = 0.0 && m = 0.0 && t = 0.0 then "-"
  else if b >= m && b >= t then "bass"
  else if m >= t then "mid"
  else "treble"

let parse args =
  let file = ref None and every = ref 0.5 and csv = ref None in
  let rec go = function
    | [] -> ()
    | "--every" :: v :: rest -> (
        match float_of_string_opt v with
        | Some s when s > 0.0 -> every := s; go rest
        | _ -> fail ("--every needs a number greater than 0\n" ^ usage))
    | "--csv" :: v :: rest -> csv := Some v; go rest
    | f :: rest when String.length f > 0 && f.[0] <> '-' && !file = None -> file := Some f; go rest
    | other :: _ -> fail ("unexpected argument: " ^ other ^ "\n" ^ usage)
  in
  go args;
  match !file with Some f -> (f, !every, !csv) | None -> fail usage

let () =
  let file, every, csv = parse (List.tl (Array.to_list Sys.argv)) in
  match Audio.load file with
  | Error e -> fail ("error: " ^ Audio.error_to_string e)
  | Ok audio ->
      let frames = Track.of_audio audio in
      if Array.length frames = 0 then fail "error: the file contains no audio";
      Printf.printf "%s: %.2f s, %d Hz, %d windows of %d samples\n\n" file (Audio.duration audio)
        audio.Audio.sample_rate (Array.length frames) Track.window_size;
      Printf.printf "%8s  %5s  %5s  %6s  %s\n" "time(s)" "bass" "mid" "treble" "dominant";
      let last = frames.(Array.length frames - 1).Analysis.time in
      let t = ref 0.0 in
      while !t <= last do
        (match Track.frame_at frames !t with
         | Some f ->
             Printf.printf "%8.2f  %5.2f  %5.2f  %6.2f  %s\n" f.Analysis.time f.Analysis.bass f.Analysis.mid
               f.Analysis.treble (dominant f)
         | None -> ());
        t := !t +. every
      done;
      (match csv with
       | None -> ()
       | Some path ->
           let oc = open_out path in
           output_string oc "time,bass,mid,treble\n";
           Array.iter
             (fun (f : Analysis.frame) ->
               Printf.fprintf oc "%.5f,%.5f,%.5f,%.5f\n" f.Analysis.time f.Analysis.bass f.Analysis.mid f.Analysis.treble)
             frames;
           close_out oc;
           Printf.printf "\nsaved %d frames to %s\n" (Array.length frames) path)
