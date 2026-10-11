/*
 * An init hook for llhttp's fixture binary that takes its mode from the
 * environment, so ONE binary can be asked for any combination of lenient
 * flags.
 *
 * WHY THIS EXISTS. This project calls upstream's harness rather than
 * reimplementing it, and every other piece of the differential
 * obeys that: the binaries are built by llhttp's own `test/fixtures/index.ts`,
 * and every trace line is printed by upstream's `extra.c`. This file is the
 * one exception, and it is a narrow one.
 *
 * `llparse-test-fixture` calls `LLPARSE__TEST_INIT(&s)` once, immediately
 * after `llparse_init`, and upstream supplies 24 such hooks -- one per
 * (kind, single flag) pair, plus two `*_lenient_all`. There is no hook for
 * any PAIR of flags, so upstream's harness cannot be asked for one at all:
 * the hook is chosen by a `-D` at compile time, and 55 pairs would be 55
 * binaries. Meanwhile `lenient_all` is a misnomer -- it sets nine of the
 * eleven flags, leaving SPACES_AFTER_CHUNK_SIZE and HEADER_VALUE_RELAXED
 * combined with nothing, anywhere in the corpus.
 *
 * WHAT IS AND IS NOT REIMPLEMENTED. This assigns two integer fields. It
 * prints nothing, parses nothing and decides nothing: every line the oracle
 * emits still comes from upstream's `extra.c`, which is what calling the
 * harness protects -- a second implementation of the TRACE FORMAT would make
 * the comparison circular, and there is none here.
 *
 * AND IT IS HELD TO UPSTREAM'S OWN HOOKS. With an empty mask this must
 * produce, byte for byte, what `http-request-c` and `http-response-c`
 * produce; with a single flag, what that flag's own upstream binary
 * produces. The differential asserts both against llhttp's real output
 * rather than trusting the four lines below.
 *
 * THE MASK IS KEYED BY NAME, NOT BY NUMBER. Each bit position below is this
 * project's own, from `(httparse modes)`, and is translated here into the
 * constant upstream declares. So the two sides agree on a FLAG rather than on
 * an integer, and upstream renumbering `LENIENT_*` changes nothing.
 */

#include <stdlib.h>

#include "fixture.h"

#ifdef LLHTTP__TEST_HTTP

static long chez_httparse__env_number(const char* name) {
  const char* value = getenv(name);

  if (value == NULL || value[0] == '\0') {
    return 0;
  }

  return strtol(value, NULL, 10);
}

void chez_httparse__test_init_modes(llparse_t* s) {
  long mask = chez_httparse__env_number("HTTPARSE_ORACLE_LENIENT");

  /* `type` is the other half of what upstream's hooks write. HTTP_BOTH is
   * deliberately unreachable: this project has no `start_req_or_res` to
   * compare against, so an unset or unknown value is a request, which is
   * what `llhttp__test_init_request` does. */
  if (chez_httparse__env_number("HTTPARSE_ORACLE_RESPONSE") != 0) {
    s->type = HTTP_RESPONSE;
  } else {
    s->type = HTTP_REQUEST;
  }

  if (mask & 0x001) s->lenient_flags |= LENIENT_HEADERS;
  if (mask & 0x002) s->lenient_flags |= LENIENT_CHUNKED_LENGTH;
  if (mask & 0x004) s->lenient_flags |= LENIENT_KEEP_ALIVE;
  if (mask & 0x008) s->lenient_flags |= LENIENT_TRANSFER_ENCODING;
  if (mask & 0x010) s->lenient_flags |= LENIENT_VERSION;
  if (mask & 0x020) s->lenient_flags |= LENIENT_DATA_AFTER_CLOSE;
  if (mask & 0x040) s->lenient_flags |= LENIENT_OPTIONAL_LF_AFTER_CR;
  if (mask & 0x080) s->lenient_flags |= LENIENT_OPTIONAL_CRLF_AFTER_CHUNK;
  if (mask & 0x100) s->lenient_flags |= LENIENT_OPTIONAL_CR_BEFORE_LF;
  if (mask & 0x200) s->lenient_flags |= LENIENT_SPACES_AFTER_CHUNK_SIZE;
  if (mask & 0x400) s->lenient_flags |= LENIENT_HEADER_VALUE_RELAXED;
}

#endif /* LLHTTP__TEST_HTTP */
