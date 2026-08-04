# Laundry App - Complete Laundry Management System

A full-featured Flutter laundry management application with **Customer**, **Staff**, and **Admin** roles.

## Features

### 👤 Customer
- Register with GPS location validation
- Browse laundry services
- Create orders with weight & service selection
- Real-time delivery fee calculation
- GCash payment with receipt upload
- Order tracking with status updates
- Order history & receipts

### 👥 Staff
- View assigned tasks
- Update laundry status (Received → Washing → Drying → Folding → Ready)
- Priority-based delivery queue (nearest first)
- Mark deliveries as completed

### 👑 Admin
- Dashboard with sales analytics
- Manage all orders
- Verify GCash payments (approve/reject)
- Walk-in transaction creation
- Staff assignment
- Reports & revenue tracking

## Tech Stack
- **Framework**: Flutter (Dart)
- **Backend**: Firebase (Auth, Firestore, Storage)
- **State Management**: Provider
- **Location**: Geolocator + Geocoding
- **Payment**: GCash receipt verification

## Setup Instructions

### Prerequisites
- Flutter SDK (^3.12.1)
- Firebase project

### Firebase Setup
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a new project
3. Add Android/iOS app
4. Download `google-services.json` (Android) and/or `GoogleService-Info.plist` (iOS)
5. Place in respective directories:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`
6. Enable Authentication (Email/Password)
7. Enable Firestore Database
8. Enable Firebase Storage

### Installation
```bash
git clone <repo-url>
cd laundry_app
flutter pub get
flutter run
```

### Default Services (auto-seeded)
| Service | Price |
|---------|-------|
| Wash & Dry | ₱35/kg |
| Wash, Dry & Fold | ₱50/kg |
| Dry Clean | ₱80/kg |
| Iron Only | ₱15/item |

### Shop Location
- **Address**: Sabalo, Brgy. 12, Caloocan City
- **Coordinates**: 14.653173, 120.967443
- **Max Delivery Radius**: 15 km
- **Delivery Fee**: ₱20 base + ₱15/km
- **GCash Number**: 09932184932

## Project Structure
```
lib/
├── config/          # Theme, routes, app config
├── core/            # Constants, utils, shared widgets
├── models/          # Data models
├── services/        # Firebase, auth, location services
├── engines/         # Business logic (distance, fee, priority)
├── repositories/    # Data access layer
├── providers/       # State management
├── features/        # Screen modules
│   ├── auth/        # Login, register, forgot password
│   ├── customer/    # Customer screens
│   ├── staff/       # Staff screens
│   └── admin/       # Admin screens
├── localization/    # i18n (English, Filipino)
├── printing/        # Thermal receipt printing
├── database/        # Firestore structure docs
└── app.dart         # App entry with routing
```

## Order Status Flow
1. Pending → Pending Payment → Paid → Order Received
2. Washing → Drying → Folding → Ready for Delivery
3. Out for Delivery → Delivered → Completed

## Delivery Priority Algorithm
```
Priority Score = (1 / Distance) * 0.4 + (Age) * 0.3 + (Urgency) * 0.3
```
- Nearest customers get highest priority
- Older orders get priority boost
- Urgent orders flagged by admin
