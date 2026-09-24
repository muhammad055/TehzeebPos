import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, Dish, PricingScheme } from '../api.service';
import { LanguageService } from '../language.service';

@Component({
  selector: 'app-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './admin.component.html',
})
export class AdminComponent implements OnInit {
  private api = inject(ApiService);
  lang = inject(LanguageService);

  dishes: Dish[] = [];
  defaultTaxRate  = 5;
  printerName     = '';
  customerCopies  = 1;
  kitchenCopies   = 1;

  email = { smtpHost: '', smtpPort: '587', smtpUsername: '', smtpPassword: '', reportToEmail: '' };

  activeSettingTab: string | null = null;
  dishSearch = '';

  get filteredDishes(): Dish[] {
    const q = this.dishSearch.toLowerCase().trim();
    return q
      ? this.dishes.filter(d =>
          d.name.toLowerCase().includes(q) || (d.printName ?? '').toLowerCase().includes(q))
      : this.dishes;
  }

  toggleSettingTab(tab: string) {
    this.activeSettingTab = this.activeSettingTab === tab ? null : tab;
  }

  form: {
    name: string; price: number; taxRate: number; printName: string;
    doublePrice: number | null; thirdPrice: number | null; pricingScheme: PricingScheme;
  } = { name: '', price: 0, taxRate: 5, printName: '', doublePrice: null, thirdPrice: null, pricingScheme: 'SingleDouble' };
  editingId: number | null = null;
  saving = false;
  message = '';

  // Labels for the tier fields/buttons, driven by the selected pricing scheme.
  readonly tierLabelSets: Record<PricingScheme, { tier1: string; tier2: string; tier3: string }> = {
    SingleDouble:    { tier1: 'Single', tier2: 'Double', tier3: '' },
    QuarterHalfFull: { tier1: 'Quarter', tier2: 'Half', tier3: 'Full' },
  };
  get formTierLabels() { return this.tierLabelSets[this.form.pricingScheme]; }

  imageFile: File | null = null;
  imagePreview: string | null = null;

  ngOnInit() { this.loadAll(); }

  loadAll() {
    this.api.getDishes().subscribe(d => this.dishes = d);
    this.api.getSettings().subscribe(settings => {
      const tax   = settings.find(s => s.key === 'DefaultTaxRate');
      if (tax)   this.defaultTaxRate  = +tax.value;
      const pname = settings.find(s => s.key === 'PrinterName');
      if (pname) this.printerName    = pname.value;
      const cust  = settings.find(s => s.key === 'PrinterCustomerCopies');
      if (cust)  this.customerCopies  = +cust.value;
      const kitch = settings.find(s => s.key === 'PrinterKitchenCopies');
      if (kitch) this.kitchenCopies   = +kitch.value;
      const h = settings.find(s => s.key === 'SmtpHost');      if (h) this.email.smtpHost      = h.value;
      const p = settings.find(s => s.key === 'SmtpPort');      if (p) this.email.smtpPort      = p.value;
      const u = settings.find(s => s.key === 'SmtpUsername');  if (u) this.email.smtpUsername  = u.value;
      const w = settings.find(s => s.key === 'SmtpPassword');  if (w) this.email.smtpPassword  = w.value;
      const t = settings.find(s => s.key === 'ReportToEmail'); if (t) this.email.reportToEmail = t.value;
    });
  }

  saveTaxRate() {
    this.api.updateSetting('DefaultTaxRate', String(this.defaultTaxRate)).subscribe(() => {
      this.flash('Default tax rate saved.');
    });
  }

  saveEmailSettings() {
    const pairs: [string, string][] = [
      ['SmtpHost',      this.email.smtpHost],
      ['SmtpPort',      this.email.smtpPort],
      ['SmtpUsername',  this.email.smtpUsername],
      ['SmtpPassword',  this.email.smtpPassword],
      ['ReportToEmail', this.email.reportToEmail],
    ];
    let remaining = pairs.length;
    pairs.forEach(([key, val]) =>
      this.api.updateSetting(key, val).subscribe(() => {
        if (--remaining === 0) this.flash('Email settings saved.');
      })
    );
  }

  savePrinterSettings() {
    this.api.updateSetting('PrinterName', this.printerName).subscribe();
    this.api.updateSetting('PrinterCustomerCopies', String(this.customerCopies)).subscribe();
    this.api.updateSetting('PrinterKitchenCopies',  String(this.kitchenCopies)).subscribe(() => {
      this.flash('Printer settings saved.');
    });
  }

  startEdit(dish: Dish) {
    this.editingId = dish.id;
    this.form = {
      name: dish.name, price: dish.price, taxRate: dish.taxRate, printName: dish.printName ?? '',
      doublePrice: dish.doublePrice ?? null, thirdPrice: dish.thirdPrice ?? null,
      pricingScheme: dish.pricingScheme ?? 'SingleDouble',
    };
    this.imageFile = null;
    this.imagePreview = dish.imagePath ?? null;
  }

  cancelEdit() {
    this.editingId = null;
    this.form = {
      name: '', price: 0, taxRate: this.defaultTaxRate, printName: '',
      doublePrice: null, thirdPrice: null, pricingScheme: 'SingleDouble',
    };
    this.imageFile = null;
    this.imagePreview = null;
  }

  onImageSelected(event: Event) {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    this.imageFile = file;
    const reader = new FileReader();
    reader.onload = e => this.imagePreview = e.target?.result as string;
    reader.readAsDataURL(file);
  }

  clearImage() { this.imageFile = null; this.imagePreview = null; }

  private resizeImage(file: File, maxPx = 480): Promise<Blob> {
    return new Promise(resolve => {
      const img = new Image();
      const url = URL.createObjectURL(file);
      img.onload = () => {
        URL.revokeObjectURL(url);
        let w = img.width, h = img.height;
        if (w > maxPx || h > maxPx) {
          if (w >= h) { h = Math.round(h * maxPx / w); w = maxPx; }
          else        { w = Math.round(w * maxPx / h); h = maxPx; }
        }
        const canvas = document.createElement('canvas');
        canvas.width = w; canvas.height = h;
        canvas.getContext('2d')!.drawImage(img, 0, 0, w, h);
        canvas.toBlob(b => resolve(b!), 'image/jpeg', 0.82);
      };
      img.src = url;
    });
  }

  saveDish() {
    if (!this.form.name.trim() || this.form.price <= 0) return;
    this.saving = true;
    const hasTier2 = !!(this.form.doublePrice && this.form.doublePrice > 0);
    const payload = {
      name: this.form.name.trim(),
      price: this.form.price,
      taxRate: this.form.taxRate,
      printName: this.form.printName.trim() || null,
      doublePrice: hasTier2 ? this.form.doublePrice : null,
      thirdPrice: hasTier2 && this.form.pricingScheme === 'QuarterHalfFull' && this.form.thirdPrice && this.form.thirdPrice > 0
        ? this.form.thirdPrice : null,
      pricingScheme: hasTier2 ? this.form.pricingScheme : null,
    };
    const msg = this.editingId ? 'Dish updated.' : 'Dish added.';

    const req = this.editingId
      ? this.api.updateDish(this.editingId, payload)
      : this.api.createDish(payload);

    req.subscribe(async (saved: Dish) => {
      if (this.imageFile) {
        const blob = await this.resizeImage(this.imageFile);
        const fd = new FormData();
        fd.append('file', blob, 'dish.jpg');
        this.api.uploadDishImage(saved.id, fd).subscribe(() => {
          this.saving = false; this.cancelEdit(); this.loadAll(); this.flash(msg);
        });
      } else {
        this.saving = false; this.cancelEdit(); this.loadAll(); this.flash(msg);
      }
    });
  }

  toggleDish(dish: import('../api.service').Dish) {
    this.api.toggleDish(dish.id).subscribe(updated => {
      dish.isActive = updated.isActive;
      this.flash(updated.isActive ? `"${updated.name}" enabled.` : `"${updated.name}" disabled.`);
    });
  }

  get allDishesActive(): boolean {
    return this.dishes.length > 0 && this.dishes.every(d => d.isActive);
  }

  toggleAllDishes() {
    const next = !this.allDishesActive;
    if (!confirm(next ? 'Enable all dishes?' : 'Disable all dishes?')) return;
    this.api.toggleAllDishes(next).subscribe(() => {
      this.dishes.forEach(d => d.isActive = next);
      this.flash(next ? 'All dishes enabled.' : 'All dishes disabled.');
    });
  }

  deleteDish(id: number) {
    if (!confirm('Delete this dish?')) return;
    this.api.deleteDish(id).subscribe(() => this.loadAll());
  }

  flash(msg: string) {
    this.message = msg;
    setTimeout(() => this.message = '', 2500);
  }
}
