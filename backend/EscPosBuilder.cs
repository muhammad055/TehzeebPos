using System.Text;

// Small fluent builder for raw ESC/POS byte streams. Kept deliberately minimal —
// only the commands the receipt/kitchen-token layouts actually need.
public class EscPosBuilder
{
    // Safe default for Font A on 80mm paper across generic ESC/POS clones.
    public const int LineWidth = 42;

    private readonly List<byte> _buf = new();

    public EscPosBuilder Init()
    {
        _buf.AddRange(new byte[] { 0x1B, 0x40 }); // ESC @
        return this;
    }

    public EscPosBuilder Align(char which) // 'l' | 'c' | 'r'
    {
        byte n = which switch { 'c' => 1, 'r' => 2, _ => 0 };
        _buf.AddRange(new byte[] { 0x1B, 0x61, n }); // ESC a n
        return this;
    }

    public EscPosBuilder Bold(bool on)
    {
        _buf.AddRange(new byte[] { 0x1B, 0x45, (byte)(on ? 1 : 0) }); // ESC E n
        return this;
    }

    public EscPosBuilder DoubleSize(bool on)
    {
        _buf.AddRange(new byte[] { 0x1D, 0x21, (byte)(on ? 0x11 : 0x00) }); // GS ! n (x2 width+height, or normal)
        return this;
    }

    public EscPosBuilder Feed(int lines = 1)
    {
        for (int i = 0; i < lines; i++) _buf.Add(0x0A);
        return this;
    }

    // Pulses the cash drawer connected to the printer's drawer-kick port.
    // pin 0 = the standard/most common wiring (RJ11 pin 2); some drawers are
    // wired to pin 5 (pin: 1) instead — try that if this doesn't trigger it.
    public EscPosBuilder KickDrawer(int pin = 0)
    {
        _buf.AddRange(new byte[] { 0x1B, 0x70, (byte)pin, 25, 250 }); // ESC p m t1 t2
        return this;
    }

    // Feed comfortably past the print-head-to-cutter gap before cutting, or the
    // blade slices through content that hasn't cleared the mechanism yet and
    // most of the receipt stays trapped inside instead of ejecting.
    public const int CutFeedLines = 8;

    public EscPosBuilder Cut()
    {
        Feed(CutFeedLines);
        _buf.AddRange(new byte[] { 0x1D, 0x56, 0x00 }); // GS V 0 — full cut
        return this;
    }

    public EscPosBuilder Raw(byte[] bytes)
    {
        _buf.AddRange(bytes);
        return this;
    }

    public EscPosBuilder Text(string s)
    {
        _buf.AddRange(Encoding.ASCII.GetBytes(Sanitize(s)));
        return this;
    }

    public EscPosBuilder Line(string s = "") => Text(s).Feed();

    public EscPosBuilder Divider(char c = '-', int width = LineWidth) => Line(new string(c, width));

    public EscPosBuilder TwoCol(string left, string right, int width = LineWidth)
    {
        left = Sanitize(left);
        right = Sanitize(right);
        int rightWidth = Math.Min(right.Length, width);
        right = right.Length > width ? right[..width] : right;
        int leftWidth = width - rightWidth;
        if (left.Length > leftWidth) left = left.Length > 0 && leftWidth > 0 ? left[..leftWidth] : "";
        return Line(left.PadRight(leftWidth) + right.PadLeft(rightWidth));
    }

    public EscPosBuilder FourCol(string c1, string c2, string c3, string c4, int w1, int w2, int w3, int w4)
    {
        string Fit(string s, int w, bool right)
        {
            s = Sanitize(s);
            if (s.Length > w) s = w > 0 ? s[..w] : "";
            return right ? s.PadLeft(w) : s.PadRight(w);
        }
        return Line(Fit(c1, w1, false) + Fit(c2, w2, true) + Fit(c3, w3, true) + Fit(c4, w4, true));
    }

    public byte[] ToBytes() => _buf.ToArray();

    // Maps common punctuation to ASCII equivalents and drops anything else
    // outside the printable ASCII range — these generic clone controllers
    // can't be relied on for a working Unicode/Arabic codepage table.
    private static string Sanitize(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;
        var sb = new StringBuilder(s.Length);
        foreach (var ch in s)
        {
            char c = ch switch
            {
                '·' or '•' => '-',              // · •
                '–' or '—' => '-',              // – —
                '‘' or '’' => '\'',              // ‘ ’
                '“' or '”' => '"',                // “ ”
                _ => ch
            };
            if (c >= 0x20 && c <= 0x7E) sb.Append(c);
        }
        return sb.ToString();
    }
}
