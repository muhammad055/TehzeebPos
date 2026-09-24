using System.Runtime.Versioning;

// Builds the raw ESC/POS byte streams for the customer receipt and kitchen
// token, mirroring the layout that used to live in pos.component.html's
// print-only blocks.
[SupportedOSPlatform("windows")]
public static class ReceiptPrinter
{
    public static byte[] BuildCustomerReceipt(PrintReceiptDto dto)
    {
        var b = new EscPosBuilder();
        b.Init();

        if (string.Equals(dto.PaymentMethod, "Cash", StringComparison.OrdinalIgnoreCase))
            b.KickDrawer();

        b.Align('c');

        var logo = LogoImage.GetReceiptLogoBytes();
        if (logo.Length > 0) b.Raw(logo).Feed(1);
        else b.DoubleSize(true).Bold(true).Line("TEHZEEB RESTAURANT").Bold(false).DoubleSize(false);

        b.Line("Restaurant & Kitchen - Ajman, UAE");
        b.Line("Tel: 0509901368");
        b.Line(dto.OrderDate);
        b.Line($"Order #{dto.OrderId}");
        b.DoubleSize(true).Bold(true).Line($"TOKEN #{dto.TokenNumber:000}").Bold(false).DoubleSize(false);
        b.Feed(1);

        b.Align('l');
        b.Divider();
        b.Bold(true).FourCol("ITEM", "QTY", "PRICE", "TOTAL", 18, 4, 10, 10).Bold(false);
        foreach (var item in dto.Items)
        {
            b.FourCol(item.DishName, item.Quantity.ToString(), item.UnitPrice.ToString("F2"), item.LineTotal.ToString("F2"), 18, 4, 10, 10);
        }
        b.Divider();

        b.TwoCol("Subtotal", $"AED {dto.SubTotal:F2}");
        if (dto.Discount > 0)
            b.TwoCol($"Discount ({dto.DiscountPercent:0.##}%)", $"-AED {dto.Discount:F2}");
        b.Bold(true).TwoCol("TOTAL", $"AED {dto.GrandTotal:F2}").Bold(false);
        if (dto.ApplyTax && dto.Tax > 0)
            b.TwoCol($"incl. VAT ({dto.TaxRate:0.##}%)", $"AED {dto.Tax:F2}");
        b.Divider();

        b.TwoCol("Payment", dto.PaymentMethod);
        if (string.Equals(dto.PaymentMethod, "Cash", StringComparison.OrdinalIgnoreCase))
        {
            b.TwoCol("Cash Received", $"AED {dto.CashReceived:F2}");
            if (dto.Change > 0)
                b.Bold(true).TwoCol("Change", $"AED {dto.Change:F2}").Bold(false);
        }

        b.Feed(1).Align('c');
        b.Line("Thank you for dining with us!");
        b.Line("Shukran!");
        b.Cut();

        return b.ToBytes();
    }

    public static byte[] BuildKitchenToken(PrintKitchenDto dto)
    {
        var b = new EscPosBuilder();
        b.Init().Align('c');

        b.Bold(true).Line("KITCHEN ORDER").Bold(false);
        b.DoubleSize(true).Bold(true).Line($"#{dto.TokenNumber:000}").Bold(false).DoubleSize(false);
        b.Line(dto.OrderDate);
        b.Feed(1);
        b.Divider();

        b.Align('l');
        foreach (var item in dto.Items)
            b.Bold(true).Line($"{item.Quantity}x {item.DishName}").Bold(false);
        b.Divider();

        b.Align('c');
        b.Line("** KITCHEN COPY **");
        b.Cut();

        return b.ToBytes();
    }
}
