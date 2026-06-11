# UAS Mobile Programming - App-to-App Payment Integration
This project integrates an **E-Commerce Merchant App** with an **E-Money Wallet App** using **Deep Linking** (App-to-App Integration) and a **Golang Backend** with Two-Factor Authentication (2FA).

## Project Structure
- /backend: Golang Gin GORM service.
- /ecommerce_app: Flutter merchant catalog application.
- /emoney_wallet: Flutter secure payment wallet application.

## How it works
1. **E-Commerce Checkout**: User adds items to cart and taps "Pay with E-Money".
2. **Deep Link Launch**: E-Commerce opens emoney://pay?amount=50000&recipient=recipient@example.com....
3. **Wallet Authentication & 2FA**: E-Money app displays details, checks balance, requests OTP/TOTP.
4. **Backend Transfer**: Wallet calls /v1/payment/transfer on backend.
5. **Callback Deep Link**: Wallet redirects back to E-Commerce using ecommerce://callback?status=success.

## Running locally
1. Run backend: cd backend && go run main.go
2. Run apps: lutter run inside ecommerce_app and emoney_wallet.
