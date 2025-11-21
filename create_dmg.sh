#!/bin/bash

# DMG Creation and Notarization Script for Luca
# This script creates a DMG, notarizes it, and staples the notarization

set -e  # Exit on any error

# Configuration
APP_NAME="Luca"
APP_PATH="$HOME/Desktop/Luca.app"
DMG_NAME="Luca"
APPLE_ID="shrreyasgurav@gmail.com"
APP_PASSWORD="wmjk-iukg-tkfd-uwua"
TEAM_ID=""  # Will be detected automatically

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting DMG creation and notarization process...${NC}"

# Check if Luca.app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Error: Luca.app not found at $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found Luca.app at $APP_PATH${NC}"

# Clean up any existing DMG
if [ -f "${DMG_NAME}.dmg" ]; then
    echo -e "${YELLOW}🗑️  Removing existing DMG...${NC}"
    rm "${DMG_NAME}.dmg"
fi

# Create temporary directory for DMG contents
DMG_TEMP_DIR="temp_dmg"
if [ -d "$DMG_TEMP_DIR" ]; then
    rm -rf "$DMG_TEMP_DIR"
fi
mkdir "$DMG_TEMP_DIR"

echo -e "${BLUE}📦 Creating DMG structure...${NC}"

# Copy app to temp directory
cp -R "$APP_PATH" "$DMG_TEMP_DIR/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# Get app bundle identifier
BUNDLE_ID=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleIdentifier)
echo -e "${GREEN}📱 Bundle ID: $BUNDLE_ID${NC}"

# Create the DMG
echo -e "${BLUE}🔨 Creating DMG file...${NC}"
hdiutil create -volname "$DMG_NAME" -srcfolder "$DMG_TEMP_DIR" -ov -format UDZO "${DMG_NAME}.dmg" -fs HFS+

# Clean up temp directory
rm -rf "$DMG_TEMP_DIR"

echo -e "${GREEN}✅ DMG created: ${DMG_NAME}.dmg${NC}"

# Get DMG size for verification
DMG_SIZE=$(ls -lh "${DMG_NAME}.dmg" | awk '{print $5}')
echo -e "${BLUE}📏 DMG size: $DMG_SIZE${NC}"

# Upload for notarization
echo -e "${BLUE}☁️  Uploading to Apple for notarization...${NC}"
NOTARIZATION_RESULT=$(xcrun notarytool submit "${DMG_NAME}.dmg" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait)

# Extract submission ID from result
SUBMISSION_ID=$(echo "$NOTARIZATION_RESULT" | grep -o 'id: [a-f0-9-]*' | cut -d' ' -f2)

if [ -z "$SUBMISSION_ID" ]; then
    echo -e "${RED}❌ Failed to get submission ID from notarization response${NC}"
    echo "Response: $NOTARIZATION_RESULT"
    exit 1
fi

echo -e "${GREEN}✅ Notarization completed with ID: $SUBMISSION_ID${NC}"

# Check notarization status
echo -e "${BLUE}🔍 Checking notarization status...${NC}"
NOTARIZATION_STATUS=$(xcrun notarytool info "$SUBMISSION_ID" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID")

echo "$NOTARIZATION_STATUS"

# Check if notarization was successful
if echo "$NOTARIZATION_STATUS" | grep -q "status: Accepted"; then
    echo -e "${GREEN}✅ Notarization successful!${NC}"
    
    # Staple the notarization
    echo -e "${BLUE}📎 Stapling notarization to DMG...${NC}"
    xcrun stapler staple "${DMG_NAME}.dmg"
    
    # Verify stapling
    echo -e "${BLUE}🔍 Verifying stapling...${NC}"
    xcrun stapler validate "${DMG_NAME}.dmg"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}🎉 Success! DMG is notarized and stapled${NC}"
        echo -e "${GREEN}📁 Final DMG: $(pwd)/${DMG_NAME}.dmg${NC}"
        
        # Final size check
        FINAL_SIZE=$(ls -lh "${DMG_NAME}.dmg" | awk '{print $5}')
        echo -e "${BLUE}📏 Final DMG size: $FINAL_SIZE${NC}"
        
        # Show file info
        echo -e "${BLUE}📋 DMG Info:${NC}"
        file "${DMG_NAME}.dmg"
        
    else
        echo -e "${RED}❌ Stapling verification failed${NC}"
        exit 1
    fi
    
else
    echo -e "${RED}❌ Notarization failed or was rejected${NC}"
    echo -e "${RED}📋 Status details:${NC}"
    echo "$NOTARIZATION_STATUS"
    exit 1
fi

echo -e "${GREEN}🎊 DMG creation, notarization, and stapling completed successfully!${NC}"
echo -e "${YELLOW}💡 You can now distribute: $(pwd)/${DMG_NAME}.dmg${NC}"
