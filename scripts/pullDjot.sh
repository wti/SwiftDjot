#!/usr/bin/env bash
# Horrible script to copy and fix up djot sources

checkout() {
  logEntry
  [ -d "$checkout" ] && return 2
  mkdir "$checkout"
  cd "$checkout"
  git clone "https://github.com/jgm/djot.git"
}

buildDjotClib() {
  logEntry
  cd "$checkout"  || return 12
  cd djot/clib
  if [ "Darwin" == "$(uname)" ]; then
    export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    make LUA_USE_MACOSX=1
  else
    make
  fi
}

copyAndFix() {
  logEntry
  [ -d "$checkout" ] || return 3
  [ -d "$copy" ] && return 2
  mkdir "$copy"
  cd "$copy"
  
  # copy from built checkout
  cp -r "$checkout/djot/clib/"* .
  mv lua-src/* .
  
  # omit files we don't use
  rm -rf lua-src
  rm -f main.c tests.c tests djot
  rm -f *.o
  rm README.md Makefile
  
  # fix others to satisfy swiftpm defaults
  cafSed lua.c '^int main' 'int mainLUA' || return $?
  cafSed luac.c '^int main' 'int mainLUAC' || return $?
  cafSed djot.h '<lua.h>' '\"lua.h\"' || return $?
  cafSed djot.c '<lua.h>' '\"lua.h\"' || return $?
  cafSed djot.c '<lauxlib.h>' '\"lauxlib.h\"'
  cafSed djot.c '<lualib.h>' '\"lualib.h\"'
  cafSed djot.c '<djot.h>' '\"djot.h\"'
  cafFixLuaHeader
  cafFixLuaConfHeader
  
  # add our files
  cafEmitDemoHeader > djot_demo.h
  cafEmitDemo > djot_demo.c
  cafEmitModulemap > module.modulemap

  # dup public headers for swiftpm
  mkdir include
  cp lua.h djot.h luaconf.h djot_demo.h include
}

cafEmitModulemap() {
  cat <<'EOF'
framework module Cdjot {
    header "djot.h"
    private header "djot.h"
}
EOF
}

cafEmitDemoHeader() {
  cat <<'EOF'
#ifndef DJOT_DEMO_H
#define DJOT_DEMO_H
#include <stdio.h>
#include "djot.h"

/* return 0 if able to parse and print to html. */
int djot_demo();


#endif
EOF
}

cafEmitDemo() {
  cat <<'EOF'
#include "djot_demo.h"

/* return 0 if able to parse and print to html. */
int djot_demo() {
  lua_State *me = djot_open();
  if (me == NULL) {
    return 1;
  }
  char* input = "# hi";
  int parseResult = djot_parse(me, input, false);
  if (1 != parseResult) { // 1 is success, 0 error (weirdly)
    djot_close(me);
    return 100 + parseResult;
  }
  char* html = djot_render_html(me);
  if (NULL == html) {
    djot_close(me);
    return 2;
  }
  printf("## djot_demo result: %s\n", html);
  djot_close(me);
  return 0;
}
EOF
}
#define luaconf_h

cafFixLuaHeader() {
  local f=lua.h
  [ -f "$f" ] || return 23
  sed '/<stddef.h>/a \
#include <stdio.h>' \
    "$f" > "${f}.tmp" && mv "$f.tmp" "$f"
}

# TODO: verify Linux build still works(?) b/c it overrides
cafFixLuaConfHeader() {
  local f=luaconf.h
  [ -f "$f" ] || return 23
  sed '/define luaconf_h/a \
#define LUA_USE_MACOSX' \
    "$f" > "${f}.tmp" && mv "$f.tmp" "$f"
}

cafSed() {
  local f="$1"
  local from="$2"
  local to="$3"
  [ -f "$f" ] || return 43
  [ -n "$from" ] || return 44
  [ -n "$to" ] || return 45
  sed "/$from/s|$from|$to|" "$f" > "${f}.tmp"  || return $?
  mv "${f}.tmp" "$f"
}

replaceCurrent() {
  logEntry
  [ -n "$dest" ] || exit 333
  rm -rf "$dest"/* \
   && cp -r "$copy"/* "$dest"
}

buildSwiftDjot() {
  logEntry
  cd "$projectdir" || return 33
  swift package clean \
  && swift package purge-cache \
  && swift build \
  && swift "test"
}

emitVersion() {
  local commit=UNKNOWN
  cd "$checkout/djot" \
    &&  commit="$(git rev-parse --verify HEAD)"
  echo "## Update version to commit: $commit"
}

logEntry() {
  echo "## ${FUNCNAME[1]} ------------------------"
}

doAll() {
  checkout \
  && buildDjotClib \
  && copyAndFix \
  && replaceCurrent \
  && buildSwiftDjot \
  && emitVersion
}

### start
# required: git, swift, make
# tested only on macOS

cd "$(dirname "${0}")/.."
if [ "" != "$(git status --short 2>&1)" ] ; then
  echo "## clean git status to restore on overwrite failure"
  return 99
fi

projectdir="$(pwd)"
basedir="${projectdir}/../SwiftDjot-temp-gen"
[ -d "$basedir" ] && rm -rf "$basedir"
mkdir "$basedir"
checkout="$basedir/checkout"
copy="$basedir/copy"
dest="$projectdir/Sources/Cdjot"

doAll
echo "## pullDjot: $?"
