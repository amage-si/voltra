import Base

# A texture atlas allocator: rectangles packed into shelves (rows), first
# fit, top to bottom. Pure bookkeeping -- the texels themselves travel with
# `update` in gpu.bend. Entries are found by a caller-chosen U32 key (a
# glyph at a size, an image), so content uploaded once is reused by every
# later frame. A full atlas refuses new entries; the caller then starts a
# fresh one (`reset`) and uploads what the current frame needs.

type Entry is Data:
  Entry{key: U32, x: U32, y: U32, width: U32, height: U32}

type Shelf is Data:
  Shelf{y: U32, height: U32, next: U32}

type Atlas is Data:
  Atlas{width: U32, height: U32, top: U32, shelves: List<&2, Shelf>,
    entries: List<&2, Entry>}

def new(+width: U32, +height: U32) -> Atlas:
  Atlas{width, height, 0, Nil{}, Nil{}}

def reset(a: Atlas) -> Atlas:
  Atlas{w, h, t, s, e} = a
  Atlas{w, h, 0, Nil{}, Nil{}}

def find(es: List<&2, Entry>, +key: U32) -> Maybe<&2, Entry>:
  match es:
    case Nil{}:
      None{}
    case Con{Entry{+k, x, y, w, h}, rest}:
      Bool.pick(Maybe<&2, Entry>, U32.is_eq(k, key), Some{Entry{k, x, y, w, h}}, find(rest, key))

def lookup(a: Atlas, +key: U32) -> Maybe<&2, Entry>:
  Atlas{w, h, t, s, entries} = a
  find(entries, key)

def count(a: Atlas) -> U32:
  Atlas{w, h, t, s, entries} = a
  U32.from_nat(List.length(&2, Entry, entries))

# A shelf fits a rectangle when it is tall enough, not more than twice as
# tall (so small glyphs do not waste tall rows), and has room to the right.
def fits(s: Shelf, +w: U32, +h: U32, +width: U32) -> Bool:
  Shelf{y, +sh, +next} = s
  U32.is_le(h, sh) && U32.is_le(sh, (h * 2 : U32)) && U32.is_le((next + w : U32), width)

type Placed is Data:
  Placed{shelves: List<&2, Shelf>, x: U32, y: U32, found: Bool}

def shelf.join(ok: Bool, s: Shelf, rest: List<&2, Shelf>, later: Placed, +w: U32) -> Placed:
  match ok:
    case True{}:
      Shelf{+y, sh, +next} = s
      Placed{Shelf{y, sh, (next + w : U32)} <> rest, next, y, True{}}
    case False{}:
      Placed{shelves, x, y, found} = later
      Placed{s <> shelves, x, y, found}

def shelf.first(ss: List<&2, Shelf>, +w: U32, +h: U32, +width: U32) -> Placed:
  match ss:
    case Nil{}:
      Placed{Nil{}, 0, 0, False{}}
    case Con{s, rest}:
      +sh = s
      +r = rest
      shelf.join(fits(sh, w, h, width), sh, r, shelf.first(r, w, h, width), w)

def place.new(room: Bool, +width: U32, +height: U32, +top: U32, ss: List<&2, Shelf>,
  es: List<&2, Entry>, +key: U32, +w: U32, +h: U32) -> Atlas & Maybe<&2, Entry>:
  match room:
    case True{}:
      +e = {Entry{key, 0, top, w, h} : Entry}
      (Atlas{width, height, (top + h : U32), List.append(&2, Shelf, ss, [Shelf{top, h, w}]),
        e <> es}, Some{e})
    case False{}:
      (Atlas{width, height, top, ss, es}, None{})

def place.found(p: Placed, +width: U32, +height: U32, +top: U32, es: List<&2, Entry>,
  +key: U32, +w: U32, +h: U32) -> Atlas & Maybe<&2, Entry>:
  match p:
    case Placed{ss, +x, +y, True{}}:
      +e = {Entry{key, x, y, w, h} : Entry}
      (Atlas{width, height, top, ss, e <> es}, Some{e})
    case Placed{ss, x, y, False{}}:
      place.new(U32.is_le((top + h : U32), height) && U32.is_le(w, width) && U32.is_gt(w, 0)
        && U32.is_gt(h, 0), width, height, top, ss, es, key, w, h)

# Reserves a w x h rectangle for `key`: on an existing shelf when one fits,
# else on a new shelf below the others. None when the atlas is full.
def place(a: Atlas, +key: U32, +w: U32, +h: U32) -> Atlas & Maybe<&2, Entry>:
  Atlas{+width, +height, +top, ss, es} = a
  place.found(shelf.first(ss, w, h, width), width, height, top, es, key, w, h)
