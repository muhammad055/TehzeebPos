import { Component, OnInit, inject, HostListener } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, Item, ItemPack, Purchase, PurchaseAttachment, PurchaseItem } from '../api.service';

interface Line { itemId: number | null; packId: number | null; count: number; price: number; }

@Component({
  selector: 'app-purchases',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './purchases.component.html',
})
export class PurchasesComponent implements OnInit {
  private api = inject(ApiService);

  purchases: Purchase[] = [];
  loading = false;
  message = '';
  imageBase = 'http://localhost:5050';

  filterFrom = this.todayStr();
  filterTo   = this.todayStr();
  filterCategory = '';

  showForm  = false;
  editingId: number | null = null;
  saving    = false;

  form = {
    date:        this.todayStr(),
    supplier:    '',
    description: '',
    totalAmount: 0,
    category:    'Food & Beverage',
  };

  // Itemised bill lines. With at least one line the total is the sum of the lines
  // (the server computes it too); with none it's the manually typed total as before.
  items: Item[] = [];
  // A line is either by pack (packId set: count = packets, price = per packet) or loose
  // (packId null: count = base units, price = per base unit). The server converts packs
  // to base units, so staff never do that arithmetic.
  lines: Line[] = [];
  showNewItem = false;
  newItem = { name: '', unit: 'kg', packName: '', packSize: null as number | null };
  newItemForLine = -1;
  showNewPack = false;
  newPack = { name: '', size: null as number | null };
  newPackForLine = -1;
  readonly units = this.api.units;

  // Existing attachments on the expense being edited (removable immediately).
  existingAttachments: PurchaseAttachment[] = [];
  // Newly-picked files staged for upload — take effect on Save.
  imageFiles: File[] = [];
  imagePreviews: string[] = [];

  readonly categories = [
    'Food & Beverage', 'Cleaning', 'Equipment',
    'Utilities', 'Salary', 'Rent', 'Packaging', 'Other',
  ];

  // Attachment gallery viewer
  viewingAttachments: PurchaseAttachment[] = [];
  viewingIndex = 0;
  get viewingImage(): string | null {
    const a = this.viewingAttachments[this.viewingIndex];
    return a ? this.imageBase + a.imagePath : null;
  }

  viewAttachments(attachments: PurchaseAttachment[], startIndex = 0) {
    if (!attachments.length) return;
    this.viewingAttachments = attachments;
    this.viewingIndex = startIndex;
  }
  closeViewer()  { this.viewingAttachments = []; this.viewingIndex = 0; }
  nextImage()    { this.viewingIndex = (this.viewingIndex + 1) % this.viewingAttachments.length; }
  prevImage()    { this.viewingIndex = (this.viewingIndex - 1 + this.viewingAttachments.length) % this.viewingAttachments.length; }

  @HostListener('document:keydown.escape')
  onEsc() { this.closeViewer(); }

  @HostListener('document:keydown.arrowRight')
  onArrowRight() { if (this.viewingAttachments.length) this.nextImage(); }

  @HostListener('document:keydown.arrowLeft')
  onArrowLeft() { if (this.viewingAttachments.length) this.prevImage(); }

  readonly categoryColors: Record<string, string> = {
    'Food & Beverage': '#4caf82',
    'Cleaning':        '#5b9bd5',
    'Equipment':       '#e07840',
    'Utilities':       '#a882cc',
    'Salary':          '#f5c518',
    'Rent':            '#e05252',
    'Packaging':       '#4cb8c4',
    'Other':           '#888',
  };

  ngOnInit() { this.load(); this.loadItems(); }

  loadItems() { this.api.getItems().subscribe(i => this.items = i); }

  get hasLines() { return this.lines.length > 0; }
  get linesTotal() {
    return Math.round(this.lines.reduce((s, l) => s + this.lineTotal(l) * 100, 0)) / 100;
  }
  lineTotal(l: Line) {
    return Math.round((l.count || 0) * (l.price || 0) * 100) / 100;
  }
  itemOf(itemId: number | null) { return this.items.find(i => i.id === itemId); }
  unitOf(itemId: number | null) { return this.itemOf(itemId)?.unit ?? ''; }
  packOf(l: Line): ItemPack | undefined {
    return l.packId === null ? undefined : this.itemOf(l.itemId)?.packs.find(p => p.id === l.packId);
  }
  /** What the "how many" box counts: packets, or the item's base unit. */
  countLabel(l: Line) { return l.packId !== null ? 'packets' : (this.unitOf(l.itemId) || 'qty'); }
  priceLabel(l: Line) { return l.packId !== null ? 'Price per packet' : 'Price per ' + (this.unitOf(l.itemId) || 'unit'); }
  /** e.g. "= 20 pcs" so the person sees what the app will record. */
  convertedText(l: Line) {
    const pk = this.packOf(l);
    if (!pk || !l.count) return '';
    return '= ' + Math.round(l.count * pk.quantity * 1000) / 1000 + ' ' + this.unitOf(l.itemId);
  }
  get linesValid() {
    return this.lines.every(l => l.itemId !== null && l.count > 0 && l.price >= 0);
  }
  get canSave() {
    if (!this.form.supplier.trim()) return false;
    return this.hasLines ? this.linesValid : this.form.totalAmount > 0;
  }

  addLine() { this.lines.push({ itemId: null, packId: null, count: 1, price: 0 }); }
  removeLine(i: number) { this.lines.splice(i, 1); }
  itemsSummary(p: Purchase, max = 3) {
    const parts = p.items.slice(0, max).map((x: PurchaseItem) =>
      x.packId !== null && x.packs !== null
        ? `${x.itemName} ${x.packs} × ${x.packName} (${x.quantity} ${x.unit})`
        : `${x.itemName} ${x.quantity} ${x.unit}`);
    return parts.join(' · ') + (p.items.length > max ? ` · +${p.items.length - max} more` : '');
  }

  // The last option in each item dropdown is "＋ New item…" (value -1).
  onItemPicked(lineIndex: number, value: number | null) {
    const l = this.lines[lineIndex];
    if (value === -1) {
      l.itemId = null;
      this.startNewItem(lineIndex);
      return;
    }
    // Default to the item's first pack when it has one (the usual way it is bought).
    const first = this.itemOf(value)?.packs[0];
    l.packId = first ? first.id : null;
  }

  // The last option in each pack dropdown is "＋ New pack…" (value -1).
  onPackPicked(lineIndex: number, value: number | null) {
    if (value === -1) {
      this.lines[lineIndex].packId = null;
      this.newPack = { name: '', size: null };
      this.newPackForLine = lineIndex;
      this.showNewPack = true;
    }
  }
  savePack() {
    const l = this.lines[this.newPackForLine];
    const name = this.newPack.name.trim();
    if (!l || l.itemId === null || !name || !this.newPack.size || this.newPack.size <= 0) return;
    this.api.createPack(l.itemId, name, this.newPack.size).subscribe({
      next: pack => {
        const it = this.itemOf(l.itemId);
        if (it) it.packs = [...it.packs, pack];
        l.packId = pack.id;
        this.showNewPack = false;
        this.flash(`Added "${pack.name}".`);
      },
      error: e => this.flash(typeof e.error === 'string' ? e.error : 'Could not add pack (admin only).'),
    });
  }

  startNewItem(lineIndex: number) {
    this.newItem = { name: '', unit: 'kg', packName: '', packSize: null };
    this.newItemForLine = lineIndex;
    this.showNewItem = true;
  }
  saveNewItem() {
    const name = this.newItem.name.trim();
    if (!name) return;
    const packName = this.newItem.packName.trim();
    const packs = packName && this.newItem.packSize && this.newItem.packSize > 0
      ? [{ name: packName, quantity: this.newItem.packSize }] : undefined;
    this.api.createItem(name, this.newItem.unit, packs).subscribe({
      next: item => {
        this.items = [...this.items, item].sort((a, b) => a.name.localeCompare(b.name));
        const l = this.lines[this.newItemForLine];
        if (l) { l.itemId = item.id; l.packId = item.packs[0]?.id ?? null; }
        this.showNewItem = false;
        this.flash(`Added "${item.name}".`);
      },
      error: e => this.flash(typeof e.error === 'string' ? e.error : 'Could not add item (admin only).'),
    });
  }

  todayStr() {
    const d = new Date();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    return `${d.getFullYear()}-${mm}-${dd}`;
  }

  load() {
    this.loading = true;
    this.api.getPurchases(this.filterFrom, this.filterTo, this.filterCategory || undefined).subscribe({
      next:  p  => { this.purchases = p; this.loading = false; },
      error: () => { this.loading = false; },
    });
  }

  get totalSpent() {
    return this.purchases.reduce((s, p) => s + p.totalAmount, 0);
  }

  catColor(cat: string) {
    return this.categoryColors[cat] ?? '#888';
  }

  formatDate(iso: string) {
    const d = new Date(iso);
    return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  openNew() {
    this.editingId = null;
    this.form = { date: this.todayStr(), supplier: '', description: '', totalAmount: 0, category: 'Food & Beverage' };
    this.existingAttachments = [];
    this.lines = [];
    this.showNewItem = false;
    this.showNewPack = false;
    this.imageFiles    = [];
    this.imagePreviews = [];
    this.showForm = true;
  }

  openEdit(p: Purchase) {
    this.editingId = p.id;
    this.form = {
      date:        p.date.slice(0, 10),
      supplier:    p.supplier,
      description: p.description,
      totalAmount: p.totalAmount,
      category:    p.category,
    };
    this.existingAttachments = [...p.attachments];
    this.lines = (p.items ?? []).map(x => {
      const packStillUsable = x.packId !== null && this.items.find(i => i.id === x.itemId)?.packs.some(k => k.id === x.packId);
      return packStillUsable
        ? { itemId: x.itemId, packId: x.packId, count: x.packs ?? 0, price: x.packPrice ?? 0 }
        : { itemId: x.itemId, packId: null, count: x.quantity, price: x.unitPrice };
    });
    this.showNewItem = false;
    this.imageFiles    = [];
    this.imagePreviews = [];
    this.showForm = true;
  }

  cancelForm() {
    this.showForm  = false;
    this.editingId = null;
    this.existingAttachments = [];
    this.lines = [];
    this.showNewItem = false;
    this.imageFiles    = [];
    this.imagePreviews = [];
  }

  onImageSelected(event: Event) {
    const files = Array.from((event.target as HTMLInputElement).files ?? []);
    (event.target as HTMLInputElement).value = ''; // allow re-picking the same file
    for (const file of files) {
      this.imageFiles.push(file);
      const reader = new FileReader();
      reader.onload = e => this.imagePreviews.push(e.target?.result as string);
      reader.readAsDataURL(file);
    }
  }

  removeNewImage(index: number) {
    this.imageFiles.splice(index, 1);
    this.imagePreviews.splice(index, 1);
  }

  removeExistingAttachment(attachment: PurchaseAttachment) {
    if (!this.editingId) return;
    if (!confirm('Remove this attachment?')) return;
    this.api.deletePurchaseAttachment(this.editingId, attachment.id).subscribe(() => {
      this.existingAttachments = this.existingAttachments.filter(a => a.id !== attachment.id);
    });
  }

  private resizeImage(file: File, maxPx = 1600): Promise<Blob> {
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
        canvas.toBlob(b => resolve(b!), 'image/jpeg', 0.90);
      };
      img.src = url;
    });
  }

  async save() {
    if (!this.canSave) return;
    this.saving = true;

    const fd = new FormData();
    fd.append('supplier',    this.form.supplier.trim());
    fd.append('description', this.form.description);
    fd.append('totalAmount', String(this.hasLines ? this.linesTotal : this.form.totalAmount));
    fd.append('category',    this.form.category);
    fd.append('date',        this.form.date);
    // Editing always sends the lines (even an empty list) so removed lines are removed.
    if (this.hasLines || this.editingId !== null) {
      fd.append('items', JSON.stringify(this.lines.map(l => l.packId !== null
        ? { itemId: l.itemId, packId: l.packId, packs: l.count, packPrice: l.price }
        : { itemId: l.itemId, quantity: l.count, unitPrice: l.price })));
    }

    const isEdit = this.editingId !== null;
    const req = isEdit
      ? this.api.updatePurchase(this.editingId!, fd)
      : this.api.createPurchase(fd);

    req.subscribe({
      next: async (saved) => {
        if (this.imageFiles.length > 0) {
          const blobs = await Promise.all(this.imageFiles.map(f => this.resizeImage(f)));
          const files = blobs.map((b, i) => new File([b], this.imageFiles[i].name || 'receipt.jpg', { type: 'image/jpeg' }));
          this.api.addPurchaseAttachments(saved.id, files).subscribe({
            next: () => this.finishSave(isEdit),
            error: () => this.finishSave(isEdit, 'Saved, but attachment upload failed.'),
          });
        } else {
          this.finishSave(isEdit);
        }
      },
      error: () => { this.saving = false; },
    });
  }

  private finishSave(isEdit: boolean, warning?: string) {
    this.saving = false;
    this.cancelForm();
    this.load();
    this.flash(warning ?? (isEdit ? 'Purchase updated.' : 'Purchase saved.'));
  }

  delete(id: number) {
    if (!confirm('Delete this purchase record?')) return;
    this.api.deletePurchase(id).subscribe(() => this.load());
  }

  flash(msg: string) {
    this.message = msg;
    setTimeout(() => this.message = '', 2500);
  }
}
