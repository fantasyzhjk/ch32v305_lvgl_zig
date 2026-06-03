/********************************** (C) COPYRIGHT *******************************
* File Name          : startup_ch32v30x.S
* Description        : Zig-local CH32V30x startup and vector table.
*******************************************************************************/

    .section .init,"ax",@progbits
    .global _start
    .align 1
_start:
    j handle_reset
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00000013
    .word 0x00100073

    .section .vector,"ax",@progbits
    .align 1
_vector_base:
    .option norvc
    .word _start
    .word 0
    .word NMI_Handler
    .word HardFault_Handler
    .word 0
    .word Ecall_M_Mode_Handler
    .word 0
    .word 0
    .word Ecall_U_Mode_Handler
    .word Break_Point_Handler
    .word 0
    .word 0
    .word SysTick_Handler
    .word 0
    .word SW_handler
    .word 0
    .word WWDG_IRQHandler
    .word PVD_IRQHandler
    .word TAMPER_IRQHandler
    .word RTC_IRQHandler
    .word FLASH_IRQHandler
    .word RCC_IRQHandler
    .word EXTI0_IRQHandler
    .word EXTI1_IRQHandler
    .word EXTI2_IRQHandler
    .word EXTI3_IRQHandler
    .word EXTI4_IRQHandler
    .word DMA1_Channel1_IRQHandler
    .word DMA1_Channel2_IRQHandler
    .word DMA1_Channel3_IRQHandler
    .word DMA1_Channel4_IRQHandler
    .word DMA1_Channel5_IRQHandler
    .word DMA1_Channel6_IRQHandler
    .word DMA1_Channel7_IRQHandler
    .word ADC1_2_IRQHandler
    .word USB_HP_CAN1_TX_IRQHandler
    .word USB_LP_CAN1_RX0_IRQHandler
    .word CAN1_RX1_IRQHandler
    .word CAN1_SCE_IRQHandler
    .word EXTI9_5_IRQHandler
    .word TIM1_BRK_IRQHandler
    .word TIM1_UP_IRQHandler
    .word TIM1_TRG_COM_IRQHandler
    .word TIM1_CC_IRQHandler
    .word TIM2_IRQHandler
    .word TIM3_IRQHandler
    .word TIM4_IRQHandler
    .word I2C1_EV_IRQHandler
    .word I2C1_ER_IRQHandler
    .word I2C2_EV_IRQHandler
    .word I2C2_ER_IRQHandler
    .word SPI1_IRQHandler
    .word SPI2_IRQHandler
    .word USART1_IRQHandler
    .word USART2_IRQHandler
    .word USART3_IRQHandler
    .word EXTI15_10_IRQHandler
    .word RTCAlarm_IRQHandler
    .word USBWakeUp_IRQHandler
    .word TIM8_BRK_IRQHandler
    .word TIM8_UP_IRQHandler
    .word TIM8_TRG_COM_IRQHandler
    .word TIM8_CC_IRQHandler
    .word RNG_IRQHandler
    .word FSMC_IRQHandler
    .word SDIO_IRQHandler
    .word TIM5_IRQHandler
    .word SPI3_IRQHandler
    .word UART4_IRQHandler
    .word UART5_IRQHandler
    .word TIM6_IRQHandler
    .word TIM7_IRQHandler
    .word DMA2_Channel1_IRQHandler
    .word DMA2_Channel2_IRQHandler
    .word DMA2_Channel3_IRQHandler
    .word DMA2_Channel4_IRQHandler
    .word DMA2_Channel5_IRQHandler
    .word ETH_IRQHandler
    .word ETH_WKUP_IRQHandler
    .word CAN2_TX_IRQHandler
    .word CAN2_RX0_IRQHandler
    .word CAN2_RX1_IRQHandler
    .word CAN2_SCE_IRQHandler
    .word OTG_FS_IRQHandler
    .word USBHSWakeup_IRQHandler
    .word USBHS_IRQHandler
    .word DVP_IRQHandler
    .word UART6_IRQHandler
    .word UART7_IRQHandler
    .word UART8_IRQHandler
    .word TIM9_BRK_IRQHandler
    .word TIM9_UP_IRQHandler
    .word TIM9_TRG_COM_IRQHandler
    .word TIM9_CC_IRQHandler
    .word TIM10_BRK_IRQHandler
    .word TIM10_UP_IRQHandler
    .word TIM10_TRG_COM_IRQHandler
    .word TIM10_CC_IRQHandler
    .word DMA2_Channel6_IRQHandler
    .word DMA2_Channel7_IRQHandler
    .word DMA2_Channel8_IRQHandler
    .word DMA2_Channel9_IRQHandler
    .word DMA2_Channel10_IRQHandler
    .word DMA2_Channel11_IRQHandler
    .option rvc

    .section .text.vector_handler, "ax", @progbits

    .macro default_handler name
        .weak \name
\name:
1:
        j 1b
    .endm

    default_handler NMI_Handler
    default_handler HardFault_Handler
    default_handler Ecall_M_Mode_Handler
    default_handler Ecall_U_Mode_Handler
    default_handler Break_Point_Handler
    default_handler SysTick_Handler
    default_handler SW_handler
    default_handler WWDG_IRQHandler
    default_handler PVD_IRQHandler
    default_handler TAMPER_IRQHandler
    default_handler RTC_IRQHandler
    default_handler FLASH_IRQHandler
    default_handler RCC_IRQHandler
    default_handler EXTI0_IRQHandler
    default_handler EXTI1_IRQHandler
    default_handler EXTI2_IRQHandler
    default_handler EXTI3_IRQHandler
    default_handler EXTI4_IRQHandler
    default_handler DMA1_Channel1_IRQHandler
    default_handler DMA1_Channel2_IRQHandler
    default_handler DMA1_Channel3_IRQHandler
    default_handler DMA1_Channel4_IRQHandler
    default_handler DMA1_Channel5_IRQHandler
    default_handler DMA1_Channel6_IRQHandler
    default_handler DMA1_Channel7_IRQHandler
    default_handler ADC1_2_IRQHandler
    default_handler USB_HP_CAN1_TX_IRQHandler
    default_handler USB_LP_CAN1_RX0_IRQHandler
    default_handler CAN1_RX1_IRQHandler
    default_handler CAN1_SCE_IRQHandler
    default_handler EXTI9_5_IRQHandler
    default_handler TIM1_BRK_IRQHandler
    default_handler TIM1_UP_IRQHandler
    default_handler TIM1_TRG_COM_IRQHandler
    default_handler TIM1_CC_IRQHandler
    default_handler TIM2_IRQHandler
    default_handler TIM3_IRQHandler
    default_handler TIM4_IRQHandler
    default_handler I2C1_EV_IRQHandler
    default_handler I2C1_ER_IRQHandler
    default_handler I2C2_EV_IRQHandler
    default_handler I2C2_ER_IRQHandler
    default_handler SPI1_IRQHandler
    default_handler SPI2_IRQHandler
    default_handler USART1_IRQHandler
    default_handler USART2_IRQHandler
    default_handler USART3_IRQHandler
    default_handler EXTI15_10_IRQHandler
    default_handler RTCAlarm_IRQHandler
    default_handler USBWakeUp_IRQHandler
    default_handler TIM8_BRK_IRQHandler
    default_handler TIM8_UP_IRQHandler
    default_handler TIM8_TRG_COM_IRQHandler
    default_handler TIM8_CC_IRQHandler
    default_handler RNG_IRQHandler
    default_handler FSMC_IRQHandler
    default_handler SDIO_IRQHandler
    default_handler TIM5_IRQHandler
    default_handler SPI3_IRQHandler
    default_handler UART4_IRQHandler
    default_handler UART5_IRQHandler
    default_handler TIM6_IRQHandler
    default_handler TIM7_IRQHandler
    default_handler DMA2_Channel1_IRQHandler
    default_handler DMA2_Channel2_IRQHandler
    default_handler DMA2_Channel3_IRQHandler
    default_handler DMA2_Channel4_IRQHandler
    default_handler DMA2_Channel5_IRQHandler
    default_handler ETH_IRQHandler
    default_handler ETH_WKUP_IRQHandler
    default_handler CAN2_TX_IRQHandler
    default_handler CAN2_RX0_IRQHandler
    default_handler CAN2_RX1_IRQHandler
    default_handler CAN2_SCE_IRQHandler
    default_handler OTG_FS_IRQHandler
    default_handler USBHSWakeup_IRQHandler
    default_handler USBHS_IRQHandler
    default_handler DVP_IRQHandler
    default_handler UART6_IRQHandler
    default_handler UART7_IRQHandler
    default_handler UART8_IRQHandler
    default_handler TIM9_BRK_IRQHandler
    default_handler TIM9_UP_IRQHandler
    default_handler TIM9_TRG_COM_IRQHandler
    default_handler TIM9_CC_IRQHandler
    default_handler TIM10_BRK_IRQHandler
    default_handler TIM10_UP_IRQHandler
    default_handler TIM10_TRG_COM_IRQHandler
    default_handler TIM10_CC_IRQHandler
    default_handler DMA2_Channel6_IRQHandler
    default_handler DMA2_Channel7_IRQHandler
    default_handler DMA2_Channel8_IRQHandler
    default_handler DMA2_Channel9_IRQHandler
    default_handler DMA2_Channel10_IRQHandler
    default_handler DMA2_Channel11_IRQHandler

    .section .text.handle_reset,"ax",@progbits
    .weak handle_reset
    .align 1
handle_reset:
    .option push
    .option norelax
    csrw mepc, t0
    la gp, __global_pointer$
    .option pop
1:
    la sp, _eusrstack
2:
    la a0, _data_lma
    la a1, _data_vma
    la a2, _edata
    bgeu a1, a2, 2f
1:
    lw t0, (a0)
    sw t0, (a1)
    addi a0, a0, 4
    addi a1, a1, 4
    bltu a1, a2, 1b
2:
    la a0, _sbss
    la a1, _ebss
    bgeu a0, a1, 2f
1:
    sw zero, (a0)
    addi a0, a0, 4
    bltu a0, a1, 1b
2:
    li t0, 0x1f
    csrw 0xbc0, t0

    li t0, 0x1f
    csrw 0x804, t0

    li t0, 0x6088
    csrs mstatus, t0

    la t0, _vector_base
    ori t0, t0, 3
    csrw mtvec, t0

    jal SystemInit
    la t0, main
    csrw mepc, t0
    mret
