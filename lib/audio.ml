type t = { samples : float array; sample_rate : int }

type error =
  | File_not_found of string
  | Unsupported_format of string
  | Invalid_wav of string
  | Ffmpeg_not_found
  | Ffmpeg_failed of string

let error_to_string = function
  | File_not_found p -> Printf.sprintf "File not found: %s" p
  | Unsupported_format m -> Printf.sprintf "Unsupported audio format: %s" m
  | Invalid_wav m -> Printf.sprintf "Invalid WAV file: %s" m
  | Ffmpeg_not_found ->
      "ffmpeg was not found. Install it (e.g. `brew install ffmpeg`) or load a WAV file."
  | Ffmpeg_failed m -> Printf.sprintf "ffmpeg could not convert the file: %s" m

let ( let* ) = Result.bind

(* ---------- WAV decoding ---------- *)

type fmt = { tag : int; channels : int; rate : int; bits : int }

let u16 s o = String.get_uint16_le s o
let u32 s o = Int32.to_int (String.get_int32_le s o) land 0xFFFFFFFF

let decode_samples (f : fmt) s off nbytes =
  let supported =
    match (f.tag, f.bits) with
    | 1, (8 | 16 | 24 | 32) -> true
    | 3, (32 | 64) -> true
    | _ -> false
  in
  if f.channels < 1 then Error (Invalid_wav "zero channels")
  else if f.rate <= 0 then Error (Invalid_wav "sample rate must be positive")
  else if not supported then
    Error
      (Unsupported_format
         (Printf.sprintf "WAV encoding %d with %d bits per sample (convert it with ffmpeg)"
            f.tag f.bits))
  else begin
    let bytes_per = f.bits / 8 in
    let frame_bytes = bytes_per * f.channels in
    let n = nbytes / frame_bytes in
    if n = 0 then Error (Invalid_wav "the data chunk contains no audio")
    else begin
      let sample pos =
        match (f.tag, f.bits) with
        | 1, 8 -> float_of_int (String.get_uint8 s pos - 128) /. 128.0
        | 1, 16 -> float_of_int (String.get_int16_le s pos) /. 32768.0
        | 1, 24 ->
            let v =
              String.get_uint8 s pos
              lor (String.get_uint8 s (pos + 1) lsl 8)
              lor (String.get_uint8 s (pos + 2) lsl 16)
            in
            let v = if v >= 0x800000 then v - 0x1000000 else v in
            float_of_int v /. 8388608.0
        | 1, _ -> Int32.to_float (String.get_int32_le s pos) /. 2147483648.0
        | _, 32 -> Int32.float_of_bits (String.get_int32_le s pos)
        | _, _ -> Int64.float_of_bits (String.get_int64_le s pos)
      in
      let inv_ch = 1.0 /. float_of_int f.channels in
      let samples =
        Array.init n (fun i ->
            let base = off + (i * frame_bytes) in
            let acc = ref 0.0 in
            for c = 0 to f.channels - 1 do
              acc := !acc +. sample (base + (c * bytes_per))
            done;
            !acc *. inv_ch (* stereo -> mono: average the channels *))
      in
      Ok { samples; sample_rate = f.rate }
    end
  end

let of_wav_bytes s =
  let len = String.length s in
  if len < 12 || String.sub s 0 4 <> "RIFF" || String.sub s 8 4 <> "WAVE" then
    Error (Invalid_wav "missing RIFF/WAVE header")
  else
    let rec scan pos fmt =
      if pos + 8 > len then
        Error (Invalid_wav (if fmt = None then "no fmt chunk" else "no data chunk"))
      else
        let id = String.sub s pos 4 in
        let size = u32 s (pos + 4) in
        let body = pos + 8 in
        let next = body + size + (size land 1) (* chunks are padded to even size *) in
        match id with
        | "fmt " ->
            if size < 16 || body + 16 > len then Error (Invalid_wav "truncated fmt chunk")
            else
              let tag = u16 s body in
              (* WAVE_FORMAT_EXTENSIBLE: real format tag is the first 2 bytes of the subformat GUID *)
              let tag = if tag = 0xFFFE && size >= 26 && body + 26 <= len then u16 s (body + 24) else tag in
              scan next
                (Some { tag; channels = u16 s (body + 2); rate = u32 s (body + 4); bits = u16 s (body + 14) })
        | "data" -> (
            match fmt with
            | None -> Error (Invalid_wav "data chunk appears before fmt chunk")
            | Some f ->
                (* streamed files may claim a huge size: clamp to what is really there *)
                decode_samples f s body (min size (len - body)))
        | _ -> scan next fmt
    in
    scan 12 None

(* ---------- reading files ---------- *)

let read_file path =
  try
    let ic = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Ok (really_input_string ic (in_channel_length ic)))
  with Sys_error _ | End_of_file -> Error (Invalid_wav ("could not read " ^ path))

(* ---------- ffmpeg ---------- *)

let tail n s =
  let s = String.trim s in
  let l = String.length s in
  if l <= n then s else String.sub s (l - n) n

let convert_to_wav ?(sample_rate = 44100) src =
  if not (Sys.file_exists src) then Error (File_not_found src)
  else begin
    let out = Filename.temp_file "audio_" ".wav" in
    let log = Filename.temp_file "ffmpeg_" ".log" in
    let devnull = Unix.openfile Filename.null [ Unix.O_RDWR ] 0 in
    let errfd = Unix.openfile log [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
    (* Arguments go in an array (no shell), so odd file names cannot inject commands.
       "file:" stops ffmpeg treating a name like "a:b.mp3" as a protocol. *)
    let args =
      [| "ffmpeg"; "-y"; "-v"; "error"; "-i"; "file:" ^ src; "-vn"; "-ac"; "1";
         "-ar"; string_of_int sample_rate; "-c:a"; "pcm_s16le"; "-f"; "wav"; "file:" ^ out |]
    in
    let result =
      match Unix.create_process "ffmpeg" args devnull devnull errfd with
      | exception Unix.Unix_error (Unix.ENOENT, _, _) -> Error Ffmpeg_not_found
      | exception Unix.Unix_error (e, _, _) -> Error (Ffmpeg_failed (Unix.error_message e))
      | pid -> (
          match snd (Unix.waitpid [] pid) with
          | Unix.WEXITED 0 -> Ok out
          | Unix.WEXITED 127 -> Error Ffmpeg_not_found (* shell-style "command not found" *)
          | _ ->
              let msg = match read_file log with Ok l -> tail 300 l | Error _ -> "" in
              Error (Ffmpeg_failed (if msg = "" then "unknown error" else msg)))
    in
    Unix.close devnull;
    Unix.close errfd;
    (try Sys.remove log with Sys_error _ -> ());
    (match result with Error _ -> (try Sys.remove out with Sys_error _ -> ()) | Ok _ -> ());
    result
  end

(* ---------- public loader ---------- *)

let load path =
  if not (Sys.file_exists path) then Error (File_not_found path)
  else if Sys.is_directory path then Error (Unsupported_format (path ^ " is a directory"))
  else
    match String.lowercase_ascii (Filename.extension path) with
    | ".wav" ->
        let* bytes = read_file path in
        of_wav_bytes bytes
    | ".mp3" | ".m4a" | ".aac" | ".flac" | ".ogg" ->
        let* tmp = convert_to_wav path in
        Fun.protect
          ~finally:(fun () -> try Sys.remove tmp with Sys_error _ -> ())
          (fun () ->
            let* bytes = read_file tmp in
            of_wav_bytes bytes)
    | "" -> Error (Unsupported_format "file has no extension (expected .wav or .mp3)")
    | ext -> Error (Unsupported_format (Printf.sprintf "%s files (expected .wav or .mp3)" ext))

(* ---------- sizes and windows ---------- *)

let num_samples t = Array.length t.samples
let duration t = float_of_int (num_samples t) /. float_of_int t.sample_rate

let window t ~start ~size =
  let n = num_samples t in
  Array.init size (fun i ->
      let j = start + i in
      if j >= 0 && j < n then t.samples.(j) else 0.0)

let num_windows t ~size = (num_samples t + size - 1) / size
