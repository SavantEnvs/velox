#include <cstdio>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include "velox/functions/prestosql/types/parser/TypeParser.h"

// File-input target: the flex scanner's fatal-error path (a '\n' has no rule, `nodefault`) calls exit(),
// which libFuzzer reports as an uncategorized exit and which ends its run on the first execution (its
// default seed is "\n"). An exit() from inside parseType is lifted to abort() so Mayhem reports it with
// the scanner frames below the handler. No input is filtered out.
static bool g_in_parse = false;

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <file>\n", argv[0]);
    return 2;
  }
  std::ifstream in(argv[1], std::ios::binary);
  const std::string text((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  if (text.size() > 4096) {
    return 0;
  }
  std::atexit([] {
    if (g_in_parse) {
      std::abort();
    }
  });
  try {
    g_in_parse = true;
    auto type = facebook::velox::functions::prestosql::parseType(text);
    g_in_parse = false;
    if (type) {
      std::cout << type->toString() << "\n";
    }
  } catch (const std::exception&) {
    g_in_parse = false;
  }
  return 0;
}
