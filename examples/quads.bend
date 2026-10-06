import Base
import ../gpu.bend as V
import ../quads.bend as Q
import ../words.bend as W
import ../../Ankra/window.bend as A
import ../../Ankra/app.bend as Loop

# Colored and textured quads on the GPU, in a window that Ankra owns.
# Resize the window: the layout follows the new size and the swapchain is
# rebuilt. Between changes the program sleeps without a deadline. Close it
# normally (or press Escape); the program then reports how many native
# objects outlived teardown (0).

# A 64x64 RGBA8 checkerboard, built in Bend, uploaded as the texture.
def checker.go(n: Nat, a: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      +x = (i % 64 : U32)
      +y = (i / 64 : U32)
      +dark = U32.is_eq((((x / 8 : U32) + (y / 8 : U32)) % 2 : U32), 0)
      checker.go(p, Array.set(U32, a, i,
        Bool.pick(U32, dark, 4155374335, 1110466047)), (i + 1 : U32))

def checker() -> Array<U32>:
  checker.go(4096n, Array.new(U32, 12n, 0), 0)

def tiles.go(n: Nat, +i: U32, +w: U32, +h: U32, acc: List<&2, Q.Quad>) -> List<&2, Q.Quad>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +col = (i % 6 : U32)
      +row = (i / 6 : U32)
      +tw = ((w - 48 : U32) / 6 : U32)
      +th = ((h - 168 : U32) / 4 : U32)
      +hue = (i * 40 : U32)
      tiles.go(p, (i + 1 : U32), w, h,
        Q.fill((24 + col * tw + 4 : U32), (144 + row * th + 4 : U32),
          (tw - 8 : U32), (th - 8 : U32),
          ((((hue .&. 255 : U32) << 24n) .|. ((((255 - hue) .&. 255 : U32)) << 16n) .|. (180 << 8n) .|. 230) : U32)) <> acc)

def scene(+w: U32, +h: U32) -> List<&2, Q.Quad>:
  tiles.go(24n, 0, w, h, [Q.fill(0, 0, w, 120, 589505535),
   Q.fill(24, 24, (w - 48 : U32), 72, 1110466047),
   Q.image(32, 32, 56, 56, 0, 0, 64, 64, 4294967295),
   Q.image(104, 32, 56, 56, 0, 0, 32, 32, 4294967295),
   Q.fill(176, 40, 200, 40, 2952773119)])

# The app state for Ankra's loop: just the GPU context.
type Demo is Data:
  Demo{gpu: V.Gpu}

def escape(es: List<&2, A.Input>) -> Bool:
  match es:
    case Nil{}:
      False{}
    case Con{A.KeyDown{27, r, m}, rest}:
      True{}
    case Con{e, rest}:
      escape(rest)

def resized(m: Maybe<&2, A.Size>, +g: V.Gpu) -> IO(V.Gpu):
  match m:
    case None{}:
      IO.pure(V.Gpu, g)
    case Some{A.Size{w, h}}:
      V.resize(g, w, h)

def decide(+stop: Bool, +redraw: Bool, +g: V.Gpu) -> Loop.Step<Demo>:
  Bool.pick(Loop.Step<Demo>, stop, Loop.Stop{Demo{g}},
    Bool.pick(Loop.Step<Demo>, redraw || V.pending(g), Loop.Redraw{Demo{g}}, Loop.Keep{Demo{g}}))

# Window changes: a new size rebuilds the swapchain; an expose re-presents.
def update(win: A.Win, batch: List<&2, A.Input>, d: Demo) -> IO(Loop.Step<Demo>):
  Demo{g} = d
  +es = batch
  do IO<Loop.Step<Demo>>:
    +g1 : V.Gpu <- resized(A.resized(es, None{}), g)
    return decide(escape(es), A.exposed(es), g1)

def draw.sized(+g: V.Gpu, s: V.Size) -> IO(V.Gpu):
  V.Size{+w, +h} = s
  V.draw(g, scene(w, h), 236267263)

# Draws at the swapchain's size; asks for another frame while one is owed
# (a swapchain rebuilt during presentation).
def draw(win: A.Win, d: Demo) -> IO(Loop.Step<Demo>):
  Demo{+g} = d
  do IO<Loop.Step<Demo>>:
    +g1 : V.Gpu <- draw.sized(g, V.target_size(g))
    return decide(False{}, False{}, g1)

def finish(end: A.Win & Demo) -> IO(Unit):
  (win, d) = end
  Demo{+g} = d
  do IO<Unit>:
    IO.print("frames presented: " ++ U32.show(V.drawn(g)) ++ ", swapchain rebuilds: " ++
      U32.show(V.rebuilds(g)))
    +report : V.Report <- V.close(g)
    IO.print(V.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("window objects left: " ++ U32.show(left))

def main() -> IO(Unit):
  do IO<Unit>:
    +win : A.Win <- IO.try(A.Win, A.open(A.options("Voltra - quads", 800, 520)))
    +native : List<&2, U32> <- A.native(win)
    +g : V.Gpu <- V.open(native, 800, 520, True{})
    IO.print(V.describe(g))
    +g1 : V.Gpu <- V.upload(g, 64, 64, checker())
    end : A.Win & Demo <- Loop.run(~Demo, ~update, ~draw, win, Demo{g1})
    finish(end)
