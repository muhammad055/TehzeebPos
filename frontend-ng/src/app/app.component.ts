import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { AuthService } from './auth.service';
import { LanguageService } from './language.service';
import { ThemeService, THEMES } from './theme.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <nav class="navbar no-print" *ngIf="auth.isLoggedIn()">
      <div class="nav-brand">
        <img src="/TL.png" alt="Tehzeeb Restaurant" class="nav-logo">
        <span class="brand-name">Tehzeeb POS</span>
      </div>
      <div class="nav-links">
        <a routerLink="/dashboard" routerLinkActive="active">Dashboard</a>
        <a routerLink="/pos"       routerLinkActive="active">Sales</a>
        <a routerLink="/expenses"  routerLinkActive="active">Expenses</a>
        <a routerLink="/orders"    routerLinkActive="active" *ngIf="auth.isAdmin()">Orders</a>
        <a routerLink="/admin"     routerLinkActive="active" *ngIf="auth.isAdmin()">Menu Setup</a>
        <a routerLink="/reports"   routerLinkActive="active" *ngIf="auth.isAdmin()">Reports</a>
        <a routerLink="/users"     routerLinkActive="active" *ngIf="auth.isAdmin()">Users</a>
      </div>
      <div class="nav-user">
        <select class="theme-select" title="Theme" [ngModel]="theme.theme()" (ngModelChange)="theme.set($event)">
          <option *ngFor="let t of themes" [value]="t.id">{{ t.label }}</option>
        </select>
        <div class="lang-toggle" title="Menu/Sales display language">
          <button [class.lang-toggle-btn--active]="lang.lang() === 'ur'" (click)="lang.set('ur')">اردو</button>
          <button [class.lang-toggle-btn--active]="lang.lang() === 'en'" (click)="lang.set('en')">EN</button>
        </div>
        <span class="nav-username">{{ auth.getUser()?.username }}</span>
        <span class="nav-role-badge" [class.role-admin]="auth.isAdmin()">
          {{ auth.getUser()?.role }}
        </span>
        <button class="btn btn-ghost btn-sm" (click)="auth.logout()">Sign Out</button>
      </div>
    </nav>
    <main>
      <router-outlet />
    </main>
  `,
})
export class AppComponent {
  auth = inject(AuthService);
  lang = inject(LanguageService);
  theme = inject(ThemeService);
  themes = THEMES;
}
