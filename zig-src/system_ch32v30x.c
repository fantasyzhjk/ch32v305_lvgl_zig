/********************************** (C) COPYRIGHT *******************************
* File Name          : system_ch32v30x.c
* Description        : Zig-local CH32V30x system clock setup.
*******************************************************************************/
#include "ch32v30x.h"

#define SYSCLK_FREQ_144MHz 144000000

uint32_t SystemCoreClock = SYSCLK_FREQ_144MHz;
__I uint8_t AHBPrescTable[16] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 6, 7, 8, 9};

static void SetSysClockTo144(void);

void SystemInit(void)
{
    RCC->CTLR |= (uint32_t)0x00000001;

#ifdef CH32V30x_D8C
    RCC->CFGR0 &= (uint32_t)0xF8FF0000;
#else
    RCC->CFGR0 &= (uint32_t)0xF0FF0000;
#endif

    RCC->CTLR &= (uint32_t)0xFEF6FFFF;
    RCC->CTLR &= (uint32_t)0xFFFBFFFF;
    RCC->CFGR0 &= (uint32_t)0xFF80FFFF;

#ifdef CH32V30x_D8C
    RCC->CTLR &= (uint32_t)0xEBFFFFFF;
    RCC->INTR = 0x00FF0000;
    RCC->CFGR2 = 0x00000000;
#else
    RCC->INTR = 0x009F0000;
#endif

    SetSysClockTo144();
}

void SystemCoreClockUpdate(void)
{
    uint32_t tmp = 0;
    uint32_t pllmull = 0;
    uint32_t pllsource = 0;
    uint32_t pll_div_6_5 = 0;

    tmp = RCC->CFGR0 & RCC_SWS;

    switch (tmp)
    {
        case 0x00:
            SystemCoreClock = HSI_VALUE;
            break;
        case 0x04:
            SystemCoreClock = HSE_VALUE;
            break;
        case 0x08:
            pllmull = RCC->CFGR0 & RCC_PLLMULL;
            pllsource = RCC->CFGR0 & RCC_PLLSRC;
            pllmull = (pllmull >> 18) + 2;

#ifdef CH32V30x_D8
            if(pllmull == 17)
            {
                pllmull = 18;
            }
#else
            if(pllmull == 2)
            {
                pllmull = 18;
            }
            if(pllmull == 15)
            {
                pllmull = 13;
                pll_div_6_5 = 1;
            }
            if(pllmull == 16)
            {
                pllmull = 15;
            }
            if(pllmull == 17)
            {
                pllmull = 16;
            }
#endif

            if(pllsource == 0x00)
            {
                SystemCoreClock = (HSI_VALUE >> 1) * pllmull;
            }
            else if((RCC->CFGR0 & RCC_PLLXTPRE) != (uint32_t)RESET)
            {
                SystemCoreClock = (HSE_VALUE >> 1) * pllmull;
            }
            else
            {
                SystemCoreClock = HSE_VALUE * pllmull;
            }

            if(pll_div_6_5 == 1)
            {
                SystemCoreClock /= 2;
            }
            break;
        default:
            SystemCoreClock = HSI_VALUE;
            break;
    }

    tmp = AHBPrescTable[((RCC->CFGR0 & RCC_HPRE) >> 4)];
    SystemCoreClock >>= tmp;
}

static void SetSysClockTo144(void)
{
    __IO uint32_t StartUpCounter = 0;
    __IO uint32_t HSEStatus = 0;

    RCC->CTLR |= (uint32_t)RCC_HSEON;

    do
    {
        HSEStatus = RCC->CTLR & RCC_HSERDY;
        StartUpCounter++;
    } while((HSEStatus == 0) && (StartUpCounter != HSE_STARTUP_TIMEOUT));

    if((RCC->CTLR & RCC_HSERDY) != RESET)
    {
        HSEStatus = (uint32_t)0x01;
    }
    else
    {
        HSEStatus = (uint32_t)0x00;
    }

    if(HSEStatus == (uint32_t)0x01)
    {
        RCC->CFGR0 |= (uint32_t)RCC_HPRE_DIV1;
        RCC->CFGR0 |= (uint32_t)RCC_PPRE2_DIV1;
        RCC->CFGR0 |= (uint32_t)RCC_PPRE1_DIV2;

        RCC->CFGR0 &= (uint32_t)(~(RCC_PLLSRC | RCC_PLLXTPRE | RCC_PLLMULL));

#ifdef CH32V30x_D8
        RCC->CFGR0 |= (uint32_t)(RCC_PLLSRC_HSE | RCC_PLLXTPRE_HSE | RCC_PLLMULL18);
#else
        RCC->CFGR0 |= (uint32_t)(RCC_PLLSRC_HSE | RCC_PLLXTPRE_HSE | RCC_PLLMULL18_EXTEN);
#endif

        RCC->CTLR |= RCC_PLLON;
        while((RCC->CTLR & RCC_PLLRDY) == 0)
        {
        }

        RCC->CFGR0 &= (uint32_t)(~RCC_SW);
        RCC->CFGR0 |= (uint32_t)RCC_SW_PLL;
        while((RCC->CFGR0 & (uint32_t)RCC_SWS) != (uint32_t)0x08)
        {
        }
    }
}
