# Icon Resizer Apple Apps

A macOS app that generates properly formatted AppIcon.appiconset folders for iOS and macOS projects.

## ✨ Features

- **iOS Support**: Generates all 18 required icon sizes (iPhone, iPad, and App Store)
- **macOS Support**: Generates all 10 required icon sizes (16x16 to 1024x1024 at 1x and 2x)
- **Xcode-Ready**: Creates proper `AppIcon.appiconset` folders with `Contents.json`
- **Drag & Drop**: Simple interface - just drag a 1024x1024 PNG
- **Web headers**: One mode exports blog / OG images at fixed sizes using **aspect-fill** (uniform scale + center crop, no stretch). See [REPO_AND_BUILDS.md](REPO_AND_BUILDS.md) if your local build differs from GitHub `main`.
- **AdSense privacy logo**: **AdSense logo** mode exports a **1000×200** (5:1) **JPEG** with your mark **aspect-fitted on a white** background, with quality auto-tuned so the file stays **≤150 KB** when possible (Google’s privacy-message logo upload limits: PNG/JPG, max 150 KB, 5:1 recommended).

## 🚀 How to Use

### Step 1: Prepare Your Icon
- Create or obtain a **1024x1024 pixel PNG** image
- Make sure it has a transparent background if needed
- Square aspect ratio is required

### Step 2: Generate output
1. Launch **Icon Resizer Apple Apps**.
2. In the mode control, choose **App Icons**, **App Screenshots**, **Web headers**, **AdSense logo**, or **Image lab**.
3. **App Icons**: pick **iOS Universal**, **iOS Only**, **macOS Only**, or **iOS + macOS**. **App Screenshots**: pick **iPhone**, **iPad**, or **Apple Watch**. **Web headers** and **AdSense logo**: no Store picker.
4. **Drag and drop** PNGs (or images): one **1024×1024** for icons; one or more for screenshots; **one** image of any size or aspect for web headers or for the AdSense privacy logo.
5. **Sandboxed builds** save under **`~/Downloads/Apple Icons`** by default (Downloads is writable with the app’s entitlements). Use **Choose folder…** if you want Desktop or another location.
6. Click **Open Output Folder** to reveal the last output folder in Finder.

### Web headers (blog / OG)

1. Select **Web headers** in the mode control.
2. Drop **one** PNG (any size or aspect).
3. Output is written to **`BlogHeaders/`** under the same base folder as icons (sandbox default: `~/Downloads/Apple Icons/BlogHeaders/`).
4. Files (PNG):

| File | Size | Typical use |
|------|------|-------------|
| `header-1200x630.png` | 1200×630 | Open Graph / social share cards |
| `header-1600x900.png` | 1600×900 | Wide 16:9 hero / retina |
| `header-1024x576.png` | 1024×576 | Lighter 16:9 variant |

Resizing uses **aspect-fill**: the image is scaled uniformly and **center-cropped** to each target rectangle (no squashing). This matches common site behaviour such as CSS `object-fit: cover`.

### AdSense privacy logo (Google AdSense)

1. Select **AdSense logo** in the mode control.
2. Drop **one** PNG or JPEG (any size or aspect — your logo or app mark).
3. Output is **`adsense-privacy-logo-1000x200.jpg`** under **`AdSenseLogo/`** when you use “category” export subfolders (sandbox default base: `~/Downloads/Apple Icons/`), or directly in the chosen base folder when exporting “direct”.
4. The image is **1000×200** (5:1), **aspect-fit** on **white**, encoded as **JPEG** with quality stepped down until the file is **≤150 KB** when possible. If the asset is still larger after the lowest quality step, the app saves the smallest attempt and warns in the status line.

### Step 3: Add to Xcode Project (icons only)

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

**Version**: 2.3  
**Updated**: May 2026  
**Compatibility**: macOS 13+, Xcode 15+

