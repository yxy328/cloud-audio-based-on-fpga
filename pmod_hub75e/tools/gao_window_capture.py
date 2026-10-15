"""Capture a verified Gowin application window for local GAO diagnostics."""
import argparse
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import time

from PIL import ImageGrab


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    user = ctypes.WinDLL('user32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    user.SetProcessDPIAware()
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    process = kernel.OpenProcess(0x1000, False, args.pid)
    if not process:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        name = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(name))
        if not kernel.QueryFullProcessImageNameW(process, 0, name, ctypes.byref(size)):
            raise ctypes.WinError(ctypes.get_last_error())
        executable = Path(name.value)
    finally:
        kernel.CloseHandle(process)
    if not str(executable).lower().startswith('e:\\130_fpga_verilog\\gowin\\'):
        raise RuntimeError('Target process is outside the Gowin installation')
    windows = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    @callback_type
    def visit(hwnd, _):
        pid = wintypes.DWORD()
        user.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == args.pid and user.IsWindowVisible(hwnd):
            title = ctypes.create_unicode_buffer(1024)
            user.GetWindowTextW(hwnd, title, len(title))
            if title.value:
                rect = wintypes.RECT()
                user.GetWindowRect(hwnd, ctypes.byref(rect))
                windows.append(((rect.right-rect.left)*(rect.bottom-rect.top), hwnd, title.value))
        return True

    user.EnumWindows(visit, 0)
    if not windows:
        raise RuntimeError('No visible Gowin window')
    _, hwnd, title = max(windows)
    user.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
    user.SetForegroundWindow.argtypes = [wintypes.HWND]
    user.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user.GetForegroundWindow.restype = wintypes.HWND
    foreground_pid = wintypes.DWORD()
    user.GetWindowThreadProcessId(user.GetForegroundWindow(), ctypes.byref(foreground_pid))
    if foreground_pid.value != args.pid:
        user.ShowWindow(hwnd, 3)
        user.SetForegroundWindow(hwnd)
        time.sleep(0.1)
        user.GetWindowThreadProcessId(user.GetForegroundWindow(), ctypes.byref(foreground_pid))
        if foreground_pid.value != args.pid:
            # Windows may reject a background process's foreground request.
            # Temporarily share input queues; send no keys to another app.
            current_thread = kernel.GetCurrentThreadId()
            foreground_thread = user.GetWindowThreadProcessId(user.GetForegroundWindow(), None)
            target_thread = user.GetWindowThreadProcessId(hwnd, None)
            user.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
            user.BringWindowToTop.argtypes = [wintypes.HWND]
            attached = []
            try:
                for thread in set((foreground_thread, target_thread)):
                    if thread != current_thread and user.AttachThreadInput(current_thread, thread, True):
                        attached.append(thread)
                user.BringWindowToTop(hwnd)
                user.SetForegroundWindow(hwnd)
            finally:
                for thread in attached:
                    user.AttachThreadInput(current_thread, thread, False)
    time.sleep(0.25)
    foreground_pid = wintypes.DWORD()
    user.GetWindowThreadProcessId(user.GetForegroundWindow(), ctypes.byref(foreground_pid))
    if foreground_pid.value != args.pid:
        raise RuntimeError('Gowin window could not be brought to the foreground')
    rect = wintypes.RECT()
    if not user.GetWindowRect(hwnd, ctypes.byref(rect)):
        raise ctypes.WinError(ctypes.get_last_error())
    bbox = (rect.left, rect.top, rect.right, rect.bottom)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    ImageGrab.grab(bbox=bbox, all_screens=True).save(args.out)
    print(json.dumps({'pid': args.pid, 'hwnd': hwnd, 'title': title, 'bounds': bbox, 'image': str(args.out.resolve())}))


if __name__ == '__main__':
    main()
