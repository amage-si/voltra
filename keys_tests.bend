import Base
import ./keys.bend as K

# Native checks of keys.bend against a reference association list: random
# puts, replacements, lookups, misses and removals, edge keys (0, the high
# bit, all ones), ascending order, persistence of older versions and the
# depth of a map of atlas-style keys. Run with `--threads 2 --gpu off`.

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ message)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ message)

def same(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{a, ra} Con{b, rb}:
      U32.is_eq(a, b) && same(ra, rb)
    case _ _:
      False{}

def holds(m: Maybe<&2, U32>, +v: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      U32.is_eq(x, v)

def absent(m: Maybe<&2, U32>) -> Bool:
  Maybe.is_none(&2, U32, m)

# Reference: a list of (key, value) pairs without repeated keys.
type Binding is Data:
  Binding{key: U32, value: U32}

def ref.del.keep(drop: Bool, p: Binding, rest: List<&2, Binding>) -> List<&2, Binding>:
  match drop:
    case True{}:
      rest
    case False{}:
      p <> rest

def ref.del(xs: List<&2, Binding>, +k: U32) -> List<&2, Binding>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Binding{+j, v}, rest}:
      ref.del.keep(U32.is_eq(j, k), Binding{j, v}, ref.del(rest, k))

def ref.put(xs: List<&2, Binding>, +k: U32, +v: U32) -> List<&2, Binding>:
  Binding{k, v} <> ref.del(xs, k)

def ref.get.pick(hit: Bool, +v: U32, later: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      later

def ref.get(xs: List<&2, Binding>, +k: U32) -> Maybe<&2, U32>:
  match xs:
    case Nil{}:
      None{}
    case Con{Binding{+j, v}, rest}:
      ref.get.pick(U32.is_eq(j, k), v, ref.get(rest, k))

def ref.keys(xs: List<&2, Binding>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Binding{k, v}, rest}:
      k <> ref.keys(rest)

def le(a: U32, b: U32) -> Bool:
  U32.is_le(a, b)

def sorted(xs: List<&2, U32>) -> List<&2, U32>:
  List.sort(~U32, ~le, xs)

def eq_maybe(a: Maybe<&2, U32>, b: Maybe<&2, U32>) -> Bool:
  match a b:
    case None{} None{}:
      True{}
    case Some{x} Some{y}:
      U32.is_eq(x, y)
    case _ _:
      False{}

def next(+x: U32) -> U32:
  (x * 1664525 + 1013904223 : U32)

type Both is Data:
  Both{map: K.Keys<U32>, ref: List<&2, Binding>, ok: Bool}

# Random operations on both: put (half), remove (a quarter), lookup (a
# quarter, compared); keys masked to `mask` so they repeat.
def ops(n: Nat, +x: U32, +mask: U32, b: Both) -> Both:
  match n:
    case 0n:
      b
    case 1n+p:
      Both{+m, +r, +ok} = b
      +k = ((x >> 7n) .&. mask : U32)
      +op = (x .&. 3 : U32)
      +put = U32.is_lt(op, 2)
      +del = U32.is_eq(op, 2)
      +m1 = Bool.pick(K.Keys<U32>, put, K.put(U32, m, k, x), Bool.pick(K.Keys<U32>, del, K.del(U32, m, k), m))
      +r1 = Bool.pick(List<&2, Binding>, put, ref.put(r, k, x), Bool.pick(List<&2, Binding>, del, ref.del(r, k), r))
      ops(p, next(x), mask, Both{m1, r1, ok && eq_maybe(K.get(U32, m1, k), ref.get(r1, k))})

# Every reference binding is in the map.
def all_found(xs: List<&2, Binding>, +m: K.Keys<U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{Binding{+k, +v}, rest}:
      holds(K.get(U32, m, k), v) && all_found(rest, m)

def agree(b: Both) -> Bool:
  Both{+m, +r, ok} = b
  ok && all_found(r, m) && same(K.keys(U32, m), sorted(ref.keys(r))) &&
    U32.is_eq(K.size(U32, m), U32.from_nat(List.length(&2, Binding, r)))

def fill(n: Nat, +x: U32, m: K.Keys<U32>) -> K.Keys<U32>:
  match n:
    case 0n:
      m
    case 1n+p:
      fill(p, next(x), K.put(U32, m, x, (x + 1 : U32)))

def drain(ks: List<&2, U32>, m: K.Keys<U32>) -> K.Keys<U32>:
  match ks:
    case Nil{}:
      m
    case Con{k, rest}:
      drain(rest, K.del(U32, m, k))

def is_tip(m: K.Keys<U32>) -> Bool:
  match m:
    case K.Tip{}:
      True{}
    case _:
      False{}

def depth(m: K.Keys<U32>) -> U32:
  match m:
    case K.Tip{}:
      0
    case K.Leaf{k, v}:
      1
    case K.Fork{p, b, lo, hi}:
      (1 + U32.max(depth(lo), depth(hi)) : U32)

def glyph_keys(n: Nat, +s: U32, +g: U32, m: K.Keys<U32>) -> K.Keys<U32>:
  match n:
    case 0n:
      m
    case 1n+p:
      +k = (1073741824 + (s * 4 << 16n) + g * 7 : U32)
      glyph_keys(p, s, (g + 1 : U32), K.put(U32, m, k, g))

# Atlas-style keys: (glyph, size) as 2^30 + quarter pixels << 16 + glyph.
def atlas_keys(sizes: List<&2, U32>, +glyphs: U32, m: K.Keys<U32>) -> K.Keys<U32>:
  match sizes:
    case Nil{}:
      m
    case Con{+s, rest}:
      atlas_keys(rest, glyphs, glyph_keys(U32.to_nat(glyphs), s, 0, m))

def put_all(ks: List<&2, U32>, m: K.Keys<U32>) -> K.Keys<U32>:
  match ks:
    case Nil{}:
      m
    case Con{+k, rest}:
      put_all(rest, K.put(U32, m, k, (k .^. 1 : U32)))

def main() -> IO(Unit):
  +edges = {[4294967295, 0, 2147483648, 1, 2147483647, 65536, 65535, 3, 2] : List<&2, U32>}
  +em = put_all(edges, K.new(U32))
  +one = K.put(U32, K.new(U32), 42, 7)
  +big = fill(400n, 12345, K.new(U32))
  +mixed = ops(3000n, 99, 255, Both{K.new(U32), Nil{}, True{}})
  +wide = ops(3000n, 7, 4095, Both{K.new(U32), Nil{}, True{}})
  +atlas = atlas_keys([13, 16, 18, 19, 34], 90, K.new(U32))
  do IO<Unit>:
    check(absent(K.get(U32, K.new(U32), 5)) && U32.is_eq(K.size(U32, K.new(U32)), 0) &&
      same(K.keys(U32, K.new(U32)), []), "keys: the empty map has no keys")
    check(holds(K.get(U32, one, 42), 7) && absent(K.get(U32, one, 43)) && U32.is_eq(K.size(U32, one), 1),
      "keys: one key")
    check(holds(K.get(U32, K.put(U32, one, 42, 9), 42), 9) && U32.is_eq(K.size(U32, K.put(U32, one, 42, 9)), 1),
      "keys: putting a key again replaces its value")
    check(holds(K.get(U32, one, 42), 7) && absent(K.get(U32, K.del(U32, one, 42), 42)),
      "keys: older versions stay valid after put and del")
    check(same(K.keys(U32, em), [0, 1, 2, 3, 65535, 65536, 2147483647, 2147483648, 4294967295]),
      "keys: ascending unsigned order across the high bit")
    check(holds(K.get(U32, em, 4294967295), 4294967294) && holds(K.get(U32, em, 0), 1) &&
      holds(K.get(U32, em, 2147483648), 2147483649) && absent(K.get(U32, em, 4)) &&
      absent(K.get(U32, em, 2147483649)), "keys: edge keys and misses beside them")
    check(U32.is_eq(K.size(U32, big), 400) && holds(K.get(U32, big, 12345), 12346),
      "keys: 400 spread keys")
    check(is_tip(drain(K.keys(U32, big), big)), "keys: removing every key leaves the empty map")
    check(agree(mixed), "keys: 3000 random puts, removals and lookups agree with a reference (256 keys)")
    check(agree(wide), "keys: 3000 random puts, removals and lookups agree with a reference (4096 keys)")
    check(U32.is_eq(K.size(U32, atlas), 450) && holds(K.get(U32, atlas, (1073741824 + (34 * 4 << 16n) + 89 * 7 : U32)), 89) &&
      U32.is_le(depth(atlas), 14), "keys: 450 atlas-style keys stay shallow (depth " ++ U32.show(depth(atlas)) ++ ")")
    IO.print("11 key map checks passed")
