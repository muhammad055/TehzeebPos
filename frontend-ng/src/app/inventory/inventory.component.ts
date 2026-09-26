import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, Item, ItemPack, OnHandRow, StockReport } from '../api.service';

/** Admin/owner inventory: stock on hand, the purchases-vs-usage report, and the item list. */
@Component({
  selector: 'app-inventory',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
<div class="page-container">
  <div class="page-header">
    <h1>Inventory</h1>
    <p class="page-subtitle">Expected stock = last count + bought − used. Counts show where stock goes missing.</p>
  </div>

  <div class="settings-tabs">
    <button class="settings-tab-btn" [class.active]="tab === 'onhand'" (click)="setTab('onhand')">Stock on hand</button>
    <button class="settings-tab-btn" [class.active]="tab === 'report'" (click)="setTab('report')">Report</button>
    <button class="settings-tab-btn" [class.active]="tab === 'items'" (click)="setTab('items')">Items</button>
  </div>

  <!-- ON HAND -->
  <div class="card" *ngIf="tab === 'onhand'">
    <div class="rpt-filter-row">
      <div class="rpt-field">
        <label class="field-label">As of</label>
        <input type="date" [(ngModel)]="asOf" (change)="loadOnHand()" />
      </div>
      <div class="rpt-field" *ngIf="onHand.length">
        <label class="field-label">Stock value</label>
        <strong>AED {{ stockValue | number:'1.2-2' }}</strong>
      </div>
    </div>
    <p class="empty-state" *ngIf="!onHand.length">No items yet. Add items on the Items tab or from a bill.</p>
    <table class="dish-table" *ngIf="onHand.length">
      <thead>
        <tr><th>Item</th><th>Last count</th><th>Bought since</th><th>Used since</th><th>Expected now</th><th>Avg cost</th><th>Value</th></tr>
      </thead>
      <tbody>
        <tr *ngFor="let r of onHand">
          <td><strong>{{ r.name }}</strong> <span class="field-hint" *ngIf="!r.isActive">(inactive)</span></td>
          <td>
            <span *ngIf="r.lastCountDate; else nocount">{{ r.lastCountQty | number:'1.0-3' }} {{ r.unit }}
              <span class="field-hint">{{ r.lastCountDate }}</span></span>
            <ng-template #nocount><span class="field-hint">never counted</span></ng-template>
          </td>
          <td>{{ r.bought | number:'1.0-3' }} {{ r.unit }}</td>
          <td>{{ r.used | number:'1.0-3' }} {{ r.unit }}</td>
          <td [style.color]="r.expected < 0 ? 'var(--danger)' : null">
            <strong>{{ r.expected | number:'1.0-3' }} {{ r.unit }}</strong>
            <span class="field-hint" *ngIf="r.expected < 0"> — used more than bought</span>
          </td>
          <td>{{ r.avgUnitCost | number:'1.2-2' }}</td>
          <td>{{ r.value | number:'1.2-2' }}</td>
        </tr>
      </tbody>
    </table>
  </div>

  <!-- REPORT -->
  <div class="card" *ngIf="tab === 'report'">
    <div class="rpt-filter-row">
      <div class="rpt-field"><label class="field-label">From</label><input type="date" [(ngModel)]="from" /></div>
      <div class="rpt-field"><label class="field-label">To</label><input type="date" [(ngModel)]="to" /></div>
      <div class="rpt-field rpt-field--btn"><label class="field-label">&nbsp;</label><button class="btn btn-primary" (click)="loadReport()">Apply</button></div>
    </div>
    <div class="purch-summary-strip" *ngIf="report">
      <span class="purch-summary-item"><span class="purch-summary-label">Spent on items</span>
        <span class="purch-summary-value">AED {{ report.totalSpend | number:'1.2-2' }}</span></span>
      <span class="purch-summary-sep">·</span>
      <span class="purch-summary-item"><span class="purch-summary-label">Lost to shortages</span>
        <span class="purch-summary-value" [style.color]="report.totalShortageValue < 0 ? 'var(--danger)' : null">
          AED {{ -report.totalShortageValue | number:'1.2-2' }}</span></span>
    </div>
    <p class="empty-state" *ngIf="report && !report.items.length">Nothing recorded in this period.</p>
    <table class="dish-table" *ngIf="report?.items?.length">
      <thead>
        <tr><th>Item</th><th>Bought</th><th>Spent</th><th>Avg price</th><th>Used</th><th>Counts</th><th>Shortage</th><th>Loss</th></tr>
      </thead>
      <tbody>
        <tr *ngFor="let r of report!.items">
          <td><strong>{{ r.name }}</strong></td>
          <td>{{ r.boughtQty | number:'1.0-3' }} {{ r.unit }}</td>
          <td>{{ r.spend | number:'1.2-2' }}</td>
          <td>{{ r.avgUnitCost | number:'1.2-2' }}</td>
          <td>{{ r.usedQty | number:'1.0-3' }} {{ r.unit }}</td>
          <td>{{ r.counts }}</td>
          <td [style.color]="r.shortageQty < 0 ? 'var(--danger)' : null">
            {{ r.shortageQty < 0 ? (-r.shortageQty | number:'1.0-3') + ' ' + r.unit : '—' }}</td>
          <td [style.color]="r.shortageValue < 0 ? 'var(--danger)' : null">
            {{ r.shortageValue < 0 ? (-r.shortageValue | number:'1.2-2') : '—' }}</td>
        </tr>
      </tbody>
    </table>
  </div>

  <!-- ITEMS -->
  <div class="admin-grid" *ngIf="tab === 'items'">
    <div class="admin-sidebar">
      <div class="card">
        <h3 class="card-title">{{ editingId ? 'Edit item' : 'Add item' }}</h3>
        <label class="field-label">Name</label>
        <input type="text" [(ngModel)]="form.name" placeholder="e.g. Chicken" />
        <label class="field-label">Unit</label>
        <select [(ngModel)]="form.unit">
          <option *ngFor="let u of api.units" [value]="u">{{ u }}</option>
        </select>
        <div class="btn-row">
          <button class="btn btn-primary" style="flex:1" (click)="saveItem()" [disabled]="!form.name.trim()">
            {{ editingId ? 'Update' : 'Add item' }}</button>
          <button class="btn btn-ghost" *ngIf="editingId" (click)="cancelEdit()">Cancel</button>
        </div>
        <p class="field-hint" style="margin-top:10px">
          An item's unit can't change once it has bills, usage or counts. Items with history are
          hidden instead of deleted, so old records still make sense.</p>
      </div>

      <div class="card" *ngIf="editingItem as it" style="margin-top:14px">
        <h3 class="card-title">Packet sizes for {{ it.name }}</h3>
        <p class="field-hint">How this item is bought. On a bill, staff pick the packet and type how many —
          the app works out the total in {{ it.unit }}.</p>
        <div class="pack-list">
          <div class="pack-row" *ngFor="let pk of it.packs" [class.pack-row--off]="!pk.isActive">
            <span><strong>{{ pk.name }}</strong> — {{ pk.quantity | number:'1.0-3' }} {{ it.unit }}
              <span class="field-hint" *ngIf="!pk.isActive">(hidden)</span></span>
            <span class="pack-row-actions">
              <button class="icon-btn" title="Edit" (click)="startEditPack(pk)">✏️</button>
              <button class="icon-btn" *ngIf="!pk.isActive" title="Show again" (click)="setPackActive(it, pk, true)">👁</button>
              <button class="icon-btn danger" title="Remove" (click)="removePack(it, pk)">🗑</button>
            </span>
          </div>
          <p class="empty-state" *ngIf="!it.packs.length">No packet sizes yet — it can still be bought loose.</p>
        </div>
        <label class="field-label">{{ editingPackId ? 'Edit packet size' : 'Add packet size' }}</label>
        <input type="text" [(ngModel)]="packForm.name" placeholder="e.g. Packet of 10 birds" />
        <div class="input-group compact">
          <input type="number" [(ngModel)]="packForm.size" min="0" step="0.001" placeholder="How many in one packet" style="margin-bottom:0" />
          <span class="input-suffix">{{ it.unit }}</span>
        </div>
        <div class="btn-row" style="margin-top:10px">
          <button class="btn btn-primary btn-sm" (click)="savePack(it)"
                  [disabled]="!packForm.name.trim() || !packForm.size || packForm.size <= 0">
            {{ editingPackId ? 'Update packet' : 'Add packet' }}</button>
          <button class="btn btn-ghost btn-sm" *ngIf="editingPackId" (click)="cancelPackEdit()">Cancel</button>
        </div>
      </div>
    </div>
    <div class="dish-table-wrap card">
      <p class="empty-state" *ngIf="!items.length">No items yet.</p>
      <table class="dish-table" *ngIf="items.length">
        <thead><tr><th>Item</th><th>Unit</th><th>Packet sizes</th><th>Status</th><th></th></tr></thead>
        <tbody>
          <tr *ngFor="let i of items" [class.editing-row]="editingId === i.id">
            <td><strong>{{ i.name }}</strong></td>
            <td>{{ i.unit }}</td>
            <td class="field-hint">{{ packSummary(i) }}</td>
            <td>{{ i.isActive ? 'Active' : 'Hidden' }}</td>
            <td class="action-cell">
              <button class="icon-btn" title="Edit" (click)="startEdit(i)">✏️</button>
              <button class="icon-btn" *ngIf="!i.isActive" title="Show again" (click)="setActive(i, true)">👁</button>
              <button class="icon-btn danger" title="Delete / hide" (click)="removeItem(i)">🗑</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</div>
<div class="toast" *ngIf="message">{{ message }}</div>
`,
})
export class InventoryComponent implements OnInit {
  api = inject(ApiService);

  tab: 'onhand' | 'report' | 'items' = 'onhand';
  message = '';

  asOf = this.todayStr();
  onHand: OnHandRow[] = [];

  from = this.monthStart();
  to = this.todayStr();
  report: StockReport | null = null;

  items: Item[] = [];
  editingId: number | null = null;
  form = { name: '', unit: 'kg' };

  ngOnInit() { this.loadOnHand(); }

  private fmt(d: Date) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }
  todayStr() { return this.fmt(new Date()); }
  monthStart() { const d = new Date(); return this.fmt(new Date(d.getFullYear(), d.getMonth(), 1)); }

  get stockValue() { return this.onHand.reduce((s, r) => s + r.value, 0); }

  setTab(t: 'onhand' | 'report' | 'items') {
    this.tab = t;
    if (t === 'onhand') this.loadOnHand();
    if (t === 'report') this.loadReport();
    if (t === 'items') this.loadItems();
  }

  loadOnHand() { this.api.getOnHand(this.asOf).subscribe(r => this.onHand = r.items); }
  loadReport() { this.api.getStockReport(this.from, this.to).subscribe(r => this.report = r); }
  loadItems() { this.api.getItems(true).subscribe(i => this.items = i); }

  editingPackId: number | null = null;
  packForm = { name: '', size: null as number | null };

  get editingItem() { return this.items.find(i => i.id === this.editingId) ?? null; }
  packSummary(i: Item) {
    const active = i.packs.filter(p => p.isActive);
    return active.length ? active.map(p => `${p.name} (${p.quantity})`).join(', ') : '—';
  }

  startEdit(i: Item) { this.editingId = i.id; this.form = { name: i.name, unit: i.unit }; this.cancelPackEdit(); }
  cancelEdit() { this.editingId = null; this.form = { name: '', unit: 'kg' }; this.cancelPackEdit(); }

  startEditPack(pk: ItemPack) { this.editingPackId = pk.id; this.packForm = { name: pk.name, size: pk.quantity }; }
  cancelPackEdit() { this.editingPackId = null; this.packForm = { name: '', size: null }; }

  savePack(it: Item) {
    const name = this.packForm.name.trim();
    const size = this.packForm.size;
    if (!name || !size || size <= 0) return;
    const req = this.editingPackId
      ? this.api.updatePack(it.id, this.editingPackId, name, size)
      : this.api.createPack(it.id, name, size);
    req.subscribe({
      next: () => { this.flash(this.editingPackId ? 'Packet updated.' : 'Packet added.'); this.cancelPackEdit(); this.loadItems(); },
      error: e => this.flash(typeof e.error === 'string' ? e.error : 'Could not save the packet.'),
    });
  }
  setPackActive(it: Item, pk: ItemPack, active: boolean) {
    this.api.updatePack(it.id, pk.id, pk.name, pk.quantity, active).subscribe(() => this.loadItems());
  }
  removePack(it: Item, pk: ItemPack) {
    if (!confirm(`Remove "${pk.name}"? If it is on past bills it will be hidden instead.`)) return;
    this.api.deletePack(it.id, pk.id).subscribe(r => {
      this.flash(r.deactivated ? 'Packet hidden (it is on past bills).' : 'Packet removed.');
      this.loadItems();
    });
  }

  saveItem() {
    const name = this.form.name.trim();
    if (!name) return;
    const req = this.editingId
      ? this.api.updateItem(this.editingId, name, this.form.unit)
      : this.api.createItem(name, this.form.unit);
    req.subscribe({
      next: () => { this.flash(this.editingId ? 'Item updated.' : 'Item added.'); this.cancelEdit(); this.loadItems(); },
      error: e => this.flash(typeof e.error === 'string' ? e.error : 'Could not save item.'),
    });
  }

  setActive(i: Item, active: boolean) {
    this.api.updateItem(i.id, i.name, i.unit, active).subscribe(() => this.loadItems());
  }

  removeItem(i: Item) {
    if (!confirm(`Remove "${i.name}"? If it has history it will be hidden instead.`)) return;
    this.api.deleteItem(i.id).subscribe(r => {
      this.flash(r.deactivated ? 'Item hidden (it has history).' : 'Item deleted.');
      this.loadItems();
    });
  }

  flash(msg: string) {
    this.message = msg;
    setTimeout(() => this.message = '', 2500);
  }
}
