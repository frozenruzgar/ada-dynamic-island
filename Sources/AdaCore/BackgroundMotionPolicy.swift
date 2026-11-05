import Foundation

public enum BackgroundMotionPolicy {
    public static func permitsAnimation(expanded: Bool, keyWindow: Bool, pointerInside: Bool,
                                        lowPower: Bool, batteryPercent: Int?, reduceMotion: Bool) -> Bool {
        expanded && keyWindow && pointerInside && !lowPower && !reduceMotion &&
            (batteryPercent.map { $0 >= 20 } ?? true)
    }
}
