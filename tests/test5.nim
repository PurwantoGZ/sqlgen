import sqlgen

var fname = "tests/standalone_primarykey.sql"
var table = fname.parseSql.parse.getTables

for tbl in table:
  echo tbl
stdout.writeGoEntity(table, needtime = table.needtime, version = version)
