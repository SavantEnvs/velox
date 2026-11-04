// Known-answer oracle for the fuzzed Velox parsers; built with the project's normal flags.
// Prints "PASS <name>" / "FAIL <name>" per check and "DONE <n>" at the end.
#include <cstdio>
#include <exception>
#include <string>
#include <string_view>

#include <folly/dynamic.h>
#include <folly/json.h>

#include "velox/functions/lib/DateTimeFormatter.h"
#include "velox/functions/prestosql/json/JsonExtractor.h"
#include "velox/functions/prestosql/types/parser/TypeParser.h"
#include "velox/type/TimestampConversion.h"
#include "velox/type/fbhive/HiveTypeParser.h"

using namespace facebook::velox;

static int total = 0;

static void check(const char* name, bool ok) {
  ++total;
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", name);
  std::fflush(stdout);
}

static std::string hive(const char* s) {
  return type::fbhive::HiveTypeParser().parse(s)->toString();
}

static std::string presto(const char* s) {
  return functions::prestosql::parseType(s)->toString();
}

int main() {
  try {
    check("hive_map", hive("map<string,array<bigint>>") == "MAP<VARCHAR,ARRAY<BIGINT>>");
    check("hive_struct", hive("struct<a:int,b:double>") == "ROW<a:INTEGER,b:DOUBLE>");
    check("hive_bad_rejected", [] {
      try {
        hive("array<");
      } catch (const std::exception&) {
        return true;
      }
      return false;
    }());

    check("presto_row", presto("row(a integer, b varchar)") == "ROW<a:INTEGER,b:VARCHAR>");
    check("presto_decimal", presto("decimal(10,2)") == "DECIMAL(10, 2)");
    check("presto_array_map", presto("array(map(varchar, bigint))") == "ARRAY<MAP<VARCHAR,BIGINT>>");

    {
      auto f = functions::buildJodaDateTimeFormatter("yyyy-MM-dd HH:mm:ss");
      auto r = f.value()->parse("2024-03-05 12:34:56");
      check("joda_parse", r.hasValue() && r.value().timestamp.getSeconds() == 1709642096);
    }
    {
      auto f = functions::buildMysqlDateTimeFormatter("%Y-%m-%d %H:%i:%s");
      auto r = f.value()->parse("1970-01-02 00:00:05");
      check("mysql_parse", r.hasValue() && r.value().timestamp.getSeconds() == 86405);
    }
    {
      auto f = functions::buildJodaDateTimeFormatter("yyyy-MM-dd");
      auto r = f.value()->parse("not a date");
      check("joda_bad_rejected", !r.hasValue());
    }

    {
      auto v = functions::jsonExtract(R"({"a":{"b":[1,2,3]}})", "$.a.b[1]");
      check("json_extract_index", v.has_value() && v->isInt() && v->asInt() == 2);
      auto s = functions::jsonExtractScalar(R"({"a":{"c":"hi"}})", "$.a.c");
      check("json_extract_scalar", s.has_value() && *s == "hi");
      auto m = functions::jsonExtractScalar(R"({"a":1})", "$.b");
      check("json_extract_missing", !m.has_value());
    }

    {
      auto d = util::fromDateString("2024-03-05", util::ParseMode::kPrestoCast);
      check("date_parse", d.hasValue() && d.value() == 19787);
      auto bad = util::fromDateString("2024-13-45", util::ParseMode::kPrestoCast);
      check("date_bad_rejected", !bad.hasValue());
      auto t = util::fromTimestampString("1970-01-01 00:00:01.5", 21, util::TimestampParseMode::kPrestoCast);
      check("timestamp_parse", t.hasValue() && t.value().getSeconds() == 1 && t.value().getNanos() == 500000000);
    }
  } catch (const std::exception& e) {
    std::printf("FAIL exception %s\n", e.what());
    return 1;
  }
  std::printf("DONE %d\n", total);
  return 0;
}
