using System.Runtime.InteropServices;
using System.Runtime.Versioning;

// Sends raw ESC/POS byte streams straight to the Windows print spooler using
// the RAW datatype. This bypasses whatever driver is bound to the printer
// queue entirely, so it works regardless of which (possibly wrong) driver
// Windows is using for the device.
[SupportedOSPlatform("windows")]
public static class RawPrinterHelper
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DOCINFOA
    {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string? pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }

    [DllImport("winspool.drv", EntryPoint = "OpenPrinterA", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartDocPrinterA", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In] ref DOCINFOA di);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool WritePrinter(IntPtr hPrinter, byte[] pBytes, int dwCount, out int dwWritten);

    public static void SendBytesToPrinter(string printerName, byte[] bytes)
    {
        if (string.IsNullOrWhiteSpace(printerName))
            throw new ArgumentException("Printer name is empty.");

        if (!OpenPrinter(printerName, out var hPrinter, IntPtr.Zero))
            throw new InvalidOperationException($"Could not open printer \"{printerName}\" (Win32 error {Marshal.GetLastWin32Error()}). Check the exact name in Windows Settings → Printers & scanners.");

        try
        {
            var docInfo = new DOCINFOA
            {
                pDocName = "TehzeebPOS Receipt",
                pOutputFile = null,
                pDataType = "RAW"
            };

            if (!StartDocPrinter(hPrinter, 1, ref docInfo))
                throw new InvalidOperationException($"StartDocPrinter failed (Win32 error {Marshal.GetLastWin32Error()}).");

            try
            {
                if (!StartPagePrinter(hPrinter))
                    throw new InvalidOperationException($"StartPagePrinter failed (Win32 error {Marshal.GetLastWin32Error()}).");

                try
                {
                    if (!WritePrinter(hPrinter, bytes, bytes.Length, out var written) || written != bytes.Length)
                        throw new InvalidOperationException($"WritePrinter failed or wrote {written} of {bytes.Length} bytes (Win32 error {Marshal.GetLastWin32Error()}).");
                }
                finally
                {
                    EndPagePrinter(hPrinter);
                }
            }
            finally
            {
                EndDocPrinter(hPrinter);
            }
        }
        finally
        {
            ClosePrinter(hPrinter);
        }
    }
}
