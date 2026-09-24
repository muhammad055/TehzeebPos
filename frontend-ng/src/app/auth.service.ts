import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';

export interface AuthUser {
  username: string;
  role: 'admin' | 'cashier';
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http   = inject(HttpClient);
  private router = inject(Router);
  private base   = 'http://localhost:5050/api';
  private readonly KEY = 'pos_user';

  login(username: string, password: string) {
    return this.http.post<AuthUser>(`${this.base}/auth/login`, { username, password });
  }

  setUser(user: AuthUser) {
    localStorage.setItem(this.KEY, JSON.stringify(user));
  }

  getUser(): AuthUser | null {
    const raw = localStorage.getItem(this.KEY);
    return raw ? JSON.parse(raw) : null;
  }

  isLoggedIn(): boolean {
    return !!this.getUser();
  }

  isAdmin(): boolean {
    return this.getUser()?.role === 'admin';
  }

  logout() {
    localStorage.removeItem(this.KEY);
    this.router.navigate(['/login']);
  }
}
