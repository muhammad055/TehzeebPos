import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../environments/environment';

export type PricingScheme = 'SingleDouble' | 'QuarterHalfFull';

export interface Dish {
  id: number;
  name: string;
  price: number;
  taxRate: number;
  imagePath?: string;
  isActive: boolean;
  printName?: string | null;
  doublePrice?: number | null;
  thirdPrice?: number | null;
  pricingScheme?: PricingScheme | null;
}

export interface OrderItem {
  dishId: number;
  dishName: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
}

export interface CreateOrder {
  subTotal: number;
  discount: number;
  taxTotal: number;
  grandTotal: number;
  paymentMethod: string;
  items: OrderItem[];
}

export interface Setting {
  key: string;
  value: string;
}

export interface TopItem {
  name: string;
  quantity: number;
  revenue: number;
}

export interface DaySales {
  date: string;
  total: number;
}

export interface Stats {
  todaySales: number;
  todayOrderCount: number;
  weekSales: number;
  monthSales: number;
  todayExpenses: number;
  weekExpenses: number;
  monthExpenses: number;
  todayProfit: number;
  weekProfit: number;
  monthProfit: number;
  topItems: TopItem[];
  last7Days: DaySales[];
}

export interface ReportSummary {
  totalOrders: number;
  totalRevenue: number;
  avgOrderValue: number;
  totalItemsSold: number;
}

export interface ItemBreakdown {
  dishId: number;
  dishName: string;
  qtySold: number;
  revenue: number;
}

export interface DailyReportSale {
  date: string;
  revenue: number;
  orders: number;
}

export interface ReportResult {
  summary: ReportSummary;
  itemBreakdown: ItemBreakdown[];
  dailySales: DailyReportSale[];
}

export interface PurchaseAttachment {
  id: number;
  purchaseId: number;
  imagePath: string;
  uploadedAt: string;
}

export interface ItemPack {
  id: number;
  itemId: number;
  name: string;
  quantity: number;   // base units per pack
  isActive: boolean;
}

export interface Item {
  id: number;
  name: string;
  unit: string;
  isActive: boolean;
  packs: ItemPack[];
}

export interface PurchaseItem {
  id: number;
  itemId: number;
  itemName: string;
  unit: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
  packId: number | null;
  packName: string;
  packs: number | null;
  packPrice: number | null;
}

export interface UsageEntry { itemId: number; quantity: number; note?: string; enteredBy?: string; }
export interface CountResult { itemId: number; name: string; unit: string; counted: number; expected: number; variance: number; }
export interface CountRow { itemId: number; countedQty: number; expectedQty: number; variance: number; note: string; }
export interface OnHandRow {
  itemId: number; name: string; unit: string; isActive: boolean;
  lastCountDate: string | null; lastCountQty: number | null;
  bought: number; used: number; expected: number; avgUnitCost: number; value: number;
}
export interface StockReportRow {
  itemId: number; name: string; unit: string;
  boughtQty: number; spend: number; avgUnitCost: number;
  usedQty: number; usedValue: number;
  counts: number; netVariance: number; shortageQty: number; shortageValue: number;
}
export interface StockReport { from: string; to: string; totalSpend: number; totalShortageValue: number; items: StockReportRow[]; }

export interface Purchase {
  id: number;
  date: string;
  supplier: string;
  description: string;
  totalAmount: number;
  imagePath?: string;
  category: string;
  attachments: PurchaseAttachment[];
  items: PurchaseItem[];
}

export interface AppUser {
  id: number;
  username: string;
  role: string;
}

export interface ZReportItem  { name: string; qty: number; revenue: number; }

export interface ZReportShift {
  nextReportNumber?: number;
  reportNumber?:     number;
  generatedAt?:      string;
  shiftStart:        string | null;
  totalOrders:       number;
  grossSales:        number;
  discounts:         number;
  taxTotal:          number;
  netSales:          number;
  topItems:          ZReportItem[];
  emailSent?:        boolean;
  emailError?:       string | null;
}

export interface PrintItem {
  dishName: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
}

export interface PrintReceiptPayload {
  orderId: number;
  tokenNumber: number;
  orderDate: string;
  items: PrintItem[];
  subTotal: number;
  discount: number;
  discountPercent: number;
  tax: number;
  taxRate: number;
  applyTax: boolean;
  grandTotal: number;
  paymentMethod: string;
  cashReceived: number;
  change: number;
}

export interface PrintKitchenItem {
  dishName: string;
  quantity: number;
}

export interface PrintKitchenPayload {
  tokenNumber: number;
  orderDate: string;
  items: PrintKitchenItem[];
}

export interface Order {
  id: number;
  orderDate: string;
  tokenNumber: number;
  subTotal: number;
  discount: number;
  taxTotal: number;
  grandTotal: number;
  items: OrderItem[];
  isCancelled: boolean;
  cancelledAt?: string | null;
  cancelReason?: string | null;
}

@Injectable({ providedIn: 'root' })
export class ApiService {
  private http = inject(HttpClient);
  private base = environment.apiBase;

  // Settings
  getSettings() { return this.http.get<Setting[]>(`${this.base}/settings`); }
  updateSetting(key: string, value: string) {
    return this.http.put(`${this.base}/settings/${key}`, { value });
  }

  // Dishes
  getDishes() { return this.http.get<Dish[]>(`${this.base}/dishes`); }
  createDish(d: Omit<Dish, 'id' | 'isActive'>) { return this.http.post<Dish>(`${this.base}/dishes`, d); }
  updateDish(id: number, d: Omit<Dish, 'id' | 'isActive'>) { return this.http.put<Dish>(`${this.base}/dishes/${id}`, d); }
  toggleDish(id: number) { return this.http.patch<Dish>(`${this.base}/dishes/${id}/toggle`, {}); }
  toggleAllDishes(isActive: boolean) { return this.http.patch<Dish[]>(`${this.base}/dishes/toggle-all`, { isActive }); }
  deleteDish(id: number) { return this.http.delete(`${this.base}/dishes/${id}`); }
  uploadDishImage(id: number, formData: FormData) {
    return this.http.post<{ imagePath: string }>(`${this.base}/dishes/${id}/image`, formData);
  }

  // Orders
  createOrder(o: CreateOrder) { return this.http.post<{ id: number; tokenNumber: number }>(`${this.base}/orders`, o); }
  getOrdersByDate(date: string) { return this.http.get<Order[]>(`${this.base}/orders?date=${date}`); }
  cancelOrder(id: number, reason?: string) {
    return this.http.patch<Order>(`${this.base}/orders/${id}/cancel`, { reason: reason || null });
  }

  // Z-Report
  getZReport()  { return this.http.get<ZReportShift>(`${this.base}/z-report`); }
  closeShift()  { return this.http.post<ZReportShift>(`${this.base}/z-report`, {}); }
  getOrdersByRange(from: string, to: string) { return this.http.get<Order[]>(`${this.base}/orders?from=${from}&to=${to}`); }

  // Printing
  printReceipt(p: PrintReceiptPayload) {
    return this.http.post<{ printed: boolean }>(`${this.base}/print/receipt`, p);
  }
  printKitchenToken(p: PrintKitchenPayload) {
    return this.http.post<{ printed: boolean }>(`${this.base}/print/kitchen-token`, p);
  }

  // Print Agent (cloud deployments only — see backend/PrintDispatch.cs)
  getPrintAgentKey() { return this.http.get<{ key: string }>(`${this.base}/printer-agent/key`); }
  regeneratePrintAgentKey() { return this.http.post<{ key: string }>(`${this.base}/printer-agent/regenerate-key`, {}); }
  getPrintAgentStatus() { return this.http.get<{ connected: boolean }>(`${this.base}/printer-agent/status`); }

  // Stats
  getStats() { return this.http.get<Stats>(`${this.base}/stats`); }

  // Reports
  getReport(from: string, to: string, dishId?: number) {
    let url = `${this.base}/reports?from=${from}&to=${to}`;
    if (dishId) url += `&dishId=${dishId}`;
    return this.http.get<ReportResult>(url);
  }

  // Users (admin)
  getUsers()    { return this.http.get<AppUser[]>(`${this.base}/users`); }
  createUser(u: { username: string; password: string; role: string }) {
    return this.http.post<AppUser>(`${this.base}/users`, u);
  }
  changePassword(id: number, password: string) {
    return this.http.put(`${this.base}/users/${id}/password`, { password });
  }
  deleteUser(id: number) { return this.http.delete(`${this.base}/users/${id}`); }

  // Purchases
  getPurchases(from?: string, to?: string, category?: string) {
    const params: string[] = [];
    if (from) params.push(`from=${from}`);
    if (to)   params.push(`to=${to}`);
    if (category) params.push(`category=${encodeURIComponent(category)}`);
    const qs = params.length ? '?' + params.join('&') : '';
    return this.http.get<Purchase[]>(`${this.base}/purchases${qs}`);
  }
  createPurchase(fd: FormData) { return this.http.post<Purchase>(`${this.base}/purchases`, fd); }
  updatePurchase(id: number, fd: FormData) { return this.http.put<Purchase>(`${this.base}/purchases/${id}`, fd); }
  deletePurchase(id: number) { return this.http.delete(`${this.base}/purchases/${id}`); }

  addPurchaseAttachments(id: number, files: File[]) {
    const fd = new FormData();
    files.forEach(f => fd.append('file', f, f.name));
    return this.http.post<PurchaseAttachment[]>(`${this.base}/purchases/${id}/attachments`, fd);
  }
  deletePurchaseAttachment(purchaseId: number, attachmentId: number) {
    return this.http.delete(`${this.base}/purchases/${purchaseId}/attachments/${attachmentId}`);
  }

  // Inventory items (readable by every role; writes are admin-only on the server)
  readonly units = ['kg', 'g', 'L', 'ml', 'pcs', 'dozen', 'pack'];
  getItems(includeInactive = false) {
    return this.http.get<Item[]>(`${this.base}/items${includeInactive ? '?includeInactive=true' : ''}`);
  }
  createItem(name: string, unit: string, packs?: { name: string; quantity: number }[]) {
    return this.http.post<Item>(`${this.base}/items`, { name, unit, packs });
  }
  createPack(itemId: number, name: string, quantity: number) {
    return this.http.post<ItemPack>(`${this.base}/items/${itemId}/packs`, { name, quantity });
  }
  updatePack(itemId: number, packId: number, name: string, quantity: number, isActive?: boolean) {
    return this.http.put<ItemPack>(`${this.base}/items/${itemId}/packs/${packId}`, { name, quantity, isActive });
  }
  deletePack(itemId: number, packId: number) {
    return this.http.delete<{ deactivated: boolean }>(`${this.base}/items/${itemId}/packs/${packId}`);
  }
  updateItem(id: number, name: string, unit: string, isActive?: boolean) {
    return this.http.put<Item>(`${this.base}/items/${id}`, { name, unit, isActive });
  }
  deleteItem(id: number) { return this.http.delete<{ deactivated: boolean }>(`${this.base}/items/${id}`); }

  // Daily usage + physical counts (any role); on-hand + report (admin)
  getUsage(date: string) {
    return this.http.get<{ date: string; entries: UsageEntry[] }>(`${this.base}/stock/usage?date=${date}`);
  }
  saveUsage(date: string, entries: UsageEntry[]) {
    return this.http.put<{ saved: number }>(`${this.base}/stock/usage`, { date, entries });
  }
  getCounts(date: string) {
    return this.http.get<{ date: string; entries: CountRow[] }>(`${this.base}/stock/counts?date=${date}`);
  }
  saveCounts(date: string, entries: { itemId: number; countedQty: number; note?: string }[]) {
    return this.http.post<{ date: string; results: CountResult[] }>(`${this.base}/stock/counts`, { date, entries });
  }
  getOnHand(asOf?: string) {
    return this.http.get<{ asOf: string; items: OnHandRow[] }>(`${this.base}/stock/on-hand${asOf ? '?asOf=' + asOf : ''}`);
  }
  getStockReport(from: string, to: string) {
    return this.http.get<StockReport>(`${this.base}/stock/report?from=${from}&to=${to}`);
  }
}
