(* Performance bench for the OCaml port. Emits one JSON line per
   build/bench/README.md; diagnostics go to stderr. *)
open Voxgig_struct

let envi k d =
  match Sys.getenv_opt k with
  | Some v -> (try int_of_string v with _ -> d)
  | None -> d

let rec build w d leaf =
  if d = 0 then Num (float_of_int leaf)
  else begin
    let m = empty_map () in
    for i = 0 to w - 1 do
      ignore (setprop m (Str ("k" ^ string_of_int i)) (build w (d - 1) leaf))
    done;
    m
  end

let nodecount w d =
  let n = ref 0 and p = ref 1 in
  for _ = 0 to d do n := !n + !p; p := !p * w done;
  !n

let sink = ref 0

let measure warm runs f =
  for _ = 1 to warm do f () done;
  let ts = Array.init runs (fun _ ->
    let a = Unix.gettimeofday () in
    f ();
    (Unix.gettimeofday () -. a) *. 1000.) in
  Array.sort compare ts;
  let n = Array.length ts in
  let sum = Array.fold_left (+.) 0. ts in
  (ts.(0), ts.(n / 2), sum /. float_of_int n)

let () =
  let w = envi "BENCH_WIDTH" 5 and d = envi "BENCH_DEPTH" 6
  and warm = envi "BENCH_WARMUP" 3 and runs = envi "BENCH_RUNS" 21
  and gp = envi "BENCH_GETPATH_ITERS" 2000 in
  let tree = build w d 0 and nodes = nodecount w d in
  let treea = build w d 1 and treeb = build w d 2 in
  let mlist = lst [ treea; treeb ] in
  let path = Str (String.concat "." (List.init d (fun _ -> "k0"))) in
  let cb _key v _parent p = sink := !sink + size p; v in
  let specs = [
    ("clone", nodes, (fun () -> ignore (clone tree); sink := !sink + 1));
    ("walk", nodes, (fun () -> ignore (walk ~before:cb tree)));
    ("merge", nodes, (fun () -> ignore (merge mlist); sink := !sink + 1));
    ("stringify", nodes, (fun () -> sink := !sink + String.length (stringify tree)));
    ("getpath", gp, (fun () ->
      for _ = 1 to gp do ignore (getpath tree path) done; sink := !sink + gp));
  ] in
  let bufs = List.map (fun (op, uc, f) ->
    let (mn, md, mean) = measure warm runs f in
    Printf.sprintf
      "{\"op\":\"%s\",\"runs\":%d,\"unit_count\":%d,\"min_ms\":%g,\"median_ms\":%g,\"mean_ms\":%g}"
      op runs uc mn md mean) specs in
  Printf.eprintf "ocaml: sink=%d\n" !sink;
  Printf.printf
    "{\"lang\":\"ocaml\",\"runtime\":\"ocaml %s\",\"nodes\":%d,\"params\":{\"width\":%d,\"depth\":%d,\"warmup\":%d,\"runs\":%d,\"getpath_iters\":%d},\"ops\":[%s]}\n"
    Sys.ocaml_version nodes w d warm runs gp (String.concat "," bufs)
