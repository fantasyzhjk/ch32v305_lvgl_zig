"""
鼠标 → 3D 旋转控制器
读取鼠标移动，转化为 yaw/pitch 旋转数据，通过 USB 串口发送给单片机。

用法: python mouse_ctrl.py [串口名] [灵敏度]
      例如: python mouse_ctrl.py COM5 0.3

需要安装: pip install pyserial
按 Ctrl+C 退出，按住鼠标左键暂停控制（方便移动鼠标到别处）
"""

import sys
import time
import serial
import serial.tools.list_ports


def find_serial_port():
    """自动查找 USB CDC 串口"""
    ports = serial.tools.list_ports.comports()
    for p in ports:
        # WCH USB CDC 设备通常的 VID
        if p.vid == 0xCafe or (p.description and "USB" in p.description.upper()):
            return p.device
    # 找不到就列出让用户选
    if ports:
        print("可用串口:")
        for i, p in enumerate(ports):
            print(f"  [{i}] {p.device} - {p.description}")
        print("请用: python mouse_ctrl.py COMx 指定串口")
    else:
        print("未找到任何串口设备！")
    return None


def main():
    port = sys.argv[1] if len(sys.argv) > 1 else None
    sensitivity = float(sys.argv[2]) if len(sys.argv) > 2 else 0.3

    if not port:
        port = find_serial_port()
        if not port:
            return

    print(f"连接 {port} ...")
    ser = serial.Serial(port, 115200, timeout=0)
    time.sleep(0.5)  # 等待设备就绪
    print(f"已连接！灵敏度: {sensitivity}")
    print("移动鼠标控制旋转，按住左键暂停，Ctrl+C 退出")
    print("协议: Y<yaw>,P<pitch>\\n")

    yaw = 0.0
    pitch = 0.0

    try:
        # 尝试用 pyautogui 获取鼠标位移（需要 pip install pyautogui）
        try:
            import pyautogui

            pyautogui.FAILSAFE = False
            screen_w, screen_h = pyautogui.size()
            center_x = screen_w // 2
            center_y = screen_h // 2
            pyautogui.moveTo(center_x, center_y)
            use_pyautogui = True
            print("使用 pyautogui 模式（精确位移）")
        except ImportError:
            use_pyautogui = False
            print("提示: 安装 pyautogui (pip install pyautogui) 可获得更精确的鼠标追踪")

        import ctypes
        import ctypes.wintypes

        # Windows API 获取鼠标输入（不抢光标焦点）
        class MOUSEINPUT(ctypes.Structure):
            _fields_ = [
                ("dx", ctypes.wintypes.LONG),
                ("dy", ctypes.wintypes.LONG),
                ("mouseData", ctypes.wintypes.DWORD),
                ("dwFlags", ctypes.wintypes.DWORD),
                ("time", ctypes.wintypes.DWORD),
                ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
            ]

        last_x, last_y = None, None
        paused = False

        while True:
            # 检测鼠标左键是否按下（暂停控制）
            left_pressed = ctypes.windll.user32.GetAsyncKeyState(0x01) & 0x8000
            if left_pressed and not paused:
                paused = True
                print("[暂停] 松开左键恢复控制")
            elif not left_pressed and paused:
                paused = False
                # 重置位置基准
                last_x, last_y = None, None
                print("[恢复] 继续控制")

            if use_pyautogui and not paused:
                # pyautogui 模式：读取位移后立即回中心
                x, y = pyautogui.position()
                dx = x - center_x
                dy = y - center_y
                if dx != 0 or dy != 0:
                    yaw += dx * sensitivity
                    pitch += dy * sensitivity
                    # pitch 限制在 ±89 度
                    if pitch > 89.0:
                        pitch = 89.0
                    elif pitch < -89.0:
                        pitch = -89.0

                    msg = f"Y{yaw:.1f},P{pitch:.1f}\n"
                    ser.write(msg.encode())

                    pyautogui.moveTo(center_x, center_y)
            elif not use_pyautogui and not paused:
                # Windows Raw Input 模式：用 GetCursorPos 做相对位移
                pt = ctypes.wintypes.POINT()
                ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
                if last_x is not None and last_y is not None:
                    dx = pt.x - last_x
                    dy = pt.y - last_y
                    if dx != 0 or dy != 0:
                        yaw += dx * sensitivity
                        pitch += dy * sensitivity
                        if pitch > 89.0:
                            pitch = 89.0
                        elif pitch < -89.0:
                            pitch = -89.0

                        msg = f"Y{yaw:.1f},P{pitch:.1f}\n"
                        ser.write(msg.encode())
                last_x, last_y = pt.x, pt.y

            # 读取串口回显数据（调试用）
            if ser.in_waiting:
                rx = ser.read(ser.in_waiting)
                try:
                    print(f"[MCU] {rx.decode(errors='replace').strip()}")
                except:
                    pass

            time.sleep(0.016)  # ~60Hz

    except KeyboardInterrupt:
        print("\n退出")
    finally:
        ser.close()


if __name__ == "__main__":
    main()
