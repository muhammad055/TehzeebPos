import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';

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

export interface Purchase {
  id: number;
  date: string;
  supplier: string;
  description: string;
  totalAmount: number;
  imagePath?: string;
  category: string;
  attachments: PurchaseAttachment[];
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
  private base = 'http://localhost:5050/api';

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
}
