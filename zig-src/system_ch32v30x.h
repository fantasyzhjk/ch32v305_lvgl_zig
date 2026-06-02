/********************************** (C) COPYRIGHT *******************************
* File Name          : system_ch32v30x.h
* Description        : Zig-local CH32V30x system header.
*******************************************************************************/
#ifndef __SYSTEM_CH32V30x_H
#define __SYSTEM_CH32V30x_H

#ifdef __cplusplus
extern "C" {
#endif

extern uint32_t SystemCoreClock;

void SystemInit(void);
void SystemCoreClockUpdate(void);

#ifdef __cplusplus
}
#endif

#endif
