#!/usr/bin/env python3
"""Checks native/voltra.c's Vulkan declarations against the Khronos headers.

The bridge declares the Vulkan structs it uses instead of including
<vulkan/vulkan.h>, so Bend builds need no Vulkan SDK. This script compiles
two small programs that print sizeof and offsetof for every declared struct
and field -- one with the bridge's declarations, one with the official
headers -- and fails on any difference.

Usage: python3 native/abi_check.py [VULKAN_INCLUDE_DIR]
The directory must contain vulkan/vulkan.h (Vulkan-Headers 1.3 or newer);
it defaults to $VULKAN_INCLUDE, then /usr/include. Needs clang and Xlib headers.
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
START = "// Vulkan declarations"
END = "// The Vulkan entry points"
# Fields that exist only in the bridge's shortened declarations.
PRIVATE_FIELDS = {"tail"}
# Partial declarations: only their leading fields are compared.
PARTIAL = {"VkDebugUtilsMessengerCallbackDataEXT"}
# Same size, different member layout (a union of arrays).
SIZE_ONLY = {"VkClearValue"}


def declarations():
    text = open(os.path.join(HERE, "voltra.c")).read()
    return text[text.index(START):text.index(END)]


def structs(block):
    found = []
    pattern = re.compile(r"typedef (struct|union) \{(.*?)\}\s*([^;]+);", re.S)
    for kind, body, names in pattern.findall(block):
        fields = []
        for decl in body.split(";"):
            decl = re.sub(r"//.*", "", decl).strip()
            if not decl:
                continue
            # "type a, b[4]" -> a, b ; skips the type words
            parts = decl.split(",")
            first = re.findall(r"[A-Za-z_]\w*(?:\[\w+\])?$", parts[0].strip())
            names_here = first + [p.strip() for p in parts[1:]]
            for n in names_here:
                fields.append(re.sub(r"\[.*\]", "", n.replace("*", "").strip()))
        for name in [n.strip() for n in names.split(",")]:
            found.append((name, [f for f in fields if f not in PRIVATE_FIELDS]))
    return found


def program(prelude, entries):
    lines = [prelude, "int main(void) {"]
    for name, fields in entries:
        lines.append(f'  printf("{name} size %zu\\n", sizeof({name}));')
        if name in SIZE_ONLY:
            continue
        for f in fields:
            lines.append(
                f'  printf("{name}.{f} %zu\\n", offsetof({name}, {f}));')
    lines.append("  return 0;\n}")
    return "\n".join(lines)


def run(source, include):
    with tempfile.TemporaryDirectory() as tmp:
        c = os.path.join(tmp, "abi.c")
        exe = os.path.join(tmp, "abi")
        open(c, "w").write(source)
        cmd = ["clang", "-std=c11", c, "-o", exe]
        if include:
            cmd[1:1] = ["-idirafter", include]
        subprocess.run(cmd, check=True)
        return subprocess.run([exe], check=True, capture_output=True,
            text=True).stdout.splitlines()


def main():
    include = (sys.argv[1] if len(sys.argv) > 1
               else os.environ.get("VULKAN_INCLUDE", "/usr/include"))
    if not os.path.exists(os.path.join(include, "vulkan", "vulkan.h")):
        sys.exit(f"abi_check: no vulkan/vulkan.h under {include}")
    block = declarations()
    entries = structs(block)
    common = "#include <stddef.h>\n#include <stdint.h>\n#include <stdio.h>\n"
    common += "#include <X11/Xlib.h>\n"
    ours = run(program(common + block, entries), None)
    official_entries = [(n, f) for n, f in entries]
    official = run(program(common + "#define VK_USE_PLATFORM_XLIB_KHR 1\n"
        "#include <vulkan/vulkan.h>\n", official_entries), include)
    bad = [(a, b) for a, b in zip(ours, official) if a != b]
    for name in PARTIAL:
        bad = [(a, b) for a, b in bad if not a.startswith(name + " size")]
    for a, b in bad:
        print(f"MISMATCH bridge '{a}' vs official '{b}'")
    checked = len(ours) - sum(1 for n in PARTIAL)
    print(f"abi_check: {len(entries)} structs, {checked} sizes/offsets "
          f"compared against {include}: "
          + ("OK" if not bad else f"{len(bad)} mismatches"))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
