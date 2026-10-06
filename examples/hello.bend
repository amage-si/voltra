import Base
import ../gpu.bend as V
import ../quads.bend as Q

# The smallest Voltra program: one quad, shown for up to two seconds (or
# until an event arrives), then a clean teardown.

def main() -> IO(Unit):
  do IO<Unit>:
    +g : V.Gpu <- V.open("Hello", 640, 400, True{}, True{})
    +g1 : V.Gpu <- V.draw(g, [Q.fill(40, 40, 200, 120, 4282664191)], 255)
    +es : List<&2, V.Input> <- V.wait(g1, 2000)
    +report : V.Report <- V.close(g1)
    IO.print(V.report.show(report))
