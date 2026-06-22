Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

$proc = Get-Process -Name "mobile" -ErrorAction SilentlyContinue
if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
    [Win32]::ShowWindow($proc.MainWindowHandle, 9) # SW_RESTORE
    [Win32]::SetForegroundWindow($proc.MainWindowHandle)
    Start-Sleep -Seconds 2

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap(1440, 900)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $path = "C:\Users\rober\.gemini\antigravity\brain\36138514-a34a-4288-8b61-6da62f8d9db7\app_screenshot_front.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $gfx.Dispose()
    $bmp.Dispose()
    Write-Output "Screenshot captured: $path"
}
else {
    Write-Output "Process 'mobile' not found or no window handle."
    Get-Process | Where-Object { $_.MainWindowTitle -like "*coliseu*" -or $_.MainWindowTitle -like "*mobile*" -or $_.MainWindowTitle -like "*sales*" } | Format-Table Id, ProcessName, MainWindowTitle
}
