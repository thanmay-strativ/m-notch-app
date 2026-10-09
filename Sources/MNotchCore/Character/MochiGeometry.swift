// Copied from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import SwiftUI
import CoreGraphics

// MARK: - Constants (mirror JS)

private let kEXP: CGFloat = 2.7
private let kVIEW_TILT: CGFloat = -0.30
private let kACC_PITCH: CGFloat = 0.4
private let kEYE_W: CGFloat = 0.25
private let kEYE_H: CGFloat = 0.27
private let kEYE_SP: CGFloat = 0.37
private let kEYE_P: CGFloat = -0.12

// MARK: - MochiH  (head geometry + physics)

struct MochiH {
    let R, rx, ry: CGFloat
    let yaw, pitch: CGFloat
    let view: CGFloat      // = VIEW_TILT (-0.30)
    let physDx, physDy: CGFloat
    let roll: CGFloat

    init(R: CGFloat, yaw: CGFloat = 0, pitch: CGFloat = 0,
         physDx: CGFloat = 0, physDy: CGFloat = 0, roll: CGFloat = 0) {
        self.R = R
        self.rx = R * 1.14
        self.ry = R * 0.88
        self.yaw = yaw
        self.pitch = pitch
        self.view = kVIEW_TILT
        self.physDx = physDx
        self.physDy = physDy
        self.roll = roll
    }
}

// MARK: - EyeFrame  (replaces mochiEyePositions)

struct EyeFrame {
    let sd: CGFloat   // -1 left, +1 right
    let x, y: CGFloat
    let fx, fy: CGFloat
    let visible: Bool
    let w, h: CGFloat
}

func mEyeFrames(_ H: MochiH) -> [EyeFrame] {
    var out: [EyeFrame] = []
    for sdD: Double in [-1.0, 1.0] {
        let sd = CGFloat(sdD)
        let eyeYaw   = sd * kEYE_SP + H.yaw
        let eyePitch = kEYE_P + H.pitch
        let cp = cos(eyePitch)
        let visible = cos(eyeYaw) * cp > 0.04
        out.append(EyeFrame(
            sd: sd,
            x:  sin(eyeYaw) * cp * H.rx,
            y: -sin(eyePitch) * H.ry,
            fx: max(0.18, cos(eyeYaw)),
            fy: max(0.18, cp),
            visible: visible,
            w: H.R * kEYE_W,
            h: H.R * kEYE_H
        ))
    }
    return out
}

// MARK: - P3  (projected screen point with depth)

struct P3 {
    let x, y, z: CGFloat
}

// MARK: - 3D helpers (faithful port)

// ringR(y) → radius of horizontal ring at head-local y
func mRingR(_ y: CGFloat) -> CGFloat {
    let a = min(1, abs(y))
    return pow(1 - pow(a, kEXP), 1 / kEXP)
}

// rot(p, yaw, pitch), rotate head-local (x right, y up, z viewer) by yaw then pitch
func mRot3(_ p: (CGFloat, CGFloat, CGFloat), yaw: CGFloat, pitch: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    var (x, y, z) = p
    let cy = cos(yaw), sy = sin(yaw)
    let x1 = x * cy + z * sy
    let z1 = -x * sy + z * cy
    x = x1
    let cp = cos(pitch), sp = sin(pitch)
    let y2 = y * cp + z1 * sp
    let z2 = -y * sp + z1 * cp
    return (x, y2, z2)
}

// proj(H, p), head-local -> screen (body space)
func mProj(_ H: MochiH, _ p: (CGFloat, CGFloat, CGFloat)) -> P3 {
    let r = mRot3(p, yaw: H.yaw, pitch: H.view + H.pitch * kACC_PITCH)
    return P3(x: r.0 * H.rx, y: -r.1 * H.ry, z: r.2)
}

// surf(y, lon, s), point on head surface at height y, longitude lon
func mSurf(_ y: CGFloat, _ lon: CGFloat, _ s: CGFloat = 1) -> (CGFloat, CGFloat, CGFloat) {
    let r = mRingR(y) * s
    return (r * sin(lon), y, r * cos(lon))
}

// MARK: - Body transform helper

func outfitBodyTransform(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          tilt: CGFloat, sx: CGFloat, sy: CGFloat) -> GraphicsContext {
    var ctx = context
    ctx.translateBy(x: cx, y: cy)
    if tilt != 0 { ctx.rotate(by: .radians(tilt)) }
    ctx.scaleBy(x: sx, y: sy)
    return ctx
}
