import Foundation
import simd

// 2-state constant-velocity Kalman filter for heart rate
// State x = [hr, dhr]^T (bpm, bpm/s)
// Model: x_k = F(dt) * x_{k-1} + w,    z_k = H * x_k + v
//   F(dt) = [1 dt; 0 1], H = [1 0]
//   Q = [[q_pos*dt + q_couple*dt^2/2, q_couple*dt], [q_couple*dt, q_vel*dt]] (simple tuned form)
//   R = r (measurement variance)
final class KalmanHR2DFilter {
    private var x: SIMD2<Double> = .init(repeating: 0)
    private var P: simd_double2x2 = .init(rows: [SIMD2(1e3, 0), SIMD2(0, 1e3)]) // large initial uncertainty
    private var lastTime: TimeInterval?
    private var initialized = false

    // Tuning
    private let qPos: Double   // process noise for HR (bpm^2 per second)
    private let qVel: Double   // process noise for HR' (bpm^2 per second)
    private let qCouple: Double // coupling noise term between pos and vel
    private let rMeas: Double  // measurement variance (bpm^2)

    init(qPos: Double = 0.2, qVel: Double = 0.8, qCouple: Double = 0.05, rMeas: Double = 9.0) {
        self.qPos = qPos
        self.qVel = qVel
        self.qCouple = qCouple
        self.rMeas = rMeas
    }

    func reset() {
        x = .init(repeating: 0)
        P = .init(rows: [SIMD2(1e3, 0), SIMD2(0, 1e3)])
        lastTime = nil
        initialized = false
    }

    // Update with measurement z (bpm) at time 'date'. Returns filtered hr and hr velocity.
    func update(measurement z: Double, at date: Date) -> (hr: Double, dhr: Double) {
        let t = date.timeIntervalSince1970
        guard z.isFinite else { return (x.x, x.y) }

        if !initialized {
            x = SIMD2(z, 0)
            // Initial uncertainty: HR has measurement noise, dHR has high uncertainty since it's unknown
            P = .init(rows: [SIMD2(rMeas, 0), SIMD2(0, 100.0)]) // 100 bpm²/s² for dHR uncertainty
            lastTime = t
            initialized = true
            return (Double(x.x), Double(x.y))
        }

        let dt = max(0.01, min(2.0, (lastTime.map { t - $0 } ?? 0.1)))
        lastTime = t

        // State transition F and its transpose
        let F = simd_double2x2(rows: [SIMD2(1, dt), SIMD2(0, 1)])
        let Ft = F.transpose

        // Process noise Q (simple time-scaled terms)
        let q11 = qPos * dt + 0.5 * qCouple * dt * dt
        let q12 = qCouple * dt
        let q22 = qVel * dt
        let Q = simd_double2x2(rows: [SIMD2(q11, q12), SIMD2(q12, q22)])

        // Predict
        x = F * x
        P = F * P * Ft + Q

        // Measurement update (H = [1 0])
        let y = z - x.x // innovation
        let S = P[0,0] + rMeas
        
        // Safety check for numerical stability
        guard S > 1e-10 && S.isFinite else { 
            return (Double(x.x), Double(x.y)) 
        }
        
        let K0 = P[0,0] / S
        let K1 = P[1,0] / S
        // Update state
        x.x = x.x + K0 * y
        x.y = x.y + K1 * y
        // Update covariance: P = (I - K H) P
        // (I - K H) = [[1-K0,  -0],[ -K1, 1]] since H = [1 0]
        let iKH = simd_double2x2(rows: [SIMD2(1 - K0, 0), SIMD2(-K1, 1)])
        P = iKH * P

        // Apply physiological limits to dHR (max ~5 bpm/s based on typical response)
        let clampedDHR = max(-5.0, min(5.0, Double(x.y)))
        return (Double(x.x), clampedDHR)
    }
}

