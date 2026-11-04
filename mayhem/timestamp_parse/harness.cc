#include <cstddef>
#include <cstdint>
#include <exception>
#include "velox/type/TimestampConversion.h"

using namespace facebook::velox;

// Input: [mode byte][text].
extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1 || size > 512) {
    return -1;
  }
  const char* text = reinterpret_cast<const char*>(data) + 1;
  size_t len = size - 1;
  static const util::TimestampParseMode kTsModes[] = {
      util::TimestampParseMode::kIso8601,
      util::TimestampParseMode::kPrestoCast,
      util::TimestampParseMode::kLegacyCast,
      util::TimestampParseMode::kSparkCast};
  static const util::ParseMode kDateModes[] = {
      util::ParseMode::kStrict,
      util::ParseMode::kNonStrict,
      util::ParseMode::kPrestoCast,
      util::ParseMode::kSparkCast,
      util::ParseMode::kIso8601};
  try {
    auto tsMode = kTsModes[data[0] % 4];
    auto dateMode = kDateModes[(data[0] >> 2) % 5];
    (void)util::fromTimestampString(text, len, tsMode);
    (void)util::fromTimestampWithTimezoneString(text, len, tsMode);
    (void)util::fromDateString(text, len, dateMode);
  } catch (const std::exception&) {
    return -1;
  }
  return 0;
}
