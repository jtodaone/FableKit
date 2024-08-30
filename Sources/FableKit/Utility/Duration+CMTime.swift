import Foundation
import AVFoundation

extension Duration {
    var seconds: Double {
        let seconds = Double(self.components.seconds)
        let attoseconds = Double(self.components.attoseconds)
        
        return seconds + attoseconds * 1e-18
    }
    
    var cmTime: CMTime {
        CMTime(seconds: seconds, preferredTimescale: 60)
    }
}
