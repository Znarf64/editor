// Odin bindings for EGL, generated from the Khronos EGL XML API Registry header (egl.h).
// Original header: Copyright 2013-2020 The Khronos Group Inc. SPDX-License-Identifier: Apache-2.0
package egl

import "core:c"

NativeDisplayType :: distinct rawptr
NativeWindowType  :: distinct rawptr
NativePixmapType  :: distinct rawptr

// ---------------------------------------------------------------------------------------------
// Core EGL types

Boolean :: b32
Display :: distinct rawptr
Config  :: distinct rawptr
Surface :: distinct rawptr
Context :: distinct rawptr
Int     :: c.int32_t

// EGL 1.2+
Enum         :: distinct c.uint32_t
ClientBuffer :: distinct rawptr

// EGL 1.5+
Sync    :: distinct rawptr
Attrib  :: distinct c.intptr_t // intptr_t
Image   :: distinct rawptr

// ---------------------------------------------------------------------------------------------
// EGL_VERSION_1_0

ALPHA_SIZE            :: 0x3021
BAD_ACCESS             :: 0x3002
BAD_ALLOC              :: 0x3003
BAD_ATTRIBUTE          :: 0x3004
BAD_CONFIG             :: 0x3005
BAD_CONTEXT            :: 0x3006
BAD_CURRENT_SURFACE    :: 0x3007
BAD_DISPLAY            :: 0x3008
BAD_MATCH              :: 0x3009
BAD_NATIVE_PIXMAP      :: 0x300A
BAD_NATIVE_WINDOW      :: 0x300B
BAD_PARAMETER          :: 0x300C
BAD_SURFACE            :: 0x300D
BLUE_SIZE              :: 0x3022
BUFFER_SIZE            :: 0x3020
CONFIG_CAVEAT          :: 0x3027
CONFIG_ID              :: 0x3028
CORE_NATIVE_ENGINE     :: 0x305B
DEPTH_SIZE             :: 0x3025
DONT_CARE              :: Int(-1)
DRAW                   :: 0x3059
EXTENSIONS             :: 0x3055
FALSE                  :: 0
GREEN_SIZE             :: 0x3023
HEIGHT                 :: 0x3056
LARGEST_PBUFFER        :: 0x3058
LEVEL                  :: 0x3029
MAX_PBUFFER_HEIGHT     :: 0x302A
MAX_PBUFFER_PIXELS     :: 0x302B
MAX_PBUFFER_WIDTH      :: 0x302C
NATIVE_RENDERABLE      :: 0x302D
NATIVE_VISUAL_ID       :: 0x302E
NATIVE_VISUAL_TYPE     :: 0x302F
NONE                   :: 0x3038
NON_CONFORMANT_CONFIG  :: 0x3051
NOT_INITIALIZED        :: 0x3001
NO_CONTEXT             :: Context{}
NO_DISPLAY             :: Display{}
NO_SURFACE             :: Surface{}
PBUFFER_BIT            :: 0x0001
PIXMAP_BIT             :: 0x0002
READ                   :: 0x305A
RED_SIZE               :: 0x3024
SAMPLES                :: 0x3031
SAMPLE_BUFFERS         :: 0x3032
SLOW_CONFIG            :: 0x3050
STENCIL_SIZE           :: 0x3026
SUCCESS                :: 0x3000
SURFACE_TYPE           :: 0x3033
TRANSPARENT_BLUE_VALUE :: 0x3035
TRANSPARENT_GREEN_VALUE :: 0x3036
TRANSPARENT_RED_VALUE  :: 0x3037
TRANSPARENT_RGB        :: 0x3052
TRANSPARENT_TYPE       :: 0x3034
TRUE                   :: 1
VENDOR                 :: 0x3053
VERSION                :: 0x3054
WIDTH                  :: 0x3057
WINDOW_BIT             :: 0x0004

// ---------------------------------------------------------------------------------------------
// EGL_VERSION_1_1

BACK_BUFFER          :: 0x3084
BIND_TO_TEXTURE_RGB  :: 0x3039
BIND_TO_TEXTURE_RGBA :: 0x303A
CONTEXT_LOST         :: 0x300E
MIN_SWAP_INTERVAL    :: 0x303B
MAX_SWAP_INTERVAL    :: 0x303C
MIPMAP_TEXTURE       :: 0x3082
MIPMAP_LEVEL         :: 0x3083
NO_TEXTURE           :: 0x305C
TEXTURE_2D           :: 0x305F
TEXTURE_FORMAT       :: 0x3080
TEXTURE_RGB          :: 0x305D
TEXTURE_RGBA         :: 0x305E
TEXTURE_TARGET       :: 0x3081

// ---------------------------------------------------------------------------------------------
// EGL_VERSION_1_2

ALPHA_FORMAT          :: 0x3088
ALPHA_FORMAT_NONPRE   :: 0x308B
ALPHA_FORMAT_PRE      :: 0x308C
ALPHA_MASK_SIZE       :: 0x303E
BUFFER_PRESERVED      :: 0x3094
BUFFER_DESTROYED      :: 0x3095
CLIENT_APIS           :: 0x308D
COLORSPACE            :: 0x3087
COLORSPACE_sRGB       :: 0x3089
COLORSPACE_LINEAR     :: 0x308A
COLOR_BUFFER_TYPE     :: 0x303F
CONTEXT_CLIENT_TYPE   :: 0x3097
DISPLAY_SCALING       :: 10000
HORIZONTAL_RESOLUTION :: 0x3090
LUMINANCE_BUFFER      :: 0x308F
LUMINANCE_SIZE        :: 0x303D
OPENGL_ES_BIT         :: 0x0001
OPENVG_BIT            :: 0x0002
OPENGL_ES_API         :: 0x30A0
OPENVG_API            :: 0x30A1
OPENVG_IMAGE          :: 0x3096
PIXEL_ASPECT_RATIO    :: 0x3092
RENDERABLE_TYPE       :: 0x3040
RENDER_BUFFER         :: 0x3086
RGB_BUFFER            :: 0x308E
SINGLE_BUFFER         :: 0x3085
SWAP_BEHAVIOR         :: 0x3093
UNKNOWN               :: Int(-1)
VERTICAL_RESOLUTION   :: 0x3091

// ---------------------------------------------------------------------------------------------
// EGL_VERSION_1_3

CONFORMANT               :: 0x3042
CONTEXT_CLIENT_VERSION   :: 0x3098
MATCH_NATIVE_PIXMAP      :: 0x3041
OPENGL_ES2_BIT           :: 0x0004
VG_ALPHA_FORMAT          :: 0x3088
VG_ALPHA_FORMAT_NONPRE   :: 0x308B
VG_ALPHA_FORMAT_PRE      :: 0x308C
VG_ALPHA_FORMAT_PRE_BIT  :: 0x0040
VG_COLORSPACE            :: 0x3087
VG_COLORSPACE_sRGB       :: 0x3089
VG_COLORSPACE_LINEAR     :: 0x308A
VG_COLORSPACE_LINEAR_BIT :: 0x0020

// ---------------------------------------------------------------------------------------------
// EGL_VERSION_1_4

DEFAULT_DISPLAY              :: NativeDisplayType{}
MULTISAMPLE_RESOLVE_BOX_BIT  :: 0x0200
MULTISAMPLE_RESOLVE          :: 0x3099
MULTISAMPLE_RESOLVE_DEFAULT  :: 0x309A
MULTISAMPLE_RESOLVE_BOX      :: 0x309B
OPENGL_API                   :: 0x30A2
OPENGL_BIT                   :: 0x0008
SWAP_BEHAVIOR_PRESERVED_BIT  :: 0x0400

// ---------------------------------------------------------------------------------------------
// EGL_VERSION_1_5

CONTEXT_MAJOR_VERSION                      :: 0x3098
CONTEXT_MINOR_VERSION                      :: 0x30FB
CONTEXT_OPENGL_PROFILE_MASK                :: 0x30FD
CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY :: 0x31BD
NO_RESET_NOTIFICATION                      :: 0x31BE
LOSE_CONTEXT_ON_RESET                      :: 0x31BF
CONTEXT_OPENGL_CORE_PROFILE_BIT            :: 0x00000001
CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT   :: 0x00000002
CONTEXT_OPENGL_DEBUG                       :: 0x31B0
CONTEXT_OPENGL_FORWARD_COMPATIBLE          :: 0x31B1
CONTEXT_OPENGL_ROBUST_ACCESS               :: 0x31B2
OPENGL_ES3_BIT                             :: 0x00000040
CL_EVENT_HANDLE                            :: 0x309C
SYNC_CL_EVENT                              :: 0x30FE
SYNC_CL_EVENT_COMPLETE                     :: 0x30FF
SYNC_PRIOR_COMMANDS_COMPLETE               :: 0x30F0
SYNC_TYPE                                  :: 0x30F7
SYNC_STATUS                                :: 0x30F1
SYNC_CONDITION                             :: 0x30F8
SIGNALED                                   :: 0x30F2
UNSIGNALED                                 :: 0x30F3
SYNC_FLUSH_COMMANDS_BIT                    :: 0x0001
FOREVER                                    :: 0xFFFFFFFFFFFFFFFF
TIMEOUT_EXPIRED                            :: 0x30F5
CONDITION_SATISFIED                        :: 0x30F6
NO_SYNC                                    :: Sync{}
SYNC_FENCE                                 :: 0x30F9
GL_COLORSPACE                              :: 0x309D
GL_COLORSPACE_SRGB                         :: 0x3089
GL_COLORSPACE_LINEAR                       :: 0x308A
GL_RENDERBUFFER                            :: 0x30B9
GL_TEXTURE_2D                              :: 0x30B1
GL_TEXTURE_LEVEL                           :: 0x30BC
GL_TEXTURE_3D                              :: 0x30B2
GL_TEXTURE_ZOFFSET                         :: 0x30BD
GL_TEXTURE_CUBE_MAP_POSITIVE_X             :: 0x30B3
GL_TEXTURE_CUBE_MAP_NEGATIVE_X             :: 0x30B4
GL_TEXTURE_CUBE_MAP_POSITIVE_Y             :: 0x30B5
GL_TEXTURE_CUBE_MAP_NEGATIVE_Y             :: 0x30B6
GL_TEXTURE_CUBE_MAP_POSITIVE_Z             :: 0x30B7
GL_TEXTURE_CUBE_MAP_NEGATIVE_Z             :: 0x30B8
IMAGE_PRESERVED                            :: 0x30D2
NO_IMAGE                                   :: Image{}

foreign import egl "system:EGL"

@(default_calling_convention="c", link_prefix="egl")
foreign egl {
	// EGL_VERSION_1_0
	ChooseConfig         :: proc(dpy: Display, attrib_list: [^]Int, configs: [^]Config, config_size: Int, num_config: ^Int) -> Boolean ---
	CopyBuffers          :: proc(dpy: Display, surface: Surface, target: NativePixmapType) -> Boolean ---
	CreateContext        :: proc(dpy: Display, config: Config, share_context: Context, attrib_list: [^]Int) -> Context ---
	CreatePbufferSurface :: proc(dpy: Display, config: Config, attrib_list: [^]Int) -> Surface ---
	CreatePixmapSurface  :: proc(dpy: Display, config: Config, pixmap: NativePixmapType, attrib_list: [^]Int) -> Surface ---
	CreateWindowSurface  :: proc(dpy: Display, config: Config, win: NativeWindowType, attrib_list: [^]Int) -> Surface ---
	DestroyContext       :: proc(dpy: Display, ctx: Context) -> Boolean ---
	DestroySurface       :: proc(dpy: Display, surface: Surface) -> Boolean ---
	GetConfigAttrib      :: proc(dpy: Display, config: Config, attribute: Int, value: ^Int) -> Boolean ---
	GetConfigs           :: proc(dpy: Display, configs: [^]Config, config_size: Int, num_config: ^Int) -> Boolean ---
	GetCurrentDisplay    :: proc() -> Display ---
	GetCurrentSurface    :: proc(readdraw: Int) -> Surface ---
	GetDisplay           :: proc(display_id: NativeDisplayType) -> Display ---
	GetError             :: proc() -> Int ---
	GetProcAddress       :: proc(procname: cstring) -> rawptr ---
	Initialize           :: proc(dpy: Display, major: ^Int, minor: ^Int) -> Boolean ---
	MakeCurrent          :: proc(dpy: Display, draw: Surface, read: Surface, ctx: Context) -> Boolean ---
	QueryContext         :: proc(dpy: Display, ctx: Context, attribute: Int, value: ^Int) -> Boolean ---
	QueryString          :: proc(dpy: Display, name: Int) -> cstring ---
	QuerySurface         :: proc(dpy: Display, surface: Surface, attribute: Int, value: ^Int) -> Boolean ---
	SwapBuffers          :: proc(dpy: Display, surface: Surface) -> Boolean ---
	Terminate            :: proc(dpy: Display) -> Boolean ---
	WaitGL               :: proc() -> Boolean ---
	WaitNative           :: proc(engine: Int) -> Boolean ---

	// EGL_VERSION_1_1
	BindTexImage    :: proc(dpy: Display, surface: Surface, buffer: Int) -> Boolean ---
	ReleaseTexImage :: proc(dpy: Display, surface: Surface, buffer: Int) -> Boolean ---
	SurfaceAttrib   :: proc(dpy: Display, surface: Surface, attribute: Int, value: Int) -> Boolean ---
	SwapInterval    :: proc(dpy: Display, interval: Int) -> Boolean ---

	// EGL_VERSION_1_2
	BindAPI                       :: proc(api: Enum) -> Boolean ---
	QueryAPI                      :: proc() -> Enum ---
	CreatePbufferFromClientBuffer :: proc(dpy: Display, buftype: Enum, buffer: ClientBuffer, config: Config, attrib_list: [^]Int) -> Surface ---
	ReleaseThread                 :: proc() -> Boolean ---
	WaitClient                    :: proc() -> Boolean ---

	// EGL_VERSION_1_4
	GetCurrentContext :: proc() -> Context ---

	// EGL_VERSION_1_5
	CreateSync                  :: proc(dpy: Display, type: Enum, attrib_list: [^]Attrib) -> Sync ---
	DestroySync                 :: proc(dpy: Display, sync: Sync) -> Boolean ---
	ClientWaitSync              :: proc(dpy: Display, sync: Sync, flags: Int, timeout: u64) -> Int ---
	GetSyncAttrib               :: proc(dpy: Display, sync: Sync, attribute: Int, value: ^Attrib) -> Boolean ---
	CreateImage                 :: proc(dpy: Display, ctx: Context, target: Enum, buffer: ClientBuffer, attrib_list: [^]Attrib) -> Image ---
	DestroyImage                :: proc(dpy: Display, image: Image) -> Boolean ---
	GetPlatformDisplay          :: proc(platform: Enum, native_display: rawptr, attrib_list: [^]Attrib) -> Display ---
	CreatePlatformWindowSurface :: proc(dpy: Display, config: Config, native_window: rawptr, attrib_list: [^]Attrib) -> Surface ---
	CreatePlatformPixmapSurface :: proc(dpy: Display, config: Config, native_pixmap: rawptr, attrib_list: [^]Attrib) -> Surface ---
	WaitSync                    :: proc(dpy: Display, sync: Sync, flags: Int) -> Boolean ---
}

gl_set_proc_address :: proc(p: rawptr, name: cstring) {
	(^rawptr)(p)^ = GetProcAddress(name)
}
