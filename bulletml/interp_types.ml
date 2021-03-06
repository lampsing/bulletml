open Syntax

(** Types used in {!Interp}. *)

(**
   Guess what. It's [(x, y)].
*)
type position = (float * float)

(**
   Environment for indirect calls ([actionRef], etc).
*)
type 'a table = ('a id * 'a) list

(**
   Description of a phenomenon that grows in a linear (well, affine) manner:

       - at frame [frame_start], its value is [val_start].
       - at frame [frame_end], its value is [val_end].
*)
type 'a linear_map =
  { frame_start : int
  ; frame_end : int
  ; val_start : 'a
  ; val_end : 'a
  }
  [@@deriving show]

(**
   Well-typed angle.
   Program is in degrees, operations are in radians so it's
   better to be careful.
*)
type angle =
  | ADeg of float
  | ARad of float

(**
   Abstract operation, specific to a particular {!obj}.

   Some cases have an both an unevaluated form and an evaluated form.
   This is because it is necessary to delay the evaluation as late as possible,
   and having a convenient form for computations in progress.

   For example, [OpWaitX]. Evaluating [Wait (Param 1)] will create a [OpWaitE
   (Param 1)] (as is in the opcode list). When it is time to handle the opcode, it
   will be replaced by [OpWaitN 3] (if we are in a context where [$1 = 3]). At the
   next frame it will be [OpWaitN 2], etc.

   Some cases have a "term", it is the number of frames in which the evolution
   will be done in the corresponding {!linear_map}.
*)
type opcode =
  | OpRepeatE of expr * action (** Repeat {i:n} times the same {!Syntax.action} *)
  | OpWaitE of expr (** Wait {i:n} frames (unevaluated form) *)
  | OpWaitN of int (** Wait {i:n} frames (evaluated form) *)
  | OpFire of fire (** Fork execution by creating a new {!obj} *)
  | OpSpdE of speed * expr (** Change speed (unevaluated form) *)
  | OpSpdN of float linear_map (** Change speed (evaluated form) *)
  | OpDirE of direction * expr (** Change direction (unevaluated form) *)
  | OpDirN of float linear_map (** Change direction (evaluated form) *)
  | OpAccelE of expr * expr * expr (** Accelerate (unevaluated form) *)
  | OpAccelN of (float * float * int) (** Accelerate (evaluated form): [h, v, term] *)
  | OpVanish (** Let the bullet disappear *)
  | OpCall of string * expr list (** Call an indirect action with parameters *)
  | OpEnterScope
  | OpLeaveScope
  [@@deriving show]

(**
   Scopes are created and destroyed at every action.
*)
type scope =
  { prev_dir : angle (** Used for interpreting [DirSeq e] *)
  ; prev_speed : float (** Used for interpreting [SpdSeq e] *)
  }

(**
   A movable (and drawable) entity.
*)
type 'a obj =
  { prog : opcode list (** Behaviour *)
  ; speed : float (** In pixels/frame *)
  ; dir : angle (** Top is 0, clockwise. Strange, I know *)
  ; children : 'a obj list (** {!obj}s created by this one *)
  ; pos : position (** Where to draw it *)
  ; scopes : scope list (** Local "variables" *)
  ; vanished : bool (** If true, don't draw this bullet *)
  ; state : 'a (** Private state *)
  }

(** A way to modify a ['a obj] *)
type 'a hook = ('a -> 'a)

(**
   Stuff that does not change during a frame and can be referred to during
   computations.
*)
type 'a env =
  { frame : int (** Frame number. Usually starts at 1, but only deltas are significant *)
  ; ship_pos : position (** Where patterns can aim *)
  ; screen_w : int (** Screen width in pixels *)
  ; screen_h : int (** Screen height in pixels *)
  ; actions : action table (** Definitions of {!Syntax.action}s *)
  ; bullets : bullet table (** Definitions of {!Syntax.bullet}s *)
  ; fires : fire table (** Definitions of {!Syntax.fire}s *)
  ; hooks : 'a hook table (** Hooks for bullets *)
  ; rank : float (** Difficulty (0=easy, 1=hard) *)
  }

(**
   Initial parameters used to build an interpreter (see {!Interp.prepare}).
*)
type init_params =
  { p_ship : position (** Where is the ship. The one that is aimed *)
  ; p_enemy : position (** Where is the enemy. The one that shoots *)
  ; p_screen_w : int (** Screen width in pixels *)
  ; p_screen_h : int (** Screen height in pixels *)
  ; p_rank : float (** Difficulty (0=easy, 1=hard) *)
  }
