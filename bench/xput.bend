import Base
import ../examples/scene.bend as Scene
import ./cpu.bend as Cpu

# Baseline: the official Bend Window (CPU quadtree fill + XPutImage, paced
# by the runtime at 60 Hz) presenting the Chromi scene at 960x630 for 600
# frames. Pair with bench/gpu.bend; run both under `time` (see docs/bench.md).

def frames(n: Nat, r: Window & Image & List<Event>) -> IO(Unit):
  match n:
    case 0n:
      (w, rest) = r
      Window.close(w)
    case 1n+p:
      (w, rest) = r
      (img, evs) = rest
      do IO<Unit>:
        next : Window & Image & List<Event> <- Window.frame(w, img)
        frames(p, next)

def run(+t0: Nat, img: Image) -> IO(Unit):
  do IO<Unit>:
    w : Window <- IO.try(Window, Window.open("Voltra bench - XPutImage", 960, 630))
    +c1 : U32 <- Cpu.ticks()
    +t1 : Nat <- IO.now()
    first : Window & Image & List<Event> <- Window.frame(w, img)
    frames(599n, first)
    +t2 : Nat <- IO.now()
    +c2 : U32 <- Cpu.ticks()
    IO.print("xput: 600 frames in " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms, " ++
      U32.show((c2 - c1 : U32)) ++ " CPU ticks, " ++ Cpu.per_frame((c2 - c1 : U32), 600))

def main() -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    img : Image <- IO.pass(Image, Scene.draw(960, 630, 0))
    run(t0, img)
