# Package

version       = "0.1.0"
author        = "Rahmatullah"
description   = "SQL parser to create table object equivalent and Go output"
license       = "MIT"
bin           = @["sqlgen"]
installExt    = @["nim"]
srcDir        = "src"
skipDirs      = @["tests"]

# Dependencies

requires "nim >= 0.18.0"

import distros

task release, "Compiling a release version":
  var exe = ""
  if detectOs(Windows):
    exe = ".exe"
  exec("nim c -d:release -o:sqlgen" & exe & " src/sqlgen.nim")

task basic, "Test 1 dummy script sql":
  exec "nim c -r tests/test1"

task constrained, "Test 2 constrained script sql":
  exec "nim c -r tests/test2"

task timezone, "Test 3 time zoned script sql":
  exec "nim c -r tests/test3"

task test_all, "Test all cases":
  exec "nimble basic"
  exec "nimble constrained"
  exec "nimble timezone"
