import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService, Stats } from '../api.service';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard.component.html',
})
export class DashboardComponent implements OnInit {
  private api = inject(ApiService);

  stats: Stats | null = null;
  loading = true;
  error = false;

  ngOnInit() {
    this.api.getStats().subscribe({
      next: s => { this.stats = s; this.loading = false; },
      error: () => { this.loading = false; this.error = true; },
    });
  }

  get maxBarTotal(): number {
    if (!this.stats?.last7Days?.length) return 1;
    const max = Math.max(...this.stats.last7Days.map(d => +d.total));
    return max > 0 ? max : 1;
  }

  get maxItemQty(): number {
    if (!this.stats?.topItems?.length) return 1;
    return Math.max(...this.stats.topItems.map(i => i.quantity), 1);
  }

  barHeight(total: number): number {
    return Math.max(Math.round((+total / this.maxBarTotal) * 100), total > 0 ? 2 : 0);
  }

  barWidth(qty: number): number {
    return Math.round((qty / this.maxItemQty) * 100);
  }

  profitClass(val: number): string {
    return val >= 0 ? 'pnl-positive' : 'pnl-negative';
  }

  profitSign(val: number): string {
    return val >= 0 ? '+' : '';
  }
}
