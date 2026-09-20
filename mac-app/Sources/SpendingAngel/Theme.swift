import SwiftUI

enum Theme {
    // — Cream/navy/gold (the overlay bubble + legacy) —
    static let cream = Color(red: 1.00, green: 0.969, blue: 0.902) // #FFF7E6
    static let navy  = Color(red: 0.114, green: 0.184, blue: 0.341) // #1D2F57
    static let gold  = Color(red: 0.957, green: 0.718, blue: 0.251) // #F4B740
    static let bubbleInk = Color(red: 0.129, green: 0.086, blue: 0.208) // #211635 (speech-bubble outline)

    // Flat dropdown palette, shared with the browser UI. The overlay keeps
    // its character-specific cream/navy/gold above.
    static let pxBG     = Color(red: 0.067, green: 0.098, blue: 0.137)
    static let pxPanel  = Color(red: 0.102, green: 0.145, blue: 0.196)
    static let pxInk    = Color(red: 0.941, green: 0.933, blue: 0.910)
    static let pxDim    = Color(red: 0.647, green: 0.694, blue: 0.749)
    static let pxAccent = Color(red: 0.722, green: 0.875, blue: 0.792)
    static let pxLine   = Color(red: 0.208, green: 0.259, blue: 0.314)
}
