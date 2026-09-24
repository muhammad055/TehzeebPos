import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './login.component.html',
})
export class LoginComponent implements OnInit {
  private auth   = inject(AuthService);
  private router = inject(Router);

  username = '';
  password = '';
  loading  = false;
  error    = '';
  showPwd  = false;

  ngOnInit() {
    if (this.auth.isLoggedIn()) {
      this.router.navigate(['/dashboard']);
    }
  }

  submit() {
    if (!this.username.trim() || !this.password) return;
    this.loading = true;
    this.error   = '';

    this.auth.login(this.username.trim(), this.password).subscribe({
      next: user => {
        this.auth.setUser(user);
        this.router.navigate(['/dashboard']);
      },
      error: () => {
        this.loading = false;
        this.error   = 'Invalid username or password.';
      },
    });
  }
}
