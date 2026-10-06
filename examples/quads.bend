import Base
import ../gpu.bend as V
import ../quads.bend as Q
import ../words.bend as W

# Colored and textured quads on the GPU. Resize the window: the layout
# follows the new size and the swapchain is rebuilt. Close it normally; the
# program then reports how many native objects outlived teardown (0).

def forever() -> U32:
  4294967295

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

def apply.size(m: Maybe<&2, V.Size>, +g: V.Gpu) -> IO(V.Gpu):
  match m:
    case None{}:
      IO.pure(V.Gpu, g)
    case Some{V.Size{w, h}}:
      V.resize(g, w, h)

def apply(+g: V.Gpu, +es: List<&2, V.Input>) -> IO(V.Gpu):
  do IO<V.Gpu>:
    +g1 : V.Gpu <- apply.size(V.resized(es, None{}), g)
    return Bool.pick(V.Gpu, V.exposed(es), V.invalidate(g1), g1)

def paint.sized(+g: V.Gpu, size: V.Size) -> IO(V.Gpu):
  V.Size{+w, +h} = size
  V.draw(g, scene(w, h), 236267263)

def paint(go: Bool, +g: V.Gpu) -> IO(V.Gpu):
  match go:
    case False{}:
      IO.pure(V.Gpu, g)
    case True{}:
      paint.sized(g, V.target_size(g))

def loop(n: Nat, stop: Bool, +g: V.Gpu) -> IO(V.Gpu):
  match n stop:
    case _ True{}:
      IO.pure(V.Gpu, g)
    case 0n _:
      IO.pure(V.Gpu, g)
    case 1n+p False{}:
      do IO<V.Gpu>:
        +g1 : V.Gpu <- paint(V.pending(g), g)
        +es : List<&2, V.Input> <- V.wait(g1, Bool.pick(U32, V.pending(g1), 0, forever()))
        +g2 : V.Gpu <- apply(g1, es)
        loop(p, V.closed(es), g2)

def main() -> IO(Unit):
  do IO<Unit>:
    +g : V.Gpu <- V.open("Voltra - quads", 800, 520, True{}, True{})
    IO.print(V.describe(g))
    +g1 : V.Gpu <- V.upload(g, 64, 64, checker())
    +g2 : V.Gpu <- loop(1000000n, False{}, g1)
    IO.print("frames presented: " ++ U32.show(V.drawn(g2)) ++ ", swapchain rebuilds: " ++
      U32.show(V.rebuilds(g2)))
    +report : V.Report <- V.close(g2)
    IO.print(V.report.show(report))
