#!/bin/bash
# Force X11/XWayland instead of native Wayland
env -u WAYLAND_DISPLAY ./zig-out/bin/zdse "$@"
