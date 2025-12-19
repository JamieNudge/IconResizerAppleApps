# Icon Resizer Apple Apps

A macOS app that generates properly formatted AppIcon.appiconset folders for iOS and macOS projects.

## ✨ Features

- **iOS Support**: Generates all 18 required icon sizes (iPhone, iPad, and App Store)
- **macOS Support**: Generates all 10 required icon sizes (16x16 to 1024x1024 at 1x and 2x)
- **Xcode-Ready**: Creates proper `AppIcon.appiconset` folders with `Contents.json`
- **Drag & Drop**: Simple interface - just drag a 1024x1024 PNG

## 🚀 How to Use

### Step 1: Prepare Your Icon
- Create or obtain a **1024x1024 pixel PNG** image
- Make sure it has a transparent background if needed
- Square aspect ratio is required

### Step 2: Generate Icons
1. Launch the **Icon Resizer Apple Apps**
2. Select your platform:
   - **iOS Universal**: Modern iOS (single icon for all devices) - 3 sizes
   - **iOS Only**: Traditional iPhone & iPad icons - 18 sizes
   - **macOS Only**: Mac app icons - 10 sizes
   - **iOS + macOS**: Both traditional iOS and macOS
3. **Drag and drop** your 1024x1024 PNG into the app
4. Choose where to save the output
5. Click **Open Output Folder** to view generated icons

### Step 3: Add to Xcode Project

#### For macOS Apps:
1. Open your Xcode project
2. Navigate to `Assets.xcassets` in your project
3. **Delete** the existing `AppIcon` if it's empty
4. **Drag** the generated `AppIcon.appiconset` folder into `Assets.xcassets`
5. Done! All sizes are automatically filled

#### For iOS Apps:
1. Open your Xcode project
2. Navigate to `Assets.xcassets` in your project
3. **Delete** the existing `AppIcon` if it's empty
4. **Drag** the generated `AppIcon.appiconset` folder into `Assets.xcassets`
5. Done! All iPhone and iPad sizes are filled

## 📦 Output Structure

### iOS Universal Output (Modern, Recommended):
```
AppIcon.appiconset/
├── Contents.json
├── AppIcon-1x.png          (1024×1024)
├── AppIcon-2x.png          (1024×1024)
└── AppIcon-3x.png          (1024×1024)
```

### macOS Output:
```
AppIcon.appiconset/
├── Contents.json
├── icon_16x16.png          (16×16)
├── icon_16x16@2x.png       (32×32)
├── icon_32x32.png          (32×32)
├── icon_32x32@2x.png       (64×64)
├── icon_128x128.png        (128×128)
├── icon_128x128@2x.png     (256×256)
├── icon_256x256.png        (256×256)
├── icon_256x256@2x.png     (512×512)
├── icon_512x512.png        (512×512)
└── icon_512x512@2x.png     (1024×1024)
```

### iOS Output:
```
AppIcon.appiconset/
├── Contents.json
├── Icon-20@2x.png          (iPhone Notification)
├── Icon-20@3x.png
├── Icon-29@2x.png          (iPhone Settings)
├── Icon-29@3x.png
├── Icon-40@2x.png          (iPhone Spotlight)
├── Icon-40@3x.png
├── Icon-60@2x.png          (iPhone App)
├── Icon-60@3x.png
├── Icon-iPad-20.png        (iPad Notification)
├── Icon-iPad-20@2x.png
├── Icon-iPad-29.png        (iPad Settings)
├── Icon-iPad-29@2x.png
├── Icon-iPad-40.png        (iPad Spotlight)
├── Icon-iPad-40@2x.png
├── Icon-76.png             (iPad App)
├── Icon-76@2x.png
├── Icon-83.5@2x.png        (iPad Pro)
└── Icon-1024.png           (App Store)
```

## 💡 Tips

- **High Quality Source**: Always start with the highest quality 1024×1024 PNG
- **Test All Sizes**: Check how your icon looks at small sizes (16×16, 20×20)
- **Simple Design**: Avoid tiny details that won't be visible at small sizes
- **No Text**: Icons should be recognizable without text
- **Test on Device**: Always test how your icon looks on actual devices

### Which iOS Option to Choose?

**iOS Universal (Recommended for new projects)**:
- ✅ Simplest approach - just 3 files (all 1024×1024)
- ✅ Works for iOS 11+ (most modern apps)
- ✅ Xcode automatically generates all needed sizes
- ✅ Less files to manage
- ✅ Perfect for apps targeting iOS 13+

**iOS Only (Traditional)**:
- Use if you need iOS 10 support
- Use if you want precise control over each size
- Generates all 18 sizes individually
- Required for older deployment targets

## 🔧 Troubleshooting

### "Xcode won't accept my AppIcon.appiconset"
- Make sure you're dragging into `Assets.xcassets`, not the project root
- Delete any existing AppIcon before dragging the new one
- Clean build folder (Cmd+Shift+K) and rebuild

### "Some icon sizes are missing"
- Ensure you selected the correct platform (iOS/macOS/Both)
- Check that all PNG files were generated in the folder
- Verify the Contents.json file exists

### "Icons look pixelated"
- Your source image might be less than 1024×1024
- Use a higher quality source image
- Ensure the source is PNG, not JPEG

## 📝 Notes

- This app generates **pixel-perfect** icons at all required sizes
- All icons maintain the aspect ratio of your source image
- The `Contents.json` file is automatically generated for Xcode compatibility
- Works with Xcode 15+ and macOS 13+

## 🎯 Example: PREPBNOH2H Project

To fix the missing icons in your PREPBNOH2H project:

1. Find or create a 1024×1024 PNG icon for your app
2. Run Icon Resizer and select **macOS Only**
3. Drag your PNG into the app
4. Save to your Desktop as "PREPBNOH2H_Icons"
5. Open your PREPBNOH2H Xcode project
6. Navigate to `Assets 2.xcassets`
7. Delete the existing empty `AppIcon`
8. Drag the generated `AppIcon.appiconset` folder into `Assets 2.xcassets`
9. Build and run - all icon sizes are now filled! ✅

---

**Version**: 2.0  
**Updated**: December 2025  
**Compatibility**: macOS 13+, Xcode 15+

