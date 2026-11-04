#include <cstddef>
#include <cstdint>
#include <cstring>
#include <exception>
#include <string_view>
#include "velox/functions/lib/DateTimeFormatter.h"

using namespace facebook::velox::functions;

// Input: [kind byte][format]\n[date/time string to parse with that format].
extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 2 || size > 4096) {
    return -1;
  }
  const char* body = reinterpret_cast<const char*>(data) + 1;
  size_t bodyLen = size - 1;
  const char* nl = static_cast<const char*>(memchr(body, '\n', bodyLen));
  size_t fmtLen = nl ? static_cast<size_t>(nl - body) : bodyLen;
  std::string_view fmt(body, fmtLen);
  std::string_view input =
      nl ? std::string_view(nl + 1, bodyLen - fmtLen - 1) : std::string_view();
  try {
    switch (data[0] % 4) {
      case 0: {
        auto f = buildMysqlDateTimeFormatter(fmt);
        if (f.hasValue()) {
          (void)f.value()->parse(input);
        }
        break;
      }
      case 1: {
        auto f = buildJodaDateTimeFormatter(fmt);
        if (f.hasValue()) {
          (void)f.value()->parse(input);
        }
        break;
      }
      case 2: {
        auto f = buildSimpleDateTimeFormatter(fmt, false);
        if (f.hasValue()) {
          (void)f.value()->parse(input);
        }
        break;
      }
      default: {
        auto f = buildSimpleDateTimeFormatter(fmt, true);
        if (f.hasValue()) {
          (void)f.value()->parse(input);
        }
        break;
      }
    }
  } catch (const std::exception&) {
    return -1;
  }
  return 0;
}
