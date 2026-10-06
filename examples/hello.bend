import Base
import ../gpu.bend as V
import ../quads.bend as Q
import ../../Ankra/window.bend as A
import ../../Ankra/app.bend as Loop

# The smallest Voltra program: Ankra opens the window, Voltra draws one
# rounded quad into it, the window stays until two seconds pass without
# events (or it is closed), then the GPU objects go before the window.

def update(win: A.Win, events: List<&2, A.Input>, g: V.Gpu) -> IO(Loop.Step<V.Gpu>):
  match events:
    case Nil{}:
      IO.pure(Loop.Step<V.Gpu>, Loop.Stop{g})
    case _:
      IO.pure(Loop.Step<V.Gpu>, Loop.Redraw{g})

def draw(win: A.Win, gpu: V.Gpu) -> IO(Loop.Step<V.Gpu>):
  +g = gpu
  do IO<Loop.Step<V.Gpu>>:
    +g1 : V.Gpu <- V.draw(g, [Q.rounded(320, 320, 1920, 1280, 96, 4282664191)], 255)
    return Loop.Sleep{g1, 2000}

def finish(end: A.Win & V.Gpu) -> IO(Unit):
  (win, g) = end
  do IO<Unit>:
    +report : V.Report <- V.close(g)
    IO.print(V.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("window objects left: " ++ U32.show(left))

def main() -> IO(Unit):
  do IO<Unit>:
    +win : A.Win <- IO.try(A.Win, A.open(A.options("Hello", 640, 400)))
    +native : List<&2, U32> <- A.native(win)
    +g : V.Gpu <- V.open(native, 640, 400, True{})
    end : A.Win & V.Gpu <- Loop.run(~V.Gpu, ~update, ~draw, win, g)
    finish(end)
