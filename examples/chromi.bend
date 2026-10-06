import Base
import ../gpu.bend as V
import ../quads.bend as Q
import ../words.bend as W
import ../../Ankra/window.bend as A
import ../../Ankra/app.bend as Loop
import ./scene.bend as Scene

# A frame rendered by Chromi on the CPU, presented by Voltra on the GPU, in
# a window that Ankra owns.
#
# Chromi draws its shape scene at the window's size. The finished quadtree
# reaches the GPU one of two ways, toggled with the M key:
#   texture: flattened to RGBA8 in Bend, uploaded, drawn as one textured quad;
#   leaves:  each uniform quadtree leaf drawn as one colored quad, no texture.
# A click changes the accent color (Chromi re-renders); resizing re-renders
# at the new size; an expose only re-presents. Escape or closing the window
# ends the program.

def background() -> U32:
  219422463

type Demo is Data:
  Demo{accent: U32, leaves: Bool, dirty: Bool, quads: List<&2, Q.Quad>,
    width: U32, height: U32, renders: U32}

type Run is Data:
  Run{gpu: V.Gpu, app: Demo}

def gpu_of(r: Run) -> V.Gpu:
  Run{g, a} = r
  g

def app_of(r: Run) -> Demo:
  Run{g, a} = r
  a

def mode_name(leaves: Bool) -> String:
  Bool.pick(String, leaves, "leaves", "texture")

def report(+mode: String, +w: U32, +h: U32, +chromi: Nat, +upload: Nat, +quads: U32) -> IO(Unit):
  IO.print("render " ++ U32.show(w) ++ "x" ++ U32.show(h) ++ " [" ++ mode ++
    "]: Chromi " ++ Nat.show(chromi) ++ " ms, to GPU " ++ Nat.show(upload) ++
    " ms, " ++ U32.show(quads) ++ " quads")

def texture_quad(+w: U32, +h: U32) -> List<&2, Q.Quad>:
  [Q.image(0, 0, w, h, 0, 0, w, h, 4294967295)]

def to_gpu(leaves: Bool, +g: V.Gpu, img: Image, +w: U32, +h: U32) -> IO(Run):
  match leaves:
    case True{}:
      IO.pure(Run, Run{g, Demo{0, True{}, False{}, Q.leaves(img, 0, 0, Q.side(w, h), w, h, []), w, h, 0}})
    case False{}:
      do IO<Run>:
        +g1 : V.Gpu <- V.upload(g, w, h,
          Q.raster(img, Array.new(U32, W.depth((w * h : U32)), 0), 0, 0, Q.side(w, h), w, h))
        return Run{g1, Demo{0, False{}, False{}, texture_quad(w, h), w, h, 0}}

def rendered(+accent: U32, +renders: U32, +t0: Nat, +t1: Nat, r: Run) -> IO(Run):
  Run{g, app} = r
  Demo{a, +leaves, d, +qs, +w, +h, n} = app
  do IO<Run>:
    +t2 : Nat <- IO.now()
    report(mode_name(leaves), w, h, Nat.sub(t1, t0), Nat.sub(t2, t1),
      U32.from_nat(List.length(&2, Q.Quad, qs)))
    return Run{g, Demo{accent, leaves, False{}, qs, w, h, (renders + 1 : U32)}}

def render.image(+g: V.Gpu, +accent: U32, +leaves: Bool, +renders: U32, +w: U32, +h: U32,
  +t0: Nat, r: Result<&1, &1, U32 & String, Image>) -> IO(Run):
  do IO<Run>:
    img : Image <- IO.pass(Image, r)
    +t1 : Nat <- IO.now()
    done : Run <- to_gpu(leaves, g, img, w, h)
    rendered(accent, renders, t0, t1, done)

def render.sized(+g: V.Gpu, app: Demo, size: V.Size) -> IO(Run):
  Demo{+accent, +leaves, d, q, ow, oh, +renders} = app
  V.Size{+w, +h} = size
  do IO<Run>:
    +t0 : Nat <- IO.now()
    render.image(g, accent, leaves, renders, w, h, t0, Scene.draw(w, h, accent))

def stale.size(app: Demo, size: V.Size) -> Bool:
  Demo{a, l, +dirty, q, +w, +h, n} = app
  V.Size{+tw, +th} = size
  dirty || U32.is_ne(w, tw) || U32.is_ne(h, th)

# Re-renders with Chromi only when the content or the target size changed.
def render(stale: Bool, +g: V.Gpu, +app: Demo) -> IO(Run):
  match stale:
    case False{}:
      IO.pure(Run, Run{g, app})
    case True{}:
      render.sized(g, app, V.target_size(g))

def present(r: Run) -> IO(Run):
  Run{+g, +app} = r
  Demo{a, l, d, +qs, w, h, n} = app
  do IO<Run>:
    +g1 : V.Gpu <- V.draw(g, qs, background())
    return Run{g1, app}

def clicks(es: List<&2, A.Input>, +n: U32) -> U32:
  match es:
    case Nil{}:
      n
    case Con{A.PointerDown{x, y, 0, m}, rest}:
      clicks(rest, (n + 1 : U32))
    case Con{e, rest}:
      clicks(rest, n)

def key(es: List<&2, A.Input>, +code: U32) -> Bool:
  match es:
    case Nil{}:
      False{}
    case Con{A.KeyDown{k, r, m}, rest}:
      U32.is_eq(k, code) || key(rest, code)
    case Con{e, rest}:
      key(rest, code)

def apply.size(m: Maybe<&2, A.Size>, +g: V.Gpu) -> IO(V.Gpu):
  match m:
    case None{}:
      IO.pure(V.Gpu, g)
    case Some{A.Size{w, h}}:
      V.resize(g, w, h)

def dirty(app: Demo) -> Bool:
  Demo{a, l, d, q, w, h, n} = app
  d

def step(+stop: Bool, +r: Run) -> Loop.Step<Run>:
  Bool.pick(Loop.Step<Run>, stop, Loop.Stop{r},
    Bool.pick(Loop.Step<Run>, V.pending(gpu_of(r)) || dirty(app_of(r)), Loop.Redraw{r}, Loop.Keep{r}))

# Input and window changes: clicks and M change the content, a new size
# rebuilds the swapchain, an expose re-presents, Escape stops.
def update(win: A.Win, batch: List<&2, A.Input>, r: Run) -> IO(Loop.Step<Run>):
  Run{+g, app} = r
  Demo{+accent, +leaves, +dirty, qs, w, h, n} = app
  +es = batch
  +c = clicks(es, 0)
  +m = key(es, 109)
  +changed = U32.is_gt(c, 0) || m
  do IO<Loop.Step<Run>>:
    +g1 : V.Gpu <- apply.size(A.resized(es, None{}), g)
    return step(key(es, 27), Run{Bool.pick(V.Gpu, changed || A.exposed(es), V.invalidate(g1), g1),
      Demo{(accent + c : U32), Bool.xor(leaves, m), dirty || changed, qs, w, h, n}})

# Re-renders with Chromi when the content or the target size changed, then
# presents; asks for another frame while one is owed.
def draw(win: A.Win, r: Run) -> IO(Loop.Step<Run>):
  Run{+g, +app} = r
  do IO<Loop.Step<Run>>:
    +r1 : Run <- render(stale.size(app, V.target_size(g)), g, app)
    +r2 : Run <- present(r1)
    return step(False{}, r2)

def finish(end: A.Win & Run) -> IO(Unit):
  (win, r) = end
  Run{+g, app} = r
  Demo{a, l, d, q, w, h, +renders} = app
  do IO<Unit>:
    IO.print("frames presented: " ++ U32.show(V.drawn(g)) ++ ", Chromi renders: " ++
      U32.show(renders) ++ ", swapchain rebuilds: " ++ U32.show(V.rebuilds(g)))
    +report : V.Report <- V.close(g)
    IO.print(V.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("window objects left: " ++ U32.show(left))

def has(args: List<String>, +word: String) -> Bool:
  match args:
    case Nil{}:
      False{}
    case Con{a, rest}:
      String.eq(a, word) || has(rest, word)

# `chromi leaves` starts in leaves mode.
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +leaves : Bool = has(args, "leaves")
    +win : A.Win <- IO.try(A.Win, A.open(A.options("Voltra - Chromi frame on the GPU", 960, 630)))
    +native : List<&2, U32> <- A.native(win)
    +g : V.Gpu <- V.open(native, 960, 630, True{})
    IO.print(V.describe(g))
    end : A.Win & Run <- Loop.run(~Run, ~update, ~draw, win, Run{g, Demo{0, leaves, True{}, [], 0, 0, 0}})
    finish(end)
