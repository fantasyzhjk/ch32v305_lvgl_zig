#include "ch32v30x.h"
#include "tusb.h"

void usb_app_init(void)
{
    tusb_rhport_init_t dev_init = {
        .role = TUSB_ROLE_DEVICE,
        .speed = TUSB_SPEED_AUTO,
    };

    tusb_init(BOARD_TUD_RHPORT, &dev_init);
}

void usb_app_task(void)
{
    tud_task();
}

void usb_write(const void* data, uint32_t len)
{
    if (!tud_cdc_connected()) {
        return;
    }

    tud_cdc_write(data, len);
    tud_cdc_write_flush();
}

uint32_t usb_read(void* buf, uint32_t len)
{
    return tud_cdc_read(buf, len);
}

uint32_t usb_available(void)
{
    return tud_cdc_available();
}

#define CH32_UID_BASE 0x1FFFF7E8u

void board_get_unique_id(uint8_t id[], size_t max_len)
{
    uint32_t const *uid = (uint32_t const *) CH32_UID_BASE;

    uint8_t raw[12];

    memcpy(&raw[0], &uid[0], 4);
    memcpy(&raw[4], &uid[1], 4);
    memcpy(&raw[8], &uid[2], 4);

    size_t len = max_len < sizeof(raw) ? max_len : sizeof(raw);
    memcpy(id, raw, len);
}