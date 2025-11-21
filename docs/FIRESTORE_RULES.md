# Firestore Security Rules

This document outlines the required Firestore security rules for the Luca application. These rules should be deployed via the Firebase Console.

## Required Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check authentication
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper function to check if user owns the document
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    // Vector Memories Collection
    match /vector_memories/{memoryId} {
      allow read, write: if isAuthenticated() && isOwner(resource.data.userId);
      allow create: if isAuthenticated() && isOwner(request.resource.data.userId);
    }
    
    // Chat Sessions Collection
    match /sessions/{sessionId} {
      allow read, write: if isAuthenticated() && isOwner(resource.data.userId);
      allow create: if isAuthenticated() && isOwner(request.resource.data.userId);
    }
    
    // Chat Messages Collection
    match /messages/{messageId} {
      allow read: if isAuthenticated() && isOwner(resource.data.userId);
      // Use getAfter() so serverTimestamp() validates as timestamp
      allow create: if isAuthenticated() && 
                      isOwner(request.resource.data.userId) &&
                      getAfter().data.createdAt is timestamp &&
                      getAfter().data.updatedAt is timestamp;
      allow update: if isAuthenticated() && 
                      isOwner(resource.data.userId) &&
                      getAfter().data.updatedAt is timestamp;
      allow delete: if isAuthenticated() && isOwner(resource.data.userId);
    }
    
    // Listen Sessions Collection
    match /user_sessions/{sessionId} {
      allow read, write: if isAuthenticated() && isOwner(resource.data.userId);
      allow create: if isAuthenticated() && isOwner(request.resource.data.userId);
      
      // Segments Subcollection
      match /segments/{segmentId} {
        // Create allowed by segment's own userId to avoid parent race
        allow create: if isAuthenticated() && isOwner(request.resource.data.userId);
        // Read/Update/Delete allowed by segment.userId OR parent userId (legacy)
        allow read, update, delete: if isAuthenticated() && (
            isOwner(resource.data.userId) ||
            isOwner(get(/databases/$(database)/documents/user_sessions/$(sessionId)).data.userId)
        );
      }
    }
  }
}
```

## Required Composite Indexes

These indexes should be created in the Firebase Console under Firestore > Indexes:

### messages collection:
1. **userId (Asc) + sessionId (Asc) + timestamp (Desc)**
   - Used by: `getRecentMessages()`, `getRecentConversationContext()`

2. **userId (Asc) + timestamp (Desc)**
   - Used by: General message queries

### sessions collection:
1. **userId (Asc) + startTime (Desc)**
   - Used by: Session listing queries

### vector_memories collection:
1. **userId (Asc) + isActive (Asc) + importance (Desc)**
   - Used by: Memory retrieval queries

2. **userId (Asc) + lastAccessedAt (Desc)**
   - Used by: Recent memory access queries

### user_sessions collection:
1. **userId (Asc) + startTime (Desc)**
   - Used by: Session listing queries

2. **userId (Asc) + isActive (Asc) + startTime (Desc)**
   - Used by: Active session queries

## Index Exemptions

To reduce index overhead for large fields:

1. Exempt `embedding` field in `vector_memories` collection from indexing
2. Exempt `finalTranscript` field in `user_sessions` collection from indexing

## Deployment Instructions

1. Open Firebase Console: https://console.firebase.google.com
2. Select your project
3. Navigate to Firestore Database > Rules
4. Copy and paste the rules above
5. Click "Publish"
6. Navigate to Firestore Database > Indexes
7. Create the composite indexes listed above
8. Navigate to Firestore Database > Indexes > Single Field
9. Add exemptions for the fields listed in "Index Exemptions"

## Testing Rules

Use the Firebase Emulator Suite for local testing:

```bash
firebase emulators:start --only firestore
```

Run queries and ensure:
- Users can only access their own data
- Server timestamps are enforced on `createdAt` and `updatedAt`
- Unauthorized access is blocked
