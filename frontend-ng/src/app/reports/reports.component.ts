import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, Dish, ReportResult, ZReportShift } from '../api.service';

@Component({
  selector: 'app-reports',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './reports.component.html',
})
export class ReportsComponent implements OnInit {
  private api = inject(ApiService);

  fromDate     = '';
  toDate       = '';
  selectedDish = '';
  activePreset = 'today';

  dishes: Dish[]       = [];
  loading              = false;
  result: ReportResult | null = null;

  // ── Z-Report ─────────────────────────────────────
  zPreview:  ZReportShift | null = null;
  zResult:   ZReportShift | null = null;
  zLoading    = false;
  zClosing    = false;
  zLoadError  = false;
  zMessage    = '';
  zExpanded   = true;

  ngOnInit() {
    this.api.getDishes().subscribe(d => this.dishes = d);
    this.applyPreset('today');
    this.loadZPreview();
  }

  loadZPreview() {
    this.zLoading   = true;
    this.zLoadError = false;
    this.api.getZReport().subscribe({
      next:  d => { this.zPreview = d; this.zLoading = false; },
      error: () => { this.zLoading = false; this.zLoadError = true; },
    });
  }

  closeShift() {
    if (!confirm('Close the current shift and generate Z-Report? This resets shift totals.')) return;
    this.zClosing = true;
    this.api.closeShift().subscribe({
      next: r => {
        this.zResult  = r;
        this.zPreview = null;
        this.zClosing = false;
        if (r.emailSent)        this.zMessage = '✓ Z-Report generated and emailed successfully.';
        else if (r.emailError)  this.zMessage = '⚠ Report saved, but email failed: ' + r.emailError;
        else                    this.zMessage = '✓ Z-Report generated. (Email not configured — see Menu Setup.)';
      },
      error: () => this.zClosing = false,
    });
  }

  uaeTime(iso: string | null): string {
    if (!iso) return 'Beginning of records';
    const d = new Date(iso);
    return d.toLocaleString('en-GB', {
      timeZone: 'Asia/Dubai',
      day: '2-digit', month: 'short', year: 'numeric',
      hour: '2-digit', minute: '2-digit'
    }) + ' UAE';
  }

  printZReport() {
    document.body.classList.add('print-zreport');
    setTimeout(() => {
      window.print();
      setTimeout(() => document.body.classList.remove('print-zreport'), 800);
    }, 50);
  }

  applyPreset(p: string) {
    this.activePreset = p;
    const fmt = (d: Date) => d.toISOString().slice(0, 10);
    const today = new Date();

    if (p === 'today') {
      this.fromDate = this.toDate = fmt(today);
    } else if (p === 'yesterday') {
      const y = new Date(today); y.setDate(today.getDate() - 1);
      this.fromDate = this.toDate = fmt(y);
    } else if (p === 'week') {
      const s = new Date(today); s.setDate(today.getDate() - 6);
      this.fromDate = fmt(s); this.toDate = fmt(today);
    } else if (p === 'month') {
      const s = new Date(today.getFullYear(), today.getMonth(), 1);
      this.fromDate = fmt(s); this.toDate = fmt(today);
    }
    this.search();
  }

  onDateChange() {
    this.activePreset = '';
    this.search();
  }

  search() {
    if (!this.fromDate || !this.toDate) return;
    this.loading = true;
    const dishId = this.selectedDish ? +this.selectedDish : undefined;
    this.api.getReport(this.fromDate, this.toDate, dishId).subscribe({
      next:  r => { this.result = r;    this.loading = false; },
      error: () => {                    this.loading = false; },
    });
  }

  get maxRev(): number {
    return Math.max(...(this.result?.dailySales.map(d => d.revenue) ?? [1]), 1);
  }

  barPct(rev: number): string {
    return Math.max(Math.round(rev / this.maxRev * 100), 2) + '%';
  }
}
