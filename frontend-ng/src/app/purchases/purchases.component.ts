import { Component, OnInit, inject, HostListener } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, Purchase, PurchaseAttachment } from '../api.service';

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

  ngOnInit() { this.load(); }

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
    this.imageFiles    = [];
    this.imagePreviews = [];
    this.showForm = true;
  }

  cancelForm() {
    this.showForm  = false;
    this.editingId = null;
    this.existingAttachments = [];
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
    if (!this.form.supplier.trim() || this.form.totalAmount <= 0) return;
    this.saving = true;

    const fd = new FormData();
    fd.append('supplier',    this.form.supplier.trim());
    fd.append('description', this.form.description);
    fd.append('totalAmount', String(this.form.totalAmount));
    fd.append('category',    this.form.category);
    fd.append('date',        this.form.date);

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
