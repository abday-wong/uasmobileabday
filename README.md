# UAS Mobile Programming - App-to-App Payment Integration Project

Proyek Ujian Akhir Semester (UAS) Mobile Programming ini mengintegrasikan **Aplikasi E-Commerce (Merchant)** yang dilanjutkan dari Ujian Tengah Semester (UTS) dengan **Aplikasi E-Money (Wallet)** menggunakan mekanisme **App-to-App Integration melalui Deep Link**, serta didukung oleh **Golang Backend** sebagai pemroses transaksi keuangan secara aman dengan verifikasi Two-Factor Authentication (2FA) dan notifikasi push Firebase Cloud Messaging (FCM).

---

## 📂 Struktur Proyek

Repositori monorepo ini memiliki struktur sebagai berikut:

- `/backend`: Layanan API backend berbasis Golang (Gin, GORM, Redis, MySQL).
- `/ecommerce_app`: Aplikasi Flutter E-Commerce (UTS Gaming Console Store) yang diperluas dengan opsi pembayaran E-Money, riwayat transaksi lokal, dan penanganan FCM.
- `/emoney_wallet`: Aplikasi Flutter secure wallet dengan visual bertema **Neubrutalism**, dilengkapi QR Scanner, verifikasi OTP/TOTP 2FA, dan deep link query.

---

## 🏗️ Arsitektur Aplikasi & Alur Transaksi

Aplikasi ini dirancang menggunakan arsitektur clean data flow dan deep link scheme:

```mermaid
sequenceDiagram
    autonumber
    participant Merchant as E-Commerce App (UTS)
    participant OS as Android/iOS OS
    participant Wallet as E-Money Wallet App
    participant Backend as Golang API Service
    
    Merchant->>Merchant: Pilih barang & Checkout
    Merchant->>OS: Launch Deep Link:<br/>emoney://pay?amount=150000&recipient=recipient@example.com&trx_id=TX-X&callback=ecommerce://callback
    OS->>Wallet: Hubungkan deep link intent
    Wallet->>Wallet: Deteksi session & validasi parameter
    Wallet->>Backend: Periksa saldo akun (/v1/auth/me)
    Wallet->>Wallet: Tampilkan detail & minta konfirmasi 2FA
    alt 2FA via Google Authenticator (TOTP)
        Wallet->>Backend: Verifikasi Kode TOTP (/v1/otp/totp/verify)
    else 2FA via Email OTP
        Wallet->>Backend: Kirim Kode OTP (/v1/otp/send-email)
        Wallet->>Backend: Validasi OTP & Transfer (/v1/payment/transfer)
    end
    Backend->>Backend: Database Transaction GORM (MySQL)<br/>(Deduksi Pengirim, Tambah Penerima)
    Backend-->>Wallet: Hasil Transaksi (Sukses/Gagal)
    Note over Backend, Merchant: Backend mengirim FCM Push Notification<br/>ke Merchant ("Pembayaran Diterima")<br/>dan ke Pengirim ("Transaksi Berhasil")
    Wallet->>OS: Redirect callback:<br/>ecommerce://callback?status=success&trx_id=TX-X&amount=150000...
    OS->>Merchant: Hubungkan callback intent
    Merchant->>Merchant: Simpan ke riwayat & Tampilkan dialog Sukses
```

---

## 🛠️ Daftar Dependensi Utama

### 1. Golang Backend
- `github.com/gin-gonic/gin`: Routing framework HTTP.
- `gorm.io/gorm` & `gorm.io/driver/mysql`: Database ORM dan driver MySQL.
- `github.com/redis/go-redis/v9`: Client cache untuk verifikasi OTP.
- `firebase.google.com/go/v4`: SDK admin untuk notifikasi Firebase Cloud Messaging.
- `github.com/pquerna/otp/totp`: Google Authenticator TOTP generator.
- `github.com/golang-jwt/jwt/v5`: Otentikasi sesi token JWT.

### 2. E-Commerce (Merchant) App (UTS)
- `provider`: State management terpusat.
- `url_launcher`: Membuka scheme link `emoney://pay`.
- `app_links`: Penanganan input deep link `ecommerce://callback`.
- `flutter_secure_storage`: Penyimpanan riwayat transaksi dan token lokal secara aman.
- `firebase_core` & `firebase_messaging`: Penerima push notifikasi transaksi.

### 3. E-Money (Wallet) App
- `app_links`: Penanganan input deep link `emoney://pay`.
- `qr_flutter`: Menampilkan QR Code rahasia untuk Google Authenticator 2FA.
- `firebase_core` & `firebase_messaging`: Otentikasi dan token client notifikasi push.
- `http`: Mengirim requests transfer dan otentikasi ke API Golang.

---

## 🚀 Cara Menjalankan Proyek

### 1. Persiapan Basis Data & Redis
Pastikan layanan berikut berjalan di localhost Anda:
- **MySQL**: Port `3306` (Gunakan database bernama `emoney`, user: `useremoney`, pass: `Password#123` atau sesuaikan `.env`).
- **Redis**: Port `6379` tanpa password.

### 2. Menjalankan Golang Backend
1. Masuk ke folder `/backend`.
2. Lengkapi konfigurasi berkas `.env` (SMTP Gmail untuk OTP dan path `firebase_service_account.json` jika ingin menggunakan notifikasi riil).
3. Jalankan aplikasi:
   ```bash
   go run main.go
   ```
4. Backend akan otomatis melakukan auto-migrate dan menyemai akun testing:
   - Pengirim / Wallet: `test@example.com` (Saldo awal Rp250.000)
   - Penerima / Merchant: `recipient@example.com` (Saldo awal Rp50.000)

### 3. Menjalankan Aplikasi Mobile (E-Commerce & Wallet)
Disarankan menggunakan dua Android Emulator atau perangkat fisik yang berbeda:

1. **Menjalankan E-Commerce (Merchant)**:
   ```bash
   cd ecommerce_app
   flutter pub get
   flutter run
   ```
2. **Menjalankan E-Money (Wallet)**:
   ```bash
   cd emoney_wallet
   flutter pub get
   flutter run
   ```

## 🌟 Fitur Baru & Pembaruan Terkini (UAS Update)

Dalam kelanjutan pengembangan proyek UAS ini, beberapa fitur utama telah berhasil diimplementasikan:

1. **Session Restore pada Web Refresh (E-Commerce)**
   - Menambahkan mekanisme `tryRestoreSession` di `SplashPage` dan `AuthProvider` menggunakan penyimpanan token JWT yang aman (`SecureStorage`).
   - Ketika aplikasi di-refresh di web browser, sistem secara otomatis membaca token tersebut dan menjaga pengguna tetap dalam keadaan terautentikasi (*stay logged in*) tanpa kembali ke halaman login.

2. **Web-based Deep Link Callback Fallback (App-to-App Web Redirect)**
   - Mendukung redireksi checkout ke E-Money Wallet berbasis web menggunakan pembukaan tab browser baru jika aplikasi e-commerce dijalankan di environment web.
   - Pemrosesan query parameter callback secara aman (`status`, `trx_id`, `amount`, `recipient_email`) baik pada mobile/emulator maupun web browser.

3. **Default Saldo Awal Rp100.000.000 (100 Juta Rupiah)**
   - Saldo default awal untuk user baru diubah dari Rp5.000.000 menjadi **Rp100.000.000**.
   - Dilakukan untuk mempermudah proses checkout produk-produk premium (seperti gaming console seharga puluhan juta) tanpa terhambat error *insufficient balance*.

4. **Integrasi Firebase Cloud Messaging (FCM)**
   - Pengiriman push notification otomatis secara real-time ketika transfer berhasil:
     - Notifikasi **"Pembayaran Diterima"** ke aplikasi E-Commerce (Penerima).
     - Notifikasi **"Transaksi Berhasil"** ke aplikasi E-Money Wallet (Pengirim).

---

## 📸 Antarmuka Aplikasi (Screenshots)

*(Tempatkan tangkapan layar aplikasi Anda di folder `screenshots/` untuk presentasi)*

- **E-Money Wallet App (Neubrutalism)**:
  `![Wallet Home](screenshots/wallet_home.png)`
  `![Wallet 2FA Verification](screenshots/wallet_2fa.png)`
- **E-Commerce App (Minimalist)**:
  `![Merchant Catalog](screenshots/merchant_catalog.png)`
  `![Checkout Selection](screenshots/checkout_payment.png)`
  `![Transaction History](screenshots/transaction_history.png)`

---

## 📺 Video Presentasi Aplikasi

Berikut adalah link presentasi demonstrasi alur transaksi proyek UAS:

👉 **[Tonton Video Demo Aplikasi di YouTube](https://youtube.com/)** *(Masukkan link video YouTube Anda di sini)*
