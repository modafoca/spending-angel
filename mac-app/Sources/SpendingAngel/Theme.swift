import SwiftUI

enum Theme {
    // — Cream/navy/gold (the overlay bubble + legacy) —
    static let cream = Color(red: 1.00, green: 0.969, blue: 0.902) // #FFF7E6
    static let navy  = Color(red: 0.114, green: 0.184, blue: 0.341) // #1D2F57
    static let gold  = Color(red: 0.957, green: 0.718, blue: 0.251) // #F4B740
    static let bubbleInk = Color(red: 0.129, green: 0.086, blue: 0.208) // #211635 (speech-bubble outline)

    // — Pixel-game palette (the dropdown, M-07) —
    static let pxBG     = Color(red: 0.039, green: 0.055, blue: 0.110) // near-black navy
    static let pxPanel  = Color(red: 0.075, green: 0.110, blue: 0.220) // deep blue panel
    static let pxInk    = Color(red: 0.80,  green: 0.87,  blue: 1.00)  // light text
    static let pxDim    = Color(red: 0.42,  green: 0.53,  blue: 0.80)  // dim labels
    static let pxAccent = Color(red: 0.40,  green: 0.82,  blue: 1.00)  // cyan glow
    static let pxLine   = Color(red: 0.20,  green: 0.31,  blue: 0.58)  // borders
}
