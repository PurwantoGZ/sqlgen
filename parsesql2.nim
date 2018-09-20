import os, strutils, sequtils, tables

when not defined(release):
  import strformat
  import future

import types, utils
import goout/gotable
import goout/goentity

proc validateTest(idx: int, tokens: seq[string], test: Validater): bool =
  result = false
  if idx != 0 and tokens.len > 1:
    result = test(idx, tokens)

proc isForeignKey(idx: int, tokens: seq[string]): bool =
  validateTest(idx, tokens, proc(x: int, tkn: seq[string]): bool =
    tkn[x] == "key" and tkn[x-1] == "foreign")

proc notValidTableName(idx: int, tokens: seq[string]): bool =
  validateTest(idx, tokens, proc(x: int, tkn: seq[string]): bool =
    tkn[x-1].endsWith ")")

proc purgeComments(exprstr: string): string =
  var buffer = ""
  var iscomment = false
  for idx, c in exprstr:
    if c in NewLines:
      iscomment = false
    elif c == '-' and idx < exprstr.len - 1 and exprstr[idx+1] == '-':
      iscomment = true

    if not iscomment: buffer &= c
    #else: stdout.write c
  buffer

proc parseOptions(expr: string): seq[FieldProps] =
  result = @[]
  if expr.len == 0:
    return

  var tokens = expr.splitWhitespace
  for idx, token in tokens:
    case token
    of "key": result.add fpPrimaryKey
    of "null": result.add fpNotNull
    of "unique": result.add fpUnique
    of "index": result.add fpIndex
    of "references": result.add fpForeignKey

proc tokenizeParenthesis(expr: string): string =
  var buffer = ""
  var isparenthesis = false
  for c in expr:
    case c
    of '(': isparenthesis = true
    of ')': isparenthesis = false
    else: discard

    if c in Whitespace and isparenthesis:
      continue
    buffer &= c
  buffer

proc getDefault(expr: string): string =
  var tokens = expr.splitWhitespace
  for idx, token in tokens:
    if token == "default" and idx != tokens.len - 1:
      return tokens[idx+1]

proc splitSchemaName(schnm: string): (string, string) =
  var schname = schnm.split('.', 1)
  (schname[0], schname[1])

proc parseForeign(expr: string): SqlForeign =
  var tokens = expr.splitWhitespace
  var pos = -1
  for idx, token in tokens:
    pos = idx
    if token == "references": break
  if pos == tokens.len - 1:
    return SqlForeign()
  for idx, token in tokens[pos+1 .. ^1]:
    var parpos = token.find '('
    if parpos == 0 and idx != 0:
      (result.schema, result.table) = tokens[pos+1+idx-1].splitSchemaName
      if idx+pos != tokens.len - 1 and token != "(":
        result.field = tokens[pos+idx].strip(chars = {'(', ')'} + Whitespace)
        break

    elif parpos != token.len - 1:
      var schname_fld = tokens[pos+1+idx].split('(', 1)
      (result.schema, result.table) = schname_fld[0].splitSchemaName
      result.field = schname_fld[1].split(')')[0]
      break

    elif parpos == token.len - 1:
      var schname_fld = tokens[idx].split('(', 1)
      (result.schema, result.table) = schname_fld[0].splitSchemaName
      if schname_fld[1].endsWith ")":
        var fld = schname_fld[1].split(')')
        result.field = fld[0]
        break
  #dump result.schema
  #dump result.table

proc parseTableField(tbl: var SqlTable, expr: string): SqlField =
  when not defined(release):
    dump expr
  var tokens = expr.splitWhitespace 2
  if tokens[0] == "foreign" and tokens[1] == "key":
    var fieldname = tokens[2].split(')', 1)[0].strip(chars = {'(', ')'})
    var field = tbl.fields[fieldname]
    #dump field
    field.options.add fpForeignKey
    field.foreign = expr.parseForeign
    return field
  result.name = tokens[0]
  result.kind = tokens[1]
  if tokens.len > 2:
    result.options = tokens[2].parseOptions
    result.default = if "default" in tokens[2]: tokens[2].getDefault
                     else: ""
    result.foreign = tokens[2].parseForeign
  else:
    result.options = @[]
    result.default = ""

proc parseSqlTable*(expr: string): SqlTable =
  var tokens = expr.toLowerAscii.purgeComments.splitWhitespace

  var pos = -1
  for idx, token in tokens:
    if ((token == "(" or token.startsWith "(") and idx != 0) or token.endsWith "(":
      pos = idx
      if isForeignKey(idx-1, tokens) or notValidTableName(idx-1, tokens):
        continue
      else:
        var schemaname = newseq[string]()
        if token.endsWith("(") and token != "(":
          schemaname = (token.split('(', 1)[0]).split('.', 1)
        else:
          schemaname = tokens[idx-1].split('.', maxsplit=1)
        if schemaname.len > 1:
          result.schema = schemaname[0]
          result.name = schemaname[1]
        else:
          result.schema = ""
          result.name = schemaname[0]
        break

  result.fields = newTable[string, SqlField]()
  tokens = (tokens[pos+1 .. ^1]).join(sep=" ").split(',')
  for idx, token in tokens:
    var field = result.parseTableField token.strip.tokenizeParenthesis
    result.fields[field.name] = field


proc parseExpression*(exprstr: string): seq[string] =
  exprstr.split(';').mapIt it.strip

proc parse*(lines: seq[string]): seq[string] =
  result = @[]
  var
    prevline = ""
    cont = false
    ln = ""
  for line in lines:
    if line.startsWith("\\") or line.startsWith("--"):
      continue

    if cont: ln = prevline & line
    else: ln = line

    prevline = ""
    cont = false

    var exprs = ln.split(';')
    if ln.endsWith ';':
      if exprs.len == 1: result.add ln
      elif exprs.len > 1:
        for expr in exprs:
          if expr != "": result.add(expr & ';')
    else:
      if exprs.len == 1:
        prevline = ln
      elif exprs.len > 1:
        for expr in exprs[0..^2]:
          if expr != "": result.add(expr & ';')
        prevline = exprs[^1]
      cont = true

proc parseSql*(file: File): SqlExpressions =
  var buff = newseq[string]()
  while not file.endOfFile:
    var line = file.readLine & "\n"
    if line == "": continue
    buff.add line.strip(trailing = false)
  buff.parse

proc parseSql*(filename: string): SqlExpressions =
  var file = open filename
  result = file.parseSql
  close file

proc getTables*(exprs: SqlExpressions): seq[SqlTable] =
  result = @[]
  for expr in exprs:
    var tokens = expr.toLowerAscii.splitWhitespace
    if tokens.len > 2 and tokens[0] == "create" and tokens[1] == "table":
      result.add expr.parseSqlTable

when isMainModule:
  proc main =
    when defined(release):
      var (filename, outpath) = parseCmd()

    when not defined(release):
      var fname: string = ""
      if paramcount() >= 1:
        fname = paramStr 1
      else:
        quit "Please supply filename"

      var file = open fname
      var line = ""
      var buff = ""
      var tables = newSeq[SqlTable]()
      while file.readLine line:
        var tokens = line.toLowerAscii.splitWhitespace

        if tokens.len > 2 and tokens[0] == "create" and tokens[1] == "table":
          #echo line
          buff &= (line & "\n")
          while file.readLine line:
            line = line.toLowerAscii
            var pos = line.find(';')
            if pos == line.len - 1:
              buff &= (line & "\n")
              tables.add buff.parseSqlTable()
              buff = ""
              break
            elif pos == -1:
              buff &= (line & "\n")
            else:
              buff &= (line[0..pos] & "\n")
              tables.add buff.parseSqlTable()
              buff = line[pos+1..^1]
        else:
          discard
      #stdout.writeGoEntity(tables, needtime = tables.needtime)

      file.setFilePos 0
      var exprs = newseq[string]()
      while not file.endOfFile:
        var line = file.readLine & "\n"
        if line == "": continue
        exprs.add line.strip(trailing = false)
      close file
      var newtables = fname.parseSql.parse.getTables
      stdout.writeGoEntity(newtables, needtime = newtables.needtime)

    when defined(release):
      var tables = filename.parseSql.parse.getTables
      var file: File
      if outpath == "stdout" or outpath == "":
        file = stdout
      else:
        file = open(outpath, fmWrite)
      file.writeGoEntity(tables, needtime = tables.needtime)


  main()
