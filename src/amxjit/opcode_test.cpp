// Self-check for opcode relocation (R5): run by ctest as "opcode_test".
#include <cstdio>
#include "opcode.h"

// opcode.cpp calls amx_Exec on Linux to fetch the table; never reached here.
extern "C" int AMXAPI amx_Exec(AMX *, cell *, int) {
  return AMX_ERR_NONE;
}

#define CHECK(expr) \
  if (!(expr)) { std::printf("FAILED: %s\n", #expr); return 1; }

int main() {
  using namespace amxjit;

  // No table (runtime without computed goto): opcode stays as is.
  CHECK(FindOpcode(0, OP_PUSH_C) == OP_PUSH_C);
  CHECK(FindOpcode(0, 0x12345678) == 0x12345678);

  // open.mp table: all 160 entries are searched.
  cell table[NUM_RUNTIME_OPCODES];
  for (int i = 0; i < NUM_RUNTIME_OPCODES; i++) {
    table[i] = 0x1000 + i * 4;
  }
  CHECK(FindOpcode(table, 0x1000 + OP_SYSREQ_D * 4) == OP_SYSREQ_D);
  CHECK(FindOpcode(table, 0x1000 + OP_CONST_S * 4) == OP_CONST_S);
  CHECK(FindOpcode(table, 0x1000 + 159 * 4) == 159);
  CHECK(FindOpcode(table, 0x42) == 0x42);

  std::printf("opcode_test: OK\n");
  return 0;
}
