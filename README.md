# Swift-Djot
- Swift wrapper for [djot](https://github.com/jgm/djot) provisional C library interface

## Status: Alpha
- Includes djot and [Lua](https://www.lua.org/license.html)
- Copyright authors, All Rights Reserved
- Same MIT license as djot and Lua

## Usage
- See e.g., [DjotTest](Tests/SwiftDjotTests/DjotTest.swift#L25)

## Development
- Swift: `swift-format -i --recursive .` (per [swift-format](./.swift-format))
- C: jdot/clib is manually adapted for building on macOS by SwiftPM
