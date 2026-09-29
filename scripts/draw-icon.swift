import AppKit
let out = CommandLine.arguments[1]
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
NSColor.clear.setFill(); NSRect(x:0,y:0,width:size,height:size).fill()
let tile=NSBezierPath(roundedRect:NSRect(x:48,y:48,width:928,height:928),xRadius:218,yRadius:218)
NSColor(srgbRed:0.149,green:0.149,blue:0.141,alpha:1).setFill();tile.fill()
let inset=NSBezierPath(roundedRect:NSRect(x:62,y:62,width:900,height:900),xRadius:208,yRadius:208)
NSColor(srgbRed:0.30,green:0.30,blue:0.28,alpha:0.8).setStroke();inset.lineWidth=3;inset.stroke()
// Original clay shield with open interior and a clean, asymmetric connection mark.
let shield=NSBezierPath();shield.move(to:NSPoint(x:512,y:804));shield.curve(to:NSPoint(x:286,y:717),controlPoint1:NSPoint(x:441,y:775),controlPoint2:NSPoint(x:356,y:735));shield.line(to:NSPoint(x:302,y:477));shield.curve(to:NSPoint(x:512,y:237),controlPoint1:NSPoint(x:310,y:365),controlPoint2:NSPoint(x:424,y:282));shield.curve(to:NSPoint(x:722,y:477),controlPoint1:NSPoint(x:600,y:282),controlPoint2:NSPoint(x:714,y:365));shield.line(to:NSPoint(x:738,y:717));shield.curve(to:NSPoint(x:512,y:804),controlPoint1:NSPoint(x:668,y:735),controlPoint2:NSPoint(x:583,y:775));shield.close()
NSColor(srgbRed:0.851,green:0.467,blue:0.341,alpha:1).setFill();shield.fill()
let gate=NSBezierPath();gate.move(to:NSPoint(x:616,y:584));gate.curve(to:NSPoint(x:440,y:650),controlPoint1:NSPoint(x:580,y:664),controlPoint2:NSPoint(x:482,y:678));gate.curve(to:NSPoint(x:409,y:474),controlPoint1:NSPoint(x:374,y:611),controlPoint2:NSPoint(x:372,y:524));gate.curve(to:NSPoint(x:597,y:446),controlPoint1:NSPoint(x:449,y:425),controlPoint2:NSPoint(x:541,y:414));gate.line(to:NSPoint(x:597,y:521));gate.line(to:NSPoint(x:523,y:521));gate.lineWidth=44;gate.lineCapStyle = .round;gate.lineJoinStyle = .round
NSColor(srgbRed:1,green:0.97,blue:0.90,alpha:1).setStroke();gate.stroke()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:out))
