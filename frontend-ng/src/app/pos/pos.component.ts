import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, Dish, PricingScheme } from '../api.service';
import { LanguageService } from '../language.service';

export type PortionTier = 'tier1' | 'tier2' | 'tier3';

export interface CartItem {
  dishId: number;
  dishName: string;
  printName?: string | null; // ASCII/English fallback name for receipt/kitchen printing
  imagePath?: string;
  quantity: number;
  unitPrice: number;   // editable override
  originalPrice: number;
  lineTotal: number;
  tier1Price: number;               // base price (Single or Quarter)
  tier2Price?: number | null;       // Double or Half — presence means this dish has multiple prices
  tier3Price?: number | null;       // Full — Quarter/Half/Full dishes only
  pricingScheme?: PricingScheme | null;
  portionTier: PortionTier | null;  // null when the dish has only one price
}

// Button/name labels per pricing scheme. Missing scheme defaults to Single/Double.
const TIER_LABELS: Record<PricingScheme, { tier1: string; tier2: string; tier3: string; btn1: string; btn2: string; btn3: string }> = {
  SingleDouble:    { tier1: 'Single',  tier2: 'Double', tier3: '',     btn1: 'S', btn2: 'D', btn3: '' },
  QuarterHalfFull: { tier1: 'Quarter', tier2: 'Half',   tier3: 'Full', btn1: 'Q', btn2: 'H', btn3: 'F' },
};

@Component({
  selector: 'app-pos',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './pos.component.html',
})
export class PosComponent implements OnInit {
  private api = inject(ApiService);
  lang = inject(LanguageService);

  allDishes: Dish[] = [];
  filtered: Dish[] = [];
  search = '';

  cart: CartItem[] = [];
  globalDiscount = 0;
  applyTax = true;
  customTaxRate: number | null = null;
  defaultTaxRate = 5;

  orderSaved = false;
  lastOrderId:     number | null = null;
  lastTokenNumber: number | null = null;
  saving = false;

  // Payment modal
  payModalOpen    = false;
  payMethod: 'cash' | 'card' | null = null;
  cashTendered: number | null = null;

  // Saved for receipt display after order placed
  receiptPayMethod: 'cash' | 'card' | null = null;
  receiptCashIn    = 0;
  receiptChange    = 0;

  get changeAmount(): number {
    if (this.cashTendered === null) return 0;
    return +Math.max(0, this.cashTendered - this.grandTotal).toFixed(2);
  }

  readonly quickCashAmounts = [10, 20, 50, 100, 200];

  get tokenDisplay(): string {
    return this.lastTokenNumber !== null
      ? String(this.lastTokenNumber).padStart(3, '0')
      : '---';
  }

  // Printer settings
  customerCopies = 1;
  kitchenCopies  = 1;

  // Receipt date snapshot
  receiptDate = '';

  printStatus = '';

  ngOnInit() {
    this.api.getDishes().subscribe(d => {
      this.allDishes = d;
      this.filtered = d.filter(x => x.isActive);
    });
    this.api.getSettings().subscribe(settings => {
      const tax   = settings.find(s => s.key === 'DefaultTaxRate');
      if (tax)   this.defaultTaxRate = +tax.value;
      const cust  = settings.find(s => s.key === 'PrinterCustomerCopies');
      if (cust)  this.customerCopies = +cust.value;
      const kitch = settings.find(s => s.key === 'PrinterKitchenCopies');
      if (kitch) this.kitchenCopies  = +kitch.value;
    });
  }

  filterDishes() {
    const q = this.search.toLowerCase();
    const active = this.allDishes.filter(d => d.isActive);
    this.filtered = q
      ? active.filter(d => d.name.toLowerCase().includes(q) || (d.printName ?? '').toLowerCase().includes(q))
      : active;
  }

  addToCart(dish: Dish) {
    const existing = this.cart.find(c => c.dishId === dish.id);
    if (existing) {
      existing.quantity++;
      this.recalcItem(existing);
    } else {
      this.cart.push({
        dishId: dish.id,
        dishName: dish.name,
        printName: dish.printName,
        imagePath: dish.imagePath,
        quantity: 1,
        unitPrice: dish.price,
        originalPrice: dish.price,
        lineTotal: dish.price,
        tier1Price: dish.price,
        tier2Price: dish.doublePrice,
        tier3Price: dish.thirdPrice,
        pricingScheme: dish.pricingScheme,
        portionTier: dish.doublePrice ? 'tier1' : null,
      });
    }
  }

  tierLabels(item: CartItem) {
    return TIER_LABELS[item.pricingScheme ?? 'SingleDouble'];
  }

  setTier(item: CartItem, tier: PortionTier) {
    const price = tier === 'tier1' ? item.tier1Price : tier === 'tier2' ? item.tier2Price : item.tier3Price;
    if (price == null) return;
    item.portionTier = tier;
    item.unitPrice = price;
    this.recalcItem(item);
  }

  portionSuffix(item: CartItem): string {
    if (!item.portionTier) return '';
    const labels = this.tierLabels(item);
    const label = item.portionTier === 'tier1' ? labels.tier1 : item.portionTier === 'tier2' ? labels.tier2 : labels.tier3;
    return ` (${label})`;
  }

  recalcItem(item: CartItem) {
    item.lineTotal = +(item.unitPrice * item.quantity).toFixed(2);
  }

  changeQty(item: CartItem, delta: number) {
    item.quantity = Math.max(1, item.quantity + delta);
    this.recalcItem(item);
  }

  removeItem(item: CartItem) {
    this.cart = this.cart.filter(c => c !== item);
  }

  get subTotal(): number {
    return +this.cart.reduce((s, i) => s + i.lineTotal, 0).toFixed(2);
  }

  get discountAmount(): number {
    return +(this.subTotal * (this.globalDiscount / 100)).toFixed(2);
  }

  get taxableAmount(): number {
    return +(this.subTotal - this.discountAmount).toFixed(2);
  }

  get effectiveTaxRate(): number {
    return this.customTaxRate !== null ? this.customTaxRate : this.defaultTaxRate;
  }

  get taxAmount(): number {
    if (!this.applyTax) return 0;
    return +(this.taxableAmount * (this.effectiveTaxRate / 100)).toFixed(2);
  }

  get grandTotal(): number {
    return this.taxableAmount; // tax is inclusive — not added on top
  }

  get netAmount(): number {
    return +(this.taxableAmount - this.taxAmount).toFixed(2);
  }

  clearCart() {
    this.cart = [];
    this.globalDiscount = 0;
    this.customTaxRate = null;
    this.applyTax = true;
    this.orderSaved = false;
    this.lastOrderId = null;
    this.lastTokenNumber = null;
    this.receiptPayMethod = null;
    this.receiptCashIn = 0;
    this.receiptChange = 0;
    this.printStatus = '';
  }

  openPayModal() {
    if (!this.cart.length || this.saving || this.orderSaved) return;
    this.payMethod    = null;
    this.cashTendered = null;
    this.payModalOpen = true;
  }

  closePayModal() {
    this.payModalOpen = false;
    this.payMethod    = null;
    this.cashTendered = null;
  }

  selectMethod(m: 'cash' | 'card') {
    this.payMethod    = m;
    this.cashTendered = null;
  }

  setQuickCash(amount: number) { this.cashTendered = amount; }

  confirmPayment() {
    if (!this.payMethod) return;
    if (this.payMethod === 'cash' && (this.cashTendered === null || this.cashTendered < this.grandTotal)) return;
    this.receiptPayMethod = this.payMethod;
    this.receiptCashIn    = this.cashTendered ?? 0;
    this.receiptChange    = this.changeAmount;
    this.payModalOpen     = false;
    this.placeOrder();
  }

  placeOrder() {
    if (!this.cart.length) return;
    this.saving = true;
    this.receiptDate = new Date().toLocaleString('en-AE', { timeZone: 'Asia/Dubai' });

    const payload = {
      subTotal:      this.applyTax ? this.netAmount : this.taxableAmount,
      discount:      this.discountAmount,
      taxTotal:      this.taxAmount,
      grandTotal:    this.grandTotal,
      paymentMethod: this.receiptPayMethod ?? 'Cash',
      items: this.cart.map(i => ({
        dishId:    i.dishId,
        dishName:  i.dishName + this.portionSuffix(i),
        quantity:  i.quantity,
        unitPrice: i.unitPrice,
        lineTotal: i.lineTotal,
      })),
    };

    this.api.createOrder(payload).subscribe(res => {
      this.lastOrderId     = res.id;
      this.lastTokenNumber = res.tokenNumber;
      this.orderSaved = true;
      this.saving = false;
    });
  }

  printReceipt() {
    this.printStatus = 'Printing…';
    this.api.printReceipt({
      orderId: this.lastOrderId ?? 0,
      tokenNumber: this.lastTokenNumber ?? 0,
      orderDate: this.receiptDate,
      items: this.cart.map(i => ({
        dishName: (i.printName || i.dishName) + this.portionSuffix(i),
        quantity: i.quantity,
        unitPrice: i.unitPrice,
        lineTotal: i.lineTotal,
      })),
      subTotal: this.subTotal,
      discount: this.discountAmount,
      discountPercent: this.globalDiscount,
      tax: this.taxAmount,
      taxRate: this.effectiveTaxRate,
      applyTax: this.applyTax,
      grandTotal: this.grandTotal,
      paymentMethod: this.receiptPayMethod === 'card' ? 'Card' : 'Cash',
      cashReceived: this.receiptCashIn,
      change: this.receiptChange,
    }).subscribe({
      next: () => this.printStatus = 'Printed ✓',
      error: err => this.printStatus = err.error?.message || err.error?.detail || 'Print failed — check printer settings',
    });
  }

  printKitchenToken() {
    this.printStatus = 'Printing…';
    this.api.printKitchenToken({
      tokenNumber: this.lastTokenNumber ?? 0,
      orderDate: this.receiptDate,
      items: this.cart.map(i => ({ dishName: (i.printName || i.dishName) + this.portionSuffix(i), quantity: i.quantity })),
    }).subscribe({
      next: () => this.printStatus = 'Printed ✓',
      error: err => this.printStatus = err.error?.message || err.error?.detail || 'Print failed — check printer settings',
    });
  }
}
