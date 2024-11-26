// Copyright 2024 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
.cc_top isSimulation.function, isSimulation
.type isSimulation, @function

.globl isSimulation
.globl isSimulation.nstackwords
.globl isSimulation.maxthreads
.globl isSimulation.maxtimers
.globl isSimulation.maxchanends
.linkset isSimulation.nstackwords,0
.linkset isSimulation.maxthreads,0
.linkset isSimulation.maxtimers,0
.linkset isSimulation.maxchanends,0

#include <xs1_kernel.h>

#define OSCALL_IS_SIMULATION 99

.globl isSimulation
isSimulation:
  ldc r0, OSCALL_IS_SIMULATION
  bu _DoSyscall
  retsp 0

.cc_bottom isSimulation.function
