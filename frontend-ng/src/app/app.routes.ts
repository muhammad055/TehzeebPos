import { Routes } from '@angular/router';
import { PosComponent } from './pos/pos.component';
import { AdminComponent } from './admin/admin.component';
import { DashboardComponent } from './dashboard/dashboard.component';
import { OrdersComponent } from './orders/orders.component';
import { LoginComponent } from './login/login.component';
import { UsersComponent } from './users/users.component';
import { ReportsComponent } from './reports/reports.component';
import { PurchasesComponent } from './purchases/purchases.component';
import { StockEntryComponent } from './inventory/stock-entry.component';
import { InventoryComponent } from './inventory/inventory.component';
import { authGuard, adminGuard } from './auth.guard';

export const routes: Routes = [
  { path: '', redirectTo: 'login', pathMatch: 'full' },
  { path: 'login',     component: LoginComponent },
  { path: 'dashboard', component: DashboardComponent, canActivate: [authGuard] },
  { path: 'pos',       component: PosComponent,       canActivate: [authGuard] },
  { path: 'orders',    component: OrdersComponent,    canActivate: [authGuard] },
  { path: 'admin',     component: AdminComponent,     canActivate: [adminGuard] },
  { path: 'users',     component: UsersComponent,     canActivate: [adminGuard] },
  { path: 'reports',   component: ReportsComponent,   canActivate: [adminGuard] },
  { path: 'expenses',  component: PurchasesComponent, canActivate: [authGuard] },
  { path: 'stock',     component: StockEntryComponent, canActivate: [authGuard] },
  { path: 'inventory', component: InventoryComponent, canActivate: [adminGuard] },
];
