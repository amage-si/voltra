import Base

# CPU time of this process (all threads, user + system) in clock ticks
# (1/100 s here), read from /proc/self/stat. Benchmarks only: assumes the
# executable name has no spaces, so utime and stime are fields 14 and 15.

def fold(s: String, +spaces: U32, +user: U32, +system: U32) -> U32:
  match s:
    case SNil{}:
      (user + system : U32)
    case SCon{c, rest}:
      +k = Char.to_u32(c)
      +space = U32.is_eq(k, 32)
      +digit = (k - 48 : U32)
      fold(rest, Bool.pick(U32, space, (spaces + 1 : U32), spaces),
        Bool.pick(U32, U32.is_eq(spaces, 13) && Bool.not(space), (user * 10 + digit : U32), user),
        Bool.pick(U32, U32.is_eq(spaces, 14) && Bool.not(space), (system * 10 + digit : U32), system))

def read(r: File & Result<&1, &1, U32 & String, String>) -> IO(U32):
  (f, text) = r
  do IO<U32>:
    File.close(f)
    s : String <- IO.pass(String, text)
    return fold(s, 0, 0, 0)

def ticks() -> IO(U32):
  do IO<U32>:
    f : File <- IO.try(File, File.open("/proc/self/stat", "r"))
    r : File & Result<&1, &1, U32 & String, String> <- File.read(f, 4096)
    read(r)

def per_frame(+ticks: U32, +frames: U32) -> String:
  # ticks are 10 ms; report microseconds per frame
  U32.show((ticks * 10000 / U32.max(frames, 1) : U32)) ++ " us CPU/frame"
