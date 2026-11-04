#include <cstddef>
#include <cstdint>
#include <cstring>
#include <exception>
#include <string_view>
#include "velox/functions/prestosql/json/JsonExtractor.h"

using namespace facebook::velox::functions;

// Input: [JSON path]\n[JSON document].
extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size > 8192) {
    return -1;
  }
  const char* buf = reinterpret_cast<const char*>(data);
  const char* nl = static_cast<const char*>(memchr(buf, '\n', size));
  if (!nl) {
    return -1;
  }
  std::string_view path(buf, nl - buf);
  std::string_view json(nl + 1, size - (nl - buf) - 1);
  try {
    (void)jsonExtract(json, path);
    (void)jsonExtractScalar(json, path);
  } catch (const std::exception&) {
    return -1;
  }
  return 0;
}
