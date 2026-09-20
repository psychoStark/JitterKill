#!/usr/bin/env swift
// generate_assets.swift — Generate JitterKill AppIcon.icns, Asset Catalog, and MenuBar Icons
// Uses updated logo.png provided by user with transparency mask from logo.svg

import Foundation
import AppKit

let projectDir = FileManager.default.currentDirectoryPath
let logoDir = "\(projectDir)/logo"
let resourcesDir = "\(projectDir)/Sources/JitterKillApp/Resources"
let xcassetsDir = "\(resourcesDir)/Assets.xcassets"

print("🎨 Starting JitterKill asset generation using updated logo.png…")

let fm = FileManager.default
try? fm.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: xcassetsDir, withIntermediateDirectories: true)

// MARK: - 1. Load Transparent Master from User's updated logo.png

let urlPNG = URL(fileURLWithPath: "\(logoDir)/logo.png")
guard let masterImage = NSImage(contentsOf: urlPNG) else {
    print("❌ Could not load logo.png")
    exit(1)
}

func renderImage(_ source: NSImage, targetPixelWidth: Int, targetPixelHeight: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: targetPixelWidth,
        pixelsHigh: targetPixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: targetPixelWidth, height: targetPixelHeight)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current = ctx
    ctx?.imageInterpolation = .high
    source.draw(
        in: NSRect(x: 0, y: 0, width: targetPixelWidth, height: targetPixelHeight),
        from: NSRect(origin: .zero, size: source.size),
        operation: .sourceOver,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// Master logo PNGs
let logo1024Data = renderImage(masterImage, targetPixelWidth: 1024, targetPixelHeight: 1024)
let logo512Data = renderImage(masterImage, targetPixelWidth: 512, targetPixelHeight: 512)

try? logo1024Data?.write(to: URL(fileURLWithPath: "\(resourcesDir)/logo_1024.png"))
try? logo512Data?.write(to: URL(fileURLWithPath: "\(resourcesDir)/logo.png"))
print("✅ Saved logo.png and logo_1024.png in Resources/")

// MARK: - 2. Generate AppIcon.iconset and compile to AppIcon.icns

let iconsetDir = "\(projectDir)/.AppIcon.iconset"
try? fm.removeItem(atPath: iconsetDir)
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in iconSizes {
    if let data = renderImage(masterImage, targetPixelWidth: item.px, targetPixelHeight: item.px) {
        let dest = URL(fileURLWithPath: "\(iconsetDir)/\(item.name)")
        try? data.write(to: dest)
    }
}

let icnsDestPath = "\(resourcesDir)/AppIcon.icns"
let iconutilTask = Process()
iconutilTask.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutilTask.arguments = ["-c", "icns", iconsetDir, "-o", icnsDestPath]
try? iconutilTask.run()
iconutilTask.waitUntilExit()

if fm.fileExists(atPath: icnsDestPath) {
    print("✅ Compiled AppIcon.icns")
}
try? fm.removeItem(atPath: iconsetDir)

// MARK: - 3. Menu Bar Mono Icons (Guarded & Unguarded)

func extractOrLoadMono(name: String) -> NSImage? {
    let pngPath = "\(logoDir)/\(name).png"
    if let img = NSImage(contentsOfFile: pngPath) { return img }
    let svgPath = "\(logoDir)/\(name).svg"
    return NSImage(contentsOfFile: svgPath)
}

guard let monoGuardRaw = extractOrLoadMono(name: "mono_guard"),
      let monoUnguardRaw = extractOrLoadMono(name: "mono_unguard") else {
    print("❌ Could not load mono_guard or mono_unguard")
    exit(1)
}

func renderCenteredMenuBarIcon(source: NSImage,
                               ptSize: CGFloat = 18.0,
                               maxTargetHeightPt: CGFloat = 16.0,
                               scale: CGFloat) -> Data? {
    let pxCanvas = Int(ptSize * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxCanvas,
        pixelsHigh: pxCanvas,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: ptSize, height: ptSize)

    let aspect = source.size.width / source.size.height
    let drawHeightPt = maxTargetHeightPt
    let drawWidthPt = drawHeightPt * aspect
    let drawXPt = (ptSize - drawWidthPt) / 2.0
    let drawYPt = (ptSize - drawHeightPt) / 2.0

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current = ctx
    ctx?.imageInterpolation = .high
    source.draw(
        in: NSRect(x: drawXPt, y: drawYPt, width: drawWidthPt, height: drawHeightPt),
        from: NSRect(origin: .zero, size: source.size),
        operation: .sourceOver,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let guard1x = renderCenteredMenuBarIcon(source: monoGuardRaw, ptSize: 18, maxTargetHeightPt: 16.0, scale: 1.0)
let guard2x = renderCenteredMenuBarIcon(source: monoGuardRaw, ptSize: 18, maxTargetHeightPt: 16.0, scale: 2.0)
let guard3x = renderCenteredMenuBarIcon(source: monoGuardRaw, ptSize: 18, maxTargetHeightPt: 16.0, scale: 3.0)

let unguard1x = renderCenteredMenuBarIcon(source: monoUnguardRaw, ptSize: 18, maxTargetHeightPt: 15.0, scale: 1.0)
let unguard2x = renderCenteredMenuBarIcon(source: monoUnguardRaw, ptSize: 18, maxTargetHeightPt: 15.0, scale: 2.0)
let unguard3x = renderCenteredMenuBarIcon(source: monoUnguardRaw, ptSize: 18, maxTargetHeightPt: 15.0, scale: 3.0)

try? guard2x?.write(to: URL(fileURLWithPath: "\(resourcesDir)/mono_guard.png"))
try? unguard2x?.write(to: URL(fileURLWithPath: "\(resourcesDir)/mono_unguard.png"))
print("✅ Saved mono_guard.png and mono_unguard.png in Resources/")

// MARK: - 4. Create Assets.xcassets

func writeContentsJSON(at path: String, json: String) {
    try? json.write(toFile: path, atomically: true, encoding: .utf8)
}

writeContentsJSON(at: "\(xcassetsDir)/Contents.json", json: """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""")

// AppIcon.appiconset
let appiconsetDir = "\(xcassetsDir)/AppIcon.appiconset"
try? fm.createDirectory(atPath: appiconsetDir, withIntermediateDirectories: true)
let appIconJSON = """
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "scale" : "1x", "filename" : "icon_16x16.png" },
    { "size" : "16x16", "idiom" : "mac", "scale" : "2x", "filename" : "icon_16x16@2x.png" },
    { "size" : "32x32", "idiom" : "mac", "scale" : "1x", "filename" : "icon_32x32.png" },
    { "size" : "32x32", "idiom" : "mac", "scale" : "2x", "filename" : "icon_32x32@2x.png" },
    { "size" : "128x128", "idiom" : "mac", "scale" : "1x", "filename" : "icon_128x128.png" },
    { "size" : "128x128", "idiom" : "mac", "scale" : "2x", "filename" : "icon_128x128.png" },
    { "size" : "256x256", "idiom" : "mac", "scale" : "1x", "filename" : "icon_256x256.png" },
    { "size" : "256x256", "idiom" : "mac", "scale" : "2x", "filename" : "icon_256x256@2x.png" },
    { "size" : "512x512", "idiom" : "mac", "scale" : "1x", "filename" : "icon_512x512.png" },
    { "size" : "512x512", "idiom" : "mac", "scale" : "2x", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
writeContentsJSON(at: "\(appiconsetDir)/Contents.json", json: appIconJSON)
for item in iconSizes {
    if let data = renderImage(masterImage, targetPixelWidth: item.px, targetPixelHeight: item.px) {
        try? data.write(to: URL(fileURLWithPath: "\(appiconsetDir)/\(item.name)"))
    }
}

// AppLogo.imageset
let logoImagesetDir = "\(xcassetsDir)/AppLogo.imageset"
try? fm.createDirectory(atPath: logoImagesetDir, withIntermediateDirectories: true)
let logoImageJSON = """
{
  "images" : [
    { "idiom" : "universal", "scale" : "1x", "filename" : "logo_512.png" },
    { "idiom" : "universal", "scale" : "2x", "filename" : "logo_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
writeContentsJSON(at: "\(logoImagesetDir)/Contents.json", json: logoImageJSON)
if let l512 = logo512Data { try? l512.write(to: URL(fileURLWithPath: "\(logoImagesetDir)/logo_512.png")) }
if let l1024 = logo1024Data { try? l1024.write(to: URL(fileURLWithPath: "\(logoImagesetDir)/logo_1024.png")) }

// MenuBarGuarded.imageset
let guardImagesetDir = "\(xcassetsDir)/MenuBarGuarded.imageset"
try? fm.createDirectory(atPath: guardImagesetDir, withIntermediateDirectories: true)
let guardImageJSON = """
{
  "images" : [
    { "idiom" : "universal", "scale" : "1x", "filename" : "guard_1x.png" },
    { "idiom" : "universal", "scale" : "2x", "filename" : "guard_2x.png" },
    { "idiom" : "universal", "scale" : "3x", "filename" : "guard_3x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
"""
writeContentsJSON(at: "\(guardImagesetDir)/Contents.json", json: guardImageJSON)
try? guard1x?.write(to: URL(fileURLWithPath: "\(guardImagesetDir)/guard_1x.png"))
try? guard2x?.write(to: URL(fileURLWithPath: "\(guardImagesetDir)/guard_2x.png"))
try? guard3x?.write(to: URL(fileURLWithPath: "\(guardImagesetDir)/guard_3x.png"))

// MenuBarUnguarded.imageset
let unguardImagesetDir = "\(xcassetsDir)/MenuBarUnguarded.imageset"
try? fm.createDirectory(atPath: unguardImagesetDir, withIntermediateDirectories: true)
let unguardImageJSON = """
{
  "images" : [
    { "idiom" : "universal", "scale" : "1x", "filename" : "unguard_1x.png" },
    { "idiom" : "universal", "scale" : "2x", "filename" : "unguard_2x.png" },
    { "idiom" : "universal", "scale" : "3x", "filename" : "unguard_3x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
"""
writeContentsJSON(at: "\(unguardImagesetDir)/Contents.json", json: unguardImageJSON)
try? unguard1x?.write(to: URL(fileURLWithPath: "\(unguardImagesetDir)/unguard_1x.png"))
try? unguard2x?.write(to: URL(fileURLWithPath: "\(unguardImagesetDir)/unguard_2x.png"))
try? unguard3x?.write(to: URL(fileURLWithPath: "\(unguardImagesetDir)/unguard_3x.png"))

print("🎉 All assets successfully generated using updated logo.png!")
