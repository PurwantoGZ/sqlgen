import sqlgenpkg/[parsesql2, utils, types]
import sqlgenpkg/goout/[gotable, goentity]

export parsesql2, utils, types, gotable, goentity

when not defined(release):
  import os

when isMainModule:
  proc main =
    when defined(release):
      var (filename, outpath) = parseCmd()
      var tables = filename.parseSql.parse.getTables
      var outfile: File
      if outpath == "stdout" or outpath == "":
        outfile = stdout
      else:
        outfile = open(outpath, fmWrite)
      outfile.writeGoEntity(tables, needtime = tables.needtime)
    else:
      if paramCount() < 1:
        quit "Provide sql file"
      var fname = paramStr 1
      var tables = fname.parseSql.parse.getTables
      stdout.writeGoEntity(tables, needtime = tables.needtime)


  main()
