import Base
import ../gpu.bend as V
import ../quads.bend as Q
import ../words.bend as W
import ../examples/scene.bend as Scene
import ./cpu.bend as Cpu

# Voltra presenting the same Chromi scene at 960x630 for 600 frames.
# Arguments pick what each frame does:
#   (none)   static content: the texture is uploaded once, frames only draw;
#   upload   content changes every frame: raster + upload + draw;
#   leaves   quadtree leaves as quads, rebuilt every frame, no texture;
#   novsync  present with IMMEDIATE (or MAILBOX) instead of FIFO.

type Opts is Data:
  Opts{mode: U32, vsync: Bool}

def opts(args: List<String>, +mode: U32, +vsync: Bool) -> Opts:
  match args:
    case Nil{}:
      Opts{mode, vsync}
    case Con{a, rest}:
      +w = a
      opts(rest, Bool.pick(U32, String.eq(w, "upload"), 1,
        Bool.pick(U32, String.eq(w, "leaves"), 2, mode)),
        vsync && Bool.not(String.eq(w, "novsync")))

def raster(+img: Image) -> Array<U32>:
  Q.raster(img, Array.new(U32, W.depth(604800), 0), 0, 0, 1024, 960, 630)

def content(leaves: Bool, +img: Image) -> List<&2, Q.Quad>:
  match leaves:
    case True{}:
      Q.leaves(img, 0, 0, 1024, 960, 630, [])
    case False{}:
      [Q.image(0, 0, 960, 630, 0, 0, 960, 630, 4294967295)]

def one(upload: Bool, +mode: U32, +g: V.Gpu, +img: Image) -> IO(V.Gpu):
  match upload:
    case True{}:
      do IO<V.Gpu>:
        +g1 : V.Gpu <- V.upload(g, 960, 630, raster(img))
        V.draw(g1, [Q.image(0, 0, 960, 630, 0, 0, 960, 630, 4294967295)], 255)
    case False{}:
      V.draw(V.invalidate(g), content(U32.is_eq(mode, 2), img), 255)

def frames(n: Nat, +mode: U32, +g: V.Gpu, +img: Image) -> IO(V.Gpu):
  match n:
    case 0n:
      IO.pure(V.Gpu, g)
    case 1n+p:
      do IO<V.Gpu>:
        +g1 : V.Gpu <- one(U32.is_eq(mode, 1), mode, g, img)
        +es : List<&2, V.Input> <- V.wait(g1, 0)
        frames(p, mode, g1, img)

def run(+mode: U32, +vsync: Bool, img: Image) -> IO(Unit):
  +im = img
  do IO<Unit>:
    +g : V.Gpu <- V.open("Voltra bench - GPU", 960, 630, vsync, False{})
    IO.print(V.describe(g))
    +g1 : V.Gpu <- V.upload(g, 960, 630, raster(im))
    +c1 : U32 <- Cpu.ticks()
    +t1 : Nat <- IO.now()
    +g2 : V.Gpu <- frames(600n, mode, g1, im)
    +t2 : Nat <- IO.now()
    +c2 : U32 <- Cpu.ticks()
    IO.print("gpu mode " ++ U32.show(mode) ++ ": " ++ U32.show(V.drawn(g2)) ++
      " frames presented in " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms, " ++
      U32.show((c2 - c1 : U32)) ++ " CPU ticks, " ++ Cpu.per_frame((c2 - c1 : U32), 600))
    +report : V.Report <- V.close(g2)
    IO.print(V.report.show(report))

def run.opts(o: Opts, img: Image) -> IO(Unit):
  Opts{mode, vsync} = o
  run(mode, vsync, img)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    img : Image <- IO.pass(Image, Scene.draw(960, 630, 0))
    run.opts(opts(args, 0, True{}), img)
