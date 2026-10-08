// Draws the app icon and writes a 1024px PNG. Usage: swift Scripts/make_icon.swift <output.png>
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Standard macOS icon shape: an 824pt rounded square centred on the 1024pt canvas.
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 20
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [NSColor(red: 1.0, green: 0.45, blue: 0.36, alpha: 1),
                    NSColor(red: 0.80, green: 0.12, blue: 0.22, alpha: 1)])!.draw(in: shape, angle: -90)

// Soft highlight across the top half.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
NSGraphicsContext.restoreGraphicsState()

let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let symbolRect = NSRect(x: (size - symbol.size.width) / 2, y: (size - symbol.size.height) / 2,
                        width: symbol.size.width, height: symbol.size.height)
NSGraphicsContext.saveGraphicsState()
let symbolShadow = NSShadow()
symbolShadow.shadowColor = NSColor(red: 0.4, green: 0, blue: 0.05, alpha: 0.35)
symbolShadow.shadowOffset = NSSize(width: 0, height: -8)
symbolShadow.shadowBlurRadius = 18
symbolShadow.set()
symbol.draw(in: symbolRect)
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
