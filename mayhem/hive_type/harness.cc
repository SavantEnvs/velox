#include <cstddef>
#include <cstdint>
#include <exception>
#include <string>
#include "velox/type/fbhive/HiveTypeParser.h"

using facebook::velox::type::fbhive::HiveTypeParser;

// HiveTypeParser::nextToken scans identifiers with `isalnum(*iter)` and no end check, so parse() relies on
// an undocumented NUL after the string_view. That is a latent upstream bug for any caller passing a
// non-NUL-terminated view; the known callers pass a literal or std::string, which has one. A raw libFuzzer
// buffer has none, so every input ending in an identifier reads one byte past the heap block (reproducer in
// mayhem/hive_type/known-findings/). Parse a std::string copy so the other parser paths stay reachable.
extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size > 4096) {
    return -1;
  }
  try {
    const std::string input(reinterpret_cast<const char*>(data), size);
    HiveTypeParser parser;
    auto type = parser.parse(input);
    if (type) {
      (void)type->toString();
    }
  } catch (const std::exception&) {
    return -1;
  }
  return 0;
}
