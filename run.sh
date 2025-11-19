#!/bin/bash
env -u WAYLAND_DISPLAY zig build run"$@"
# env -u WAYLAND_DISPLAY ./zig-out/bin/zm"$@"
