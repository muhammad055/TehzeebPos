import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, Order } from '../api.service';

@Component({
  selector: 'app-orders',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './orders.component.html',
})
export class OrdersComponent implements OnInit {
  private api = inject(ApiService);

  selectedDate = this.todayIso();
  toDate       = this.todayIso();
  orders: Order[] = [];
  loading = false;
  expandedId: number | null = null;

  ngOnInit() { this.fetchOrders(); }

  todayIso(): string { return new Date().toLocaleDateString('en-CA'); }

  fetchOrders() {
    this.loading = true;
    this.expandedId = null;
    this.api.getOrdersByRange(this.selectedDate, this.toDate).subscribe({
      next: o => { this.orders = o; this.loading = false; },
      error: () => { this.loading = false; },
    });
  }

  get activeOrders(): Order[] {
    return this.orders.filter(o => !o.isCancelled);
  }

  get dayTotal(): number {
    return +this.activeOrders.reduce((s, o) => s + o.grandTotal, 0).toFixed(2);
  }

  toggleExpand(id: number) {
    this.expandedId = this.expandedId === id ? null : id;
  }

  cancelOrder(order: Order) {
    if (order.isCancelled) return;
    if (!confirm(`Cancel order #${order.id}? This will remove it from sales totals but keep it visible here for the record.`)) return;
    const reason = prompt('Reason for cancelling (optional):') ?? '';
    this.api.cancelOrder(order.id, reason).subscribe({
      next: () => this.fetchOrders(),
      error: err => alert(err.error?.message || 'Failed to cancel order.'),
    });
  }

  formatTime(utcStr: string): string {
    const d = new Date(utcStr);
    return new Date(d.getTime() + 4 * 3600 * 1000).toISOString().substring(11, 16);
  }

  private fmtDate(iso: string, short = false): string {
    const [y, m, d] = iso.split('-').map(Number);
    return new Date(y, m - 1, d).toLocaleDateString('en-AE', short
      ? { day: 'numeric', month: 'short', year: 'numeric' }
      : { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  }

  formatSelectedDate(): string {
    if (!this.selectedDate) return '';
    return this.selectedDate === this.toDate
      ? this.fmtDate(this.selectedDate)
      : `${this.fmtDate(this.selectedDate, true)} → ${this.fmtDate(this.toDate, true)}`;
  }

  goToday() {
    this.selectedDate = this.toDate = this.todayIso();
    this.fetchOrders();
  }

  shiftDate(days: number) {
    const shift = (iso: string) => {
      const [y, m, d] = iso.split('-').map(Number);
      return new Date(y, m - 1, d + days).toLocaleDateString('en-CA');
    };
    this.selectedDate = shift(this.selectedDate);
    this.toDate       = shift(this.toDate);
    this.fetchOrders();
  }

  get totalSubtotal(): number { return +this.activeOrders.reduce((s, o) => s + o.subTotal, 0).toFixed(2); }
  get totalDiscount(): number { return +this.activeOrders.reduce((s, o) => s + o.discount, 0).toFixed(2); }
  get totalTax():      number { return +this.activeOrders.reduce((s, o) => s + o.taxTotal, 0).toFixed(2); }

  printSummary() {
    if (!this.activeOrders.length) return;

    const date    = this.formatSelectedDate();
    const fmt2    = (n: number) => n.toFixed(2);
    const multiDay  = this.selectedDate !== this.toDate;
    const uaeDate   = (utcStr: string) => {
      const d = new Date(new Date(utcStr).getTime() + 4 * 3600 * 1000);
      return d.toLocaleDateString('en-AE', { day: 'numeric', month: 'short' });
    };
    const dateCol   = multiDay ? `<th>Date</th>` : '';
    const footSpan  = multiDay ? 5 : 4;

    const rows    = this.activeOrders.map((o, i) => `
      <tr>
        <td>${i + 1}</td>
        <td>#${o.id}</td>
        ${multiDay ? `<td>${uaeDate(o.orderDate)}</td>` : ''}
        <td>${this.formatTime(o.orderDate)}</td>
        <td class="dishes">${o.items.map(it => `${it.dishName} &times;${it.quantity}`).join('<br>')}</td>
        <td class="num">${fmt2(o.subTotal)}</td>
        <td class="num">${o.taxTotal > 0 ? fmt2(o.taxTotal) : '&mdash;'}</td>
        <td class="num bold">${fmt2(o.grandTotal)}</td>
      </tr>`).join('');

    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"/>
<title>Order Summary – ${date}</title>
<style>
  body{font-family:Arial,sans-serif;font-size:12px;color:#000;margin:20px}
  .hdr{display:flex;justify-content:space-between;align-items:flex-start;
       border-bottom:2px solid #222;padding-bottom:12px;margin-bottom:16px}
  .brand{font-size:20px;font-weight:700}
  h1{font-size:16px;margin:4px 0}
  .sub{font-size:11px;color:#555}
  .kpi{text-align:right}.kpi-val{font-size:18px;font-weight:700}
  table{width:100%;border-collapse:collapse;margin-bottom:16px}
  th{background:#f0f0f0;padding:6px 8px;text-align:left;font-size:11px;
     border-bottom:2px solid #bbb}
  td{padding:5px 8px;border-bottom:1px solid #eee;vertical-align:top}
  .dishes{font-size:11px;line-height:1.6}
  .num{text-align:right;font-family:'Courier New',monospace}
  .bold{font-weight:700}
  tfoot tr{background:#f5f5f5;font-weight:700;border-top:2px solid #333}
  .footer{font-size:10px;color:#888;border-top:1px solid #ddd;
          padding-top:8px;margin-top:16px}
  @media print{@page{size:A4;margin:15mm}}
</style></head><body>
<div class="hdr">
  <div>
    <div class="brand">🍽 Tehzeeb POS</div>
    <h1>Order Summary</h1>
    <div class="sub">${date}</div>
  </div>
  <div class="kpi">
    <div class="sub">${this.activeOrders.length} order${this.activeOrders.length !== 1 ? 's' : ''}</div>
    <div class="kpi-val">AED ${fmt2(this.dayTotal)}</div>
  </div>
</div>
<table>
  <thead><tr>
    <th>#</th><th>Order</th>${dateCol}<th>Time</th><th>Dishes</th>
    <th class="num">Subtotal</th><th class="num">Tax</th><th class="num">Grand Total</th>
  </tr></thead>
  <tbody>${rows}</tbody>
  <tfoot><tr>
    <td colspan="${footSpan}">TOTAL — ${this.activeOrders.length} orders</td>
    <td class="num">${fmt2(this.totalSubtotal)}</td>
    <td class="num">${this.totalTax > 0 ? fmt2(this.totalTax) : '&mdash;'}</td>
    <td class="num">AED ${fmt2(this.dayTotal)}</td>
  </tr></tfoot>
</table>
<div class="footer">Printed: ${new Date().toLocaleString('en-AE', { timeZone: 'Asia/Dubai' })}</div>
</body></html>`;

    const win = window.open('', '_blank', 'width=900,height=700');
    if (!win) return;
    win.document.write(html);
    win.document.close();
    win.focus();
    setTimeout(() => win.print(), 300);
  }
}
