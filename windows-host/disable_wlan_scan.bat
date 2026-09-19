@echo off
:: ==============================================================================
:: Disables Windows WLAN AutoConfig background scanning
:: Prevents Windows Mobile Hotspot from hopping off-channel every 60 seconds
:: ==============================================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Administrator privileges required. Right-click and select "Run as administrator".
    pause
    exit /b 1
)

echo [*] Disabling Wi-Fi background scans on interface "Wi-Fi"...
netsh wlan set autoconfig enabled=no interface="Wi-Fi"
echo [✓] DONE! Windows Wi-Fi scanning is OFF. Your Hotspot latency is now locked.
pause
