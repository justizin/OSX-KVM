#!/usr/bin/env python3
"""Drive the OSX-KVM macOS VM through QEMU's QMP socket.

HMP's `mouse_move` only emits *relative* events, which a `usb-tablet`
(absolute) pointer ignores -- so clicking is impossible over HMP. QMP's
`input-send-event` takes absolute axes, which is what this uses.

Usage:
    vmctl.py shot out.png            # screendump -> png
    vmctl.py click X Y               # click at framebuffer pixel X,Y
    vmctl.py dclick X Y              # double click
    vmctl.py move X Y
    vmctl.py key KEY [KEY ...]       # e.g. key ret / key down down ret
    vmctl.py type "some text"

Selecting which VM (they each get their own socket):
    VM=mojave vmctl.py shot /tmp/s.png
    QMP_SOCK=/run/user/1000/osx-mojave-qmp.sock vmctl.py click 100 200
"""
import json
import os
import socket
import subprocess
import sys
import time

def _default_sock():
    """QMP socket path. Override with VM=<version> or QMP_SOCK=<path>."""
    if os.environ.get("QMP_SOCK"):
        return os.environ["QMP_SOCK"]
    run = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    vm = os.environ.get("VM")
    if vm:
        return f"{run}/osx-{vm}-qmp.sock"
    return f"{run}/osx-kvm-qmp.sock"      # legacy single-VM default


SOCK = _default_sock()
ABS_MAX = 32767


class QMP:
    def __init__(self, path=SOCK):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.settimeout(20)
        self.s.connect(path)
        self.f = self.s.makefile("rwb")
        self._read()                      # greeting
        self.cmd("qmp_capabilities")

    def _read(self):
        while True:
            line = self.f.readline()
            if not line:
                raise RuntimeError("QMP closed")
            msg = json.loads(line)
            if "event" in msg:            # skip async events
                continue
            return msg

    def cmd(self, execute, **args):
        payload = {"execute": execute}
        if args:
            payload["arguments"] = args
        self.f.write((json.dumps(payload) + "\n").encode())
        self.f.flush()
        msg = self._read()
        if "error" in msg:
            raise RuntimeError(f"{execute}: {msg['error']}")
        return msg.get("return")

    def send_events(self, events):
        self.cmd("input-send-event", events=events)

    def fb_size(self):
        """Framebuffer size, read back from a throwaway PPM header."""
        tmp = "/tmp/.vmctl-probe.ppm"
        self.cmd("screendump", filename=tmp)
        with open(tmp, "rb") as fh:
            assert fh.readline().strip() == b"P6"
            w, h = map(int, fh.readline().split())
        os.unlink(tmp)
        return w, h

    def _abs(self, x, y):
        w, h = self.fb_size()
        return [
            {"type": "abs", "data": {"axis": "x",
                                     "value": int(x * ABS_MAX / w)}},
            {"type": "abs", "data": {"axis": "y",
                                     "value": int(y * ABS_MAX / h)}},
        ]

    def move(self, x, y):
        self.send_events(self._abs(x, y))

    def click(self, x, y, count=1):
        self.move(x, y)
        time.sleep(0.4)
        for _ in range(count):
            self.send_events([{"type": "btn",
                               "data": {"down": True, "button": "left"}}])
            time.sleep(0.06)
            self.send_events([{"type": "btn",
                               "data": {"down": False, "button": "left"}}])
            time.sleep(0.12)

    def key(self, *keys):
        for k in keys:
            self.send_events([{"type": "key", "data": {"down": True,
                              "key": {"type": "qcode", "data": k}}}])
            time.sleep(0.04)
            self.send_events([{"type": "key", "data": {"down": False,
                              "key": {"type": "qcode", "data": k}}}])
            time.sleep(0.12)

    def chord(self, *keys):
        """Press keys together, release in reverse (e.g. chord meta_l q)."""
        ev = [{"type": "key", "data": {"down": True,
               "key": {"type": "qcode", "data": k}}} for k in keys]
        ev += [{"type": "key", "data": {"down": False,
                "key": {"type": "qcode", "data": k}}} for k in reversed(keys)]
        self.send_events(ev)
        time.sleep(0.2)

    def type_text(self, text):
        shifted = {"!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
                   "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
                   "_": "minus", "+": "equal", "?": "slash", ":": "semicolon",
                   '"': "apostrophe", "<": "comma", ">": "dot", "~": "grave"}
        plain = {" ": "spc", "-": "minus", "=": "equal", ".": "dot",
                 ",": "comma", "/": "slash", ";": "semicolon",
                 "'": "apostrophe", "`": "grave"}
        for ch in text:
            if ch.isalpha():
                self._maybe_shift(ch.lower(), ch.isupper())
            elif ch.isdigit():
                self.key(ch)
            elif ch in shifted:
                self._maybe_shift(shifted[ch], True)
            elif ch in plain:
                self.key(plain[ch])
            else:
                raise ValueError(f"unmapped char {ch!r}")

    def _maybe_shift(self, qcode, shift):
        ev = []
        if shift:
            ev.append({"type": "key", "data": {"down": True,
                       "key": {"type": "qcode", "data": "shift"}}})
        ev.append({"type": "key", "data": {"down": True,
                   "key": {"type": "qcode", "data": qcode}}})
        ev.append({"type": "key", "data": {"down": False,
                   "key": {"type": "qcode", "data": qcode}}})
        if shift:
            ev.append({"type": "key", "data": {"down": False,
                       "key": {"type": "qcode", "data": "shift"}}})
        self.send_events(ev)
        time.sleep(0.08)

    def shot(self, png):
        ppm = png.rsplit(".", 1)[0] + ".ppm"
        self.cmd("screendump", filename=ppm)
        subprocess.run(["magick", ppm, png], check=True)
        os.unlink(ppm)
        return png


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    q = QMP()
    op, rest = sys.argv[1], sys.argv[2:]
    if op == "shot":
        print(q.shot(rest[0]))
    elif op == "click":
        q.click(int(rest[0]), int(rest[1]))
    elif op == "dclick":
        q.click(int(rest[0]), int(rest[1]), count=2)
    elif op == "move":
        q.move(int(rest[0]), int(rest[1]))
    elif op == "key":
        q.key(*rest)
    elif op == "chord":
        q.chord(*rest)
    elif op == "type":
        q.type_text(rest[0])
    elif op == "size":
        print(q.fb_size())
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
