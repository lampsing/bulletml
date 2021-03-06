open Interp_types
open Syntax

let pi = acos (-1.)

let from_deg x =
  2. *. pi *. x /. 360.

let to_deg x =
  360. *. x /. (2. *. pi)

let (+:) (xa, ya) (xb, yb) =
  (xa +. xb, ya +. yb)

let (-:) (xa, ya) (xb, yb) =
  (xa -. xb, ya -. yb)

let ( *% ) (x, y) l =
  (x *. l, y *. l)

let add_angle a b = match (a, b) with
  | ADeg da, ADeg db -> ADeg (da +. db)
  | ARad ra, ARad rb -> ARad (ra +. rb)
  | ARad ra, ADeg db -> ARad (ra +. from_deg db)
  | ADeg da, ARad rb -> ARad (from_deg da +. rb)

let sub_angle a = function
  | ADeg d -> add_angle a (ADeg (-.d))
  | ARad r -> add_angle a (ARad (-.r))

let in_rads = function
  | ARad r -> r
  | ADeg r -> from_deg r

let in_degs = function
  | ADeg d -> d
  | ARad r -> to_deg r

let unit_vec_rad dir =
  (sin dir, cos dir)

let unit_vec dir =
  unit_vec_rad (in_rads dir)

let polar (x, y) =
  let r = hypot x y in
  let t = ARad (atan2 x y) in
  (r, t)

let from_polar (r, t) =
  unit_vec t *% r

let eval_op = function
  | Add -> ( +. )
  | Mul -> ( *. )
  | Sub -> ( -. )
  | Div -> ( /. )
  | Mod -> fun x y -> float (int_of_float x mod int_of_float y)

let rec eval st = function
  | Num f -> f
  | Op (op, x, y) -> eval_op op (eval st x) (eval st y)
  | Rand -> Random.float 1.0
  | Param _ -> failwith "Param"
  | Rank -> st.rank

let rec subst_expr p = function
  | (Num _ | Rand | Rank) as e -> e
  | Op (op, x, y) -> Op (op, subst_expr p x, subst_expr p y)
  | Param n -> List.assoc n p

let subst_dir p = function
  | DirAbs e -> DirAbs (subst_expr p e)
  | DirSeq e -> DirSeq (subst_expr p e)
  | DirAim e -> DirAim (subst_expr p e)
  | DirRel e -> DirRel (subst_expr p e)

let subst_spd p = function
  | SpdAbs e -> SpdAbs (subst_expr p e)
  | SpdRel e -> SpdRel (subst_expr p e)
  | SpdSeq e -> SpdSeq (subst_expr p e)

let subst_ind subst_elem p = function
  | Direct x -> Direct (subst_elem p x)
  | Indirect (s, args) -> Indirect (s, List.map (subst_expr p) args)

let subst_opt subst_elem p = function
  | Some x -> Some (subst_elem p x)
  | None -> None

let rec subst_action p =
  List.map (subst_subaction p)

and subst_subaction p = function
  | Repeat (e, ai) -> Repeat (subst_expr p e, subst_ind subst_action p ai)
  | Fire fi -> Fire (subst_ind subst_fire p fi)
  | ChangeSpeed (spd, e) -> ChangeSpeed (subst_spd p spd, subst_expr p e)
  | ChangeDirection (dir, e) -> ChangeDirection (subst_dir p dir, subst_expr p e)
  | Accel (eo1, eo2, e3) ->
    Accel (
      subst_opt subst_expr p eo1,
      subst_opt subst_expr p eo1,
      subst_expr p e3)
  | Wait e -> Wait (subst_expr p e)
  | Vanish -> Vanish
  | Action ai -> Action (subst_ind subst_action p ai)

and subst_fire p (diro, spdo, bi) =
  ( subst_opt subst_dir p diro
  , subst_opt subst_spd p spdo
  , subst_ind subst_bullet p bi
  )

and subst_bullet p (Bullet (diro, spdo, ais)) =
  Bullet (
    subst_opt subst_dir p diro,
    subst_opt subst_spd p spdo,
    List.map (subst_ind subst_action p) ais
  )

let number_params l =
  let i = ref 0 in
  List.map (fun p ->
      incr i;
      (!i, p)
    ) l

let ind_call st env sub = function
  | Direct x -> (x, None)
  | Indirect (n, params) ->
    let a = List.assoc n env in
    let params_ev = List.map (
        fun e -> Num (eval st e)
      ) params in
    let p = number_params params_ev in
    (sub p a, Some n)

let eval_ai st = ind_call st st.actions subst_action
let eval_bi st = ind_call st st.bullets subst_bullet
let eval_fi st = ind_call st st.fires subst_fire

let interp_map st m =
  let frames_done = float (st.frame - m.frame_start) in
  let frames_total = float (m.frame_end - m.frame_start) in
  m.val_start +. frames_done *. (m.val_end -. m.val_start) /. frames_total

let replicate_list n l =
  print_endline (string_of_int n);
  let rec go n acc =
    match n with
    | _ when n < 0 -> invalid_arg "replicate_list"
    | 0 -> acc
    | _ -> go (n-1) (l @ acc)
  in
  go n []

let rec build_prog st next = function
  | Repeat (e_n, ai) ->
    let (a, _) = eval_ai st ai in
    OpRepeatE (e_n, a) :: next
  | Wait e_n -> OpWaitE e_n :: next
  | Fire fi ->
    let (f, _) = eval_fi st fi in
    OpFire f :: next
  | ChangeSpeed (s, e) -> OpSpdE (s, e) :: next
  | ChangeDirection (d, e) -> OpDirE (d, e) :: next
  | Accel (ho, vo, e) ->
    let default = function
      | Some x -> x
      | None -> Num 0.0
    in
    OpAccelE (default ho, default vo, e)::next
  | Vanish -> OpVanish :: next
  | Action (Direct a) ->
    OpEnterScope::seq_prog st a next@[OpLeaveScope]
  | Action (Indirect (n, exprs)) ->
    OpEnterScope::OpCall (n, exprs)::next@[OpLeaveScope]

and seq_prog st act next =
  List.fold_left (build_prog st) next (List.rev act)

let read_prog (BulletML (hv, ts)) =
  let ae = ref [] in
  let be = ref [] in
  let fe = ref [] in
  List.iter (function
      | EAction (l, a) -> ae := (l, a)::!ae
      | EBullet (l, b) -> be := (l, b)::!be
      | EFire (l, f) -> fe := (l, f)::!fe
    ) ts;
  (!ae, !be, !fe)

let initial_obj k pos s =
  { prog = k
  ; speed = 0.0
  ; dir = ARad 0.0
  ; children = []
  ; pos = pos
  ; scopes = [{ prev_dir = ARad 0.0
              ; prev_speed = 0.0
              }]
  ; vanished = false
  ; state = s
  }

let dir_to_ship st obj =
  let (vx, vy) = (st.ship_pos -: obj.pos) in
  ARad (atan2 vx vy)

let dir_to_prev obj =
  let scope = List.hd obj.scopes in
  scope.prev_dir

let repeat_prog st n act next =
  seq_prog st (replicate_list n act) next

let eval_dir st self = function
  | DirAbs e -> ADeg (eval st e)
  | DirAim e -> add_angle (ADeg (eval st e)) (dir_to_ship st self)
  | DirSeq e -> add_angle (ADeg (eval st e)) (dir_to_prev self)
  | DirRel e -> add_angle (ADeg (eval st e)) self.dir

let eval_speed st self = function
  | SpdAbs e -> eval st e
  | SpdRel e -> eval st e +. self.speed
  | SpdSeq e ->
    let scope = List.hd self.scopes in
    eval st e +. scope.prev_speed

let oneof x y z =
  match x with
  | Some r -> r
  | None ->
    match y with
    | Some r -> r
    | None -> z

let apply_hook st obj = function
  | None -> obj
  | Some n ->
    try
      let f = List.assoc n st.hooks in
      { obj with state = f obj.state }
    with Not_found -> obj

let rec next_prog st self :'a obj = match self.prog with
  | [] -> self
  | OpRepeatE (n_e, a)::k ->
    let n = int_of_float (eval st n_e) in
    next_prog st { self with prog = repeat_prog st n a k }
  | OpWaitE n_e::k ->
    let n = int_of_float (eval st n_e) in
    next_prog st { self with prog = OpWaitN n::k }
  | OpWaitN 0::k -> next_prog st { self with prog = k }
  | OpWaitN 1::k -> { self with prog = k }
  | OpWaitN n::k -> { self with prog = OpWaitN (n-1)::k }
  | OpFire (dir_f, spd_f, bi)::k ->
    let Bullet (dir_b, spd_b, ais), name_o = eval_bi st bi in
    let dir = oneof dir_b dir_f (DirAim (Num 0.)) in
    let spd = oneof spd_b spd_f (SpdAbs (Num 1.)) in
    let d = eval_dir st self dir in
    let s = eval_speed st self spd in
    let sas: action = List.map (fun ai -> Action ai) ais in
    let ops: opcode list = seq_prog st sas [] in
    let o_base =
      { self with
        speed = s
      ; dir = d
      ; prog = ops
      ; children = []
      }
    in
    let o = apply_hook st o_base name_o in
    let scope = List.hd self.scopes in
    let pd = match dir with
      | DirSeq _ -> d
      | _ -> scope.prev_dir
    in
    let ps = match spd with
      | SpdSeq _ -> s
      | _ -> scope.prev_speed
    in
    let other_scopes = List.tl self.scopes in
    { self with
      prog = k
    ; children = o::self.children
    ; scopes = { prev_dir = pd
               ; prev_speed = ps
               }::other_scopes
    }
  | OpSpdE (sp_e, t_e)::k ->
    let sp = eval_speed st self sp_e in
    let t = int_of_float (eval st t_e) in
    let m =
      { frame_start = st.frame - 1
      ; frame_end = st.frame + t - 1
      ; val_start = self.speed
      ; val_end = sp
      }
    in
    next_prog st { self with prog = OpSpdN m::k }
  | OpSpdN m::k ->
    if st.frame > m.frame_end then
      { self with prog = k }
    else
      { self with speed = interp_map st m }
  | OpDirN m::k ->
    if st.frame > m.frame_end then
      { self with prog = k }
    else
      let new_dir = ARad (interp_map st m) in
      { self with dir = new_dir }
  | OpDirE (d_e, t_e)::k ->
    let dir = eval_dir st self d_e in
    let t = int_of_float (eval st t_e) in
    let m =
      { frame_start = st.frame - 1
      ; frame_end = st.frame + t - 1
      ; val_start = in_rads self.dir
      ; val_end = in_rads dir
      }
    in
    next_prog st { self with prog = OpDirN m::k }
  | OpVanish::_ -> next_prog st { self with prog = [] ; vanished = true }
  | OpAccelE (h_e, v_e, t_e)::k ->
    let h = eval st h_e in
    let v = eval st v_e in
    let t = eval st t_e in
    next_prog st { self with prog = OpAccelN (h, v, int_of_float t)::k }
  | OpAccelN (h, v, t)::k when t <= 0 ->
    next_prog st { self with prog = k }
  | OpAccelN (h, v, t)::k ->
    let (vx, vy) = (unit_vec self.dir *% self.speed) +: (h, v) in
    let (ns, nd) = polar (vx, vy) in
    { self with
      prog = OpAccelN (h, v, t - 1)::k
    ; speed = ns
    ; dir = nd
    }
  | OpCall (n, params)::k ->
    let act_templ = List.assoc n st.actions in
    let params_ev = List.map (fun e -> Num (eval st e)) params in
    let p = number_params params_ev in
    let act = subst_action p act_templ in
    next_prog st { self with prog = seq_prog st act k }
  | OpEnterScope::k ->
    let new_scope =
      { prev_dir = ADeg 0.0
      ; prev_speed = 0.0
      }
    in
    { self with
      prog = k
    ; scopes = new_scope::self.scopes
    }
  | OpLeaveScope::k ->
    { self with
      prog = k
    ; scopes = List.tl self.scopes
    }

(**
 * Detect if a bullet should be deleted.
 *
 * It's unclear what to do about orphan bullets:
 *  - Sometimes oob bullets continue to spawn bullets that will get in bounds.
 *  - Sometimes oob bullets should be pruned, but their children need to live
 *
 * To be conservative, a children = [] works.
 * At worst, the parent bullet will get deleted next frame.
 **)
let prunable st o =
  let is_oob (x, y) =
    x < 0.0 || y < 0.0 || x >= float st.screen_w || y >= float st.screen_w
  in
  o.children = [] && (o.vanished || is_oob o.pos)

let animate_physics o =
  { o with pos = (o.pos +: unit_vec o.dir *% o.speed) }

let rec animate st o =
  let new_children =
    List.map (animate st)
      ( List.filter (fun o -> not (prunable st o)) o.children)
  in
  let o1 = { o with children = new_children } in
  let o2 = next_prog st o1 in
  let o3 = animate_physics o2 in
  o3

let rec collect_obj p =
  [p] @ List.flatten (List.map collect_obj p.children)

let rec find_assoc env = function
  | [] -> raise Not_found
  | x::xs -> try (List.assoc x env, x) with Not_found -> find_assoc env xs

let prepare bml params s =
  let (aenv, benv, fenv) = read_prog bml in
  let print_env e = String.concat ", " (List.map fst e) in
  Printf.printf "a: %s\nb: %s\nf: %s\n"
    (print_env aenv)
    (print_env benv)
    (print_env fenv);
  let (act, top) = find_assoc aenv ["top";"top1"] in
  let global_env =
    { frame = 0
    ; ship_pos = params.p_ship
    ; screen_w = params.p_screen_w
    ; screen_h = params.p_screen_h
    ; actions = aenv
    ; bullets = benv
    ; fires = fenv
    ; hooks = []
    ; rank = params.p_rank
    }
  in
  let k = build_prog global_env [] (Action (Direct act)) in
  let obj = initial_obj k params.p_enemy s in
  (global_env, obj, top)
