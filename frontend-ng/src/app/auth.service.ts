import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { environment } from '../environments/environment';

export interface AuthUser {
  token: string;
  username: string;
  role: 'owner' | 'admin' | 'cashier';
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http   = inject(HttpClient);
  private router = inject(Router);
  private base   = environment.apiBase;
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

  getToken(): string | null {
    return this.getUser()?.token ?? null;
  }

  isLoggedIn(): boolean {
    return !!this.getUser();
  }

  isAdmin(): boolean {
    const role = this.getUser()?.role;
    return role === 'admin' || role === 'owner';
  }

  logout() {
    localStorage.removeItem(this.KEY);
    this.router.navigate(['/login']);
  }
}
