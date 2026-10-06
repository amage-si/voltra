import Base

# Helpers for the flat U32 word lists and arrays that cross the bridge.

# The word at index n, or 0 past the end.
def at(xs: List<&2, U32>, n: Nat) -> U32:
  match xs n:
    case Nil{} _:
      0
    case Con{h, t} 0n:
      h
    case Con{h, t} 1n+p:
      at(t, p)

def drop(xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  match xs n:
    case ys 0n:
      ys
    case Nil{} 1n+p:
      Nil{}
    case Con{h, t} 1n+p:
      drop(t, p)

def take(xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  match xs n:
    case _ 0n:
      Nil{}
    case Nil{} 1n+p:
      Nil{}
    case Con{h, t} 1n+p:
      h <> take(t, p)

def count(xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

def contains(xs: List<&2, U32>, +x: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      U32.is_eq(h, x) || contains(t, x)

def show(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, Nil{}}:
      U32.show(h)
    case Con{h, t}:
      U32.show(h) ++ " " ++ show(t)

# Bend arrays hold a power of two of slots: the depth that fits n words.
def depth.pick(small: Bool, +n: U32) -> Nat:
  match small:
    case True{}:
      0n
    case False{}:
      1n+U32.log2((n - 1 : U32))

def depth(+n: U32) -> Nat:
  depth.pick(U32.is_le(n, 1), n)

def fill(xs: List<&2, U32>, a: Array<U32>, +i: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      a
    case Con{h, t}:
      fill(t, Array.set(U32, a, i, h), (i + 1 : U32))

# A list as an array (zero padded to a power of two) with its word count.
def to_array(+xs: List<&2, U32>) -> Array<U32> & U32:
  +n = count(xs)
  (fill(xs, Array.new(U32, depth(n), 0), 0), n)
