import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, AppUser } from '../api.service';
import { AuthService } from '../auth.service';

@Component({
  selector: 'app-users',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './users.component.html',
})
export class UsersComponent implements OnInit {
  private api  = inject(ApiService);
  auth         = inject(AuthService);

  users: AppUser[] = [];
  loading = false;

  // Create user form
  newUser = { username: '', password: '', confirmPassword: '', role: 'cashier' };
  creating = false;
  createError = '';
  createSuccess = '';

  // Change password
  changingId: number | null = null;
  newPassword = '';
  confirmNewPassword = '';
  pwdError = '';
  pwdSuccess = '';

  // Delete confirm
  deleteConfirmId: number | null = null;

  ngOnInit() { this.load(); }

  load() {
    this.loading = true;
    this.api.getUsers().subscribe({ next: u => { this.users = u; this.loading = false; }, error: () => { this.loading = false; } });
  }

  isSelf(u: AppUser) { return u.username === this.auth.getUser()?.username; }

  submitCreate() {
    this.createError = ''; this.createSuccess = '';
    if (!this.newUser.username.trim() || !this.newUser.password) { this.createError = 'Username and password are required.'; return; }
    if (this.newUser.password !== this.newUser.confirmPassword) { this.createError = 'Passwords do not match.'; return; }
    if (this.newUser.password.length < 6) { this.createError = 'Password must be at least 6 characters.'; return; }
    this.creating = true;
    this.api.createUser({ username: this.newUser.username.trim(), password: this.newUser.password, role: this.newUser.role }).subscribe({
      next: () => {
        this.creating = false;
        this.createSuccess = `User "${this.newUser.username}" created.`;
        this.newUser = { username: '', password: '', confirmPassword: '', role: 'cashier' };
        this.load();
      },
      error: err => {
        this.creating = false;
        this.createError = err.status === 409 ? 'Username already exists.' : 'Failed to create user.';
      },
    });
  }

  startChangePassword(id: number) {
    this.changingId = id; this.newPassword = ''; this.confirmNewPassword = '';
    this.pwdError = ''; this.pwdSuccess = '';
  }

  cancelChangePassword() { this.changingId = null; }

  submitChangePassword(id: number) {
    this.pwdError = ''; this.pwdSuccess = '';
    if (!this.newPassword) { this.pwdError = 'Password is required.'; return; }
    if (this.newPassword.length < 6) { this.pwdError = 'Minimum 6 characters.'; return; }
    if (this.newPassword !== this.confirmNewPassword) { this.pwdError = 'Passwords do not match.'; return; }
    this.api.changePassword(id, this.newPassword).subscribe({
      next: () => { this.pwdSuccess = 'Password updated.'; this.changingId = null; },
      error: () => { this.pwdError = 'Failed to update password.'; },
    });
  }

  confirmDelete(id: number) { this.deleteConfirmId = id; }
  cancelDelete() { this.deleteConfirmId = null; }

  doDelete(id: number) {
    this.api.deleteUser(id).subscribe({
      next: () => { this.deleteConfirmId = null; this.load(); },
      error: () => { this.deleteConfirmId = null; },
    });
  }
}
