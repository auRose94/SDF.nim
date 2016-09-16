#[
    Copyright (C) 2016 Cory Noll Crimmins - Golden (cory190@live.com)
    Copyright (C) 2014 Mikko Mononen (memon@inside.org)
    Copyright (C) 2009-2012 Stefan Gustavson (stefan.gustavson@gmail.com)

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
]#

import math

type Float = float64

const MaxPasses = 10
const Slack: Float = 0.001
const SQRT2: Float = sqrt(2.0)
const BIG: Float = 1e+37

type Point = array[3, Float] # X, Y, Distance

proc point(x, y: Float): Point = [x, y, BIG]

proc x(self: Point): Float = self[0]
proc y(self: Point): Float = self[1]
proc dist(self: Point): Float = self[2]

proc `x=`(self: var Point, value: Float) = self[0] = value
proc `y=`(self: var Point, value: Float) = self[1] = value
proc `dist=`(self: var Point, value: Float) = self[2] = value

proc distSqr(a, b: Point): Float =
    let dx = b.x - a.x
    let dy = b.y - a.y
    result = dx * dx + dy * dy

proc coverageToDistanceField*(
     outStride: int,
     img: seq[uint8],
     width, height, stride: int): seq[uint8] =
    result = newSeq[uint8](width * height)
    # newSeq makes the buffer blank with 0's
    for y in 1..height-1:
        for x in 1..width-1:
            var k = x + y * stride
            var d, gx, gy, glen, a, a1: Float
            if img[k] == 255:
                result[x+y*outStride] = 255
                continue
            if img[k] == 0:
                # Special handling for cases where full opaque pixels are next to full transparent pixels.
                let he = img[k-1] == 255 or img[k+1] == 255
                let ve = img[k-stride] == 255 or img[k+stride] == 255
                if not he and not ve:
                    result[x+y*outStride] = 0
                    continue

            gx = - Float(img[k-stride-1]) - SQRT2 * Float(img[k-1]) -
                Float(img[k+stride-1]) + Float(img[k-stride+1]) + SQRT2 *
                Float(img[k+1]) + Float(img[k+stride+1])

            gy = - Float(img[k-stride-1]) - SQRT2 * Float(img[k-stride]) -
                Float(img[k-stride+1]) + Float(img[k+stride-1]) + SQRT2 *
                Float(img[k+stride]) + Float(img[k+stride+1])

            a = Float(img[k]) / 255.0

            gx = abs(gx)
            gy = abs(gy)

            if gx < 0.0001 or gy < 0.000:
                d = (0.5 - a) * SQRT2
            else:
                glen = gx*gx + gy*gy
                glen = 1.0 / sqrt(glen)
                gx *= glen
                gy *= glen
                if (gx < gy):
                    let temp = gx
                    gx = gy
                    gy = temp
                a1 = 0.5 * gy / gx
                if a < a1:
                    d = 0.5 * (gx + gy) - sqrt(2.0*gx*gy*a)
                elif a < (1.0-a1):
                    d = (0.5-a) * gx
                else:
                    d = -0.5 * (gx + gy) + sqrt(2.0*gx*gy*(1.0-a))
            d *= 1.0 / SQRT2
            result[x+y*outStride] = uint8(clamp(0.5 - d, 0.0, 1.0) * 255.0)

proc edgeDistanceField(gx, gy, a: Float): Float =
    var a1: Float
    if gx == 0 or gy == 0:
        result = 0.5 - a
    else:
        var agx = abs(gx)
        var agy = abs(gy)
        # NOTE: any gx|gy after this note, needs to be agx|agy
        if agx < agy:
            let temp = agx
            agx = agy
            agy = temp
        a1 = 0.5 * agy / agx
        if a < a1:
            result = 0.5 * (agx+ agy) - sqrt(2.0*agx*agy*a)
        elif a < (1.0-a1):
            result = (0.5-a) * agx
        else:
            result = -0.5*(agx + agy) + sqrt(2.0*agx*agy*(1.0-a))

proc BuildDistanceField*(
     outStride: int,
     radius: Float,
     img: seq[uint8],
     width, height, stride: int): seq[uint8] =

    var temp = newSeq[Point](width * height)

    # Initialize work buffer
    for p in temp.mitems:
        p = [Float(0.0), Float(0.0), BIG]

    # Calculate position of the anti-aliased pixels and distance to the boundary of the shape.
    for y in 1..height-2:
        for x in 1..width-2:
            let k = x + (y * stride)
            let c = point(Float(x), Float(y))
            var gx, gy, glen: Float

            if img[k] == 255: continue
            if img[k] == 0:
                let he = img[k-1] == 255 or img[k+1] == 255
                let ve = img[k-stride] == 255 or img[k+stride] == 255
                if not he and not ve: continue

            gx = -Float(img[k-stride-1]) - SQRT2*Float(img[k-1]) -
                Float(img[k+stride-1]) + Float(img[k-stride+1]) +
                SQRT2*Float(img[k+1]) + Float(img[k+stride+1])

            gy = -Float(img[k-stride-1]) - SQRT2*Float(img[k-stride]) -
                Float(img[k-stride+1]) + Float(img[k+stride-1]) +
                SQRT2*Float(img[k+stride]) + Float(img[k+stride+1])

            if abs(gx) < 0.001 and abs(gy) < 0.001: continue

            glen = gx*gx + gy*gy
            if glen > 0.0001:
                glen = 1.0 / sqrt(glen)
                gx *= glen
                gy *= glen

            let tk = x + y * width
            let d = edgeDistanceField(gx, gy, Float(img[k])/255.0)
            temp[tk].x = Float(x) + gx * d
            temp[tk].y = Float(y) + gy * d
            temp[tk].dist = distSqr(c, temp[tk])

    for pass in 0..MaxPasses:
        var changed = false

        # Bottom-left to top-right.
        for y in 1..height-2:
            for x in 1..width-2:
                let k = x+y*width
                let c = point(Float(x), Float(y))
                var ch: bool = false
                var d: Float
                var pd: Float = temp[k].dist
                var pt: Point

                # (-1, -1)
                var kn = ((x-1)+(y-1)*width)
                if temp[kn].dist < pd:
                    d = distSqr(c, temp[kn])
                    if d + Slack < pd:
                        pt = temp[kn]
                        pd = d
                        ch = true

                # (0, -1)
                kn = ((x-0)+(y-1)*width)
                if temp[kn].dist < pd:
                    d = distSqr(c, temp[kn])
                    if d + Slack < pd:
                        pt = temp[kn]
                        pd = d
                        ch = true

                # (1, -1)
                kn = ((x+1)+(y-1)*width)
                if temp[kn].dist < pd:
                    d = distSqr(c, temp[kn])
                    if d + Slack < pd:
                        pt = temp[kn]
                        pd = d
                        ch = true

                # (-1, 0)
                kn = ((x-1)+(y-0)*width)
                if temp[kn].dist < pd:
                    d = distSqr(c, temp[kn])
                    if d + Slack < pd:
                        pt = temp[kn]
                        pd = d
                        ch = true

                if ch:
                    temp[k] = [pt.x, pt.y, pd]
                    changed = true

        # Top-right to bottom-left.
        for y in countDown(height-2, 0):
            for x in countDown(width-2, 0):
                let k = x+y*width
                let c = point(Float(x), Float(y))
                var ch: bool = false
                var d: Float
                var pd: Float = temp[k].dist
                var pt: Point

                # (1, 0)
                var kn = ((x+1)+(y+0)*width)
                if temp[kn].dist < pd:
                    d = distSqr(c, temp[kn])
                    if d + Slack < pd:
                        pt = temp[kn]
                        pd = d
                        ch = true

                # (-1, 1)
                kn = ((x-1)+(y+1)*width)
                if temp[kn].dist < pd:
                    d = distSqr(c, temp[kn])
                    if d + Slack < pd:
                        pt = temp[kn]
                        pd = d
                        ch = true

                # (0, 1)
                kn = ((x+0)+(y+1)*width)
                if temp[kn].dist < pd:
                    d = distSqr(c, temp[kn])
                    if d + Slack < pd:
                        pt = temp[kn]
                        pd = d
                        ch = true

                # (1, 1)
                kn = ((x+1)+(y+1)*width)
                if temp[kn].dist < pd:
                    d = distSqr(c, temp[kn])
                    if d + Slack < pd:
                        pt = temp[kn]
                        pd = d
                        ch = true

                if ch:
                    temp[k] = [pt.x, pt.y, pd]
                    changed = true

        if not changed: break

    # map to good range
    result = newSeq[uint8](width * height)

    let scale = 1.0 / radius
    for y in 0..height-1:
        for x in 0..width-1:
            assert(x+y*width < height * width)
            var d = sqrt(temp[x+y*width].dist) * scale
            if img[x+y*stride] > 127'u8: d = -d
            result[x+y*outStride] = uint8(clamp(0.5 - d * 0.5, 0.0, 1.0) * 255.0)
