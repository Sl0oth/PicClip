// Scripted, smooth mouse + keyboard for recording demos. Reads commands from stdin, one per line:
//   move X Y [ms]        glide the pointer to X,Y (screen points, top-left origin)
//   drag X Y [ms]        glide with the button held (button must be down)
//   down / up / click    left button at the current position
//   key COMBO            e.g. cmd+shift+4, m, cmd+s, escape
//   wait MS
//   win LAYER DX DY [ms] glide to a PicClip window on LAYER: DX/DY ≥ 0 from its left/top edge, < 0 from right/bottom
//   # comment
import AppKit

let keyCodes: [String: CGKeyCode] = ["a":0,"s":1,"d":2,"b":11,"r":15,"4":21,"m":46,"p":35,"v":9,"z":6,"escape":53,"space":49,"return":36]
let source = CGEventSource(stateID: .hidSystemState)
var buttonDown = false

func position() -> CGPoint { CGEvent(source: nil)!.location }

func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
}

func glide(to target: CGPoint, ms: Double) {
    let start = position()
    let steps = max(1, Int(ms / 8))
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 // ease in-out
        let p = CGPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
        post(buttonDown ? .leftMouseDragged : .mouseMoved, p)
        usleep(8000)
    }
}

func picclipWindow(layer: Int) -> CGRect? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { w -> CGRect? in
        guard (w[kCGWindowOwnerName as String] as? String) == "PicClip", (w[kCGWindowLayer as String] as? Int) == layer,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return nil }
        return r
    }.max { $0.maxY < $1.maxY } // bottom-most (newest preview)
}

func key(_ combo: String) {
    var flags: CGEventFlags = []
    var name = combo
    for part in combo.split(separator: "+").map(String.init) {
        switch part {
        case "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt": flags.insert(.maskAlternate)
        case "ctrl": flags.insert(.maskControl)
        default: name = part
        }
    }
    guard let code = keyCodes[name] else { fputs("unknown key \(name)\n", stderr); return }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(30000)
    }
}

while let line = readLine() {
    let a = line.split(separator: " ").map(String.init)
    guard let cmd = a.first, !cmd.hasPrefix("#") else { continue }
    let n = { (i: Int) in Double(a[i])! }
    switch cmd {
    case "move", "drag": glide(to: CGPoint(x: n(1), y: n(2)), ms: a.count > 3 ? n(3) : 600)
    case "down": buttonDown = true; post(.leftMouseDown, position())
    case "up": buttonDown = false; post(.leftMouseUp, position())
    case "click": post(.leftMouseDown, position()); usleep(60000); post(.leftMouseUp, position())
    case "key": key(a[1])
    case "wait": usleep(useconds_t(n(1) * 1000))
    case "win":
        guard let r = picclipWindow(layer: Int(a[1])!) else { fputs("no PicClip window on layer \(a[1])\n", stderr); continue }
        let dx = n(2), dy = n(3)
        glide(to: CGPoint(x: dx >= 0 ? r.minX + dx : r.maxX + dx, y: dy >= 0 ? r.minY + dy : r.maxY + dy), ms: a.count > 4 ? n(4) : 600)
    default: fputs("unknown command \(cmd)\n", stderr)
    }
}
