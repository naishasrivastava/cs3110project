(* Tests for Audio (WAV parsing, errors, windows, ffmpeg MP3 loading). Expected values are worked out by hand in the comments. *)
let failures = ref 0
let check name cond =
  if cond then Printf.printf "PASS %s\n" name
  else (Printf.printf "FAIL %s\n" name; incr failures)
let close a b = abs_float (a -. b) < 1e-4

(* A WAV built in memory, with an odd-sized junk chunk before the data (tests chunk padding). *)
let wav ~channels ~rate ~bits ~tag data =
  let b = Buffer.create 128 in
  let u32 n = Buffer.add_int32_le b (Int32.of_int n) in
  Buffer.add_string b "RIFF"; u32 (36 + String.length data); Buffer.add_string b "WAVE";
  Buffer.add_string b "fmt "; u32 16;
  Buffer.add_uint16_le b tag; Buffer.add_uint16_le b channels; u32 rate;
  u32 (rate * channels * bits / 8); Buffer.add_uint16_le b (channels * bits / 8);
  Buffer.add_uint16_le b bits;
  Buffer.add_string b "junk"; u32 3; Buffer.add_string b "abc\000";
  Buffer.add_string b "data"; u32 (String.length data); Buffer.add_string b data;
  Buffer.contents b

let pcm16 vals =
  let b = Buffer.create 16 in
  List.iter (Buffer.add_int16_le b) vals;
  Buffer.contents b

let () =
  (* Stereo frames (L, R) = (16384, 0) and (-16384, -16384).
     16384 / 32768 = 0.5, so frame 0 = (0.5 + 0) / 2 = 0.25 and frame 1 = (-0.5 + -0.5) / 2 = -0.5. *)
  (match Audio.of_wav_bytes (wav ~channels:2 ~rate:44100 ~bits:16 ~tag:1 (pcm16 [ 16384; 0; -16384; -16384 ])) with
   | Ok a ->
       check "stereo gives one sample per frame" (Array.length a.Audio.samples = 2);
       check "frame 0 is the average of its channels (0.25)" (close a.Audio.samples.(0) 0.25);
       check "frame 1 is the average of its channels (-0.5)" (close a.Audio.samples.(1) (-0.5));
       check "sample rate is read" (a.Audio.sample_rate = 44100)
   | Error e -> check ("stereo decode: " ^ Audio.error_to_string e) false);
  (* 32767 / 32768 is about 1.0 and -32768 / 32768 is exactly -1.0 *)
  (match Audio.of_wav_bytes (wav ~channels:1 ~rate:22050 ~bits:16 ~tag:1 (pcm16 [ 32767; -32768 ])) with
   | Ok a -> check "mono 16-bit extremes" (close a.Audio.samples.(0) 1.0 && close a.Audio.samples.(1) (-1.0))
   | Error _ -> check "mono decode" false);
  check "garbage is rejected"
    (match Audio.of_wav_bytes "hello world, not a wav" with Error (Audio.Invalid_wav _) -> true | _ -> false);
  check "WAV with an empty data chunk is rejected"
    (match Audio.of_wav_bytes (wav ~channels:1 ~rate:44100 ~bits:16 ~tag:1 "") with Error (Audio.Invalid_wav _) -> true | _ -> false);
  check "compressed WAV tag is reported as unsupported"
    (match Audio.of_wav_bytes (wav ~channels:1 ~rate:44100 ~bits:16 ~tag:2 (pcm16 [ 1; 2 ])) with Error (Audio.Unsupported_format _) -> true | _ -> false);
  check "missing file"
    (match Audio.load "/no/such/file.wav" with Error (Audio.File_not_found _) -> true | _ -> false);
  let tmp = Filename.temp_file "audio_test" ".txt" in
  check "unsupported extension"
    (match Audio.load tmp with Error (Audio.Unsupported_format _) -> true | _ -> false);
  Sys.remove tmp;
  check "error messages are non-empty" (Audio.error_to_string Audio.Ffmpeg_not_found <> "");
  (* 2500 samples at 1000 Hz = 2.5 s; ceil(2500 / 1024) = 3 windows *)
  let a = { Audio.samples = Array.init 2500 float_of_int; sample_rate = 1000 } in
  check "duration is 2.5 s" (close (Audio.duration a) 2.5);
  check "num_windows rounds up to 3" (Audio.num_windows a ~size:1024 = 3);
  check "last window is zero-padded"
    (let w = Audio.window a ~start:2048 ~size:1024 in
     Array.length w = 1024 && w.(0) = 2048.0 && w.(451) = 2499.0 && w.(452) = 0.0);
  (* real files produced by ffmpeg (see scripts/make_samples.sh) *)
  (match Audio.load "../samples/sine440_stereo.wav" with
   | Ok a ->
       check "ffmpeg stereo WAV: 44100 Hz" (a.Audio.sample_rate = 44100);
       check "ffmpeg stereo WAV: 3 s long (132300 samples)" (Audio.num_samples a = 132300);
       check "ffmpeg stereo WAV: samples in range" (Array.for_all (fun x -> abs_float x <= 1.0) a.Audio.samples)
   | Error e -> check ("load stereo WAV: " ^ Audio.error_to_string e) false);
  (match Audio.load "../samples/sine1000_mono22k.wav" with
   | Ok a -> check "mono 22050 Hz WAV rate and length" (a.Audio.sample_rate = 22050 && Audio.num_samples a = 66150)
   | Error e -> check ("load mono WAV: " ^ Audio.error_to_string e) false);
  (match Audio.load "../samples/sine440.mp3" with
   | Ok a -> check "MP3 via ffmpeg: 44100 Hz, about 3 s" (a.Audio.sample_rate = 44100 && abs_float (Audio.duration a -. 3.0) < 0.2)
   | Error Audio.Ffmpeg_not_found -> Check.skip "MP3 via ffmpeg" "ffmpeg is not installed"
   | Error e -> check ("load MP3: " ^ Audio.error_to_string e) false);
  (match Audio.load "../samples/bass_then_treble.mp3" with
   | Ok a -> check "second MP3: about 2 s, samples in range" (abs_float (Audio.duration a -. 2.0) < 0.2 && Array.for_all (fun x -> abs_float x <= 1.0) a.Audio.samples)
   | Error Audio.Ffmpeg_not_found -> Check.skip "second MP3" "ffmpeg is not installed"
   | Error e -> check ("load second MP3: " ^ Audio.error_to_string e) false);
  exit (if !failures = 0 then 0 else 1)
