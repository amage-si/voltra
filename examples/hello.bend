import Base
import ../gpu.bend as V
import ../quads.bend as Q
import ../../Ankra/window.bend as A

# The smallest Voltra program: Ankra opens the window, Voltra draws one
# quad into it, the program waits up to two seconds (or until an event
# arrives), then tears down the GPU objects before the window.

def main() -> IO(Unit):
  do IO<Unit>:
    +win : A.Win <- IO.try(A.Win, A.open(A.options("Hello", 640, 400)))
    +native : List<&2, U32> <- A.native(win)
    +g : V.Gpu <- V.open(native, 640, 400, True{})
    +g1 : V.Gpu <- V.draw(g, [Q.fill(40, 40, 200, 120, 4282664191)], 255)
    got : A.Win & List<&2, A.Input> <- A.wait(win, 2000)
    +report : V.Report <- V.close(g1)
    IO.print(V.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("window objects left: " ++ U32.show(left))
