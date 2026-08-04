# Laundry App - Firebase Database Structure

## Collections

### users
```
users/{userId}
  - id: string
  - name: string
  - email: string
  - phone: string
  - role: string (customer | staff | admin)
  - latitude: number
  - longitude: number
  - address: string
  - createdAt: timestamp
```

### orders
```
orders/{orderId}
  - id: string
  - userId: string
  - customerName: string
  - customerPhone: string
  - serviceType: string
  - pricePerKg: number
  - items: array<orderItem>
  - weight: number
  - subtotal: number
  - deliveryFee: number
  - totalAmount: number
  - customerLatitude: number
  - customerLongitude: number
  - distanceKm: number
  - paymentMethod: string
  - paymentStatus: string
  - status: string (See status flow)
  - assignedTo: string
  - staffId: string
  - notes: string
  - isWalkIn: boolean
  - createdAt: timestamp
  - updatedAt: timestamp
  - completedAt: timestamp
```

### services
```
services/{serviceId}
  - name: string
  - description: string
  - pricePerKg: number
  - pricePerItem: number
  - type: string
  - estimatedMinutes: number
  - isActive: boolean
  - order: number
```

### payments
```
payments/{paymentId}
  - id: string
  - orderId: string
  - userId: string
  - amount: number
  - method: string (GCash | Cash)
  - referenceNumber: string
  - receiptImageUrl: string
  - status: string (Pending Verification | Approved | Rejected)
  - verifiedBy: string
  - verifiedAt: timestamp
  - rejectionReason: string
  - createdAt: timestamp
```

### deliveries
```
deliveries/{deliveryId}
  - id: string
  - orderId: string
  - staffId: string
  - customerName: string
  - customerAddress: string
  - customerLatitude: number
  - customerLongitude: number
  - distanceKm: number
  - priority: string (HIGH | MEDIUM | LOW)
  - status: string
  - pickedUpAt: timestamp
  - deliveredAt: timestamp
  - createdAt: timestamp
```

### soaps
```
soaps/{soapId}
  - name: string
  - brand: string
  - description: string
  - price: number
  - unit: string (sachet | bottle | bar)
  - stockQuantity: number
  - stockStatus: string (In Stock | Out of Stock)
  - category: string (Detergent | Fabric Conditioner | Bleach | Laundry Soap)
  - colorHex: string (brand color for UI display)
  - isActive: boolean
  - imageUrl: string
  - order: number
  - createdAt: timestamp
```

### notifications
```
notifications/{notificationId}
  - id: string
  - userId: string
  - title: string
  - body: string
  - type: string
  - isRead: boolean
  - createdAt: timestamp
```

## Order Status Flow
1. Pending
2. Pending Payment
3. Paid
4. Order Received
5. Washing
6. Drying
7. Folding
8. Ready for Delivery
9. Out for Delivery
10. Delivered
11. Completed

## Security Rules (Firestore)
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      allow read: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
    match /orders/{orderId} {
      allow read: if request.auth != null && 
        (resource.data.userId == request.auth.uid || 
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role in ['admin', 'staff']);
      allow create: if request.auth != null;
      allow update: if request.auth != null;
    }
    match /payments/{paymentId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
