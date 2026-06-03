#include "lvgl.h"
#include "lcd.h"

#define MY_DISP_HOR_RES 240
#define MY_DISP_VER_RES 240

static void disp_flush(
    lv_display_t * disp,
    const lv_area_t * area,
    uint8_t * px_map)
{
    uint16_t * color_p = (uint16_t *)px_map;

    for(int32_t y = area->y1; y <= area->y2; y++) {
        for(int32_t x = area->x1; x <= area->x2; x++) {
            lcd_draw_point_color(x, y, *color_p++);
        }
    }

    lv_display_flush_ready(disp);
}

void lv_port_disp_init(void)
{
    static lv_color_t buf_1[MY_DISP_HOR_RES * 10];

    lv_display_t * disp = lv_display_create(MY_DISP_HOR_RES, MY_DISP_VER_RES);

    lv_display_set_flush_cb(disp, disp_flush);

    lv_display_set_buffers(
        disp,
        buf_1,
        NULL,
        sizeof(buf_1),
        LV_DISPLAY_RENDER_MODE_PARTIAL
    );
}