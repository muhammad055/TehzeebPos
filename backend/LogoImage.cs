using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

// Converts the receipt logo (wwwroot/logo-receipt.jpg) into an ESC/POS raster
// bit-image command (GS v 0), cached after the first call since the source
// file doesn't change while the process is running. This is a separate,
// higher-detail image from the one used on the website (src/TL.png) — it
// was supplied specifically for print use, with a bigger "TEHZEEB" wordmark
// so the text survives the resize to raster width.
[SupportedOSPlatform("windows")]
public static class LogoImage
{
    // 384px is a safe raster width across generic 80mm ESC/POS clones —
    // wider rasters risk being clipped or wrapped on printers with a
    // narrower physical dot area than advertised.
    private const int TargetWidth = 384;
    private const int BlackThreshold = 175; // 0-255 luminance; below this prints black

    private static byte[]? _cached;

    public static byte[] GetReceiptLogoBytes()
    {
        if (_cached != null) return _cached;

        var path = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", "logo-receipt.jpg");
        if (!File.Exists(path))
            return _cached = Array.Empty<byte>();

        using var source = new Bitmap(path);
        var height = Math.Max(1, (int)Math.Round(source.Height * (TargetWidth / (double)source.Width)));

        using var resized = new Bitmap(TargetWidth, height);
        using (var g = Graphics.FromImage(resized))
        {
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.DrawImage(source, 0, 0, TargetWidth, height);
        }

        int widthBytes = (TargetWidth + 7) / 8;
        var data = new byte[widthBytes * height];

        var bmpData = resized.LockBits(new Rectangle(0, 0, TargetWidth, height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var rowBytes = new byte[bmpData.Stride];
            for (int y = 0; y < height; y++)
            {
                Marshal.Copy(bmpData.Scan0 + y * bmpData.Stride, rowBytes, 0, bmpData.Stride);
                for (int x = 0; x < TargetWidth; x++)
                {
                    byte b = rowBytes[x * 4];
                    byte g2 = rowBytes[x * 4 + 1];
                    byte r = rowBytes[x * 4 + 2];
                    byte a = rowBytes[x * 4 + 3];
                    // Transparent pixels print as white (unset bit).
                    int luminance = a == 0 ? 255 : (int)(0.299 * r + 0.587 * g2 + 0.114 * b);
                    if (luminance < BlackThreshold)
                    {
                        int byteIndex = y * widthBytes + (x / 8);
                        data[byteIndex] |= (byte)(0x80 >> (x % 8));
                    }
                }
            }
        }
        finally
        {
            resized.UnlockBits(bmpData);
        }

        var xL = (byte)(widthBytes & 0xFF);
        var xH = (byte)((widthBytes >> 8) & 0xFF);
        var yL = (byte)(height & 0xFF);
        var yH = (byte)((height >> 8) & 0xFF);

        var cmd = new byte[8 + data.Length];
        cmd[0] = 0x1D; cmd[1] = 0x76; cmd[2] = 0x30; cmd[3] = 0x00; // GS v 0, m=0 (normal)
        cmd[4] = xL; cmd[5] = xH; cmd[6] = yL; cmd[7] = yH;
        Buffer.BlockCopy(data, 0, cmd, 8, data.Length);

        return _cached = cmd;
    }
}
