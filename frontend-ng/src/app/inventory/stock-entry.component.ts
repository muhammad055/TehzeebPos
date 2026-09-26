import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, CountResult, Item } from '../api.service';
import { AuthService } from '../auth.service';

interface Row { item: Item; qty: number | null; note: string; had: boolean; }

/**
 * Kitchen-facing entry screen (any signed-in role): the day-end usage list and the
 * periodic physical stock count. Deliberately shows no expected-stock figures to
 * non-admins, so a count can't be nudged towards what the system expects.
 */
@Component({
  selector: 'app-stock-entry',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
<div class="page-container">
  <div class="page-header">
    <h1>Stock Entry</h1>
    <p class="page-subtitle">Record what the kitchen used today, or count what is on the shelf</p>
  </div>

  <div class="settings-tabs">
    <button class="settings-tab-btn" [class.active]="tab === 'usage'" (click)="setTab('usage')">Daily usage</button>
    <button class="settings-tab-btn" [class.active]="tab === 'count'" (click)="setTab('count')">Stock count</button>
  </div>

  <div class="card">
    <div class="rpt-filter-row">
      <div class="rpt-field">
        <label class="field-label">Date</label>
        <input type="date" [(ngModel)]="date" (change)="loadDay()" />
      </div>
      <div class="rpt-field rpt-field--wide">
        <label class="field-label">&nbsp;</label>
        <span class="field-hint" *ngIf="tab === 'usage'">Enter the quantity used today for each item. Leave blank for items not used.</span>
        <span class="field-hint" *ngIf="tab === 'count'">Enter what is physically on the shelf right now. Leave blank for items you did not count.</span>
      </div>
    </div>

    <p class="empty-state" *ngIf="!rows.length && !loading">No items yet. Ask a manager to add items (or add them on a bill).</p>

    <table class="dish-table stock-table" *ngIf="rows.length">
      <thead>
        <tr>
          <th>Item</th>
          <th>{{ tab === 'usage' ? 'Used' : 'Counted' }}</th>
          <th>{{ tab === 'usage' ? 'Used in (dishes)' : 'Note' }}</th>
        </tr>
      </thead>
      <tbody>
        <tr *ngFor="let r of rows">
          <td><strong>{{ r.item.name }}</strong></td>
          <td>
            <div class="input-group compact">
              <input type="number" min="0" step="0.001" [(ngModel)]="r.qty" placeholder="0" style="margin-bottom:0" />
              <span class="input-suffix">{{ r.item.unit }}</span>
            </div>
          </td>
          <td><input type="text" [(ngModel)]="r.note" [placeholder]="tab === 'usage' ? 'e.g. biryani, korma' : 'optional'" style="margin-bottom:0" /></td>
        </tr>
      </tbody>
    </table>

    <div class="btn-row" *ngIf="rows.length" style="margin-top:14px">
      <button class="btn btn-primary" (click)="save()" [disabled]="saving">
        {{ saving ? 'Saving…' : (tab === 'usage' ? 'Save usage' : 'Save count') }}
      </button>
    </div>
  </div>

  <!-- Count result: admins see how it compares with expected stock -->
  <div class="card" *ngIf="results.length && auth.isAdmin()" style="margin-top:16px">
    <h3 class="card-title">Count result</h3>
    <table class="dish-table">
      <thead><tr><th>Item</th><th>Expected</th><th>Counted</th><th>Difference</th></tr></thead>
      <tbody>
        <tr *ngFor="let r of results">
          <td>{{ r.name }}</td>
          <td>{{ r.expected | number:'1.0-3' }} {{ r.unit }}</td>
          <td>{{ r.counted | number:'1.0-3' }} {{ r.unit }}</td>
          <td [style.color]="r.variance < 0 ? 'var(--danger)' : (r.variance > 0 ? 'var(--warning)' : 'var(--success)')">
            <strong>{{ r.variance > 0 ? '+' : '' }}{{ r.variance | number:'1.0-3' }} {{ r.unit }}</strong>
            <span *ngIf="r.variance < 0"> short</span>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</div>
<div class="toast" *ngIf="message">{{ message }}</div>
`,
})
export class StockEntryComponent implements OnInit {
  private api = inject(ApiService);
  auth = inject(AuthService);

  tab: 'usage' | 'count' = 'usage';
  date = this.todayStr();
  items: Item[] = [];
  rows: Row[] = [];
  results: CountResult[] = [];
  loading = false;
  saving = false;
  message = '';

  ngOnInit() {
    this.api.getItems().subscribe(i => { this.items = i; this.loadDay(); });
  }

  todayStr() {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  setTab(t: 'usage' | 'count') { this.tab = t; this.results = []; this.loadDay(); }

  loadDay() {
    this.loading = true;
    this.results = [];
    const blank = () => this.items.map(item => ({ item, qty: null as number | null, note: '', had: false }));
    if (this.tab === 'usage') {
      this.api.getUsage(this.date).subscribe({
        next: r => {
          this.rows = blank().map(row => {
            const e = r.entries.find(x => x.itemId === row.item.id);
            return e ? { ...row, qty: e.quantity, note: e.note ?? '', had: true } : row;
          });
          this.loading = false;
        },
        error: () => { this.loading = false; },
      });
    } else {
      this.api.getCounts(this.date).subscribe({
        next: r => {
          this.rows = blank().map(row => {
            const e = r.entries.find(x => x.itemId === row.item.id);
            return e ? { ...row, qty: e.countedQty, note: e.note ?? '', had: true } : row;
          });
          this.loading = false;
        },
        error: () => { this.loading = false; },
      });
    }
  }

  save() {
    this.saving = true;
    if (this.tab === 'usage') {
      // A blank box on an item that had a value clears it (sent as 0); otherwise blank = skip.
      const entries = this.rows
        .filter(r => r.qty !== null && r.qty !== undefined || r.had)
        .map(r => ({ itemId: r.item.id, quantity: Number(r.qty ?? 0), note: r.note }));
      this.api.saveUsage(this.date, entries).subscribe({
        next: () => { this.saving = false; this.flash('Usage saved.'); this.loadDay(); },
        error: e => this.fail(e),
      });
    } else {
      const entries = this.rows
        .filter(r => r.qty !== null && r.qty !== undefined && (r.qty as unknown) !== '')
        .map(r => ({ itemId: r.item.id, countedQty: Number(r.qty), note: r.note }));
      if (!entries.length) { this.saving = false; this.flash('Enter at least one count.'); return; }
      this.api.saveCounts(this.date, entries).subscribe({
        next: r => {
          this.saving = false;
          this.results = r.results;
          this.flash('Count saved.');
        },
        error: e => this.fail(e),
      });
    }
  }

  private fail(e: { error?: unknown }) {
    this.saving = false;
    this.flash(typeof e.error === 'string' ? e.error : 'Could not save. Check your connection.');
  }

  flash(msg: string) {
    this.message = msg;
    setTimeout(() => this.message = '', 2500);
  }
}
