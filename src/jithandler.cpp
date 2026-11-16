// Copyright (c) 2012-2015 Zeex
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#include <cassert>
#include <cstdarg>
#include <cstdlib>
#include <cstring>
#include <string>
#include <configreader.h>
#include "jithandler.h"
#include "logprintf.h"
#include "plugin.h"
#include "amxjit/compiler.h"
#include "amxjit/disasm.h"
#include "amxjit/logger.h"

#define logprintf Use_jit_printf_instead_of_logprintf

namespace {

void jit_printf(const char *format, ...) {
  std::va_list va;
  va_start(va, format);

  std::string new_format;
  new_format.append("[jit] ");
  new_format.append(format);

  vlogprintf(new_format.c_str(), va);
  va_end(va);
}

class ErrorHandler: public amxjit::CompileErrorHandler {
 public:
  explicit ErrorHandler(AMX *amx): amx_(amx) {}
  virtual void Execute(const amxjit::Instruction &instr) {
    jit_printf("Invalid or unsupported instruction at address %08x:",
               instr.address());
    jit_printf("  => %s", instr.ToString().c_str());
    // Raw cells tell a relocated opcode (Linux) apart from a decoding slip.
    AMX_HEADER *hdr = reinterpret_cast<AMX_HEADER *>(amx_->base);
    const cell *code = reinterpret_cast<const cell *>(amx_->base + hdr->cod);
    const cell *p = code + instr.address() / sizeof(cell);
    jit_printf("  raw: %08x %08x %08x (opcode id %d, flags %04x)",
               (unsigned)p[0], (unsigned)p[1], (unsigned)p[2],
               (int)amxjit::RelocateOpcode(p[0]), (unsigned)amx_->flags);
  }
 private:
  AMX *amx_;
};

cell OnJITCompile(AMX *amx) {
  int index;
  if (amx_FindPublic(amx, "OnJITCompile", &index) == AMX_ERR_NONE) {
    cell retval;
    amx_Exec(amx, &retval, index);
    return retval;
  }
  return 1;
}

cell OnJITError(AMX *amx) {
  int index;
  if (amx_FindPublic(amx, "OnJITError", &index) == AMX_ERR_NONE) {
    cell retval;
    amx_Exec(amx, &retval, index);
    return retval;
  }
  return 0;
}

void AMXJIT_CDECL ReportInvalidJump(cell address) {
  static int reported = 0;
  if (reported++ < 20) {
    jit_printf("Jump to invalid address 0x%x ignored (SCTRL 6 / JUMP.PRI)",
               (unsigned)address);
  }
}

amxjit::CodeBuffer *Compile(AMX *amx) {
  amxjit::SetInvalidJumpHandler(ReportInvalidJump);
  if (!OnJITCompile(amx)) {
    jit_printf("Compilation was disabled");
    return 0;
  }

  ConfigReader server_cfg("server.cfg");
  bool enable_log = false;
  server_cfg.GetValue("jit_log", enable_log);
  bool enable_sysreq_d = true;
  server_cfg.GetValue("jit_sysreq_d", enable_sysreq_d);
  bool enable_sleep_support = false;
  server_cfg.GetValue("jit_sleep", enable_sleep_support);
  unsigned int debug_flags = 0;
  server_cfg.GetValue("jit_debug", debug_flags);

  if (std::getenv("JIT_SLEEP") != 0) {
    enable_sleep_support = true;
  }

  amxjit::Logger *logger = 0;
  if (enable_log) {
    logger = new amxjit::FileLogger("plugins/jit.log");
  }

  amxjit::Compiler compiler;
  ErrorHandler error_handler(amx);
  compiler.SetLogger(logger);
  compiler.SetErrorHandler(&error_handler);
  compiler.SetSysreqDEnabled(enable_sysreq_d);
  compiler.SetSleepEnabled(enable_sleep_support);
  compiler.SetDebugFlags(debug_flags);
  amxjit::CodeBuffer *code = compiler.Compile(amx);
  delete logger;

  if (code == 0) {
    jit_printf("Compilation failed");
    OnJITError(amx);
  }
  return code;
}

} // anonymous namespace

JITHandler::JITHandler(AMX *amx):
  AMXHandler<JITHandler>(amx),
  state_(INIT),
  code_()
{
  cell jit_var_addr;
  if (amx_FindPubVar(amx, "__JIT", &jit_var_addr) == AMX_ERR_NONE) {
    cell *jit_var;
    if (amx_GetAddr(amx, jit_var_addr, &jit_var) == AMX_ERR_NONE) {
      *jit_var = 1;
    }
  }
}

JITHandler::~JITHandler() {
  if (state_ == COMPILE_SUCCEDED) {
    assert(code_ != 0);
    code_->Delete();
  }
}

namespace {

// open.mp builds the AMX with sNAMEMAX=63, so the buffer must hold 64 chars.
struct PublicName {
  char str[64];
  PublicName(AMX *amx, int index) {
    std::strcpy(str, "<main/cont>");
    if (index >= 0 && amx_GetPublic(amx, index, str) != AMX_ERR_NONE) {
      std::strcpy(str, "<invalid>");
    }
  }
};

} // anonymous namespace

int JITHandler::Exec(cell *retval, int index) {
  switch (state_) {
    case INIT:
      // Keep the caller's index even if OnJITCompile rewrites the public
      // table: YSI puts a repair stub in the old slot (Hooks_RepairJITInit)
      // that restores the table on this first call.
      state_ = COMPILE;
      if ((code_ = Compile(amx())) != 0) {
        state_ = COMPILE_SUCCEDED;
      } else {
        state_ = COMPILE_FAILED;
        return AMX_ERR_INIT_JIT;
      }
    case COMPILE_SUCCEDED: {
      amxjit::CodeEntryPoint entry_point = code_->GetEntryPoint();
      int error = entry_point(index, retval);
      // Hosts like open.mp don't report runtime errors, so a failing public
      // would otherwise stop silently. Capped to avoid flooding the log.
      static int reported = 0;
      // index < AMX_EXEC_CONT: sampgdk (e.g. inside Streamer) forges such
      // indexes for publics the script lacks and expects AMX_ERR_INDEX.
      if (error != AMX_ERR_NONE && error != AMX_ERR_SLEEP &&
          index >= AMX_EXEC_CONT && reported < 50) {
        reported++;
        jit_printf("Run time error %d in public '%s' (index %d)",
                   error, PublicName(amx(), index).str, index);
      }
      return error;
    }
    case COMPILE:
    case COMPILE_FAILED:
      return AMX_ERR_INIT_JIT;
    default:
      assert(0 && "Invalid JIT state");
      return AMX_ERR_NONE;
  }
}
