@echo off
:: ==============================================================================
:: Re-enables Windows WLAN AutoConfig background scanning
:: Restores normal network search and auto-connection functionality
:: ==============================================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Administrator privileges required. Right-click and select "Run as administrator".
    pause
    exit /b 1
)

echo [*] Re-enabling Wi-Fi background scans on interface "Wi-Fi"...
netsh wlan set autoconfig enabled=yes interface="Wi-Fi"
echo [✓] DONE! Windows Wi-Fi network scanning is restored to normal.
pause
