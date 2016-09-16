#[
    Copyright (C) 2016 Cory Noll Crimmins - Golden (cory190@live.com)
    Copyright (C) 2014 Mikko Mononen (memon@inside.org)

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

# This uses GLFW3 and OpenGL
# It only handles greyscale images converted from FreeImage.
import ../SDF
import glfw3 as glfw
import opengl
import freeimage
import strutils

var ImageFileName: string = "./test.tga"
var radius: float = 2.0
var scale: float = 1.0
var x: float = 0.0
var y: float = 0.0
var alphaTest: bool = true
var imageAspect: float = 1.0
var tex: GLuint = 0
var tex2: GLuint = 0

type Image = ref object
    data: seq[uint8]
    width: int
    height: int

proc unload(self: var Image) =
    self.data.setLen(0)
    self.width = 0
    self.height = 0

proc inverse(self: var Image) =
    for b in self.data.mitems:
        b = 255'u8 - b

proc loadGreyscale(path: string): Image =
    # TODO: Add better error checking
    var FIF = FreeImage_GetFileType(path, 0)
    if FIF == FIF_UNKNOWN:
        FIF = FreeImage_GetFIFFromFilename(path)
    assert(FIF != FIF_UNKNOWN)
    var colorBitmap = FreeImage_Load(FIF, path, 0)
    assert(not colorBitmap.isNil)
    assert(FreeImage_FlipVertical(colorBitmap) == 1)
    var bitmap = FreeImage_ConvertToGreyscale(colorBitmap)
    assert(not bitmap.isNil)
    FreeImage_Unload(colorBitmap)

    var image_type = FreeImage_GetImageType(bitmap)
    assert(image_type == FIT_BITMAP)
    assert(FreeImage_GetBPP(bitmap) == 8)

    # FreeImage_GetLine gets the bytes per row
    let width = int(FreeImage_GetWidth(bitmap))
    let height = int(FreeImage_GetHeight(bitmap))

    let imageSize = width * height
    result = Image(
        data: newSeq[uint8](imageSize),
        width: width,
        height: height,
    )
    copyMem(unsafeAddr(result.data[0]), FreeImage_GetBits(bitmap), imageSize)

    FreeImage_Unload(bitmap)

proc createDistanceField(source: var Image): Image =
    result = Image(
        data: BuildDistanceField(source.width, radius, source.data, source.width,
                                 source.height, source.width),
        width: source.width,
        height: source.height,
    )

proc loadTexture(img: Image): GLuint =
    var texture: GLuint = 0
    glGenTextures(1, unsafeAddr(texture))
    assert(texture != 0)
    glBindTexture(GL_TEXTURE_2D, texture)

    glPixelStorei(GL_UNPACK_ALIGNMENT,1)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, GLint(img.width))
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)

    let dataPtr = cast[pointer](unsafeAddr(img.data[0]))
    glTexImage2D(GL_TEXTURE_2D, GLint(0), GLint(GL_ALPHA), GLsizei(img.width),
        GLsizei(img.height), GLint(0), GL_ALPHA, GL_UNSIGNED_BYTE, dataPtr)

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

    glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)

    return texture

proc loadImage(
               imageFile: string,
               radius: float,
               imageAspect: var float,
               texId, texIdSDF: var GLuint) =
    var img1: Image = nil
    var img2: Image = nil

    img1 = loadGreyscale(imageFile)
    img1.inverse()

    imageAspect = float(img1.height) / float(img1.width)

    echo "Loading an image of $1 x $2 with a radius of $3".format(
         img1.width, img1.height, radius)

    img2 = createDistanceField(img1)

    if texId != 0: glDeleteTextures(1, texId.addr)
    texId = loadTexture(img1)

    if texIdSDF != 0: glDeleteTextures(1, texIdSDF.addr)
    texIdSDF = loadTexture(img2)

    img1.unload()
    img2.unload()

proc FreeImageErrorCB(fif: FREE_IMAGE_FORMAT; msg: cstring) =
    echo "[FreeImage]:" & "failed to load:" & $fif & ", with message: " & $msg

proc keyCB(window: Window; key: cint; scancode: cint; action: cint;
           modifiers: cint) {.cdecl.} =
    if key == glfw.KEY_ESCAPE and action == glfw.PRESS:
        glfw.SetWindowShouldClose(window, 1)

    if key == glfw.KEY_HOME and action == glfw.PRESS:
        radius += 0.5
        loadImage(ImageFileName, radius, imageAspect, tex, tex2)

    if key == glfw.KEY_END and action == glfw.PRESS:
        radius -= 0.5
        loadImage(ImageFileName, radius, imageAspect, tex, tex2)

    if key == glfw.KEY_PAGE_UP and action == glfw.PRESS:
        scale *= 1.1

    if key == glfw.KEY_PAGE_DOWN and action == glfw.PRESS:
        scale /= 1.1

    if key == glfw.KEY_LEFT and action == glfw.PRESS:
        x += 50.0 * scale

    if key == glfw.KEY_RIGHT and action == glfw.PRESS:
        x -= 50.0 * scale

    if key == glfw.KEY_UP and action == glfw.PRESS:
        y += 50.0 * scale

    if key == glfw.KEY_DOWN and action == glfw.PRESS:
        y -= 50.0 * scale

    if key == glfw.KEY_A and action == glfw.PRESS:
        alphaTest = not alphaTest


proc Main() =
    var window: glfw.Window

    if glfw.Init() != glfw.TRUE:
        echo "GLFW Failed to init!"
        return

    FreeImage_Initialise(0)
    FreeImage_SetOutputMessage(FreeImageErrorCB)

    window = glfw.CreateWindow(1280, 720, "Distance Transform", nil, nil)
    if window.isNil:
        echo "GLFW Failed to create window!"
        glfw.Terminate()
        return

    discard glfw.SetKeyCallback(window, keyCB)
    glfw.MakeContextCurrent(window)

    opengl.loadExtensions()

    loadImage(ImageFileName, radius, imageAspect, tex, tex2)

    glEnable(GL_LINE_SMOOTH)

    while glfw.WindowShouldClose(window) != 1:
        var o, w, h: float
        var width, height: cint

        glfw.GetFramebufferSize(window, width.addr, height.addr)

        # Update and render
        glViewport(0, 0, width, height)
        glClearColor(0.3, 0.3, 0.32, 1.0)
        glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
        glEnable(GL_BLEND)
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        glDisable(GL_TEXTURE_2D)

        # Draw UI?
        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()
        glOrtho(0.0, float(width), float(height), 0.0, -1.0, 1.0)

        glMatrixMode(GL_MODELVIEW)
        glLoadIdentity()

        glDisable(GL_DEPTH_TEST)
        glDisable(GL_CULL_FACE)

        w = float(width-40) * 0.5 * scale
        h = w * imageAspect
        o = w

        # Draw orig texture using bilinear filtering
        glEnable(GL_TEXTURE_2D)

        glBindTexture(GL_TEXTURE_2D, tex)
        glColor4ub(255,255,255,255)

        glBegin(GL_QUADS)

        glTexCoord2f(0,0)
        glVertex2f(x+o,y)

        glTexCoord2f(1,0)
        glVertex2f(x+w+o,y)

        glTexCoord2f(1,1);
        glVertex2f(x+w+o,y+h)

        glTexCoord2f(0,1)
        glVertex2f(x+o,y+h)

        glEnd()

        # Draw distance texture using alpha testing
        glBindTexture(GL_TEXTURE_2D, tex2)
        glColor4ub(255,255,255,255)

        if alphaTest:
            glDisable(GL_BLEND)
            glEnable(GL_ALPHA_TEST)
            glAlphaFunc(GL_GREATER, 0.5)

        glBegin(GL_QUADS)

        glTexCoord2f(0,0)
        glVertex2f(x,y)

        glTexCoord2f(1,0)
        glVertex2f(x+w,y)

        glTexCoord2f(1,1)
        glVertex2f(x+w,y+h)

        glTexCoord2f(0,1)
        glVertex2f(x,y+h)

        glEnd()

        glDisable(GL_TEXTURE_2D)

        if alphaTest:
            glEnable(GL_BLEND)
            glDisable(GL_ALPHA_TEST)

        glEnable(GL_DEPTH_TEST)

        glfw.SwapBuffers(window)
        glfw.PollEvents()

    glfw.Terminate()
    FreeImage_DeInitialise()

Main()
