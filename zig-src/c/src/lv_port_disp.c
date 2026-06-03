#include "lvgl.h"
#include "lcd.h"

#define MY_DISP_HOR_RES 240
#define MY_DISP_VER_RES 240

static void disp_flush(
    lv_display_t *disp,
    const lv_area_t *area,
    uint8_t *px_map)
{
    lcd_flush_pixels(
        (uint16_t)area->x1,
        (uint16_t)area->y1,
        (uint16_t)area->x2,
        (uint16_t)area->y2,
        (const uint16_t *)px_map);

    lv_display_flush_ready(disp);
}

void lv_port_disp_init(void)
{
    static lv_color_t buf_1[MY_DISP_HOR_RES * 10];

    lv_display_t *disp = lv_display_create(
        MY_DISP_HOR_RES,
        MY_DISP_VER_RES);

    lv_display_set_flush_cb(disp, disp_flush);

    lv_display_set_buffers(
        disp,
        buf_1,
        NULL,
        sizeof(buf_1),
        LV_DISPLAY_RENDER_MODE_PARTIAL);
}