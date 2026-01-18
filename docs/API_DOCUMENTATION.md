# Flame Dating App - Backend API Documentation

## Overview

This document outlines all the API endpoints required for the Flame dating app. The backend should implement RESTful APIs with JWT-based authentication.

---

## Base Configuration

- **Base URL**: `https://api.flame.app/v1`
- **Content-Type**: `application/json`
- **Authentication**: Bearer Token (JWT)

### Headers

```
Authorization: Bearer <access_token>
Content-Type: application/json
```

---

## Authentication Endpoints

### 1. Register New User

Creates a new user account.

**Endpoint**: `POST /auth/register`

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "securePassword123",
  "name": "John Doe",
  "age": 25,
  "gender": "male",
  "looking_for": "female",
  "bio": "Looking for something meaningful",
  "interests": ["Music", "Travel", "Food", "Photography"],
  "photos": ["base64_encoded_image_or_url"]
}
```

**Validation Rules**:
- `email`: Required, valid email format, unique
- `password`: Required, min 8 characters, must contain uppercase, lowercase, and number
- `name`: Required, 2-50 characters
- `age`: Required, 18-100
- `gender`: Required, enum: `male`, `female`, `non_binary`, `other`
- `looking_for`: Required, enum: `male`, `female`, `non_binary`, `other`
- `bio`: Optional, max 500 characters
- `interests`: Required, array of strings, min 1, max 10
- `photos`: Required, array of strings, min 1, max 6

**Response (201 Created)**:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "usr_abc123",
      "email": "user@example.com",
      "name": "John Doe",
      "age": 25,
      "gender": "male",
      "looking_for": "female",
      "bio": "Looking for something meaningful",
      "interests": ["Music", "Travel", "Food", "Photography"],
      "photos": ["https://cdn.flame.app/photos/usr_abc123/1.jpg"],
      "location": null,
      "is_online": true,
      "last_active": "2024-01-15T10:30:00Z",
      "created_at": "2024-01-15T10:30:00Z",
      "preferences": {
        "min_age": 18,
        "max_age": 50,
        "max_distance": 50
      }
    },
    "tokens": {
      "access_token": "eyJhbGciOiJIUzI1NiIs...",
      "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
      "expires_in": 3600
    }
  }
}
```

**Error Response (400 Bad Request)**:
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Validation failed",
    "details": {
      "email": "Email already registered",
      "password": "Password must be at least 8 characters"
    }
  }
}
```

---

### 2. Login

Authenticates user and returns tokens.

**Endpoint**: `POST /auth/login`

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "securePassword123",
  "device_token": "fcm_device_token_for_push_notifications"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "usr_abc123",
      "email": "user@example.com",
      "name": "John Doe",
      "age": 25,
      "gender": "male",
      "looking_for": "female",
      "bio": "Looking for something meaningful",
      "interests": ["Music", "Travel", "Food", "Photography"],
      "photos": ["https://cdn.flame.app/photos/usr_abc123/1.jpg"],
      "location": "New York, NY",
      "is_online": true,
      "last_active": "2024-01-15T10:30:00Z",
      "preferences": {
        "min_age": 18,
        "max_age": 50,
        "max_distance": 50
      }
    },
    "tokens": {
      "access_token": "eyJhbGciOiJIUzI1NiIs...",
      "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
      "expires_in": 3600
    }
  }
}
```

**Error Response (401 Unauthorized)**:
```json
{
  "success": false,
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "Invalid email or password"
  }
}
```

---

### 3. Refresh Token

Refreshes the access token using refresh token.

**Endpoint**: `POST /auth/refresh`

**Request Body**:
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_in": 3600
  }
}
```

---

### 4. Logout

Invalidates the current session and tokens.

**Endpoint**: `POST /auth/logout`

**Headers**: Authorization required

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Successfully logged out"
}
```

---

### 5. Forgot Password

Sends password reset email.

**Endpoint**: `POST /auth/forgot-password`

**Request Body**:
```json
{
  "email": "user@example.com"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Password reset email sent"
}
```

---

### 6. Reset Password

Resets password using token from email.

**Endpoint**: `POST /auth/reset-password`

**Request Body**:
```json
{
  "token": "reset_token_from_email",
  "password": "newSecurePassword123",
  "password_confirmation": "newSecurePassword123"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Password successfully reset"
}
```

---

### 7. Verify Email

Verifies user email address.

**Endpoint**: `POST /auth/verify-email`

**Request Body**:
```json
{
  "token": "verification_token_from_email"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Email successfully verified"
}
```

---

### 8. Resend Verification Email

**Endpoint**: `POST /auth/resend-verification`

**Headers**: Authorization required

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Verification email sent"
}
```

---

### 9. Change Password

**Endpoint**: `POST /auth/change-password`

**Headers**: Authorization required

**Request Body**:
```json
{
  "current_password": "oldPassword123",
  "new_password": "newSecurePassword123",
  "new_password_confirmation": "newSecurePassword123"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Password successfully changed"
}
```

---

## Social Authentication

### 10. Google Sign In

**Endpoint**: `POST /auth/google`

**Request Body**:
```json
{
  "id_token": "google_id_token",
  "device_token": "fcm_device_token"
}
```

**Response**: Same as login response

---

### 11. Apple Sign In

**Endpoint**: `POST /auth/apple`

**Request Body**:
```json
{
  "id_token": "apple_id_token",
  "authorization_code": "apple_auth_code",
  "device_token": "fcm_device_token"
}
```

**Response**: Same as login response

---

### 12. Facebook Sign In

**Endpoint**: `POST /auth/facebook`

**Request Body**:
```json
{
  "access_token": "facebook_access_token",
  "device_token": "fcm_device_token"
}
```

**Response**: Same as login response

---

## User Profile Endpoints

### 13. Get Current User Profile

**Endpoint**: `GET /users/me`

**Headers**: Authorization required

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "id": "usr_abc123",
    "email": "user@example.com",
    "name": "John Doe",
    "age": 25,
    "gender": "male",
    "looking_for": "female",
    "bio": "Looking for something meaningful",
    "interests": ["Music", "Travel", "Food", "Photography"],
    "photos": [
      {
        "id": "photo_1",
        "url": "https://cdn.flame.app/photos/usr_abc123/1.jpg",
        "is_primary": true,
        "order": 0
      }
    ],
    "location": {
      "city": "New York",
      "state": "NY",
      "country": "USA",
      "coordinates": {
        "latitude": 40.7128,
        "longitude": -74.0060
      }
    },
    "is_online": true,
    "is_verified": true,
    "last_active": "2024-01-15T10:30:00Z",
    "created_at": "2024-01-01T00:00:00Z",
    "preferences": {
      "min_age": 18,
      "max_age": 35,
      "max_distance": 50,
      "show_distance": true,
      "show_online_status": true
    },
    "settings": {
      "notifications_enabled": true,
      "discovery_enabled": true,
      "dark_mode": false
    }
  }
}
```

---

### 14. Update User Profile

**Endpoint**: `PATCH /users/me`

**Headers**: Authorization required

**Request Body** (partial update):
```json
{
  "name": "John Updated",
  "bio": "Updated bio",
  "interests": ["Music", "Sports"],
  "looking_for": "female"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "id": "usr_abc123",
    "name": "John Updated",
    "bio": "Updated bio",
    "interests": ["Music", "Sports"],
    "looking_for": "female"
    // ... other fields
  }
}
```

---

### 15. Update User Location

**Endpoint**: `PATCH /users/me/location`

**Headers**: Authorization required

**Request Body**:
```json
{
  "latitude": 40.7128,
  "longitude": -74.0060
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "location": {
      "city": "New York",
      "state": "NY",
      "country": "USA",
      "coordinates": {
        "latitude": 40.7128,
        "longitude": -74.0060
      }
    }
  }
}
```

---

### 16. Update User Preferences

**Endpoint**: `PATCH /users/me/preferences`

**Headers**: Authorization required

**Request Body**:
```json
{
  "min_age": 20,
  "max_age": 35,
  "max_distance": 25,
  "show_distance": true,
  "show_online_status": false
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "preferences": {
      "min_age": 20,
      "max_age": 35,
      "max_distance": 25,
      "show_distance": true,
      "show_online_status": false
    }
  }
}
```

---

### 17. Upload Photo

**Endpoint**: `POST /users/me/photos`

**Headers**: Authorization required, Content-Type: multipart/form-data

**Request Body**:
```
photo: <binary_image_file>
is_primary: false
```

**Response (201 Created)**:
```json
{
  "success": true,
  "data": {
    "id": "photo_123",
    "url": "https://cdn.flame.app/photos/usr_abc123/photo_123.jpg",
    "is_primary": false,
    "order": 2
  }
}
```

---

### 18. Delete Photo

**Endpoint**: `DELETE /users/me/photos/:photo_id`

**Headers**: Authorization required

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Photo deleted successfully"
}
```

---

### 19. Reorder Photos

**Endpoint**: `PATCH /users/me/photos/reorder`

**Headers**: Authorization required

**Request Body**:
```json
{
  "photo_ids": ["photo_2", "photo_1", "photo_3"]
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "photos": [
      {"id": "photo_2", "order": 0, "is_primary": true},
      {"id": "photo_1", "order": 1, "is_primary": false},
      {"id": "photo_3", "order": 2, "is_primary": false}
    ]
  }
}
```

---

### 20. Get User by ID (for viewing other profiles)

**Endpoint**: `GET /users/:user_id`

**Headers**: Authorization required

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "id": "usr_xyz789",
    "name": "Jane Doe",
    "age": 24,
    "gender": "female",
    "bio": "Adventure seeker",
    "interests": ["Travel", "Hiking", "Photography"],
    "photos": ["https://cdn.flame.app/photos/usr_xyz789/1.jpg"],
    "location": "Brooklyn, NY",
    "distance": 5.2,
    "is_online": false,
    "last_active": "2024-01-15T09:00:00Z"
  }
}
```

---

### 21. Delete Account

**Endpoint**: `DELETE /users/me`

**Headers**: Authorization required

**Request Body**:
```json
{
  "password": "currentPassword123",
  "reason": "Found someone"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Account successfully deleted"
}
```

---

## Discovery Endpoints

### 22. Get Potential Matches (Discovery Feed)

**Endpoint**: `GET /discover`

**Headers**: Authorization required

**Query Parameters**:
- `limit`: Number of profiles to return (default: 10, max: 50)
- `offset`: Pagination offset

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "users": [
      {
        "id": "usr_xyz789",
        "name": "Jane",
        "age": 24,
        "gender": "female",
        "bio": "Adventure seeker",
        "interests": ["Travel", "Hiking", "Photography"],
        "photos": ["https://cdn.flame.app/photos/usr_xyz789/1.jpg"],
        "location": "Brooklyn, NY",
        "distance": 5.2,
        "is_online": true,
        "last_active": "2024-01-15T10:00:00Z",
        "common_interests": ["Travel", "Photography"]
      }
    ],
    "pagination": {
      "total": 150,
      "limit": 10,
      "offset": 0,
      "has_more": true
    }
  }
}
```

---

## Swipe/Like Endpoints

### 23. Like a User (Swipe Right)

**Endpoint**: `POST /swipes/like`

**Headers**: Authorization required

**Request Body**:
```json
{
  "user_id": "usr_xyz789"
}
```

**Response (200 OK)** - No match:
```json
{
  "success": true,
  "data": {
    "liked": true,
    "is_match": false
  }
}
```

**Response (200 OK)** - Match!:
```json
{
  "success": true,
  "data": {
    "liked": true,
    "is_match": true,
    "match": {
      "id": "match_abc123",
      "user": {
        "id": "usr_xyz789",
        "name": "Jane",
        "photos": ["https://cdn.flame.app/photos/usr_xyz789/1.jpg"]
      },
      "matched_at": "2024-01-15T10:30:00Z"
    }
  }
}
```

---

### 24. Pass a User (Swipe Left)

**Endpoint**: `POST /swipes/pass`

**Headers**: Authorization required

**Request Body**:
```json
{
  "user_id": "usr_xyz789"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "passed": true
  }
}
```

---

### 25. Super Like a User

**Endpoint**: `POST /swipes/super-like`

**Headers**: Authorization required

**Request Body**:
```json
{
  "user_id": "usr_xyz789"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "super_liked": true,
    "is_match": false,
    "remaining_super_likes": 2
  }
}
```

---

### 26. Undo Last Swipe

**Endpoint**: `POST /swipes/undo`

**Headers**: Authorization required

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "undone": true,
    "user": {
      "id": "usr_xyz789",
      "name": "Jane"
    }
  }
}
```

---

## Match Endpoints

### 27. Get All Matches

**Endpoint**: `GET /matches`

**Headers**: Authorization required

**Query Parameters**:
- `limit`: Number of matches (default: 20)
- `offset`: Pagination offset
- `new_only`: Filter only new matches (boolean)

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "matches": [
      {
        "id": "match_abc123",
        "user": {
          "id": "usr_xyz789",
          "name": "Jane",
          "age": 24,
          "photos": ["https://cdn.flame.app/photos/usr_xyz789/1.jpg"],
          "is_online": true,
          "last_active": "2024-01-15T10:00:00Z"
        },
        "matched_at": "2024-01-15T08:00:00Z",
        "is_new": true,
        "last_message": null
      }
    ],
    "pagination": {
      "total": 25,
      "limit": 20,
      "offset": 0,
      "has_more": true
    }
  }
}
```

---

### 28. Unmatch User

**Endpoint**: `DELETE /matches/:match_id`

**Headers**: Authorization required

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Successfully unmatched"
}
```

---

## Messaging Endpoints

### 29. Get Conversations

**Endpoint**: `GET /conversations`

**Headers**: Authorization required

**Query Parameters**:
- `limit`: Number of conversations (default: 20)
- `offset`: Pagination offset

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "conversations": [
      {
        "id": "conv_abc123",
        "match_id": "match_abc123",
        "other_user": {
          "id": "usr_xyz789",
          "name": "Jane",
          "photos": ["https://cdn.flame.app/photos/usr_xyz789/1.jpg"],
          "is_online": true
        },
        "last_message": {
          "id": "msg_123",
          "content": "Hey! How are you?",
          "sender_id": "usr_xyz789",
          "timestamp": "2024-01-15T10:30:00Z",
          "status": "delivered"
        },
        "unread_count": 2,
        "updated_at": "2024-01-15T10:30:00Z"
      }
    ],
    "pagination": {
      "total": 10,
      "limit": 20,
      "offset": 0,
      "has_more": false
    }
  }
}
```

---

### 30. Get Messages in Conversation

**Endpoint**: `GET /conversations/:conversation_id/messages`

**Headers**: Authorization required

**Query Parameters**:
- `limit`: Number of messages (default: 50)
- `before`: Message ID for pagination (get messages before this)

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "messages": [
      {
        "id": "msg_123",
        "sender_id": "usr_xyz789",
        "content": "Hey! How are you?",
        "type": "text",
        "timestamp": "2024-01-15T10:30:00Z",
        "status": "read"
      },
      {
        "id": "msg_124",
        "sender_id": "usr_abc123",
        "content": "I'm great! Nice to match with you!",
        "type": "text",
        "timestamp": "2024-01-15T10:31:00Z",
        "status": "delivered"
      }
    ],
    "has_more": true
  }
}
```

---

### 31. Send Message

**Endpoint**: `POST /conversations/:conversation_id/messages`

**Headers**: Authorization required

**Request Body**:
```json
{
  "content": "Hey! Nice to meet you!",
  "type": "text"
}
```

**Response (201 Created)**:
```json
{
  "success": true,
  "data": {
    "id": "msg_125",
    "sender_id": "usr_abc123",
    "content": "Hey! Nice to meet you!",
    "type": "text",
    "timestamp": "2024-01-15T10:35:00Z",
    "status": "sent"
  }
}
```

---

### 32. Send Image Message

**Endpoint**: `POST /conversations/:conversation_id/messages/image`

**Headers**: Authorization required, Content-Type: multipart/form-data

**Request Body**:
```
image: <binary_image_file>
```

**Response (201 Created)**:
```json
{
  "success": true,
  "data": {
    "id": "msg_126",
    "sender_id": "usr_abc123",
    "content": "https://cdn.flame.app/messages/msg_126.jpg",
    "type": "image",
    "timestamp": "2024-01-15T10:36:00Z",
    "status": "sent"
  }
}
```

---

### 33. Mark Messages as Read

**Endpoint**: `POST /conversations/:conversation_id/read`

**Headers**: Authorization required

**Request Body**:
```json
{
  "message_ids": ["msg_123", "msg_124"]
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "Messages marked as read"
}
```

---

## Reporting & Blocking

### 34. Report User

**Endpoint**: `POST /reports`

**Headers**: Authorization required

**Request Body**:
```json
{
  "user_id": "usr_xyz789",
  "reason": "inappropriate_content",
  "details": "User sent inappropriate messages"
}
```

**Reason Enums**: `inappropriate_content`, `fake_profile`, `harassment`, `spam`, `underage`, `other`

**Response (201 Created)**:
```json
{
  "success": true,
  "message": "Report submitted successfully"
}
```

---

### 35. Block User

**Endpoint**: `POST /blocks`

**Headers**: Authorization required

**Request Body**:
```json
{
  "user_id": "usr_xyz789"
}
```

**Response (201 Created)**:
```json
{
  "success": true,
  "message": "User blocked successfully"
}
```

---

### 36. Unblock User

**Endpoint**: `DELETE /blocks/:user_id`

**Headers**: Authorization required

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "User unblocked successfully"
}
```

---

### 37. Get Blocked Users

**Endpoint**: `GET /blocks`

**Headers**: Authorization required

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "blocked_users": [
      {
        "id": "usr_xyz789",
        "name": "Jane",
        "blocked_at": "2024-01-15T10:00:00Z"
      }
    ]
  }
}
```

---

## Push Notifications

### 38. Register Device Token

**Endpoint**: `POST /devices`

**Headers**: Authorization required

**Request Body**:
```json
{
  "token": "fcm_device_token",
  "platform": "ios"
}
```

**Platform Enums**: `ios`, `android`

**Response (201 Created)**:
```json
{
  "success": true,
  "message": "Device registered successfully"
}
```

---

### 39. Update Notification Settings

**Endpoint**: `PATCH /users/me/notifications`

**Headers**: Authorization required

**Request Body**:
```json
{
  "new_matches": true,
  "new_messages": true,
  "super_likes": true,
  "promotions": false
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "notifications": {
      "new_matches": true,
      "new_messages": true,
      "super_likes": true,
      "promotions": false
    }
  }
}
```

---

## WebSocket Events

For real-time messaging, implement WebSocket connection.

**Connection URL**: `wss://api.flame.app/ws?token=<access_token>`

### Events to Implement:

#### Client to Server:
- `ping` - Keep connection alive
- `typing` - User is typing
- `stop_typing` - User stopped typing
- `message_read` - Mark message as read

#### Server to Client:
- `new_message` - New message received
- `message_status` - Message status update (delivered, read)
- `user_typing` - Other user is typing
- `user_online` - User came online
- `user_offline` - User went offline
- `new_match` - New match notification

**Event Payload Examples**:

```json
// new_message
{
  "event": "new_message",
  "data": {
    "conversation_id": "conv_abc123",
    "message": {
      "id": "msg_127",
      "sender_id": "usr_xyz789",
      "content": "Hello!",
      "type": "text",
      "timestamp": "2024-01-15T10:40:00Z"
    }
  }
}

// new_match
{
  "event": "new_match",
  "data": {
    "match_id": "match_xyz789",
    "user": {
      "id": "usr_xyz789",
      "name": "Jane",
      "photos": ["https://cdn.flame.app/photos/usr_xyz789/1.jpg"]
    }
  }
}
```

---

## Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `VALIDATION_ERROR` | 400 | Request validation failed |
| `INVALID_CREDENTIALS` | 401 | Wrong email or password |
| `UNAUTHORIZED` | 401 | Missing or invalid token |
| `TOKEN_EXPIRED` | 401 | Access token has expired |
| `FORBIDDEN` | 403 | Action not allowed |
| `NOT_FOUND` | 404 | Resource not found |
| `EMAIL_EXISTS` | 409 | Email already registered |
| `ALREADY_MATCHED` | 409 | Already matched with user |
| `RATE_LIMITED` | 429 | Too many requests |
| `SERVER_ERROR` | 500 | Internal server error |

---

## Data Models

### User
```typescript
interface User {
  id: string;
  email: string;
  name: string;
  age: number;
  gender: 'male' | 'female' | 'non_binary' | 'other';
  looking_for: 'male' | 'female' | 'non_binary' | 'other';
  bio: string;
  interests: string[];
  photos: Photo[];
  location: Location;
  distance?: number;
  is_online: boolean;
  is_verified: boolean;
  last_active: string; // ISO 8601
  created_at: string;
  preferences: UserPreferences;
}

interface Photo {
  id: string;
  url: string;
  is_primary: boolean;
  order: number;
}

interface Location {
  city: string;
  state: string;
  country: string;
  coordinates: {
    latitude: number;
    longitude: number;
  };
}

interface UserPreferences {
  min_age: number;
  max_age: number;
  max_distance: number;
  show_distance: boolean;
  show_online_status: boolean;
}
```

### Match
```typescript
interface Match {
  id: string;
  user: User;
  matched_at: string;
  is_new: boolean;
  last_message?: Message;
}
```

### Message
```typescript
interface Message {
  id: string;
  sender_id: string;
  content: string;
  type: 'text' | 'image' | 'gif';
  timestamp: string;
  status: 'sending' | 'sent' | 'delivered' | 'read' | 'failed';
}
```

### Conversation
```typescript
interface Conversation {
  id: string;
  match_id: string;
  other_user: User;
  last_message?: Message;
  unread_count: number;
  updated_at: string;
}
```

---

## Security Requirements

1. **Password Hashing**: Use bcrypt with salt rounds >= 12
2. **JWT**:
   - Access token expiry: 1 hour
   - Refresh token expiry: 30 days
   - Use RS256 algorithm
3. **Rate Limiting**:
   - Login: 5 attempts per 15 minutes
   - Registration: 3 per hour per IP
   - API calls: 100 per minute per user
4. **Input Validation**: Sanitize all inputs, prevent SQL injection and XSS
5. **HTTPS**: All endpoints must use HTTPS
6. **Photo Upload**:
   - Max size: 10MB
   - Allowed formats: JPEG, PNG, WebP
   - Scan for inappropriate content

---

## Notes for Backend Developer

1. Implement proper indexing on MongoDB for:
   - User location (2dsphere index for geo queries)
   - User preferences for matching algorithm
   - Conversation timestamps

2. Use Redis for:
   - Session management
   - Rate limiting
   - Online status caching
   - Real-time typing indicators

3. Consider implementing:
   - Photo moderation (AI-based)
   - Spam detection for messages
   - Fake profile detection
   - Email verification flow
   - SMS verification as optional

4. Push Notifications via Firebase Cloud Messaging (FCM) for:
   - New matches
   - New messages
   - Super likes received
   - Profile likes (premium feature)

---

**Document Version**: 1.0
**Last Updated**: January 2024
**App Version**: 1.0.0
