import Base
import ../quads.bend as Q
import ../words.bend as W
import ./scene.bend as Scene

# Writes the Chromi scene, rasterized exactly as Voltra uploads it, to a
# binary PPM (default build/reference-960x630.ppm). Comparing it with a
# capture of the GPU-presented window checks the whole path pixel by pixel.

# Emits pixel i (already read into r) and reads pixel i - 1, back to front.
def bytes(n: Nat, r: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      (a, +c) = r
      +j = (i - 1 : U32)
      bytes(p, Array.get(U32, a, j), j,
        (c >> 24n : U32) <> ((c >> 16n) .&. 255 : U32) <> ((c >> 8n) .&. 255 : U32) <> acc)

def header() -> String:
  "P6\n960 630\n255\n"

def write.done(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, ok) = r
  do IO<Unit>:
    File.close(f)
    IO.print("wrote build/reference-960x630.ppm")

def write.body(r: File & Result<&1, &1, U32 & String, Unit>, pixels: List<&2, U32>) -> IO(Unit):
  (f, ok) = r
  do IO<Unit>:
    r2 : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, pixels)
    write.done(r2)

def write(img: Image) -> IO(Unit):
  +pixels = bytes(604800n, Array.get(U32, Q.raster(img, Array.new(U32, W.depth(604800), 0),
    0, 0, 1024, 960, 630), 604799), 604799, [])
  do IO<Unit>:
    f : File <- IO.try(File, File.open("build/reference-960x630.ppm", "w"))
    r1 : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, header())
    write.body(r1, pixels)

def main() -> IO(Unit):
  do IO<Unit>:
    img : Image <- IO.pass(Image, Scene.draw(960, 630, 0))
    write(img)
