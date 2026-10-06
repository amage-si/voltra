import Base
import ../../Chromi/main.bend as C
import ../../Chromi/geometry.bend as G

# The shape scene from Chromi's examples/shapes.bend, drawn by Chromi on the
# CPU at any physical size: logical 640x420 geometry scaled to fit w x h.

def f32(+n: U32) -> F32:
  F32.from_nat(U32.to_nat(n))

def fit(+w: U32, +h: U32) -> F32:
  F32.max(0.0625, F32.min((f32(w) / 640.0 : F32), (f32(h) / 420.0 : F32)))

def draw(+w: U32, +h: U32, +counter: U32) -> Result<&1, &1, U32 & String, Image>:
  +accent = Bool.pick(U32, U32.is_eq((counter % 2 : U32), 0), 1089715967, 4288766719)
  c = C.new(w, h, fit(w, h), 219422463)
  c = C.fill_rect(c, G.Rect{24.0, 24.0, 592.0, 372.0}, 354033919)
  c = C.fill_rect(c, G.Rect{48.0, 50.0, 120.0, 6.0}, accent)
  c = C.fill_rect(c, G.Rect{48.0, 86.0, 250.0, 122.0}, 555886591)
  c = C.stroke_rect(c, G.Rect{48.0, 86.0, 250.0, 122.0}, 2.0, 1078740735)
  c = C.circle(c, 133.0, 146.0, 38.0, accent)
  c = C.circle(c, 181.0, 146.0, 38.0, 4284311936)
  c = C.clip_rect(c, G.Rect{328.0, 86.0, 264.0, 122.0})
  c = C.fill_rect(c, G.Rect{328.0, 86.0, 264.0, 122.0}, 270611711)
  c = C.circle(c, 378.0, 146.0, 75.0, 1759685375)
  c = C.circle(c, 524.0, 146.0, 75.0, 1089715967)
  c = C.reset_clip(c)
  c = C.fill_rect(c, G.Rect{48.0, 246.0, 544.0, 126.0}, 270611711)
  c = C.fill_rect(c, G.Rect{68.0, 266.0, 504.0, 6.0}, accent)
  c = C.fill_rect(c, G.Rect{68.0, 290.0, 328.0, 6.0}, 943805439)
  c = C.fill_rect(c, G.Rect{68.0, 314.0, 224.0, 6.0}, 943805439)
  c = C.fill_rect(c, G.Rect{68.0, 338.0, 404.0, 6.0}, 943805439)
  C.finish(c)
