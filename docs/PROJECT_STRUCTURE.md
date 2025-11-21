# Luca Project Structure

## Overview
This document outlines the organized structure of the Luca project for better maintainability and development workflow.

## Root Directory Structure
```
Luca/
├── docs/                           # Documentation files
│   ├── README.md                   # Main project documentation
│   ├── PROJECT_STRUCTURE.md        # This file
│   └── MULTI_WINDOW_ARCHITECTURE_SUMMARY.md
├── assets/                         # Static assets and logos
│   ├── Luca Logo Circle NoBG.png
│   ├── Luca Logo NoBG White.png
│   ├── Luca White Logo NoBG.png
│   └── LucaAppIcon.png
├── Luca/                          # iOS Application
├── Server/                        # Node.js Backend
├── LucaTests/                     # Unit Tests
├── LucaUITests/                   # UI Tests
├── Luca.xcodeproj/               # Xcode Project
└── vercel.json                   # Vercel Configuration
```

## iOS Application Structure (`Luca/`)
```
Luca/
├── Assets.xcassets/              # App icons, images, and assets
├── Resources/                    # Configuration files
│   └── GoogleService-Info.plist
├── Audio/                        # Audio processing and speech recognition
│   ├── AudioCaptureManager.swift
│   ├── DeepgramConfig.swift
│   └── DeepgramSTT.swift
├── Auth/                         # Authentication management
│   └── AuthenticationManager.swift
├── Capture/                      # Screen capture and OCR
│   ├── CaptureManager.swift
│   ├── ScreenOCRManager.swift
│   ├── ScreenshotDecisionEngine.swift
│   ├── ScreenshotManager.swift
│   └── SelectionController.swift
├── Memory/                       # Memory and vector storage
│   ├── SessionTranscriptStore.swift
│   └── VectorMemoryManager.swift
├── Networking/                   # API communication
│   ├── AnalyzeAPI.swift
│   ├── ChatAPI.swift
│   ├── ClientAPI.swift
│   └── ListenAPI.swift
├── System/                       # Core system functionality
│   ├── AppConfig.swift
│   ├── FeatureFlags.swift
│   ├── GlobalHotKey.swift
│   └── SessionManager.swift
├── UI/                          # User Interface
│   ├── App/                     # App lifecycle
│   │   ├── AppDelegate.swift
│   │   └── LucaApp.swift
│   ├── Components/              # Reusable UI components
│   │   ├── MessageRendering.swift
│   │   └── ViewExtensions.swift
│   ├── Services/                # UI services
│   │   └── DesignSystem.swift
│   ├── Dashboard/               # Main dashboard interface
│   │   └── Components/          # Dashboard-specific components
│   │       ├── DashboardView.swift
│   │       ├── MainAppView.swift
│   │       ├── MemoryManagementView.swift
│   │       ├── PermissionRequestView.swift
│   │       ├── SessionDetailView.swift
│   │       ├── SessionListView.swift
│   │       └── VectorMemoryView.swift
│   ├── Overlay/                 # Floating overlay interface
│   │   ├── Views/               # Overlay view controllers
│   │   │   ├── ButtonsPanelView.swift
│   │   │   ├── ChatPanelView.swift
│   │   │   ├── ListenPanelView.swift
│   │   │   ├── WindowDragArea.swift
│   │   │   └── WindowOrchestrator.swift
│   │   ├── Components/          # Overlay components
│   │   │   ├── ChatComponents.swift
│   │   │   ├── MainChatView.swift
│   │   │   ├── OverlayButtons.swift
│   │   │   ├── OverlayButtonsPanel.swift
│   │   │   ├── OverlayButton.swift
│   │   │   ├── SelectionOverlayWindow.swift
│   │   │   └── SelectionWindow.swift
│   │   ├── Extra/               # Additional overlay functionality
│   │   │   ├── ChatMessage.swift
│   │   │   ├── ConversationStore.swift
│   │   │   ├── MainWindow.swift
│   │   │   ├── OverlayStateManager.swift
│   │   │   ├── ProfileButton.swift
│   │   │   └── ResponseOverlay.swift
│   │   └── Services/            # Overlay services
│   │       ├── OverlayButtonService.swift
│   │       ├── OverlayService.swift
│   │       ├── SuggestedQuestionsEngine.swift
│   │       └── WindowManager.swift
│   └── Controllers/             # View controllers (future use)
├── Utils/                       # Utility functions and extensions
│   └── View+Compatibility.swift
├── Info.plist                  # App configuration
└── Luca.entitlements          # App permissions
```

## Server Structure (`Server/`)
```
Server/
├── api/                        # API endpoints
│   ├── lib/                    # API utilities
│   ├── analyze.js
│   ├── chat.js
│   ├── embedding.js
│   ├── guide.js
│   ├── health.js
│   ├── healthz.js
│   ├── index.js
│   ├── listen.js
│   ├── memory.js
│   ├── places.js
│   ├── package.json
│   └── streaming-chat.js
├── lib/                        # Core server libraries
│   ├── errorHandler.js
│   ├── logger.js
│   ├── openaiClient.js
│   ├── redis.js
│   ├── sentry.js
│   ├── storage.js
│   └── streaming.js
├── middleware/                 # Express middleware
│   ├── auth.js
│   ├── cors.js
│   └── monitoring.js
├── tests/                      # Server tests
│   ├── api.test.js
│   ├── integration.test.js
│   ├── load.test.js
│   └── setup.js
├── config.js                   # Server configuration
├── docker-compose.prod.yml     # Docker production setup
├── Dockerfile.prod             # Docker configuration
├── package.json                # Dependencies
├── README.md                   # Server documentation
├── server.js                   # Main server file
├── vercel-server.js           # Vercel deployment
└── vercel.json                # Vercel configuration
```

## Key Design Principles

### 1. Separation of Concerns
- **Audio/**: Handles all audio processing and speech recognition
- **Auth/**: Manages authentication and user sessions
- **Capture/**: Handles screen capture and OCR functionality
- **Memory/**: Manages vector memory and session storage
- **Networking/**: Handles all API communications
- **System/**: Core system functionality and configuration

### 2. UI Organization
- **Components/**: Reusable UI components
- **Views/**: Main view controllers and panels
- **Services/**: UI-related services and utilities
- **Dashboard/**: Main application interface
- **Overlay/**: Floating overlay interface with organized subdirectories

### 3. Maintainability
- Clear folder structure with descriptive names
- Related functionality grouped together
- Separation between client and server code
- Documentation in dedicated docs folder
- Assets organized separately from code

### 4. Scalability
- Modular architecture allows easy feature additions
- Clear boundaries between different system components
- Organized UI structure supports multiple interface types
- Server API structure supports easy endpoint additions

## Development Workflow

1. **Feature Development**: Create new features in appropriate directories
2. **UI Components**: Add reusable components to `UI/Components/`
3. **API Endpoints**: Add new endpoints to `Server/api/`
4. **Documentation**: Update docs in `docs/` folder
5. **Assets**: Store images and logos in `assets/` folder

## File Naming Conventions

- **Swift Files**: PascalCase (e.g., `VectorMemoryManager.swift`)
- **JavaScript Files**: camelCase (e.g., `memoryExtraction.js`)
- **Assets**: Descriptive names with spaces (e.g., `Luca White Logo NoBG.png`)
- **Directories**: PascalCase for Swift, camelCase for JavaScript
