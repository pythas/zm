# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Enemy drone system with stateful AI (Idle/Combat modes).
- `smart_core` high-tech modular ship part
- AI combat: Reactors-first targeting priority and raycast-based hit detection.
- Tile damage system: Lasers can now damage and destroy ship components and terrain.
- Visual effects for Laser Beams with fading color support.
- Railgun weapon system with raycast-based firing.
- Health system for terrain tiles, allowing destruction.
- Physics impulse on hit objects, causing them to react to railgun impacts.
- Visual effects for railgun shots.
- UI: Labeled panels in the ship management screen.
- Action bar and action switching.
- Starry background renderer.
- UI: Context menu support.
- Visual laser range indication and target tile highlighting.

### Changed

- Added context menu in ship management for handling tile interactions.
- Tools are no longer toggled and welding is triggered via the tile menu.
