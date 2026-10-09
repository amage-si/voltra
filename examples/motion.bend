import Base
import ../gpu.bend as V
import ../quads.bend as Q
import ../../Ankra/window.bend as A
import ../../Ankra/app.bend as Loop

# A rect slides across the window for 2 s at a constant speed, then the
# program goes idle: 0 frames and 0 wakeups until the next event. Space
# or a click slides it again; Escape or closing the window ends it.
#
# While it moves, `draw` answers `Loop.animate`, so Ankra's loop draws one
# frame per refresh of the window's monitor, and the position is computed
# at `A.frame_time(win)`, the frame's grid time, not at the moment the
# loop woke. The last frame lands exactly on the end position and answers
# Keep, which ends the animation.
#
# Arguments (for measurement): `fifo` draws back to back instead (Redraw
# from every frame, throttled only by the swapchain), the strategy the
# loop's grid replaced; `log` prints every frame's time at exit.

def duration() -> U32:
  2000

def distance() -> U32:
  520

def background() -> U32:
  589505535

type Demo is Data:
  Demo{gpu: V.Gpu, start: U32, moving: Bool, fifo: Bool, logging: Bool,
    times: List<&2, U32>, refresh: U32}

def rect(+x: U32) -> Q.Quad:
  Q.rounded((x * 8 : U32), 1120, ((x + 120) * 8 : U32), 2080, 128, 4282664191)

# Linear position at `elapsed` ms, held at the end.
def position(+elapsed: U32) -> U32:
  (40 + (U32.min(elapsed, duration()) * distance() / duration() : U32) : U32)

def escape(es: List<&2, A.Input>) -> Bool:
  match es:
    case Nil{}:
      False{}
    case Con{A.KeyDown{27, r, m}, rest}:
      True{}
    case Con{e, rest}:
      escape(rest)

def again(es: List<&2, A.Input>) -> Bool:
  match es:
    case Nil{}:
      False{}
    case Con{A.KeyDown{32, False{}, m}, rest}:
      True{}
    case Con{A.PointerDown{x, y, 0, m}, rest}:
      True{}
    case Con{e, rest}:
      again(rest)

def resized(m: Maybe<&2, A.Size>, +g: V.Gpu) -> IO(V.Gpu):
  match m:
    case None{}:
      IO.pure(V.Gpu, g)
    case Some{A.Size{w, h}}:
      V.resize(g, w, h)

def moved(es: List<&2, A.Input>) -> Bool:
  match es:
    case Nil{}:
      False{}
    case Con{A.Moved{x, y}, rest}:
      True{}
    case Con{e, rest}:
      moved(rest)

def coordinate(+v: F32) -> String:
  Bool.pick(String, F32.is_lt(v, 0.0), "-" ++ U32.show(F32.to_u32(F32.neg(v))), U32.show(F32.to_u32(v)))

# Prints the monitor's refresh when it changes, and on every move (the
# window may have reached another monitor).
def announce(changed: Bool, +win: A.Win) -> IO(Unit):
  match changed:
    case True{}:
      IO.print("at " ++ coordinate(A.position_x(win)) ++ "," ++ coordinate(A.position_y(win)) ++
        ": refresh " ++ U32.show(A.refresh(win)) ++ " mHz")
    case False{}:
      IO.pure(Unit, Unit{})

def decide(+stop: Bool, +restart: Bool, +stale: Bool, d: Demo) -> Loop.Step<Demo>:
  Demo{+g, +start, +moving, +fifo, +lg, +ts, +hz} = d
  Bool.pick(Loop.Step<Demo>, stop, Loop.Stop{Demo{g, start, moving, fifo, lg, ts, hz}},
    Bool.pick(Loop.Step<Demo>, restart, Loop.animate(Demo, Demo{g, 0, True{}, fifo, lg, ts, hz}),
      Bool.pick(Loop.Step<Demo>, stale || V.pending(g), Loop.Redraw{Demo{g, start, moving, fifo, lg, ts, hz}},
        Loop.Keep{Demo{g, start, moving, fifo, lg, ts, hz}})))

def update.go(+win: A.Win, batch: List<&2, A.Input>, d: Demo) -> IO(Loop.Step<Demo>):
  Demo{+g, +start, +moving, +fifo, +lg, ts, +hz} = d
  +es = batch
  +rate = A.refresh(win)
  do IO<Loop.Step<Demo>>:
    announce(U32.is_ne(rate, hz) || moved(es), win)
    +g1 : V.Gpu <- resized(A.resized(es, None{}), g)
    return decide(escape(es), again(es), A.exposed(es),
      Demo{g1, start, moving, fifo, lg, ts, rate})

def update(win: A.Win, batch: List<&2, A.Input>, d: Demo) -> IO(Loop.Step<Demo>):
  update.go(win, batch, d)

# The answer after a frame: animate (or, in fifo mode, Redraw) while the
# rect moves; Keep once it rests, unless the swapchain still owes a frame.
def next(+moving: Bool, +fifo: Bool, +d: Demo) -> Loop.Step<Demo>:
  Demo{+g, s, m, f, l, ts, r} = d
  Bool.pick(Loop.Step<Demo>, moving && Bool.not(fifo), Loop.animate(Demo, d),
    Bool.pick(Loop.Step<Demo>, moving || V.pending(g), Loop.Redraw{d}, Loop.Keep{d}))

def finished(was: Bool, +now: Bool, +frames: U32) -> IO(Unit):
  match was:
    case True{}:
      match now:
        case True{}:
          IO.pure(Unit, Unit{})
        case False{}:
          IO.print("rest after " ++ U32.show(frames) ++ " frames presented")
    case False{}:
      IO.pure(Unit, Unit{})

def drawn(+g: V.Gpu, +start: U32, +was: Bool, +fifo: Bool, +lg: Bool, +ts: List<&2, U32>,
  +hz: U32, +t: U32) -> IO(Loop.Step<Demo>):
  +elapsed = (t - start : U32)
  +moving = U32.is_lt(elapsed, duration())
  do IO<Loop.Step<Demo>>:
    +g1 : V.Gpu <- V.draw(g, [rect(position(elapsed))], background())
    finished(was, moving, V.drawn(g1))
    return next(moving, fifo, Demo{g1, start, moving, fifo, lg,
      Bool.pick(List<&2, U32>, lg, t <> ts, ts), hz})

# Draws at the frame time; the first frame of a slide starts its clock.
def draw(win: A.Win, d: Demo) -> IO(Loop.Step<Demo>):
  Demo{+g, +start, +moving, +fifo, +lg, ts, +hz} = d
  +t = A.frame_time(win)
  drawn(g, Bool.pick(U32, U32.is_eq(start, 0), t, start), moving, fifo, lg, ts, hz, t)

def show(xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}:
      acc
    case Con{x, rest}:
      show(rest, U32.show(x) ++ " " ++ acc)

def logged(on: Bool, ts: List<&2, U32>) -> IO(Unit):
  match on:
    case True{}:
      IO.print("frame times " ++ show(ts, ""))
    case False{}:
      IO.pure(Unit, Unit{})

def finish(end: A.Win & Demo) -> IO(Unit):
  (win, d) = end
  Demo{+g, s, m, f, +lg, ts, r} = d
  do IO<Unit>:
    IO.print("frames presented: " ++ U32.show(V.drawn(g)))
    logged(lg, ts)
    +report : V.Report <- V.close(g)
    IO.print(V.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("window objects left: " ++ U32.show(left))

# The initial state; the arguments `fifo` and `log` set those modes.
def initial(xs: List<String>, +g: V.Gpu, +fifo: Bool, +lg: Bool, +hz: U32) -> Demo:
  match xs:
    case Nil{}:
      Demo{g, 0, True{}, fifo, lg, Nil{}, hz}
    case Con{+x, rest}:
      initial(rest, g, fifo || String.eq(x, "fifo"), lg || String.eq(x, "log"), hz)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +win : A.Win <- IO.try(A.Win, A.open(A.options("Voltra - motion", 720, 400)))
    +native : List<&2, U32> <- A.native(win)
    +g : V.Gpu <- V.open(native, 720, 400, True{})
    IO.print("refresh " ++ U32.show(A.refresh(win)) ++ " mHz")
    end : A.Win & Demo <- Loop.run(~Demo, ~update, ~draw, win,
      initial(args, g, False{}, False{}, A.refresh(win)))
    finish(end)
