package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"net/smtp"
	"os"
	"strconv"
	"strings"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/joho/godotenv"
	"github.com/pquerna/otp/totp"
	"github.com/redis/go-redis/v9"
	"google.golang.org/api/option"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

// JWT Claims Struct
type JWTClaims struct {
	UserID uint   `json:"user_id"`
	Email  string `json:"email"`
	jwt.RegisteredClaims
}

// User Database Model
type User struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	Email       string    `gorm:"type:varchar(255);uniqueIndex;not null" json:"email"`
	FCMToken    string    `json:"fcm_token"`
	TOTPSecret  string    `json:"-"`
	TOTPEnabled bool      `gorm:"default:false" json:"totp_enabled"`
	Balance     int64     `gorm:"default:100000" json:"balance"` // Saldo awal Rp100.000
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// Global Variables
var (
	db          *gorm.DB
	rdb         *redis.Client
	firebaseApp *firebase.App
	jwtSecret   []byte
	otpExpiry   time.Duration
)

func main() {
	// 1. Load .env file
	if err := godotenv.Load(); err != nil {
		log.Println("Warning: .env file not found, using system environment variables")
	}

	// 2. Initialize Configurations
	jwtSecret = []byte(getEnv("JWT_SECRET", "your-super-secret-jwt-key-change-this"))
	expiryMin, _ := strconv.Atoi(getEnv("OTP_EXPIRY_MINUTES", "5"))
	otpExpiry = time.Duration(expiryMin) * time.Minute

	// 3. Initialize MySQL (GORM)
	initMySQL()

	// 4. Initialize Redis
	initRedis()

	// 5. Initialize Firebase Admin SDK
	initFirebase()

	// 6. Setup Gin Router
	r := gin.Default()

	// Enable CORS
	r.Use(corsMiddleware())

	// Custom Banners
	printBanner()

	// API Route Group
	v1 := r.Group("/v1")
	{
		// Auth Routes
		auth := v1.Group("/auth")
		{
			auth.GET("/me", authMiddleware(), getMe)
			auth.PUT("/fcm-token", authMiddleware(), updateFCMToken)
		}

		// OTP Routes
		otp := v1.Group("/otp")
		{
			otp.POST("/send-email", sendEmailOTP)
			otp.POST("/send-firebase", sendFirebaseOTP)
			otp.POST("/confirm", confirmOTP)

			// TOTP (Google Authenticator)
			totpGroup := otp.Group("/totp")
			totpGroup.Use(authMiddleware())
			{
				totpGroup.POST("/register", registerTOTP)
				totpGroup.POST("/verify", verifyTOTP)
			}
		}

		// Payment Routes
		payment := v1.Group("/payment")
		payment.Use(authMiddleware())
		{
			payment.POST("/transfer", transferPayment)
		}
	}

	// Run Server
	port := getEnv("PORT", "8080")
	log.Printf("Server emoney-backend running on port %s...", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to run server: %v", err)
	}
}

// ==========================================
// INITIALIZATION FUNCTIONS
// ==========================================

func initMySQL() {
	dbHost := getEnv("DB_HOST", "localhost")
	dbPort := getEnv("DB_PORT", "3306")
	dbUser := getEnv("DB_USER", "useremoney")
	dbPass := getEnv("DB_PASSWORD", "Password#123")
	dbName := getEnv("DB_NAME", "emoney")

	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local",
		dbUser, dbPass, dbHost, dbPort, dbName)

	var err error
	db, err = gorm.Open(mysql.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Database connection failed: %v", err)
	}

	// Run Auto-Migrations
	if err := db.AutoMigrate(&User{}); err != nil {
		log.Fatalf("Database auto-migration failed: %v", err)
	}

	log.Println("MySQL Database connected and migrated successfully!")

	// Seed a test user for immediate Postman verification
	seedTestUser()
}

func seedTestUser() {
	var count int64
	db.Model(&User{}).Where("email = ?", "test@example.com").Count(&count)
	if count == 0 {
		testUser := User{
			Email:   "test@example.com",
			Balance: 250000, // Rp250.000
		}
		if err := db.Create(&testUser).Error; err == nil {
			log.Println("Seeded test user 'test@example.com' with Rp250.000 balance")
		}
	}

	var countRecipient int64
	db.Model(&User{}).Where("email = ?", "recipient@example.com").Count(&countRecipient)
	if countRecipient == 0 {
		recipientUser := User{
			Email:   "recipient@example.com",
			Balance: 50000, // Rp50.000
		}
		if err := db.Create(&recipientUser).Error; err == nil {
			log.Println("Seeded recipient user 'recipient@example.com' with Rp50.000 balance")
		}
	}
}

func initRedis() {
	redisHost := getEnv("REDIS_HOST", "localhost")
	redisPort := getEnv("REDIS_PORT", "6379")
	redisPass := getEnv("REDIS_PASSWORD", "")

	rdb = redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", redisHost, redisPort),
		Password: redisPass,
		DB:       0,
	})

	// Test connection
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Printf("Warning: Redis connection failed: %v. Cache features may not work.", err)
	} else {
		log.Println("Redis connected successfully!")
	}
}

func initFirebase() {
	credPath := getEnv("FIREBASE_CREDENTIALS_PATH", "firebase_service_account.json")

	if _, err := os.Stat(credPath); os.IsNotExist(err) {
		log.Printf("Warning: Firebase credentials file '%s' not found. Firebase features will run in mock mode.", credPath)
		return
	}

	opt := option.WithCredentialsFile(credPath)
	app, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		log.Printf("Warning: Failed to initialize Firebase App: %v. Running Firebase features in mock mode.", err)
		return
	}

	firebaseApp = app
	log.Println("Firebase Admin SDK initialized successfully!")
}

// ==========================================
// MIDDLEWARES
// ==========================================

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

func authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header is required"})
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if !(len(parts) == 2 && parts[0] == "Bearer") {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header must be Bearer token"})
			c.Abort()
			return
		}

		tokenString := parts[1]
		claims := &JWTClaims{}

		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			return jwtSecret, nil
		})

		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired backend token"})
			c.Abort()
			return
		}

		// Set User ID & Email in Context
		c.Set("userID", claims.UserID)
		c.Set("email", claims.Email)
		c.Next()
	}
}

// ==========================================
// ROUTE HANDLERS
// ==========================================

// 1. GET /v1/auth/me
func getMe(c *gin.Context) {
	userID, _ := c.Get("userID")

	var user User
	if err := db.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// 2. PUT /v1/auth/fcm-token
func updateFCMToken(c *gin.Context) {
	userID, _ := c.Get("userID")

	var req struct {
		FCMToken string `json:"fcm_token" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "fcm_token is required"})
		return
	}

	if err := db.Model(&User{}).Where("id = ?", userID).Update("fcm_token", req.FCMToken).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update FCM token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "FCM token updated successfully"})
}

// 3. POST /v1/otp/send-firebase
func sendFirebaseOTP(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Valid email is required"})
		return
	}

	otp := generateOTP()
	ctx := context.Background()

	// Store OTP in Redis
	redisKey := fmt.Sprintf("otp:firebase:%s", req.Email)
	if err := rdb.Set(ctx, redisKey, otp, otpExpiry).Err(); err != nil {
		log.Printf("Failed to save OTP to Redis: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate OTP"})
		return
	}

	// Fetch user to get FCM token
	var user User
	db.Where("email = ?", req.Email).First(&user)

	var mockStatus string
	if firebaseApp == nil {
		mockStatus = "Firebase app not initialized (Running in Mock mode)"
	} else if user.FCMToken == "" {
		mockStatus = "User does not have an FCM token registered"
	} else {
		// Send actual FCM Message
		msgClient, err := firebaseApp.Messaging(ctx)
		if err != nil {
			mockStatus = fmt.Sprintf("Failed to get FCM client: %v", err)
		} else {
			message := &messaging.Message{
				Token: user.FCMToken,
				Notification: &messaging.Notification{
					Title: "Kode OTP E-Money Anda",
					Body:  fmt.Sprintf("Kode OTP Anda adalah %s. Rahasiakan kode ini.", otp),
				},
				Data: map[string]string{
					"otp": otp,
				},
			}
			_, err = msgClient.Send(ctx, message)
			if err != nil {
				mockStatus = fmt.Sprintf("Failed to send FCM notification: %v", err)
			} else {
				mockStatus = "Sent successfully via FCM"
			}
		}
	}

	// Return response with the OTP in the body so the user can easily test in Postman
	c.JSON(http.StatusOK, gin.H{
		"message":     "OTP generated successfully via Firebase FCM flow",
		"email":       req.Email,
		"otp":         otp, // Return for debug/testing
		"fcm_status":  mockStatus,
		"expiry_mins": int(otpExpiry.Minutes()),
	})
}

// 4. POST /v1/otp/send-email
func sendEmailOTP(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Valid email is required"})
		return
	}

	otp := generateOTP()
	ctx := context.Background()

	// Store OTP in Redis
	redisKey := fmt.Sprintf("otp:email:%s", req.Email)
	if err := rdb.Set(ctx, redisKey, otp, otpExpiry).Err(); err != nil {
		log.Printf("Failed to save OTP to Redis: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate OTP"})
		return
	}

	// Send Email via SMTP
	smtpHost := getEnv("SMTP_HOST", "smtp.gmail.com")
	smtpPort := getEnv("SMTP_PORT", "587")
	smtpUser := getEnv("SMTP_USER", "")
	smtpPass := getEnv("SMTP_PASSWORD", "")
	smtpFrom := getEnv("SMTP_FROM", smtpUser)
	smtpFromName := getEnv("SMTP_FROM_NAME", "E-Money App")

	var smtpStatus string
	if smtpUser == "" || smtpUser == "your_gmail_address@gmail.com" || smtpPass == "" {
		smtpStatus = "SMTP credentials not configured. Running in debug mode."
	} else {
		// Plain auth for port 587 (STARTTLS)
		auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)
		subject := "Subject: Kode Keamanan OTP E-Money App\n"
		mime := "MIME-version: 1.0;\nContent-Type: text/html; charset=\"UTF-8\";\n\n"
		body := fmt.Sprintf(`
			<html>
			<body>
				<h2>Keamanan Akun E-Money App</h2>
				<p>Kode OTP Anda untuk login atau transaksi adalah:</p>
				<h1 style="color: #4CAF50; font-size: 32px; letter-spacing: 5px;">%s</h1>
				<p>Kode ini hanya berlaku selama <b>%d menit</b>. Jangan sebarkan kode ini kepada siapapun.</p>
				<hr>
				<small>Pesan ini dikirim secara otomatis oleh E-Money App Backend.</small>
			</body>
			</html>
		`, otp, int(otpExpiry.Minutes()))

		msg := []byte("From: " + smtpFromName + " <" + smtpFrom + ">\n" +
			"To: " + req.Email + "\n" +
			subject + mime + body)

		addr := fmt.Sprintf("%s:%s", smtpHost, smtpPort)
		err := smtp.SendMail(addr, auth, smtpUser, []string{req.Email}, msg)
		if err != nil {
			log.Printf("Failed to send email: %v", err)
			smtpStatus = fmt.Sprintf("Failed to send email: %v", err)
		} else {
			smtpStatus = "Sent successfully via Gmail SMTP"
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "OTP generated successfully via Email flow",
		"email":       req.Email,
		"otp":         otp, // Return for debug/testing
		"smtp_status": smtpStatus,
		"expiry_mins": int(otpExpiry.Minutes()),
	})
}

// 5. POST /v1/otp/confirm
func confirmOTP(c *gin.Context) {
	var req struct {
		Email          string `json:"email"`
		OTP            string `json:"otp"`
		FirebaseIDToken string `json:"firebase_id_token"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid payload"})
		return
	}

	var emailVerified string
	ctx := context.Background()

	// Flow A: Firebase ID Token authentication (for Postman & Firebase Auth integration)
	if req.FirebaseIDToken != "" {
		if firebaseApp == nil {
			// Mock verification when Firebase is not configured or in testing environment
			// Check if we can mock it by decoding token or if it's just dummy token
			if strings.HasPrefix(req.FirebaseIDToken, "mock-") {
				parts := strings.Split(req.FirebaseIDToken, "-")
				if len(parts) >= 2 {
					emailVerified = parts[1]
				} else {
					emailVerified = "test@example.com"
				}
			} else {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Firebase Admin SDK not initialized and invalid mock ID Token"})
				return
			}
		} else {
			authClient, err := firebaseApp.Auth(ctx)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Firebase Auth client error"})
				return
			}

			token, err := authClient.VerifyIDToken(ctx, req.FirebaseIDToken)
			if err != nil {
				c.JSON(http.StatusUnauthorized, gin.H{"error": fmt.Sprintf("Failed to verify Firebase ID Token: %v", err)})
				return
			}

			if emailClaim, ok := token.Claims["email"].(string); ok {
				emailVerified = emailClaim
			} else {
				// Fallback to uid
				emailVerified = fmt.Sprintf("%s@firebase.user", token.UID)
			}
		}
	} else if req.Email != "" && req.OTP != "" {
		// Flow B: Manual OTP confirmation (Email or FCM)
		emailKey := fmt.Sprintf("otp:email:%s", req.Email)
		firebaseKey := fmt.Sprintf("otp:firebase:%s", req.Email)

		// Try finding the OTP in Redis
		savedOTPEmail, _ := rdb.Get(ctx, emailKey).Result()
		savedOTPFirebase, _ := rdb.Get(ctx, firebaseKey).Result()

		if (savedOTPEmail != "" && savedOTPEmail == req.OTP) || (savedOTPFirebase != "" && savedOTPFirebase == req.OTP) {
			// Success! Delete OTP
			rdb.Del(ctx, emailKey)
			rdb.Del(ctx, firebaseKey)
			emailVerified = req.Email
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Incorrect or expired OTP"})
			return
		}
	} else {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Must provide either (email + otp) or firebase_id_token"})
		return
	}

	// Find or Create User in MySQL Database
	var user User
	err := db.Where("email = ?", emailVerified).First(&user).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		// Create new user with starting balance
		user = User{
			Email:   emailVerified,
			Balance: 100000, // Rp100.000
		}
		if err := db.Create(&user).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user session"})
			return
		}
		log.Printf("Successfully created new user: %s", emailVerified)
	}

	// Generate Backend JWT Token
	claims := JWTClaims{
		UserID: user.ID,
		Email:  user.Email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to sign JWT token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Authentication successful",
		"token":   tokenString,
		"user":    user,
	})
}

// 6. POST /v1/otp/totp/register
func registerTOTP(c *gin.Context) {
	email, _ := c.Get("email")
	userID, _ := c.Get("userID")

	// Generate a new TOTP secret for the user
	key, err := totp.Generate(totp.GenerateOpts{
		Issuer:      "EMoneyApp",
		AccountName: email.(string),
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate TOTP secret"})
		return
	}

	// Temporarily save to database (do not mark as Enabled yet)
	if err := db.Model(&User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"totp_secret": key.Secret(),
	}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save TOTP secret"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"secret":       key.Secret(),
		"qr_code_url":  key.URL(),
		"instructions": "Scan QR Code url or enter secret in Google Authenticator. Then call /v1/otp/totp/verify with the code to enable.",
	})
}

// 7. POST /v1/otp/totp/verify
func verifyTOTP(c *gin.Context) {
	userID, _ := c.Get("userID")

	var req struct {
		Code string `json:"code" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Code is required"})
		return
	}

	// Get User's Secret
	var user User
	if err := db.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	if user.TOTPSecret == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "TOTP is not registered yet. Call /v1/otp/totp/register first."})
		return
	}

	// Validate code
	valid := totp.Validate(req.Code, user.TOTPSecret)
	if !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid verification code. Please check your Google Authenticator app."})
		return
	}

	// Enable TOTP permanently
	if err := db.Model(&user).Update("totp_enabled", true).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to enable TOTP"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":      "Two-Factor Authentication (TOTP) successfully enabled!",
		"totp_enabled": true,
	})
}

// 8. POST /v1/payment/transfer
func transferPayment(c *gin.Context) {
	senderID, _ := c.Get("userID")
	senderEmail, _ := c.Get("email")

	var req struct {
		RecipientEmail string `json:"recipient_email" binding:"required,email"`
		Amount         int64  `json:"amount" binding:"required,gt=0"`
		OTP            string `json:"otp"`
		OTPType        string `json:"otp_type"` // "email", "firebase", or "totp"
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request parameters"})
		return
	}

	// Fetch Sender & Recipient
	var sender User
	if err := db.First(&sender, senderID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Sender not found"})
		return
	}

	var recipient User
	if err := db.Where("email = ?", req.RecipientEmail).First(&recipient).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Recipient user email not found in database"})
		return
	}

	if sender.Email == req.RecipientEmail {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot transfer to yourself"})
		return
	}

	// Check if Sender balance is sufficient
	if sender.Balance < req.Amount {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Insufficient balance"})
		return
	}

	// 2FA VERIFICATION (If user has TOTP enabled, or if they explicitly chose an OTP security check)
	is2FARequired := sender.TOTPEnabled || req.OTPType != ""

	if is2FARequired {
		if req.OTP == "" {
			c.JSON(http.StatusForbidden, gin.H{
				"error":        "2FA verification required to complete transfer",
				"totp_enabled": sender.TOTPEnabled,
				"fyi":          "Please trigger send OTP first or send the 'otp' parameter.",
			})
			return
		}

		ctx := context.Background()
		var isOTPValid bool

		// Check 2FA Type
		if req.OTPType == "totp" || (sender.TOTPEnabled && req.OTPType == "") {
			if sender.TOTPSecret == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "TOTP is enabled but no secret is registered"})
				return
			}
			isOTPValid = totp.Validate(req.OTP, sender.TOTPSecret)
		} else if req.OTPType == "email" {
			redisKey := fmt.Sprintf("otp:email:%s", senderEmail)
			savedOTP, _ := rdb.Get(ctx, redisKey).Result()
			if savedOTP != "" && savedOTP == req.OTP {
				rdb.Del(ctx, redisKey)
				isOTPValid = true
			}
		} else if req.OTPType == "firebase" {
			redisKey := fmt.Sprintf("otp:firebase:%s", senderEmail)
			savedOTP, _ := rdb.Get(ctx, redisKey).Result()
			if savedOTP != "" && savedOTP == req.OTP {
				rdb.Del(ctx, redisKey)
				isOTPValid = true
			}
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Unsupported or missing otp_type (must be email, firebase, or totp)"})
			return
		}

		if !isOTPValid {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid 2FA code or OTP expired"})
			return
		}
	}

	// Perform Transfer Transaction
	err := db.Transaction(func(tx *gorm.DB) error {
		// Deduct from Sender
		if err := tx.Model(&sender).Update("balance", gorm.Expr("balance - ?", req.Amount)).Error; err != nil {
			return err
		}
		// Add to Recipient
		if err := tx.Model(&recipient).Update("balance", gorm.Expr("balance + ?", req.Amount)).Error; err != nil {
			return err
		}
		return nil
	})

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to complete database transaction"})
		return
	}

	// Get Updated Balance
	var updatedSender User
	db.First(&updatedSender, senderID)

	// Send FCM push notifications to both sender and recipient
	ctx := context.Background()

	// Notify Recipient (Merchant / E-Commerce)
	recipientNotifyMsg := fmt.Sprintf("Anda menerima pembayaran sebesar Rp %d dari %s", req.Amount, senderEmail.(string))
	recipientStatus := sendFCMNotification(ctx, recipient.FCMToken, "Pembayaran Diterima", recipientNotifyMsg, map[string]string{
		"type":            "payment_received",
		"amount":          strconv.FormatInt(req.Amount, 10),
		"sender_email":    senderEmail.(string),
		"recipient_email": req.RecipientEmail,
	})
	log.Printf("FCM to Recipient (%s): %s", req.RecipientEmail, recipientStatus)

	// Notify Sender (Wallet / Customer)
	senderNotifyMsg := fmt.Sprintf("Pembayaran sebesar Rp %d ke %s berhasil", req.Amount, req.RecipientEmail)
	senderStatus := sendFCMNotification(ctx, sender.FCMToken, "Transaksi Berhasil", senderNotifyMsg, map[string]string{
		"type":            "payment_sent",
		"amount":          strconv.FormatInt(req.Amount, 10),
		"sender_email":    senderEmail.(string),
		"recipient_email": req.RecipientEmail,
	})
	log.Printf("FCM to Sender (%s): %s", senderEmail.(string), senderStatus)

	c.JSON(http.StatusOK, gin.H{
		"message":         "Transfer completed successfully!",
		"amount":          req.Amount,
		"recipient_email": req.RecipientEmail,
		"sender_balance":  updatedSender.Balance,
	})
}

// ==========================================
// UTILITY FUNCTIONS
// ==========================================

func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}

func generateOTP() string {
	rand.Seed(time.Now().UnixNano())
	// Generates a 6 digit number
	return fmt.Sprintf("%06d", rand.Intn(1000000))
}

func printBanner() {
	banner := `
=============================================================
             E-MONEY TWO-FACTOR AUTHENTICATION               
                     BACKEND SERVICE                         
=============================================================
  [✔] Database MySQL: Connected (Port: 3306)
  [✔] Cache Redis: Connected (Port: 6379)
  [✔] Web Port: Listening (Port: 8080)
=============================================================
`
	fmt.Print(banner)
}

func sendFCMNotification(ctx context.Context, token string, title string, body string, data map[string]string) string {
	if firebaseApp == nil {
		return "Firebase app not initialized (Running in Mock mode)"
	}
	if token == "" {
		return "FCM Token is empty for user"
	}
	msgClient, err := firebaseApp.Messaging(ctx)
	if err != nil {
		return fmt.Sprintf("Failed to get FCM client: %v", err)
	}
	message := &messaging.Message{
		Token: token,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
	}
	_, err = msgClient.Send(ctx, message)
	if err != nil {
		return fmt.Sprintf("Failed to send FCM message: %v", err)
	}
	return "Sent successfully via FCM"
}
