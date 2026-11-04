#!/usr/bin/env bash
# Builds, from the in-image dependency cache (/opt/toolchains/velox-deps, no network):
#   * sanitized Velox type/parse libs + the five fuzz harnesses (+ -standalone reproducers)
#   * a normal-flag known-answer oracle (/mayhem/_build/bin/velox_oracle) that mayhem/test.sh runs
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export HOME="${HOME:-/tmp}"
[ -w "$HOME" ] || export HOME=/tmp
D=/opt/toolchains/velox-deps
cd "$SRC"

TARGETS="velox_type velox_type_fbhive velox_presto_type_parser velox_functions_lib_date_time_formatter"
HARNESSES="hive_type presto_type datetime_format json_extract timestamp_parse"
JSON_SRCS="velox/functions/prestosql/json/JsonExtractor.cpp velox/functions/prestosql/json/JsonPathTokenizer.cpp
 velox/functions/prestosql/json/JsonStringUtil.cpp velox/functions/prestosql/json/SIMDJsonExtractor.cpp
 velox/functions/prestosql/json/SIMDJsonUtil.cpp velox/functions/lib/Utf8Utils.cpp"
CXXSTD="-std=gnu++20 -fPIC -mavx2 -mfma -mavx -mf16c -mlzcnt -mbmi2 -DUSE_VELOX_COMMON_BASE -DHAS_UNCAUGHT_EXCEPTIONS -fsized-deallocation -pthread -Wno-everything"
INCS="-I$SRC -isystem $SRC/velox -isystem $SRC/velox/external -isystem $D/include"
DEPLIBS="-Wl,--start-group $D/lib/*.a -Wl,--end-group -lglog -lgflags -ldouble-conversion -levent -lre2 -lboost_context -lboost_filesystem -lboost_program_options -lboost_regex -lboost_system -lboost_atomic -lboost_thread -lboost_chrono -licuuc -licui18n -licudata -lssl -lcrypto -lz -lzstd -llz4 -lsnappy -lbz2 -llzma -lsodium -lunwind -lstemmer -ldl -lrt"

# build_libs <dir> <opt flags> <sanitizer+debug flags>: configure + build the Velox libs and the JSON sources.
build_libs() {
  local dir="$1" opt="$2" fl="$3"
  # A cache from another compiler path (ccache masquerade vs /usr/bin) makes cmake wipe it AND drop -D flags.
  rm -rf "$dir/CMakeCache.txt" "$dir/CMakeFiles"
  cmake -S "$SRC" -B "$dir" -G Ninja -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
    -DCMAKE_C_FLAGS_RELEASE="$opt -DNDEBUG" -DCMAKE_CXX_FLAGS_RELEASE="$opt -DNDEBUG" \
    -DCMAKE_C_FLAGS="$fl" -DCMAKE_CXX_FLAGS="$fl" -DCMAKE_PREFIX_PATH="$D" \
    -DVELOX_DEPENDENCY_SOURCE=SYSTEM -DVELOX_BUILD_MINIMAL=ON -DVELOX_BUILD_TESTING=OFF \
    -DVELOX_ENABLE_BENCHMARKS=OFF -DVELOX_ENABLE_BENCHMARKS_BASIC=OFF -DVELOX_MONO_LIBRARY=OFF \
    -DVELOX_BUILD_SHARED=OFF -DVELOX_ENABLE_PARSE=OFF -DVELOX_ENABLE_GEO=OFF \
    -DVELOX_ENABLE_ICEBERG_FUNCTIONS=OFF -DVELOX_ENABLE_CCACHE=OFF -DVELOX_ENABLE_PARQUET=OFF \
    -DVELOX_ENABLE_REMOTE_FUNCTIONS=OFF -DVELOX_ENABLE_LOCAL_RUNNER_SERVICE=OFF
  # shellcheck disable=SC2086
  ninja -C "$dir" -j"$MAYHEM_JOBS" $TARGETS
  mkdir -p "$dir/json"
  local objs=() s o
  for s in $JSON_SRCS; do
    o="$dir/json/$(basename "$s").o"
    # shellcheck disable=SC2086
    $CXX $opt -DNDEBUG $fl $CXXSTD $INCS -DSIMDJSON_EXPERIMENTAL_ALLOW_INCOMPLETE_JSON -c "$s" -o "$o" &
    objs+=("$o")
    while [ "$(jobs -rp | wc -l)" -ge "$MAYHEM_JOBS" ]; do wait -n; done
  done
  wait
  rm -f "$dir/libmayhem_json.a"
  ar rcs "$dir/libmayhem_json.a" "${objs[@]}"
}

lib_args() { echo "$1/libmayhem_json.a -Wl,--start-group $(find "$1" -name 'lib*.a' ! -name libmayhem_json.a | sort | tr '\n' ' ') -Wl,--end-group"; }

mkdir -p "$SRC/_build/bin"

# 1) Normal-flag oracle (separate tree; no sanitizers)
build_libs "$SRC/_build/oracle" "-O1" "$COVERAGE_FLAGS"
# shellcheck disable=SC2046,SC2086
$CXX -O1 $COVERAGE_FLAGS $CXXSTD $INCS "$SRC/mayhem/oracle.cc" $(lib_args "$SRC/_build/oracle") $DEPLIBS -o "$SRC/_build/bin/velox_oracle"

# 2) Sanitized fuzz tree
FUZZ_FL="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
build_libs "$SRC/_build/fuzz" "-O1" "$FUZZ_FL"

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$SRC/_build/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$SRC/_build/standalone_main.o"
for h in $HARNESSES; do
  # shellcheck disable=SC2046,SC2086
  {
    $CXX $FUZZ_FL -O1 $CXXSTD $INCS -c "$SRC/mayhem/$h/harness.cc" -o "$SRC/_build/$h.o"
    if [ "$h" = presto_type ]; then
      # File-input target with its own main() (see mayhem/presto_type/harness.cc).
      $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$SRC/_build/$h.o" "$SRC/_build/lsan_off.o" \
        $(lib_args "$SRC/_build/fuzz") $DEPLIBS -o "$SRC/_build/bin/$h"
      continue
    fi
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$SRC/_build/$h.o" "$SRC/_build/lsan_off.o" \
      $(lib_args "$SRC/_build/fuzz") $DEPLIBS -o "$SRC/_build/bin/$h"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$SRC/_build/$h.o" "$SRC/_build/lsan_off.o" "$SRC/_build/standalone_main.o" \
      $(lib_args "$SRC/_build/fuzz") $DEPLIBS -o "$SRC/_build/bin/$h-standalone"
  }
done
echo "build ok"
