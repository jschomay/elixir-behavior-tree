# Changelog

## 0.3.1

Fix bug with nested repeat_n bugs not repeating correctly

## 0.3.0

Add 3 new nodes:

- `negate`
- `always_succeed`
- `always_fail`

## 0.2.0

Switch to protocol-based implementation (allows for defining custom nodes), which changes the api for creating nodes.

Added additional node types:

- `repeat_until_succeed`
- `repeat_until_fail`
- `repeat_n`
- `random`
- `random_weighted`

See docs for full usage instructions, and protocol information.

## 0.1.0

Initial release

### Added
- Initial implementation including selector and sequence nodes
- Documentation
- CI integration
